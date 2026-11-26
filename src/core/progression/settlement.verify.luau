--!strict
local Bdd = require("@verify/src/bdd")
local Run = require("../quest/run")
local Settlement = require("./settlement")
local Value = require("../../kernel/value")
local Verify = require("@verify/src/core")
type Ledger = { items: number, receipts: { [string]: boolean } }
local package = { id = "route" }
local completed: Run.RunState = {
	schemaVersion = 1,
	expeditionId = "route",
	runId = "run",
	revision = 2,
	startedAtSec = 0,
	lastClockSec = 1,
	status = "completed",
	phaseIndex = 1,
	attempt = 1,
	leaderId = "a",
	members = { { id = "a", connected = true, departed = false } },
	receipts = {},
}
local Core = Settlement.settlement({
	readPackage = function(value: unknown): typeof(package)?
		return if value == package then package else nil
	end,
	packageId = function(value: typeof(package)): string
		return value.id
	end,
	readRunState = function(value: unknown, _): Run.RunState?
		return if value == completed then completed else nil
	end,
	copyPersonalState = function(value: unknown): Ledger?
		if type(value) ~= "table" then
			return nil
		end
		local raw = assert(Value.raw(value))
		if type(raw.items) ~= "number" or type(raw.receipts) ~= "table" then
			return nil
		end
		local receipts: { [string]: boolean } = {}
		for key, held in raw.receipts do
			if type(key) ~= "string" or held ~= true then
				return nil
			end
			receipts[key] = true
		end
		return { items = raw.items, receipts = receipts }
	end,
	readQuality = function(value: unknown): string?
		return if value == "standard" then "standard" else nil
	end,
	roleUpgrade = function(_: string): boolean
		return false
	end,
	knownRole = function(_, role: string): boolean
		return role == "role"
	end,
	rewardForClear = function(_, _: string, count: number): Settlement.RewardGrant<string>?
		return { transactionId = "", itemId = "item", quality = "standard", clearNumber = count, roleUpgrade = false }
	end,
	hasReceipt = function(state: Ledger, id: string): boolean
		return state.receipts[id] == true
	end,
	grant = function(state: Ledger, id: string, _: string, refuse: boolean): Settlement.GrantResult<Ledger>
		if refuse then
			return { ok = false, reason = "full" }
		end
		local receipts = table.clone(state.receipts)
		local replayed = receipts[id] == true
		receipts[id] = true
		return {
			ok = true,
			replayed = replayed,
			state = { items = state.items + (if replayed then 0 else 1), receipts = receipts },
		}
	end,
})
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("shared reward queue", function()
		it("retries saves and released receipts before reporting claims as settled", function()
			local staged: { string } = {}
			local saves: { string } = {}
			local notices: { string } = {}
			local accept, loaded, durable = false, true, false
			local awarded, writes = 0, 0
			local pending: { string } = { "reward" }
			local config: Settlement.QueueConfig<string, string, string> = {
				claimKey = function(event, member)
					return event .. member
				end,
				stage = function(member, _, confirm)
					if accept then
						table.insert(staged, member)
						confirm(member == "b")
					end
				end,
				loaded = function(member)
					return member == "a" or loaded
				end,
				save = function(member)
					expect(staged):toEqual({ "b", "a" })
					table.insert(saves, member)
					return durable
				end,
				saveReleased = function(member)
					table.insert(saves, "released:" .. member)
					return durable
				end,
				scope = function()
					return "scope"
				end,
				members = function()
					return { "a" }
				end,
				pending = function()
					return pending
				end,
				marker = function(reward)
					return reward
				end,
				deliver = function()
					writes += 1
					if writes == 1 then
						error("interrupted write")
					end
					if not durable then
						return false, "capacity"
					end
					table.clear(pending)
					return true, nil
				end,
				reward = function()
					awarded += 1
				end,
				notice = function(member, event, reason)
					table.insert(notices, member .. "/" .. event .. "/" .. (reason or ""))
				end,
			}
			local queue = Settlement.rewardQueue(config)
			queue.stage("run", { "a", "b" })
			accept = true
			queue.stage("run", { "b", "a", "b" })
			config.reward = function()
				awarded += 1
				queue.drain()
			end
			local ok = pcall(queue.drain)
			expect(ok):toBe(false)
			expect(queue.settled("run")):toBe(false)
			queue.drain()
			queue.drain()
			expect(notices):toEqual({ "a/save_pending/", "b/save_pending/", "a/delivery_pending/capacity" })
			loaded, durable = false, true
			table.clear(saves)
			queue.drain()
			queue.drain()
			expect(saves):toEqual({ "a", "released:b" })
			expect(notices[4]):toBe("b/locked/")
			expect(queue.settled("run")):toBe(true)
			expect(awarded):toBe(1)
		end)
	end)
	describe("run settlement", function()
		it("keeps failed grants atomic and reconciles both ledgers on replay", function()
			local history = assert(Core.emptyRewardHistory("route", "a"))
			local state: Ledger = { items = 0, receipts = {} }
			local request = { transactionId = "grant", expectedRevision = 0, characterId = "a", roleId = "role" }
			local failed = Core.applyPersonalReward(package, completed, history, state, true, request)
			assert(not failed.ok)
			expect(failed.reason):toBe("personal_transaction_rejected:full")
			expect(history.revision):toBe(0)
			expect(state.items):toBe(0)
			local granted = Core.applyPersonalReward(package, completed, history, state, false, request)
			assert(granted.ok)
			expect(granted.personalState.items):toBe(1)
			local replay =
				Core.applyPersonalReward(package, completed, granted.history, granted.personalState, false, request)
			assert(replay.ok)
			expect(replay.replayed):toBe(true)
			expect(replay.personalState.items):toBe(1)
			local missing = Core.applyPersonalReward(package, completed, granted.history, state, false, request)
			assert(not missing.ok)
			expect(missing.reason):toBe("receipt_state_mismatch")
			request.transactionId = "other"
			request.expectedRevision = 1
			local duplicate =
				Core.applyPersonalReward(package, completed, granted.history, granted.personalState, false, request)
			assert(not duplicate.ok)
			expect(duplicate.reason):toBe("run_already_rewarded")
		end)
	end)
end
