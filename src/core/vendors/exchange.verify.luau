--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Exchange = require("./exchange")
local Scene = require("../../test-scene/vendor")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("exchange", function()
		it("purchases and sales exchange coin and holdings without mutating inputs", function()
			local scene = Scene.new()
			local original = { gold = 20, inventory = { food = 1 } }
			local bought, decision = scene.law.buy(original, scene.vendor, "food", 3, nil)
			expect(decision):toEqual({ ok = true, itemId = "food", quantity = 3, price = 12, gold = 8 })
			expect(bought.inventory.food):toBe(4)
			expect(original):toEqual({ gold = 20, inventory = { food = 1 } })
			local sold, sale = scene.law.sell(bought, scene.vendor, "food", 4)
			expect(sale.action):toBe("sell")
			expect(sold.gold):toBe(16)
			expect(sold.inventory.food):toBeNil()
			expect(bought.inventory.food):toBe(4)
		end)
		it("refusals preserve identity and keep legacy validation precedence", function()
			local scene = Scene.new()
			local account: Exchange.Account = { gold = 1, inventory = {} }
			local refused, decision = scene.law.buy(account, scene.vendor, "food", 1, nil)
			expect(refused):toBe(account)
			expect(decision.reason):toBe("insufficient_gold")
			local invalid: { unknown } =
				{ false, {}, "1", 0, -1, 1.5, 11, math.huge, -math.huge, math.huge - math.huge }
			for _, count in invalid do
				expect(select(2, scene.law.buy(account, scene.vendor, "food", count, nil)).reason):toBe(
					"invalid_quantity"
				)
				expect(select(2, scene.law.sell(account, scene.vendor, "food", count)).reason):toBe("invalid_quantity")
			end
			expect(select(2, scene.law.buy(account, scene.vendor, false, 0, nil)).reason):toBe("invalid_item")
			expect(select(2, scene.law.buy(account, scene.vendor, "prize", 1, nil)).reason):toBe("not_sold")
			expect(select(2, scene.law.sell(account, scene.vendor, "prize", 1)).reason):toBe("not_sellable")
			expect(select(2, scene.law.sell(account, scene.vendor, "tool", 1)).reason):toBe("not_held")
		end)
		it("stock is shared across senders and debits only after a successful purchase", function()
			local scene = Scene.new()
			local state = Exchange.empty()
			local poor: Exchange.Account = { gold = 0, inventory = {} }
			local unchanged = scene.law.buyStock(state, poor, scene.vendor, "food", 2, nil)
			expect(unchanged):toBe(state)
			local account: Exchange.Account = { gold = 100, inventory = {} }
			local sold, first, decision = scene.law.buyStock(state, account, scene.vendor, "food", 2, nil)
			expect(decision.ok):toBe(true)
			expect(sold.stock.merchant.food):toBe(1)
			expect((next(state.stock))):toBeNil()
			local exhausted, denied, refusal = scene.law.buyStock(sold, account, scene.vendor, "food", 2, nil)
			expect(exhausted):toBe(sold)
			expect(denied):toBe(account)
			expect(refusal.reason):toBe("out_of_stock")
			local final, _, bought = scene.law.buyStock(sold, first, scene.vendor, "food", 1, nil)
			expect(bought.ok):toBe(true)
			expect(final.stock.merchant.food):toBe(0)
			expect(select(3, scene.law.buyStock(final, account, scene.vendor, "food", 1, nil)).reason):toBe(
				"out_of_stock"
			)
			expect(select(3, scene.law.buyStock(final, account, scene.vendor, "tool", 1, nil)).ok):toBe(true)
		end)
		it("buyback uses the sale price, isolates owners and cannot replay consumed receipts", function()
			local scene = Scene.new()
			local original: Exchange.Account = { gold = 0, inventory = { food = 3 } }
			local state, sold =
				scene.law.sellBack(Exchange.empty(), original, scene.vendor, "first", "food", 3, scene.clock.clock())
			expect(sold.gold):toBe(6)
			expect(select(3, scene.law.buyBack(state, sold, "other", 1, 1, nil, 0)).reason):toBe("unknown_buyback")
			local partial, account, bought = scene.law.buyBack(state, sold, "first", 1, 1, nil, 0)
			expect(bought.price):toBe(2)
			expect(partial.buyback.first[1].quantity):toBe(2)
			expect(state.buyback.first[1].quantity):toBe(3)
			local final, restored = scene.law.buyBack(partial, account, "first", 1, 2, nil, 0)
			expect(restored):toEqual(original)
			expect(select(3, scene.law.buyBack(final, restored, "first", 1, 1, nil, 0)).reason):toBe("unknown_buyback")
		end)
		it("buyback retains receipts on refusal and expires on the host clock boundary", function()
			local scene = Scene.new()
			local original: Exchange.Account = { gold = 0, inventory = { food = 3 } }
			local state, account = scene.law.sellBack(Exchange.empty(), original, scene.vendor, "owner", "food", 1, 0)
			local unchanged, _, decision = scene.law.buyBack(state, { gold = 0, inventory = {} }, "owner", 1, 1, nil, 0)
			expect(unchanged):toBe(state)
			expect(decision.reason):toBe("insufficient_gold")
			scene.clock.advance(10)
			expect(select(3, scene.law.buyBack(state, account, "owner", 1, 1, nil, scene.clock.clock())).reason):toBe(
				"buyback_expired"
			)
		end)
		it("bounded history drops oldest receipts and rejects invalid vendor definitions", function()
			local scene = Scene.new()
			local state = Exchange.empty()
			local account: Exchange.Account = { gold = 0, inventory = { food = 3 } }
			for _ = 1, 3 do
				state, account = scene.law.sellBack(state, account, scene.vendor, "owner", "food", 1, 0)
			end
			expect(#state.buyback.owner):toBe(2)
			expect(state.buyback.owner[1].id):toBe(2)
			expect(select(3, scene.law.buyBack(state, account, "owner", 1, 1, nil, 0)).reason):toBe("unknown_buyback")
			local cases: { unknown } = {
				false,
				{},
				{ id = "v", npcId = "n", wares = {} },
				{ id = "v", npcId = "n", wares = { { itemId = "missing", price = 1 } } },
				{ id = "v", npcId = "n", wares = { { itemId = "food", price = 0 } } },
				{ id = "v", npcId = "n", wares = { { itemId = "food", price = 1, stock = -1 } } },
				{ id = "v", npcId = "n", wares = { { itemId = "food", price = 1 }, { itemId = "food", price = 2 } } },
			}
			for _, raw in cases do
				expect((scene.law.validateVendor(raw))):toBe(false)
			end
		end)
		it("stack and capacity refusal leave both stock and wallet intact", function()
			local scene = Scene.new()
			local full: Exchange.Account = { gold = 100, inventory = { food = 20 } }
			expect(select(2, scene.law.buy(full, scene.vendor, "food", 1, nil)).reason):toBe("stack_full")
			local packed: Exchange.Account = { gold = 100, inventory = { food = 1, prize = 1 } }
			local state = Exchange.empty()
			local unchanged, wallet, refusal = scene.law.buyStock(state, packed, scene.vendor, "tool", 1, nil)
			expect(unchanged):toBe(state)
			expect(wallet):toBe(packed)
			expect(refusal.reason):toBe("inventory_full")
			expect(select(3, scene.law.buyStock(state, packed, scene.vendor, "tool", 1, "large")).ok):toBe(true)
		end)
		it("buyback rejects excess quantity and full bags without consuming the receipt", function()
			local scene = Scene.new()
			local state = scene.law.sellBack(
				Exchange.empty(),
				{ gold = 0, inventory = { tool = 1 } },
				scene.vendor,
				"owner",
				"tool",
				1,
				0
			)
			local packed: Exchange.Account = { gold = 100, inventory = { food = 1, prize = 1 } }
			local unchanged, account, refused = scene.law.buyBack(state, packed, "owner", 1, 2, nil, 0)
			expect(unchanged):toBe(state)
			expect(account):toBe(packed)
			expect(refused.reason):toBe("not_held")
			unchanged, account, refused = scene.law.buyBack(state, packed, "owner", 1, 1, nil, 0)
			expect(unchanged):toBe(state)
			expect(account):toBe(packed)
			expect(refused.reason):toBe("inventory_full")
			expect(select(3, scene.law.buyBack(state, packed, "owner", 1, 1, "large", 0)).ok):toBe(true)
		end)
		it("invalid clocks and currency overflow fail without changing balances or receipts", function()
			local scene = Scene.new()
			local state = Exchange.empty()
			local account: Exchange.Account = { gold = 0, inventory = { food = 1 } }
			local unchanged, wallet, refused =
				scene.law.sellBack(state, account, scene.vendor, "owner", "food", 1, math.huge)
			expect(unchanged):toBe(state)
			expect(wallet):toBe(account)
			expect(refused.reason):toBe("invalid_time")
			expect(select(3, scene.law.buyBack(state, account, "owner", 1, 1, nil, math.huge - math.huge)).reason):toBe(
				"invalid_time"
			)
			scene.prices.food = 1e308
			local rich: Exchange.Account = { gold = 1e308, inventory = { food = 2 } }
			local retained, overflow = scene.law.sell(rich, scene.vendor, "food", 2)
			expect(retained):toBe(rich)
			expect(overflow.reason):toBe("invalid_gold")
		end)
	end)
end
