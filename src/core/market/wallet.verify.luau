--!strict

local Wallets = require("./wallet")
local settings: Wallets.Config = {
	claimedWindow = 512,
	healRetentionSec = 40 * 24 * 60 * 60,
	maxPending = 32,
	maxId = 128,
	maxCount = 1000000000,
	maxCoin = 1000000000000,
	maxTime = 1000000000000,
	realms = { north = true, south = true, east = true },
}
local Wallet = Wallets.wallet(settings)
local Value = require("../internal/value")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type State = Wallets.State
type Result = Wallets.Result
type Ledger = Wallets.Ledger

return function(suite: Verify.Harness)
	do
		suite:case("projects an empty wallet state", function(context)
			local state = Wallet.emptyState(7, 100, { ore = 5 })
			context:expect((state ~= nil)):toBe(true)
			context:expect(assert(state).userId):toBe(7)
			context:expect(assert(state).coin):toBe(100)
			context:expect(assert(state).goods.ore):toBe(5)
		end)

		suite:case("refuses a zero or negative goods count and a bad userId", function(context)
			context:expect((Wallet.emptyState(7, 100, { ore = 0 }))):toBeNil()
			context:expect((Wallet.emptyState(7, 100, { ore = -1 }))):toBeNil()
			context:expect((Wallet.emptyState(0, 100, { ore = 5 }))):toBeNil()
			context:expect((Wallet.emptyState(-1, 100, { ore = 5 }))):toBeNil()
		end)
	end

	do
		local base = Wallet.emptyState(7, 100, { ore = 5 })

		suite:case("debits goods and records a pending consign", function(context)
			local result = Wallet.beginConsign(base, "op1", "north", "ore", 3, 10)
			context:expect(result.ok):toBe(true)
			context:expect(result.replayed):toBe(false)
			context:expect(assert(result.state).goods.ore):toBe(2)
			context:expect(assert(result.state).pending.op1.kind):toBe("consign")
			context:expect(assert(result.state).pending.op1.count):toBe(3)
		end)

		suite:case("replays an exact repeat of the same opId and body", function(context)
			local first = Wallet.beginConsign(base, "op1", "north", "ore", 3, 10)
			local again = Wallet.beginConsign(first.state, "op1", "north", "ore", 3, 10)
			context:expect(again.ok):toBe(true)
			context:expect(again.replayed):toBe(true)
			context:expect(assert(again.state).goods.ore):toBe(2)
		end)

		suite:case("refuses the same opId with a different count as operation_conflict", function(context)
			local first = Wallet.beginConsign(base, "op1", "north", "ore", 3, 10)
			local conflict = Wallet.beginConsign(first.state, "op1", "north", "ore", 2, 10)
			context:expect(conflict.ok):toBe(false)
			context:expect(conflict.reason):toBe("operation_conflict")
		end)

		suite:case("refuses insufficient goods", function(context)
			local short = Wallet.beginConsign(base, "op2", "north", "ore", 6, 10)
			context:expect(short.ok):toBe(false)
			context:expect(short.reason):toBe("goods_insufficient")
		end)

		suite:case("refuses a foreign realm id", function(context)
			local foreign = Wallet.beginConsign(base, "op3", "contested", "ore", 1, 10)
			context:expect(foreign.ok):toBe(false)
			context:expect(foreign.reason):toBe("request_invalid")
		end)
	end

	do
		local base = Wallet.emptyState(7, 100, { ore = 5 })

		suite:case("debits coin into a hold", function(context)
			local buy = Wallet.beginBuy(base, "b1", "south", "ore", 40, 10)
			context:expect(buy.ok):toBe(true)
			context:expect(assert(buy.state).coin):toBe(60)
			context:expect(assert(buy.state).pending.b1.kind):toBe("buy")
			context:expect(assert(buy.state).pending.b1.hold):toBe(40)
		end)

		suite:case("refuses insufficient coin", function(context)
			local poor = Wallet.beginBuy(base, "b2", "south", "ore", 1000, 10)
			context:expect(poor.ok):toBe(false)
			context:expect(poor.reason):toBe("coin_insufficient")
		end)
	end

	do
		suite:case(
			"keeps both operation kinds bound to a book and refunds without mutating their snapshots",
			function(context)
				for _, begin in { Wallet.beginConsign, Wallet.beginBuy } do
					local base = Wallet.emptyState(7, 100, { ore = 5 })
					local begun = begin(base, "op", "north", "ore", 2, 10, "book-a")
					local state = assert(begun.state)
					local replay = begin(state, "op", "north", "ore", 2, 20, "book-a")
					context:expect(replay.replayed):toBe(true)
					context:expect(assert(replay.state).pending.op.startedAtSec):toBe(10)
					context
						:expect(begin(state, "op", "north", "ore", 2, 20, "book-b").reason)
						:toBe("operation_conflict")
					local healed = assert(Wallet.heal(state, "op", false, 20).state)
					local refunded = assert(Wallet.refund(state, "op").state)
					context:expect(healed):toEqual(refunded)
					context:expect(healed.coin):toBe(100)
					context:expect(healed.goods.ore):toBe(5)
					context:expect(healed.pending.op):toBeNil()
					context:expect(state.pending.op.bookId):toBe("book-a")
					context:expect((healed.pending == state.pending)):toBe(false)
					context:expect((healed.goods == state.goods)):toBe(false)
					context:expect((table.isfrozen(healed))):toBe(true)
					context:expect((table.isfrozen(healed.pending))):toBe(true)
				end
			end
		)

		suite:case("returns consign goods exactly once", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local consigned = Wallet.beginConsign(base, "op1", "north", "ore", 3, 10)
			local refunded = Wallet.refund(consigned.state, "op1")
			context:expect(refunded.ok):toBe(true)
			context:expect(refunded.replayed):toBe(false)
			context:expect(assert(refunded.state).goods.ore):toBe(5)
			context:expect(assert(refunded.state).pending.op1):toBeNil()
			local again = Wallet.refund(refunded.state, "op1")
			context:expect(again.replayed):toBe(true)
			context:expect(assert(again.state).goods.ore):toBe(5)
		end)

		suite:case("returns a buy hold exactly once", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local buy = Wallet.beginBuy(base, "b1", "south", "ore", 40, 10)
			local refunded = Wallet.refund(buy.state, "b1")
			context:expect(refunded.ok):toBe(true)
			context:expect(assert(refunded.state).coin):toBe(100)
			local again = Wallet.refund(refunded.state, "b1")
			context:expect(again.replayed):toBe(true)
			context:expect(assert(again.state).coin):toBe(100)
		end)
	end

	do
		suite:case("removes the pending consign without returning goods", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local consigned = Wallet.beginConsign(base, "op1", "north", "ore", 3, 10)
			local settled = Wallet.settleConsign(consigned.state, "op1")
			context:expect(settled.ok):toBe(true)
			context:expect(assert(settled.state).pending.op1):toBeNil()
			context:expect(assert(settled.state).goods.ore):toBe(2)
		end)

		suite:case("refuses to settle a buy op as operation_conflict", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local buy = Wallet.beginBuy(base, "b1", "south", "ore", 40, 10)
			local conflict = Wallet.settleConsign(buy.state, "b1")
			context:expect(conflict.ok):toBe(false)
			context:expect(conflict.reason):toBe("operation_conflict")
		end)
	end

	do
		suite:case("credits proceeds coin once and replays a second claim of the same receipt", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local receipt = {
				receiptId = "r1",
				ownerId = 7,
				kind = "proceeds",
				opId = "op1",
				coin = 50,
				goods = 0,
				issuedAtSec = 20,
			}
			local claimed = Wallet.claim(base, receipt, "ore")
			context:expect(claimed.ok):toBe(true)
			context:expect(claimed.replayed):toBe(false)
			context:expect(assert(claimed.state).coin):toBe(150)
			local again = Wallet.claim(claimed.state, receipt, "ore")
			context:expect(again.replayed):toBe(true)
			context:expect(assert(again.state).coin):toBe(150)
		end)

		suite:case("adds goods on a return receipt", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local receipt =
				{ receiptId = "r2", ownerId = 7, kind = "return", opId = "op1", coin = 0, goods = 4, issuedAtSec = 21 }
			local returned = Wallet.claim(base, receipt, "ore")
			context:expect(returned.ok):toBe(true)
			context:expect(assert(returned.state).goods.ore):toBe(9)
		end)

		suite:case("credits a purchase from the matching pending buy and removes it", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local buy = Wallet.beginBuy(base, "b1", "south", "ore", 40, 10)
			local receipt = {
				receiptId = "r3",
				ownerId = 7,
				kind = "purchase",
				opId = "b1",
				coin = 10,
				goods = 3,
				issuedAtSec = 22,
			}
			local purchased = Wallet.claim(buy.state, receipt, "ore")
			context:expect(purchased.ok):toBe(true)
			context:expect(assert(purchased.state).coin):toBe(90)
			context:expect(assert(purchased.state).goods.ore):toBe(8)
			context:expect(assert(purchased.state).pending.b1):toBeNil()
		end)

		suite:case("refuses a purchase receipt whose coin exceeds the hold", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local buy = Wallet.beginBuy(base, "b1", "south", "ore", 40, 10)
			local receipt = {
				receiptId = "r4",
				ownerId = 7,
				kind = "purchase",
				opId = "b1",
				coin = 50,
				goods = 3,
				issuedAtSec = 22,
			}
			local badCoin = Wallet.claim(buy.state, receipt, "ore")
			context:expect(badCoin.ok):toBe(false)
			context:expect(badCoin.reason):toBe("receipt_invalid")
		end)

		suite:case("refuses a purchase with no matching pending buy", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local receipt = {
				receiptId = "r5",
				ownerId = 7,
				kind = "purchase",
				opId = "nope",
				coin = 0,
				goods = 1,
				issuedAtSec = 22,
			}
			local noPending = Wallet.claim(base, receipt, "ore")
			context:expect(noPending.ok):toBe(false)
			context:expect(noPending.reason):toBe("purchase_unmatched")
		end)

		suite:case("refuses a receipt whose ownerId is another user", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local receipt = {
				receiptId = "r6",
				ownerId = 99,
				kind = "proceeds",
				opId = "op1",
				coin = 1,
				goods = 0,
				issuedAtSec = 1,
			}
			local notOwned = Wallet.claim(base, receipt, "ore")
			context:expect(notOwned.ok):toBe(false)
			context:expect(notOwned.reason):toBe("receipt_not_owned")
		end)
	end

	do
		suite:case("settles a pending consign the book knows about, keeping goods debited", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local consigned = Wallet.beginConsign(base, "h1", "north", "ore", 2, 10)
			local healed = Wallet.heal(consigned.state, "h1", true, 20)
			context:expect(healed.ok):toBe(true)
			context:expect(healed.replayed):toBe(false)
			context:expect(assert(healed.state).pending.h1):toBeNil()
			context:expect(assert(healed.state).goods.ore):toBe(3)
		end)

		suite:case("leaves a pending buy the book knows about pending, as a replay", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local bought = Wallet.beginBuy(base, "h2", "south", "ore", 40, 10)
			local healed = Wallet.heal(bought.state, "h2", true, 20)
			context:expect(healed.ok):toBe(true)
			context:expect(healed.replayed):toBe(true)
			context:expect((assert(healed.state).pending.h2 ~= nil)):toBe(true)
		end)

		suite:case("refunds a pending op the book does not know about while it is still young", function(context)
			local base = Wallet.emptyState(7, 100, { ore = 5 })
			local consigned = Wallet.beginConsign(base, "h1", "north", "ore", 2, 10)
			local healed = Wallet.heal(consigned.state, "h1", false, 15)
			context:expect(healed.ok):toBe(true)
			context:expect(assert(healed.state).pending.h1):toBeNil()
			context:expect(assert(healed.state).goods.ore):toBe(5)
		end)

		suite:case(
			"refuses heal_ambiguous once the op passes retention and leaves the state unchanged",
			function(context)
				local base = Wallet.emptyState(7, 100, { ore = 5 })
				local consigned = Wallet.beginConsign(base, "h1", "north", "ore", 2, 10)
				local healed = Wallet.heal(consigned.state, "h1", false, 10 + settings.healRetentionSec)
				context:expect(healed.ok):toBe(false)
				context:expect(healed.reason):toBe("heal_ambiguous")
				context:expect(healed.state):toBeNil()
				context:expect((assert(consigned.state).pending.h1 ~= nil)):toBe(true)
			end
		)
	end

	do
		suite:case("refuses more than 32 pending ops with pending_full", function(context)
			local state: State? = Wallet.emptyState(1, 1000, {})
			for index = 1, 32 do
				local result = Wallet.beginBuy(state, "op" .. tostring(index), "north", "ore", 1, 10)
				context:expect(result.ok):toBe(true)
				state = result.state
			end
			local full = Wallet.beginBuy(state, "op33", "north", "ore", 1, 10)
			context:expect(full.ok):toBe(false)
			context:expect(full.reason):toBe("pending_full")
		end)
	end

	do
		suite:case("projects a fresh deeply frozen ledger while leaving the stored input mutable", function(context)
			local raw = {
				schemaVersion = 1,
				pending = {
					op = {
						kind = "buy",
						realmId = "north",
						materialId = "ore",
						count = 0,
						hold = 40,
						startedAtSec = 10,
					},
				},
				claimedOrder = { "receipt" },
			}
			local projected = assert(Wallet.projectLedger(7, raw))
			context:expect((projected.pending == raw.pending)):toBe(false)
			context:expect((projected.pending.op == raw.pending.op)):toBe(false)
			context:expect((projected.claimedOrder == raw.claimedOrder)):toBe(false)
			context:expect((table.isfrozen(projected))):toBe(true)
			context:expect((table.isfrozen(projected.pending))):toBe(true)
			context:expect((table.isfrozen(projected.pending.op))):toBe(true)
			context:expect((table.isfrozen(projected.claimedOrder))):toBe(true)
			context:expect((table.isfrozen(raw.pending.op))):toBe(false)
			raw.pending.op.hold = 1
			raw.claimedOrder[1] = "changed"
			context:expect(projected.pending.op.hold):toBe(40)
			context:expect(projected.claimedOrder[1]):toBe("receipt")
		end)

		suite:case("splits a wallet into the ledger the profile stores and composes it back", function(context)
			local begun: Result =
				Wallet.beginConsign(Wallet.emptyState(7, 50, { ore = 5 }), "op1", "north", "ore", 2, 10)
			local ledger: Ledger? = Wallet.ledgerOf(begun.state)
			context:expect(assert(ledger).pending.op1.count):toBe(2)
			context:expect(assert(Value.raw(ledger)).coin):toBeNil()
			local again: State? = Wallet.compose(7, 50, { ore = 3 }, ledger)
			context:expect(assert(again).pending.op1.count):toBe(2)
			context:expect(assert(again).coin):toBe(50)
		end)

		suite:case("accepts the empty ledger and refuses a malformed stored ledger", function(context)
			context:expect((Wallet.projectLedger(7, Wallet.emptyLedger()) ~= nil)):toBe(true)
			context:expect((Wallet.projectLedger(7, { schemaVersion = 2, pending = {}, claimedOrder = {} }))):toBeNil()
			context
				:expect((Wallet.projectLedger(7, { schemaVersion = 1, pending = { op = {} }, claimedOrder = {} })))
				:toBeNil()
			context:expect((Wallet.projectLedger(7, nil))):toBeNil()
			context
				:expect((Wallet.projectLedger(7, { schemaVersion = 1, pending = {}, claimedOrder = {}, coin = 5 })))
				:toBeNil()
		end)
	end

	do
		suite:case("sells goods for floor coin and buys goods for ceiling coin in one step", function(context)
			local state = Wallet.emptyState(7, 10, { ore = 3 })
			local sold: Result = Wallet.npcTrade(state, "sell", "ore", 3, 4)
			context:expect(sold.ok):toBe(true)
			context:expect(assert(sold.state).coin):toBe(22)
			context:expect(assert(sold.state).goods.ore):toBeNil()
			local bought: Result = Wallet.npcTrade(sold.state, "buy", "ore", 2, 11)
			context:expect(bought.ok):toBe(true)
			context:expect(assert(bought.state).coin):toBe(0)
			context:expect(assert(bought.state).goods.ore):toBe(2)
			context:expect((next(assert(bought.state).pending))):toBeNil()
		end)

		suite:case("refuses missing goods, missing coin, and an unknown side without a state", function(context)
			local state = Wallet.emptyState(7, 10, { ore = 1 })
			context:expect(Wallet.npcTrade(state, "sell", "ore", 2, 4).reason):toBe("goods_insufficient")
			context:expect(Wallet.npcTrade(state, "buy", "ore", 1, 11).reason):toBe("coin_insufficient")
			context:expect(Wallet.npcTrade(state, "gift", "ore", 1, 1).reason):toBe("request_invalid")
			context:expect(Wallet.npcTrade(state, "buy", "ore", 1, 0).reason):toBe("request_invalid")
			context:expect(Wallet.npcTrade(state, "buy", "ore", 1, 10).ok):toBe(true)
		end)
	end

	suite:case("uses configured realms, identity, currency, goods, time and pending limits", function(context)
		local cfg: Wallets.Config = {
			claimedWindow = 1,
			healRetentionSec = 3,
			maxPending = 1,
			maxId = 2,
			maxCount = 3,
			maxCoin = 10,
			maxTime = 10,
			realms = { zone = true },
		}
		local wallet = Wallets.wallet(cfg)
		local state = assert(wallet.emptyState(10, 10, { ab = 3 }))
		context:expect(wallet.emptyState(11, 10, {})):toBeNil()
		context:expect(wallet.emptyState(10, 11, {})):toBeNil()
		context:expect(wallet.emptyState(10, 10, { ab = 4 })):toBeNil()
		context:expect(wallet.emptyState(10, 10, { abc = 1 })):toBeNil()
		context:expect(wallet.beginBuy(state, "abc", "zone", "ab", 1, 7).reason):toBe("request_invalid")
		context:expect(wallet.beginBuy(state, "a", "north", "ab", 1, 7).reason):toBe("request_invalid")
		context:expect(wallet.beginBuy(state, "a", "zone", "abc", 1, 7).reason):toBe("request_invalid")
		context:expect(wallet.beginBuy(state, "a", "zone", "ab", 1, 7, "abc").reason):toBe("request_invalid")
		context:expect(wallet.beginBuy(state, "a", "zone", "ab", 11, 7).reason):toBe("request_invalid")
		context:expect(wallet.beginConsign(state, "a", "zone", "ab", 4, 7).reason):toBe("request_invalid")
		context:expect(wallet.beginBuy(state, "a", "zone", "ab", 1, 11).reason):toBe("request_invalid")
		local begun = wallet.beginBuy(state, "a", "zone", "ab", 1, 7, "bk")
		context:expect(begun.ok):toBe(true)
		context:expect(wallet.beginBuy(begun.state, "b", "zone", "ab", 1, 7).reason):toBe("pending_full")
		context:expect(wallet.heal(begun.state, "a", false, 9).ok):toBe(true)
		context:expect(wallet.heal(begun.state, "a", false, 10).reason):toBe("heal_ambiguous")
		local function claim(previous: unknown, id: string): Wallets.Result
			return wallet.claim(
				previous,
				{ receiptId = id, ownerId = 10, kind = "proceeds", opId = "a", coin = 0, goods = 0, issuedAtSec = 0 },
				"ab"
			)
		end
		local first = claim(state, "r1")
		context:expect(claim(first.state, "r1").replayed):toBe(true)
		local second = claim(first.state, "r2")
		context:expect(assert(second.state).claimedOrder):toEqual({ "r2" })
		context:expect(claim(second.state, "r1").replayed):toBe(false)
		context:expect(wallet.npcTrade(state, "sell", "ab", 4, 1).reason):toBe("request_invalid")
		context:expect(wallet.npcTrade(state, "sell", "ab", 1, 1).reason):toBe("coin_overflow")
	end)
end
