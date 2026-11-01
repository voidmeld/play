--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./stacks")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local InventoryRules = Module.stacks({ maxStack = 9999, baseCapacity = 24, permanentItems = {}, bagBonus = {} })
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("InventoryRules", function()
		describe("isValidCount", function()
			it("accepts positive integers", function()
				expect(InventoryRules.isValidCount(1)):toBe(true)
				expect(InventoryRules.isValidCount(50)):toBe(true)
			end)
			it("rejects zero, negatives, fractions, NaN, Inf, non-numbers", function()
				expect(InventoryRules.isValidCount(0)):toBe(false)
				expect(InventoryRules.isValidCount(-1)):toBe(false)
				expect(InventoryRules.isValidCount(1.5)):toBe(false)
				expect(InventoryRules.isValidCount(math.nan)):toBe(false)
				expect(InventoryRules.isValidCount(math.huge)):toBe(false)
				expect(InventoryRules.isValidCount("3")):toBe(false)
			end)
		end)

		describe("addToBag", function()
			it("adds a new item to a fresh slot without mutating the input", function()
				local base = {}
				local out = InventoryRules.addToBag(base, "a", 3)
				expect(out.a):toBe(3)
				expect((next(base))):toBeNil()
			end)
			it("stacks onto an existing count", function()
				local out = InventoryRules.addToBag({ a = 2 }, "a", 5)
				expect(out.a):toBe(7)
			end)
			it("clamps at MAX_STACK", function()
				local out = InventoryRules.addToBag({ a = InventoryRules.MAX_STACK }, "a", 10)
				expect(out.a):toBe(InventoryRules.MAX_STACK)
			end)
		end)

		describe("removeFromBag", function()
			it("removes a partial amount and reports ok", function()
				local out, ok = InventoryRules.removeFromBag({ a = 5 }, "a", 2)
				expect(ok):toBe(true)
				expect(out.a):toBe(3)
			end)
			it("clears the entry when removing all of it", function()
				local out, ok = InventoryRules.removeFromBag({ a = 2 }, "a", 2)
				expect(ok):toBe(true)
				expect(out.a):toBeNil()
			end)
			it("rejects over-removing and leaves the bag untouched", function()
				local base = { a = 1 }
				local out, ok = InventoryRules.removeFromBag(base, "a", 4)
				expect(ok):toBe(false)
				expect(out):toBe(base)
			end)
			it("rejects removing an item not held", function()
				local base = {}
				local out, ok = InventoryRules.removeFromBag(base, "ghost", 1)
				expect(ok):toBe(false)
				expect(out):toBe(base)
			end)
		end)

		describe("hasItem", function()
			it("honours the requested count (default 1)", function()
				local bag = { a = 2 }
				expect(InventoryRules.hasItem(bag, "a")):toBe(true)
				expect(InventoryRules.hasItem(bag, "a", 2)):toBe(true)
				expect(InventoryRules.hasItem(bag, "a", 3)):toBe(false)
				expect(InventoryRules.hasItem(bag, "missing")):toBe(false)
			end)
		end)

		describe("copyBag", function()
			it("returns a copy that does not write back to the source", function()
				local bag = { a = 1 }
				local copy = InventoryRules.copyBag(bag)
				copy.a = 999
				expect(copy.a):toBe(999)
				expect(bag.a):toBe(1)
			end)
		end)
	end)
	type Sample = { item: string, count: number, startCount: number, held: number, adding: number, removing: number }
	local function forAll(seed: number, predicate: (Sample) -> boolean): boolean
		local state = seed
		local function nextInt(low: number, high: number): number
			state = (state * 48271) % 2147483647
			return low + state % (high - low + 1)
		end
		for _ = 1, 200 do
			local sample: Sample = {
				item = ({ "item-a", "item-b", "item-c", "item-d", "item-e" })[nextInt(1, 5)],
				count = nextInt(1, 100),
				startCount = nextInt(0, InventoryRules.MAX_STACK - 100),
				held = nextInt(1, InventoryRules.MAX_STACK),
				adding = nextInt(1, InventoryRules.MAX_STACK),
				removing = nextInt(1, InventoryRules.MAX_STACK),
			}
			if not predicate(sample) then
				return false
			end
		end
		return true
	end
	it("round trips successful adds and removals across generated bags", function()
		expect(forAll(111222, function(v)
			local bag: Module.Inventory = {}
			if v.startCount > 0 then
				bag[v.item] = v.startCount
			end
			local added = InventoryRules.addToBag(bag, v.item, v.count)
			local removed, ok = InventoryRules.removeFromBag(added, v.item, v.count)
			return ok and (removed[v.item] or 0) == v.startCount
		end)):toBe(true)
	end)
	it("never loses an input item when adding", function()
		expect(forAll(222333, function(v)
			local out = InventoryRules.addToBag({ [v.item] = v.held }, v.item, v.adding)
			return out[v.item] >= v.held
		end)):toBe(true)
	end)
	it("never exceeds the configured stack cap", function()
		expect(forAll(333444, function(v)
			local out = InventoryRules.addToBag({ [v.item] = v.held }, v.item, v.adding)
			return out[v.item] <= InventoryRules.MAX_STACK
		end)):toBe(true)
	end)
	it("successful removal is nonnegative and rejected removal preserves the count", function()
		expect(forAll(444555, function(v)
			local out, ok = InventoryRules.removeFromBag({ [v.item] = v.held }, v.item, v.removing)
			return if ok then (out[v.item] or 0) >= 0 else out[v.item] == v.held
		end)):toBe(true)
	end)
	it("full removal leaves no zero or negative entries", function()
		expect(forAll(555666, function(v)
			local out, ok = InventoryRules.removeFromBag({ [v.item] = v.held }, v.item, v.held)
			for _, count in out do
				if count <= 0 then
					return false
				end
			end
			return ok and out[v.item] == nil
		end)):toBe(true)
	end)
	it("does not mutate generated input bags when adding", function()
		expect(forAll(666777, function(v)
			local bag = { [v.item] = v.held }
			InventoryRules.addToBag(bag, v.item, v.adding)
			return bag[v.item] == v.held
		end)):toBe(true)
	end)
	it("falsifies the deliberately false claim that adding cannot increase counts", function()
		expect(forAll(777888, function(v)
			local held = math.min(v.held, InventoryRules.MAX_STACK - 1)
			local out = InventoryRules.addToBag({ [v.item] = held }, v.item, 1)
			return out[v.item] <= held
		end)):toBe(false)
		local minimal = InventoryRules.addToBag({}, "item", 1)
		expect(minimal.item):toBe(1)
	end)
	it("uses supplied capacity bonuses, permanent classification and stack bounds", function()
		local law =
			Module.stacks({ maxStack = 7, baseCapacity = 2, permanentItems = { key = true }, bagBonus = { pack = 3 } })
		expect(law.capacity(nil)):toBe(2)
		expect(law.capacity("pack")):toBe(5)
		expect(law.capacity("unknown")):toBe(2)
		expect(law.permanent("key")):toBe(true)
		expect(law.entries({ key = 1, item = 3 })):toBe(1)
		expect(law.entries({ key = 1 })):toBe(0)
		expect(law.addToBag({ item = 6 }, "item", 3).item):toBe(7)
		expect(law.fits({}, { key = 1, item = 1 }, 1)):toBe(true)
		expect(law.fits({ a = 1, b = 1, c = 1 }, { a = 1, b = 1 }, 1)):toBe(true)
		expect(law.fits({ a = 1, b = 1 }, { a = 1, b = 1, c = 1 }, 1)):toBe(false)
		local bag = { key = 1 }
		expect((pcall(law.addToBag, bag, "key", 1))):toBe(false)
		local rejected, ok = law.removeFromBag(bag, "key", 1)
		expect(ok):toBe(false)
		expect(rejected):toBe(bag)
		expect(law.unboundCount({ inventory = bag, equipment = {}, bank = nil }, "key")):toBe(0)
	end)
	it("normalizes bindings to owned inventory, equipment and bank without changing inputs", function()
		local law = Module.stacks({ maxStack = 7, baseCapacity = 2, permanentItems = { key = true }, bagBonus = {} })
		local holdings: Module.Holdings = {
			inventory = { item = 4, key = 1 },
			equipment = { first = "item", second = "item" },
			bank = {
				items = { item = 3 },
			},
		}
		local bindings = { item = 99, missing = 1 }
		expect(law.normalizeBindings(bindings, holdings)):toEqual({ item = 9, key = 1 })
		expect(law.normalizeBindings(nil, holdings)):toEqual({ item = 2, key = 1 })
		expect(bindings.item):toBe(99)
		expect(holdings.inventory.item):toBe(4)
		for _, raw in { false, { item = 0 }, { item = 1.5 }, { [1] = 2 } } do
			expect((pcall(law.normalizeBindings, raw, holdings))):toBe(false)
		end
		local invalid: Module.Holdings = { inventory = { key = 2 }, equipment = {}, bank = nil }
		expect((pcall(law.normalizeBindings, nil, invalid))):toBe(false)
	end)
	it("excludes bindings and worn bag copies while retaining bank-backed tradeable copies", function()
		local law = Module.stacks({ maxStack = 20, baseCapacity = 2, permanentItems = {}, bagBonus = {} })
		local holdings = {
			inventory = { item = 5 },
			equipment = { hand = "item" },
			bank = { items = { item = 2 } },
			boundItems = { item = 7 },
			itemWear = { equipped = {}, bag = { item = { 1, 2 } }, bank = {} },
		}
		expect(law.unboundCount(holdings, "item")):toBe(1)
		holdings.boundItems = { item = 1 }
		expect(law.unboundCount(holdings, "item")):toBe(3)
		holdings.itemWear = nil
		expect(law.unboundCount(holdings, "item")):toBe(5)
		expect(law.unboundCount(holdings, "absent")):toBe(0)
	end)
	it("invalid add counts clone the bag and invalid removals retain it", function()
		local bag = { item = 2 }
		for _, count in { 0, -1, 0.5, math.nan, math.huge } do
			local out = InventoryRules.addToBag(bag, "item", count)
			expect(out):toEqual(bag)
			expect(out == bag):toBe(false)
			local removed, ok = InventoryRules.removeFromBag(bag, "item", count)
			expect(ok):toBe(false)
			expect(removed):toBe(bag)
		end
	end)
end
