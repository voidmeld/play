--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./patron")
local Shape = require("../social/shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local settings = {
		weekSec = 7 * 24 * 60 * 60,
		weekAnchorSec = 4 * 24 * 60 * 60,
		receiptWindow = 64,
		maxId = 128,
		maxOrders = 64,
		maxCount = 1000,
		maxCoin = 1000000,
		maxTime = 1000000000000,
		realms = Shape.freezeDeep({ north = true, south = true, east = true }),
	}
	local Core = Module.patron(settings)
	local Orders = {
		weeklyCoinCap = 240,
		orders = {
			{
				orderId = "patron.north.reedwatch-cloaks",
				realmId = "north",
				itemId = "item.cloak",
				count = 1,
				payout = 40,
				label = "Cloaks",
			},
			{
				orderId = "patron.north.shore-reeds",
				realmId = "north",
				itemId = "material.woodland_shore_reeds",
				count = 6,
				payout = 24,
				label = "Reeds",
			},
		},
	}

	local WEEK = settings.weekSec
	local MONDAY = settings.weekAnchorSec + 2900 * WEEK
	local CLOAKS = "patron.north.reedwatch-cloaks"
	local REEDS = "patron.north.shore-reeds"

	local function catalog(): Module.Catalog
		local value, reason = Core.catalog(Orders)
		assert(value ~= nil, reason)
		return value
	end

	local function turnIn(
		state: unknown,
		id: string,
		orderId: string,
		held: number,
		atSec: number,
		realmId: string?
	): Module.Result
		return Core.turnIn(state, catalog(), {
			turnInId = id,
			orderId = orderId,
			realmId = if realmId ~= nil then realmId else "north",
			held = held,
			atSec = atSec,
		})
	end

	local function payUntilRefused(state: Module.State, prefix: string, atSec: number): (Module.State, number)
		local paid = 0
		for index = 1, 40 do
			local result = turnIn(state, prefix .. tostring(index), CLOAKS, 1, atSec)
			if not result.ok then
				return state, paid
			end
			assert(result.state ~= nil)
			state = result.state
			paid += result.payout
		end
		return state, paid
	end

	describe("PatronOrderCore authored orders", function()
		it("accepts the authored catalog and refuses a payout above the weekly cap or a duplicate id", function()
			expect(catalog().weeklyCoinCap):toBe(240)
			local broken = table.clone(Orders)
			broken.orders = { table.clone(Orders.orders[1]) }
			broken.orders[1].payout = 241
			expect((select(2, Core.catalog(broken)))):toBe("order_invalid")
			broken.orders = { Orders.orders[1], Orders.orders[1] }
			expect((select(2, Core.catalog(broken)))):toBe("order_invalid")
			broken.orders = { table.clone(Orders.orders[1]) }
			broken.orders[1].realmId = "frontier"
			expect((select(2, Core.catalog(broken)))):toBe("order_invalid")
		end)
	end)

	describe("PatronOrderCore turn-ins", function()
		it("consumes the order's goods for its payout once per turn-in id", function()
			local first = turnIn(Core.emptyState(), "t1", REEDS, 7, MONDAY + 10)
			expect(first.ok):toBe(true)
			assert(first.state ~= nil)
			expect(first.payout):toBe(24)
			expect(first.consume):toBe(6)
			expect(first.itemId):toBe("material.woodland_shore_reeds")
			local replay = turnIn(first.state, "t1", REEDS, 7, MONDAY + 11)
			expect(replay.replayed):toBe(true)
			assert(replay.state ~= nil)
			expect(replay.payout):toBe(0)
			expect(replay.consume):toBe(0)
			expect(replay.state.paidThisWeek):toBe(24)
		end)

		it("refuses short goods, a foreign realm and an unknown order without a state", function()
			expect(turnIn(Core.emptyState(), "t1", REEDS, 5, MONDAY).reason):toBe("goods_insufficient")
			expect(turnIn(Core.emptyState(), "t1", REEDS, 6, MONDAY, "south").reason):toBe("realm_foreign")
			expect(turnIn(Core.emptyState(), "t1", "patron.none", 6, MONDAY).reason):toBe("order_unknown")
			expect(turnIn(Core.emptyState(), "t1", REEDS, 6, MONDAY).ok):toBe(true)
		end)

		it("pays at most the weekly cap and refuses the turn-in that would exceed it whole", function()
			local state, paid = payUntilRefused(Core.emptyState(), "a", MONDAY + 5)
			expect(paid):toBe(240)
			local refusal = turnIn(state, "over", CLOAKS, 1, MONDAY + 6)
			expect(refusal.reason):toBe("weekly_cap_reached")
			expect(refusal.consume):toBe(0)
			expect((Core.allowance(state, catalog(), MONDAY + 6))):toBe(0)
		end)

		it("banks one week of unused allowance, never more, and has no daily limit", function()
			local state = turnIn(Core.emptyState(), "w0", CLOAKS, 1, MONDAY).state
			assert(state ~= nil)
			expect((Core.allowance(state, catalog(), MONDAY + WEEK))):toBe(240 + 200)
			expect((Core.allowance(state, catalog(), MONDAY + 3 * WEEK))):toBe(480)
			local _, sameDay = payUntilRefused(state, "d", MONDAY + WEEK + 60)
			expect(sameDay):toBe(440)
			local spent = payUntilRefused(state, "s", MONDAY + 1)
			expect((Core.allowance(spent, catalog(), MONDAY + WEEK))):toBe(240)
			local nextWeek = turnIn(state, "n1", REEDS, 6, MONDAY + WEEK).state
			assert(nextWeek ~= nil)
			expect((Core.allowance(nextWeek, catalog(), MONDAY + 2 * WEEK))):toBe(480)
		end)

		it("starts a new character with one week's cap and never rolls the week back", function()
			expect((Core.allowance(Core.emptyState(), catalog(), MONDAY))):toBe(240)
			local later = turnIn(Core.emptyState(), "late", CLOAKS, 1, MONDAY + WEEK).state
			assert(later ~= nil)
			local earlier = turnIn(later, "early", CLOAKS, 1, MONDAY)
			assert(earlier.state ~= nil)
			expect(earlier.state.weekIndex):toBe(later.weekIndex)
			expect(earlier.state.paidThisWeek):toBe(80)
		end)

		it("keeps only the last 64 turn-in ids and refuses a malformed stored state", function()
			local state = Core.emptyState()
			for index = 1, 70 do
				local nextState = turnIn(state, "k" .. tostring(index), REEDS, 6, MONDAY + index * WEEK).state
				assert(nextState ~= nil)
				state = nextState
			end
			expect(#state.receiptOrder):toBe(settings.receiptWindow)
			expect(state.receiptOrder[1].turnInId):toBe("k7")
			expect((Core.projectState(state) ~= nil)):toBe(true)
			local broken = assert(Shape.raw(table.clone(state)))
			broken.paidThisWeek = -1
			expect((Core.projectState(broken))):toBeNil()
			broken = assert(Shape.raw(table.clone(state)))
			broken.extra = true
			expect((Core.projectState(broken))):toBeNil()
		end)
	end)

	it("uses configured catalog bounds, calendar anchor, receipt window and time limit", function()
		local changes: { (Module.Config) -> () } = {
			function(cfg)
				cfg.maxOrders = 1
			end,
			function(cfg)
				cfg.maxCount = 1
			end,
			function(cfg)
				cfg.maxCoin = 100
			end,
			function(cfg)
				cfg.maxId = 1
			end,
			function(cfg)
				cfg.realms = { elsewhere = true }
			end,
		}
		for _, change in changes do
			local cfg: Module.Config = table.clone(settings)
			change(cfg)
			expect((Module.patron(cfg).catalog(Orders))):toBeNil()
		end
		local cfg: Module.Config = table.clone(settings)
		cfg.weekSec, cfg.weekAnchorSec, cfg.receiptWindow, cfg.maxTime = 2, 1, 1, 10
		local core = Module.patron(cfg)
		expect(core.weekOf(5)):toBe(2)
		local authored = catalog()
		local first = assert(
			core.turnIn(
				core.emptyState(),
				authored,
				{ turnInId = "a", orderId = CLOAKS, realmId = "north", held = 1, atSec = 5 }
			).state
		)
		local second = assert(
			core.turnIn(first, authored, { turnInId = "b", orderId = CLOAKS, realmId = "north", held = 1, atSec = 5 }).state
		)
		expect(#second.receiptOrder):toBe(1)
		expect(second.receiptOrder[1].turnInId):toBe("b")
		expect(
			core.turnIn(second, authored, { turnInId = "c", orderId = CLOAKS, realmId = "north", held = 1, atSec = 11 }).reason
		):toBe("turn_in_invalid")
	end)
end
