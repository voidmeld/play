--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Run = require("../quest/run")
local Settlement = require("./settlement")
local Value = require("../value")
local Verify = require("../../../.lute/dependencies/verify/src/core")
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
