--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./guildbank")
local Shape = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local settings = {
		maxKinds = 32,
		maxStack = 9999,
		maxReceipts = 256,
		maxReceiptsPerOwner = 16,
		maxLog = 50,
		maxWithdrawals = 512,
		daySec = 24 * 60 * 60,
		memberDailyWithdrawal = 20,
		healRetentionSec = 41 * (24 * 60 * 60),
		receiptTtlSec = 30 * (24 * 60 * 60),
		maxOperations = 2048,
		maxOperationsPerActor = 128,
		maxId = 128,
		maxTime = 1000000000000,
		roles = Shape.freezeDeep({ member = true, steward = true }),
		maxMembers = 64,
		privilegedRoles = { steward = true },
	}
	local Core = Module.guildbank(settings)
	local function settled(result: Module.Result): SettledResult
		return {
			ok = result.ok,
			state = assert(result.state),
			replayed = result.replayed,
			reason = result.reason,
			receipts = assert(result.receipts),
			fence = result.fence,
		}
	end

	local REEDS = "material.woodland_shore_reeds"
	local DAY = 24 * 60 * 60
	local T0 = 1800000000
	type State = Module.State
	type SettledResult = {
		ok: boolean,
		state: Module.State,
		receipts: { Module.Receipt },
		replayed: boolean,
		reason: string?,
		fence: string?,
	}

	local function move(kind: string, opId: string, actorId: number, count: number, role: string?, materialId: string?)
		return {
			kind = kind,
			opId = opId,
			actorId = actorId,
			role = if role ~= nil then role else "member",
			materialId = if materialId ~= nil then materialId else REEDS,
			count = count,
		}
	end

	local function stocked(count: number): State
		return assert(Core.apply(Core.emptyState("guild-1"), move("deposit", "d0", 7, count, "steward"), T0).state)
	end

	describe("GuildBankCore deposits and withdrawals", function()
		it("adds deposits to stock and logs who moved what", function()
			local state = stocked(30)
			local more = settled(Core.apply(state, move("deposit", "d1", 8, 5), T0 + 1))
			expect(more.ok):toBe(true)
			expect(more.state.stock[REEDS]):toBe(35)
			expect(more.state.log[2]):toEqual({
				atSec = T0 + 1,
				actorId = 8,
				kind = "deposit",
				materialId = REEDS,
				count = 5,
			})
			expect(#more.receipts):toBe(0)
		end)

		it("withdraws into a receipt the member claims once, then acks away", function()
			local state = stocked(30)
			local taken = settled(Core.apply(state, move("withdraw", "w1", 8, 4), T0 + 1))
			expect(taken.ok):toBe(true)
			expect(taken.state.stock[REEDS]):toBe(26)
			expect((assert(taken.receipts))[1]):toEqual({
				receiptId = "w1",
				ownerId = 8,
				materialId = REEDS,
				count = 4,
				issuedAtSec = T0 + 1,
			})
			expect(#(assert(Core.receiptsFor(taken.state, 8)))):toBe(1)
			expect(#(assert(Core.receiptsFor(taken.state, 9)))):toBe(0)
			local foreignAck = settled(
				Core.apply(taken.state, { kind = "ack", opId = "a0", actorId = 9, receiptIds = { "w1" } }, T0 + 2)
			)
			expect(#foreignAck.state.receipts):toBe(1)
			local acked = settled(
				Core.apply(taken.state, { kind = "ack", opId = "a1", actorId = 8, receiptIds = { "w1" } }, T0 + 2)
			)
			expect(#acked.state.receipts):toBe(0)
			local emptied = settled(Core.apply(taken.state, move("withdraw", "w2", 7, 26, "steward"), T0 + 3))
			expect(emptied.state.stock[REEDS]):toBeNil()
		end)

		it("refuses a withdrawal the stock cannot cover", function()
			expect(Core.apply(stocked(3), move("withdraw", "w1", 8, 4), T0 + 1).reason):toBe("stock_insufficient")
		end)

		it("limits a member to 20 units per rolling day and leaves the steward unlimited", function()
			local state = stocked(100)
			state = assert(Core.apply(state, move("withdraw", "w1", 8, 15), T0 + 1).state)
			expect(Core.apply(state, move("withdraw", "w2", 8, 6), T0 + 2).reason):toBe("withdrawal_limit")
			state = assert(Core.apply(state, move("withdraw", "w3", 8, 5), T0 + 2).state)
			expect(Core.apply(state, move("withdraw", "w4", 9, 20), T0 + 3).ok):toBe(true)
			expect(Core.apply(state, move("withdraw", "w5", 7, 60, "steward"), T0 + 3).ok):toBe(true)
			expect(Core.apply(state, move("withdraw", "w6", 8, 1), T0 + DAY).reason):toBe("withdrawal_limit")
			expect(Core.apply(state, move("withdraw", "w7", 8, 15), T0 + DAY + 1).ok):toBe(true)
		end)

		it("refuses more than 16 unclaimed receipts for one member until they ack", function()
			local state = stocked(100)
			for index = 1, 16 do
				state = assert(
					Core.apply(state, move("withdraw", "w" .. tostring(index), 7, 1, "steward"), T0 + index).state
				)
			end
			expect(Core.apply(state, move("withdraw", "w17", 7, 1, "steward"), T0 + 20).reason):toBe(
				"receipts_unclaimed"
			)
			local ids: { string } = {}
			for _, receipt in state.receipts do
				table.insert(ids, receipt.receiptId)
			end
			state =
				assert(Core.apply(state, { kind = "ack", opId = "a1", actorId = 7, receiptIds = ids }, T0 + 21).state)
			expect(Core.apply(state, move("withdraw", "w17", 7, 1, "steward"), T0 + 22).ok):toBe(true)
		end)

		it("caps material kinds and the stack per kind", function()
			local state = Core.emptyState("guild-1")
			for index = 1, Core.MAX_KINDS do
				state = Core.apply(
					state,
					move("deposit", "k" .. tostring(index), 7, 1, "member", "m" .. tostring(index)),
					T0
				).state
			end
			expect(Core.apply(state, move("deposit", "k33", 7, 1, "member", "m33"), T0).reason):toBe("bank_full")
			expect(Core.apply(state, move("deposit", "k34", 7, 1, "member", "m1"), T0).ok):toBe(true)
			expect(Core.apply(state, move("deposit", "k35", 7, Core.MAX_STACK, "member", "m1"), T0).reason):toBe(
				"bank_full"
			)
		end)
	end)

	describe("GuildBankCore replay, void fence and clock", function()
		it("replays the same op, refuses a changed reuse, and refuses a role it does not know", function()
			local state = stocked(30)
			local taken = settled(Core.apply(state, move("withdraw", "w1", 8, 4), T0 + 1))
			local replay = settled(Core.apply(taken.state, move("withdraw", "w1", 8, 4), T0 + 2))
			expect(replay.replayed):toBe(true)
			expect(replay.state.stock[REEDS]):toBe(26)
			expect(Core.apply(taken.state, move("withdraw", "w1", 8, 5), T0 + 2).reason):toBe("operation_conflict")
			expect(Core.apply(state, move("withdraw", "w9", 8, 1, "guest"), T0 + 1).reason):toBe("command_invalid")
		end)

		it("fences a voided op so its late write never lands, and reports a known op as known", function()
			local state = stocked(30)
			local voided = Core.apply(state, { kind = "void", opId = "d9" }, T0 + 1)
			expect(voided.fence):toBe("voided")
			expect((Core.knowsOperation(voided.state, "d9"))):toBe(true)
			expect(Core.apply(voided.state, move("deposit", "d9", 8, 5), T0 + 2).reason):toBe("operation_void")
			expect(Core.apply(voided.state, { kind = "void", opId = "d9" }, T0 + 3).fence):toBe("voided")
			expect(Core.apply(state, { kind = "void", opId = "d0" }, T0 + 3).fence):toBe("known")
		end)

		it("refuses a regressed clock after checking replays", function()
			local state = Core.apply(stocked(30), move("deposit", "d1", 8, 1), T0 + 100).state
			expect(Core.apply(state, move("deposit", "d1", 8, 1), T0 + 50).replayed):toBe(true)
			expect(Core.apply(state, move("deposit", "d2", 8, 1), T0 + 50).reason):toBe("clock_regressed")
		end)

		it("keeps deposit and void ids past the heal window and every other id one day", function()
			local state = stocked(100)
			state = assert(Core.apply(state, move("withdraw", "w1", 7, 1, "steward"), T0 + 1).state)
			state = assert(Core.apply(state, { kind = "void", opId = "v1" }, T0 + 2).state)
			local nextDay = Core.apply(state, move("deposit", "d1", 8, 1), T0 + Core.DAY_SEC + 2).state
			expect((Core.knowsOperation(nextDay, "w1"))):toBe(false)
			expect((Core.knowsOperation(nextDay, "d0"))):toBe(true)
			expect((Core.knowsOperation(nextDay, "v1"))):toBe(true)
			local healEnd = Core.apply(nextDay, move("deposit", "d2", 8, 1), T0 + Core.HEAL_RETENTION_SEC - 1).state
			expect((Core.knowsOperation(healEnd, "d0"))):toBe(true)
			local past = Core.apply(healEnd, move("deposit", "d3", 8, 1), T0 + Core.HEAL_RETENTION_SEC + 3).state
			expect((Core.knowsOperation(past, "d0"))):toBe(false)
			expect((Core.knowsOperation(past, "v1"))):toBe(false)
			expect((Core.knowsOperation(past, "d2"))):toBe(true)
		end)

		it("lets an active guild move 60 times a day for the whole heal window without saturating", function()
			local state = stocked(100)
			for day = 0, 45 do
				for move_ = 1, 30 do
					local at = T0 + day * Core.DAY_SEC + move_ * 60
					local id = tostring(day) .. ":" .. tostring(move_)
					local deposited = Core.apply(state, move("deposit", "d" .. id, 7, 1, "steward"), at)
					assert(deposited.ok, deposited.reason)
					local taken = Core.apply(deposited.state, move("withdraw", "w" .. id, 7, 1, "steward"), at + 1)
					assert(taken.ok, taken.reason)
					state = assert(
						Core.apply(
							taken.state,
							{ kind = "ack", opId = "a" .. id, actorId = 7, receiptIds = { "w" .. id } },
							at + 2
						).state
					)
				end
			end
			expect((#state.operationOrder < 2048)):toBe(true)
		end)

		it("returns a non-member's receipt to stock after 30 days and never a member's", function()
			local state = stocked(30)
			state = assert(Core.apply(state, move("withdraw", "w1", 8, 4), T0 + 1).state)
			state = assert(Core.apply(state, move("withdraw", "w2", 9, 3), T0 + 1).state)
			local early =
				Core.apply(state, { kind = "expire", opId = "e1", memberIds = { 7, 9 } }, T0 + Core.RECEIPT_TTL_SEC)
			expect(early.reason):toBe("nothing_expired")
			local expired = settled(
				Core.apply(state, { kind = "expire", opId = "e2", memberIds = { 7, 9 } }, T0 + Core.RECEIPT_TTL_SEC + 1)
			)
			expect(expired.ok):toBe(true)
			expect(expired.state.stock[REEDS]):toBe(27)
			expect(#expired.state.receipts):toBe(1)
			expect(expired.state.receipts[1].ownerId):toBe(9)
			expect(expired.state.log[#expired.state.log].kind):toBe("return")
		end)

		it("refuses a malformed stored bank", function()
			local state = stocked(30)
			local broken = assert(Shape.raw(table.clone(state)))
			broken.stock = { [REEDS] = 0 }
			expect((Core.projectState(broken))):toBeNil()
			broken = assert(Shape.raw(table.clone(state)))
			local operations: Shape.Raw = assert(Shape.raw(state.operations))
			operations.ghost = { fingerprint = "0000000000000000", atSec = 1, actorId = 1 }
			broken.operations = operations
			expect((Core.projectState(broken))):toBeNil()
			expect((Core.projectState(state) ~= nil)):toBe(true)
		end)
	end)

	it("uses configured storage, receipt, operation and withdrawal bounds", function()
		local source = stocked(30)
		local changes: { (Module.Config) -> () } = {
			function(cfg)
				cfg.maxStack = 1
			end,
			function(cfg)
				cfg.maxLog = 0
			end,
			function(cfg)
				cfg.maxOperations = 0
			end,
			function(cfg)
				cfg.maxId = 1
			end,
			function(cfg)
				cfg.maxTime = 0
			end,
		}
		for _, change in changes do
			local cfg: Module.Config = table.clone(settings)
			change(cfg)
			expect(Module.guildbank(cfg).projectState(source)):toBeNil()
		end
		local cfg: Module.Config = table.clone(settings)
		cfg.maxKinds = 1
		expect(Module.guildbank(cfg).apply(source, move("deposit", "other", 8, 1, nil, "other"), T0).reason):toBe(
			"bank_full"
		)
		cfg = table.clone(settings)
		cfg.maxReceipts = 0
		expect(Module.guildbank(cfg).apply(source, move("withdraw", "w", 8, 1), T0).reason):toBe("receipts_full")
		cfg = table.clone(settings)
		cfg.maxReceiptsPerOwner = 0
		expect(Module.guildbank(cfg).apply(source, move("withdraw", "w", 8, 1), T0).reason):toBe("receipts_unclaimed")
		cfg = table.clone(settings)
		cfg.maxWithdrawals = 0
		expect(Module.guildbank(cfg).apply(source, move("withdraw", "w", 8, 1), T0).reason):toBe("bank_saturated")
		cfg = table.clone(settings)
		cfg.maxOperationsPerActor = 0
		expect(Module.guildbank(cfg).apply(source, move("deposit", "d", 8, 1), T0).reason):toBe("actor_saturated")
		cfg = table.clone(settings)
		cfg.memberDailyWithdrawal = 1
		expect(Module.guildbank(cfg).apply(source, move("withdraw", "w", 8, 2), T0).reason):toBe("withdrawal_limit")
		cfg.maxMembers = 1
		expect(Module.guildbank(cfg).apply(source, { kind = "expire", opId = "e", memberIds = { 7, 8 } }, T0).reason):toBe(
			"command_invalid"
		)
		cfg = table.clone(settings)
		cfg.roles, cfg.privilegedRoles = { keeper = true }, { keeper = true }
		cfg.memberDailyWithdrawal = 1
		expect(Module.guildbank(cfg).apply(source, move("withdraw", "w", 8, 2, "keeper"), T0).ok):toBe(true)
		cfg = table.clone(settings)
		cfg.healRetentionSec = 1
		local held = assert(Module.guildbank(cfg).apply(source, move("deposit", "d", 8, 1), T0).state)
		expect(held.operations.d.keepUntilSec):toBe(T0 + 1)
		cfg.daySec = 1
		local taken = assert(Module.guildbank(cfg).apply(source, move("withdraw", "w", 8, 1), T0).state)
		expect(taken.operations.w.keepUntilSec):toBe(T0 + 1)
		cfg.receiptTtlSec = 1
		expect(Module.guildbank(cfg).apply(taken, { kind = "expire", opId = "e", memberIds = {} }, T0 + 1).ok):toBe(
			true
		)
	end)
end
