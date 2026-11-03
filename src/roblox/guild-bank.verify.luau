--!strict

local Banks = require("../core/social/guildbank")
local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Host = require("./guild-bank")
local Ledgers = require("../core/social/guildledger")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Profile = { inventory: { [string]: number }, ledger: Ledgers.Ledger }
local bankRules = Banks.guildbank({
	maxKinds = 8,
	maxStack = 100,
	maxReceipts = 32,
	maxReceiptsPerOwner = 8,
	maxLog = 8,
	maxWithdrawals = 16,
	daySec = 86400,
	memberDailyWithdrawal = 5,
	healRetentionSec = 1000,
	receiptTtlSec = 500,
	maxOperations = 64,
	maxOperationsPerActor = 16,
	maxId = 64,
	maxTime = 1000000000000,
	maxMembers = 8,
	roles = { member = true, steward = true },
	privilegedRoles = { steward = true },
})
local ledger = Ledgers.guildledger({
	readProfile = function(profile: Profile): Ledgers.ProfileInput
		return { inventory = profile.inventory, guildBank = profile.ledger }
	end,
	writeProfile = function(profile: Profile, inventory: { [string]: number }?, value: Ledgers.Ledger): Profile
		return { inventory = inventory or profile.inventory, ledger = value }
	end,
	maxUnacked = 8,
	withdrawRoom = 4,
	maxPending = 4,
	maxId = 64,
	maxCount = 100,
	maxTime = 1000000000000,
	healRetentionSec = 1000,
})
local configured = Host.configure({
	ledger = ledger,
	copy = function(profile: Profile): Profile
		return table.clone(profile)
	end,
	profileLedger = function(profile: Profile): unknown
		return profile.ledger
	end,
	inventory = function(profile: Profile): { [string]: number }
		return profile.inventory
	end,
	capacity = function(_profile: Profile?): number
		return 3
	end,
	receiptsFor = bankRules.receiptsFor,
	maxItemCount = 10,
	maxMove = 10,
	joinRetrySec = 1,
	healRetentionSec = 1000,
	receiptTtlSec = 500,
	memberDailyWithdrawal = 5,
	logRows = 3,
})
local function rig()
	local profiles: { [number]: Profile } = {
		[1] = { inventory = { ore = 8 }, ledger = ledger.emptyLedger() },
		[2] = { inventory = {}, ledger = ledger.emptyLedger() },
	}
	local state = assert(bankRules.emptyState("guild"))
	local sequence = 0
	local skip, unreadable, uncertain = false, false, false
	local retry: ((Profile) -> Profile)? = nil
	local saves = 0
	local service = assert(configured.mount({
		bank = {
			read = function(_id: string): Host.BankResult
				return { ok = true, state = if unreadable then nil else state, replayed = false, ambiguous = false }
			end,
			apply = function(_id: string, command: unknown): Host.BankResult
				local result = bankRules.apply(state, command, 100)
				if result.state ~= nil then
					state = result.state
				end
				if uncertain then
					uncertain = false
					return { ok = false, replayed = false, ambiguous = true, reason = "reply_lost" }
				end
				return {
					ok = result.ok,
					state = result.state,
					replayed = result.replayed,
					ambiguous = false,
					receipts = result.receipts,
					reason = result.reason,
					fence = result.fence,
				}
			end,
		},
		materials = { { id = "ore", label = "Ore" } },
		profileFor = function(id: number): Host.ProfileAccess<Profile>?
			return {
				read = function(): Profile?
					return profiles[id]
				end,
				update = function(apply: (Profile) -> Profile)
					if skip then
						return
					end
					if retry ~= nil then
						local change = retry
						retry = nil
						apply(profiles[id])
						profiles[id] = change(profiles[id])
					end
					profiles[id] = apply(profiles[id])
				end,
				save = function(): boolean
					saves += 1
					return true
				end,
			}
		end,
		membershipFor = function(id: number, _fresh: boolean): (Host.Membership?, string?)
			return { fellowshipId = "guild", role = if id == 1 then "steward" else "member", memberIds = { 1, 2 } }, nil
		end,
		clock = function(): number
			return 100
		end,
		newOpId = function(): string
			sequence += 1
			return "operation-" .. sequence
		end,
	}))
	return {
		service = service,
		profiles = profiles,
		state = function()
			return state
		end,
		saves = function()
			return saves
		end,
		skip = function()
			skip = true
		end,
		unreadable = function()
			unreadable = true
		end,
		uncertain = function()
			uncertain = true
		end,
		retry = function(change: (Profile) -> Profile)
			retry = change
		end,
	}
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("guild bank host", function()
		it("settles deposits and claims withdrawals without duplicate receipt credits", function()
			local scene = rig()
			local deposited = scene.service.deposit(1, "ore", 6)
			assert(deposited.ok, deposited.reason)
			local withdrawn = scene.service.withdraw(2, "ore", 3)
			assert(withdrawn.ok, withdrawn.reason)
			expect(scene.state().stock.ore):toBe(3)
			expect(scene.profiles[2].inventory.ore):toBe(3)
			local refreshed = scene.service.refresh(2)
			assert(refreshed.ok, refreshed.reason)
			expect(scene.profiles[2].inventory.ore):toBe(3)
			expect(scene.service.withdraw(2, "ore", 3).reason):toBe("withdrawal_limit")
		end)
		it("reconciles an uncertain deposit with a durable operation fence", function()
			local scene = rig()
			scene.uncertain()
			expect(scene.service.deposit(1, "ore", 3).pending):toBe(true)
			expect(scene.profiles[1].inventory.ore):toBe(5)
			expect(scene.service.refresh(1).ok):toBe(true)
			expect(scene.profiles[1].ledger.pending):toEqual({})
			expect(scene.state().stock.ore):toBe(3)
		end)
		it("uses final transform acceptance and refuses a missing callback", function()
			local scene = rig()
			scene.profiles[1].inventory = { ore = 1 }
			scene.retry(function(profile)
				return { inventory = { ore = 5 }, ledger = profile.ledger }
			end)
			expect(scene.service.deposit(1, "ore", 3).ok):toBe(true)
			expect(scene.state().stock.ore):toBe(3)
			local missing = rig()
			missing.skip()
			expect(missing.service.deposit(1, "ore", 3).ok):toBe(false)
			expect(missing.saves()):toBe(0)
			expect(missing.state().stock.ore):toBeNil()
		end)
		it("keeps receipt acknowledgments while a bank read has no state", function()
			local scene = rig()
			scene.profiles[2] =
				{ inventory = {}, ledger = { schemaVersion = 1, pending = {}, unacked = { receipt = "guild" } } }
			scene.unreadable()
			expect(scene.service.join(2).pending):toBe(true)
			expect(scene.profiles[2].ledger.unacked.receipt):toBe("guild")
			expect(scene.saves()):toBe(0)
		end)
	end)
end
