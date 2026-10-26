--!strict

local Module = require("./guildledger")
local Shape = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local current: Verify.Context? = nil
	local function expect(value: unknown): Verify.Expectation
		return assert(current):expect(value)
	end
	local function it(name: string, body: () -> ())
		suite:case(name, function(context)
			current = context
			body()
		end)
	end
	local function describe(_name: string, body: () -> ())
		body()
	end
	type Inventory = { [string]: number }
	type Receipt = Module.Receipt
	type Profile = { gold: number, inventory: Inventory, guildBank: Module.Ledger }
	local settings = {
		maxUnacked = 64,
		withdrawRoom = 48,
		maxPending = 16,
		maxId = 128,
		maxCount = 9999,
		maxTime = 1000000000000,
		healRetentionSec = 40 * 24 * 60 * 60,
		readProfile = function(profile: Profile): Module.ProfileInput
			return { inventory = profile.inventory, guildBank = profile.guildBank }
		end,
		writeProfile = function(profile: Profile, inventory: Inventory?, ledger: Module.Ledger): Profile
			local updated = table.clone(profile)
			if inventory ~= nil then
				updated.inventory = inventory
			end
			updated.guildBank = ledger
			return updated
		end,
	}
	local Ledger = Module.guildledger(settings)

	local REEDS = "material.woodland_shore_reeds"
	local LIMITS = { maxItemCount = 50, maxInventoryEntries = 3 }

	local function profile(reeds: number): Profile
		return { gold = 1, inventory = { [REEDS] = reeds, sword = 1 }, guildBank = Ledger.emptyLedger() }
	end

	local function receipt(id: string, count: number, ownerId: number?): Receipt
		return {
			receiptId = id,
			ownerId = if ownerId ~= nil then ownerId else 7,
			materialId = REEDS,
			count = count,
			issuedAtSec = 1,
		}
	end

	describe("GuildBankLedgerCore deposits", function()
		it("moves deposited goods into a pending entry, then settles or refunds them exactly", function()
			local begun = assert(Ledger.beginDeposit(profile(5), "d1", "guild-1", REEDS, 3, 100, LIMITS))
			expect(begun.inventory[REEDS]):toBe(2)
			expect(begun.guildBank.pending.d1):toEqual({
				fellowshipId = "guild-1",
				materialId = REEDS,
				count = 3,
				startedAtSec = 100,
			})
			expect(begun.gold):toBe(1)
			local settled = assert(Ledger.settle(begun, "d1"))
			expect(settled.inventory[REEDS]):toBe(2)
			expect(settled.guildBank.pending.d1):toBeNil()
			local refunded = assert(Ledger.refund(begun, "d1", LIMITS))
			expect(refunded.inventory[REEDS]):toBe(5)
			expect(refunded.guildBank.pending.d1):toBeNil()
			expect((Ledger.refund(refunded, "d1", LIMITS))):toBe(refunded)
			expect((Ledger.settle(refunded, "d1"))):toBe(refunded)
		end)

		it("refuses a deposit it cannot cover, a reused op id and a seventeenth pending entry", function()
			expect((select(2, Ledger.beginDeposit(profile(2), "d1", "guild-1", REEDS, 3, 100, LIMITS)))):toBe(
				"goods_insufficient"
			)
			local begun = assert(Ledger.beginDeposit(profile(40), "d1", "guild-1", REEDS, 1, 100, LIMITS))
			expect((select(2, Ledger.beginDeposit(begun, "d1", "guild-1", REEDS, 1, 100, LIMITS)))):toBe(
				"operation_conflict"
			)
			local state = profile(40)
			for index = 1, Ledger.MAX_PENDING do
				state = assert(Ledger.beginDeposit(state, "p" .. tostring(index), "guild-1", REEDS, 1, 100, LIMITS))
			end
			expect((select(2, Ledger.beginDeposit(state, "p17", "guild-1", REEDS, 1, 100, LIMITS)))):toBe(
				"pending_full"
			)
		end)
	end)

	describe("GuildBankLedgerCore claims", function()
		it("credits a receipt once by id and refuses another owner's receipt", function()
			local claimed = assert(Ledger.claim(profile(1), receipt("w1", 4), 7, "guild-1", LIMITS))
			expect(claimed.inventory[REEDS]):toBe(5)
			expect((Ledger.claimed(claimed, "w1"))):toBe(true)
			expect((select(2, Ledger.claim(claimed, receipt("w2", 1, 8), 7, "guild-1", LIMITS)))):toBe(
				"receipt_invalid"
			)
		end)

		it("refuses a credit past the stack or a new inventory slot past the limit", function()
			expect((select(2, Ledger.claim(profile(48), receipt("w1", 3), 7, "guild-1", LIMITS)))):toBe(
				"inventory_full"
			)
			local crowded = profile(1)
			crowded.inventory.cloak = 1
			crowded.inventory[REEDS] = nil
			crowded.inventory.band = 1
			expect((select(2, Ledger.claim(crowded, receipt("w1", 1), 7, "guild-1", LIMITS)))):toBe("inventory_full")
		end)

		it("keeps a claimed id until its bank acknowledges it, so no trim can let it credit twice", function()
			local state = profile(0)
			local big = { maxItemCount = 100000, maxInventoryEntries = 10 }
			for index = 1, Ledger.WITHDRAW_ROOM do
				state = assert(
					Ledger.claim(state, receipt("w" .. tostring(index), 1), 7, "guild-" .. tostring(index % 3), big)
				)
			end
			expect((Ledger.canWithdraw(state))):toBe(false)
			expect(state.guildBank.unacked.w1):toBe("guild-1")
			for index = Ledger.WITHDRAW_ROOM + 1, Ledger.MAX_UNACKED do
				state = assert(Ledger.claim(state, receipt("w" .. tostring(index), 1), 7, "guild-1", big))
			end
			expect((select(2, Ledger.claim(state, receipt("w999", 1), 7, "guild-1", big)))):toBe("receipts_unacked")
			expect((Ledger.claim(state, receipt("w1", 1), 7, "guild-1", big))):toBe(state)
			local acked = assert(Ledger.acked(state, { "w1", "w2" }))
			expect((Ledger.claimed(acked, "w1"))):toBe(false)
			expect((Ledger.claimed(acked, "w3"))):toBe(true)
			expect((Ledger.acked(acked, { "w1" }))):toBe(acked)
			local broken = table.clone(acked.guildBank)
			local malformed: Shape.Raw = assert(Shape.raw(broken))
			malformed.unacked = { w1 = 7 }
			expect((Ledger.projectLedger(malformed))):toBeNil()
			broken = table.clone(acked.guildBank)
			broken.pending = { d1 = { fellowshipId = "g", materialId = REEDS, count = 0, startedAtSec = 1 } }
			expect((Ledger.projectLedger(malformed))):toBeNil()
		end)
	end)

	it("uses configured pending, unacknowledged, identity, count and time bounds", function()
		local source = profile(3)
		local cfg: Module.Config<Profile> = table.clone(settings)
		cfg.maxPending = 0
		local _, reason = Module.guildledger(cfg).beginDeposit(source, "d", "g", REEDS, 1, 1, LIMITS)
		expect(reason):toBe("pending_full")
		cfg = table.clone(settings)
		cfg.maxCount = 2
		_, reason = Module.guildledger(cfg).beginDeposit(source, "d", "g", REEDS, 3, 1, LIMITS)
		expect(reason):toBe("request_invalid")
		cfg = table.clone(settings)
		cfg.maxTime = 0
		_, reason = Module.guildledger(cfg).beginDeposit(source, "d", "g", REEDS, 1, 1, LIMITS)
		expect(reason):toBe("request_invalid")
		cfg = table.clone(settings)
		cfg.maxId = 1
		_, reason = Module.guildledger(cfg).beginDeposit(source, "d", "g", REEDS, 1, 1, LIMITS)
		expect(reason):toBe("request_invalid")
		cfg = table.clone(settings)
		cfg.maxUnacked = 0
		_, reason = Module.guildledger(cfg).claim(source, receipt("r", 1), 7, "g", LIMITS)
		expect(reason):toBe("receipts_unacked")
		cfg = table.clone(settings)
		cfg.withdrawRoom = 0
		expect(Module.guildledger(cfg).canWithdraw(source)):toBe(false)
		cfg.healRetentionSec = 1
		expect(Module.guildledger(cfg).HEAL_RETENTION_SEC):toBe(1)
	end)
end
