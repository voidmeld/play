--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./actionbar")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local ActionBarCore =
	Module.actionbar({ barSize = 5, barCount = 2, maxActionId = 128, maxLevel = 100, itemPrefix = "item:" })
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	local LOADOUT = {
		slots = {
			{ slot = 1, abilityId = "a1", requiredLevel = 1 },
			{ slot = 2, abilityId = "a2", requiredLevel = 1 },
			{ slot = 3, abilityId = "a3", requiredLevel = 3 },
			{ slot = 4, abilityId = "a4", requiredLevel = 4 },
			{ slot = 5, abilityId = "a5", requiredLevel = 5 },
		},
	}

	local function ctxAt(level: number): Module.Context
		return ActionBarCore.contextFor(LOADOUT, level)
	end

	describe("ActionBarCore", function()
		it("skips malformed and unearned loadout rows while retaining valid entries", function()
			local slots: { unknown } = {
				false,
				{ slot = "1", abilityId = "string-slot", requiredLevel = 1 },
				{ slot = 0, abilityId = "zero-slot", requiredLevel = 1 },
				{ slot = 11, abilityId = "overflow-slot", requiredLevel = 1 },
				{ slot = 1.5, abilityId = "fraction-slot", requiredLevel = 1 },
				{ slot = 1, abilityId = false, requiredLevel = 1 },
				{ slot = 1, abilityId = "string-level", requiredLevel = "1" },
				{ slot = 1, abilityId = "fraction-level", requiredLevel = 1.5 },
				{ slot = 1, abilityId = "unearned", requiredLevel = 4 },
				{ slot = 1, abilityId = "earned", requiredLevel = 3 },
				{ slot = 10, abilityId = "second-bar", requiredLevel = 1 },
			}
			local loadout = { slots = slots }
			expect(ActionBarCore.contextFor(loadout, 3)):toEqual({
				authored = { [1] = "earned", [10] = "second-bar" },
				owned = { earned = true, ["second-bar"] = true },
				required = { earned = 3, ["second-bar"] = 1 },
				level = 3,
			})
			local empty = { authored = {}, owned = {}, required = {}, level = 0 }
			for _, invalid in { false, {}, { slots = false } } do
				expect(ActionBarCore.contextFor(invalid, 3)):toEqual(empty)
			end
			for _, invalid in { false, "3", 1.5, math.nan } do
				expect(ActionBarCore.contextFor(loadout, invalid)):toEqual(empty)
			end
		end)

		it("defaults to the authored order of earned abilities", function()
			local layout = ActionBarCore.effective(ActionBarCore.default(), ctxAt(3))
			expect(layout):toEqual({ [1] = "a1", [2] = "a2", [3] = "a3" })
			expect(ActionBarCore.effective(nil, ctxAt(5))):toEqual({ "a1", "a2", "a3", "a4", "a5" })
		end)

		it("assigns an owned ability to a slot on the second bar", function()
			local state = assert(ActionBarCore.assign(ActionBarCore.default(), ctxAt(5), 7, "a3"))
			expect(state.custom):toBe(true)
			local layout = ActionBarCore.effective(state, ctxAt(5))
			expect(layout[7]):toBe("a3")
			expect(layout[3]):toBeNil()
			expect(layout[1]):toBe("a1")
		end)

		it("swaps when the target slot is occupied and the ability moves", function()
			local state = assert(ActionBarCore.assign(ActionBarCore.default(), ctxAt(5), 2, "a5"))
			local layout = ActionBarCore.effective(state, ctxAt(5))
			expect(layout[2]):toBe("a5")
			expect(layout[5]):toBe("a2")
		end)

		it("swaps two slots, including an empty one", function()
			local state = assert(ActionBarCore.swap(nil, ctxAt(5), 1, 2))
			expect(ActionBarCore.effective(state, ctxAt(5))[1]):toBe("a2")
			expect(ActionBarCore.effective(state, ctxAt(5))[2]):toBe("a1")
			local toEmpty = assert(ActionBarCore.swap(nil, ctxAt(5), 1, 9))
			local layout = ActionBarCore.effective(toEmpty, ctxAt(5))
			expect(layout[9]):toBe("a1")
			expect(layout[1]):toBeNil()
		end)

		it("clears a slot and keeps it cleared", function()
			local state = assert(ActionBarCore.clear(nil, ctxAt(5), 3))
			local layout = ActionBarCore.effective(state, ctxAt(5))
			expect(layout[3]):toBeNil()
			expect(ActionBarCore.placed(layout, "a3")):toBeNil()
		end)

		it("refuses an unowned ability, a bad slot and a malformed intent", function()
			local _, unowned = ActionBarCore.assign(nil, ctxAt(2), 1, "a5")
			expect(unowned):toBe("ability_not_owned")
			local _, foreign = ActionBarCore.assign(nil, ctxAt(5), 1, "stranger")
			expect(foreign):toBe("ability_not_owned")
			for _, slot in { 0, 11, 1.5, -1, "1", math.huge } do
				local _, reason = ActionBarCore.assign(nil, ctxAt(5), slot, "a1")
				expect(reason):toBe("slot_invalid")
			end
			local _, op = ActionBarCore.apply(nil, ctxAt(5), { op = "teleport" })
			expect(op):toBe("op_invalid")
			local _, shape = ActionBarCore.apply(nil, ctxAt(5), "assign")
			expect(shape):toBe("intent_invalid")
		end)

		it("applies each intent operation and resets to the default", function()
			local ctx = ctxAt(5)
			local assigned = assert(ActionBarCore.apply(nil, ctx, { op = "assign", slot = 6, actionId = "a1" }))
			expect(ActionBarCore.effective(assigned, ctx)[6]):toBe("a1")
			local swapped = assert(ActionBarCore.apply(assigned, ctx, { op = "swap", from = 6, slot = 7 }))
			expect(ActionBarCore.effective(swapped, ctx)[7]):toBe("a1")
			local cleared = assert(ActionBarCore.apply(swapped, ctx, { op = "clear", slot = 7 }))
			expect(ActionBarCore.placed(ActionBarCore.effective(cleared, ctx), "a1")):toBeNil()
			local reset = assert(ActionBarCore.apply(cleared, ctx, { op = "reset" }))
			expect(reset):toEqual(ActionBarCore.default())
		end)

		it("never duplicates an ability and drops unowned entries on normalize", function()
			local raw = { custom = true, slots = { ["1"] = "a2", ["2"] = "a2", ["3"] = "ghost", ["4"] = "a5" } }
			local state = ActionBarCore.normalize(raw, ctxAt(2))
			expect(state.slots):toEqual({ ["1"] = "a2" })
			local layout = ActionBarCore.effective(state, ctxAt(2))
			expect(layout[1]):toBe("a2")
			expect(layout[2]):toBeNil()
		end)

		it("normalizes anything that is not a custom bar to the default", function()
			for _, raw in { false, "x", 3, { custom = false, slots = { ["1"] = "a1" } }, { custom = true } } do
				expect(ActionBarCore.normalize(raw, ctxAt(5))):toEqual(ActionBarCore.default())
			end
		end)

		it("places a newly earned ability in its authored slot on a custom bar when free", function()
			local state = assert(ActionBarCore.assign(nil, ctxAt(1), 8, "a1"))
			local layout = ActionBarCore.effective(state, ctxAt(3))
			expect(layout[8]):toBe("a1")
			expect(layout[3]):toBe("a3")
			expect(layout[2]):toBe("a2")
		end)

		it("projects a strict persisted shape without sharing mutable slots", function()
			expect(ActionBarCore.project(ActionBarCore.default())):toEqual(ActionBarCore.default())
			local source = { custom = true, level = 4, slots = { ["10"] = "a1" } }
			local projected = assert(ActionBarCore.project(source))
			expect(projected):toEqual(source)
			projected.slots["10"] = "a2"
			expect(source.slots["10"]):toBe("a1")
			for _, raw in
				{
					false,
					{ custom = true },
					{ custom = true, slots = {} },
					{ custom = true, level = 101, slots = {} },
					{ custom = true, level = 1.5, slots = {} },
					{ custom = true, level = 1, slots = { ["11"] = "a1" } },
					{ custom = true, level = 1, slots = { ["01"] = "a1" } },
					{ custom = true, level = 1, slots = { ["1"] = "" } },
					{ custom = true, level = 1, slots = { [1] = "a1" } },
					{ custom = true, level = 1, slots = {}, extra = 1 },
					setmetatable({ custom = true, level = 1, slots = {} }, {}),
					{ custom = true, level = 1, slots = setmetatable({}, {}) },
				}
			do
				expect(ActionBarCore.project(raw)):toBeNil()
			end
		end)

		it("round-trips explicit action identities without accepting the displaced digit wire", function()
			local ctx = ctxAt(5)
			local state = assert(ActionBarCore.assign(nil, ctx, 7, "a3"))
			local layout = ActionBarCore.effective(state, ctx)
			local wire = ActionBarCore.encodeWire(layout)
			expect(wire):toBe("a1|a2|-|a4|a5|-|a3|-|-|-")
			expect(ActionBarCore.decodeWire(wire, ctx)):toEqual(layout)
			expect(ActionBarCore.decodeWire("120450300", ctx)):toBeNil()
			expect(ActionBarCore.decodeWire("1100000000", ctx)):toBeNil()
			expect(ActionBarCore.decodeWire("9000000000", ctx)):toBeNil()
			expect(ActionBarCore.decodeWire(nil, ctx)):toBeNil()
		end)

		it("retains depleted usable item references while refusing new assignment until carried", function()
			local ctx = ActionBarCore.contextFor(LOADOUT, 1, { bindstone = true, bread = true })
			local state = assert(ActionBarCore.apply(nil, ctx, { op = "assign", slot = 5, actionId = "item:bread" }))
			local empty = ActionBarCore.contextFor(LOADOUT, 1, { bindstone = true, bread = false })
			expect(ActionBarCore.effective(ActionBarCore.normalize(state, empty), empty)[5]):toBe("item:bread")
			expect(
				assert(ActionBarCore.decodeWire(ActionBarCore.encodeWire(ActionBarCore.effective(state, empty)), empty))[5]
			):toBe("item:bread")
			local rejected, reason = ActionBarCore.assign(state, empty, 6, "item:bread")
			expect(rejected):toBeNil()
			expect(reason):toBe("item_not_carried")
			local restored = ActionBarCore.contextFor(LOADOUT, 1, { bindstone = true, bread = true })
			expect(ActionBarCore.effective(state, restored)[5]):toBe("item:bread")
			local bound = assert(ActionBarCore.assign(state, restored, 10, "item:bindstone"))
			expect(bound.slots["10"]):toBe("item:bindstone")
		end)

		it("lists the occupied slots of one bar in position order", function()
			local layout = { [5] = "a5", [2] = "a2", [7] = "a3", [6] = "a1" }
			expect(ActionBarCore.layerEntries(layout, 1)):toEqual({
				{ position = 2, slot = 2, actionId = "a2" },
				{ position = 5, slot = 5, actionId = "a5" },
			})
			expect(ActionBarCore.layerEntries(layout, 2)):toEqual({
				{ position = 1, slot = 6, actionId = "a1" },
				{ position = 2, slot = 7, actionId = "a3" },
			})
			expect(ActionBarCore.layerEntries(layout, 3)):toEqual({})
			expect(ActionBarCore.layerEntries({}, 1)):toEqual({})
		end)

		it("resolves a key press to the slot on the held layer", function()
			local layout = { [2] = "a2", [7] = "a3" }
			expect(ActionBarCore.resolvePress(layout, 2, 1)):toBe("a2")
			expect(ActionBarCore.resolvePress(layout, 2, 2)):toBe("a3")
			expect(ActionBarCore.resolvePress(layout, 1, 2)):toBeNil()
			expect(ActionBarCore.resolvePress(layout, 6, 1)):toBeNil()
			expect(ActionBarCore.resolvePress(layout, 1, 3)):toBeNil()
			expect(ActionBarCore.slotFor(5, 2)):toBe(10)
			for _, invalid in { false, "1", 0, -1, 1.5, math.huge, math.nan } do
				expect(ActionBarCore.slotFor(invalid, 1)):toBeNil()
				expect(ActionBarCore.slotFor(1, invalid)):toBeNil()
			end
		end)
	end)
	it("configures bar dimensions, identities and persisted level bounds", function()
		local law = Module.actionbar({ barSize = 2, barCount = 3, maxActionId = 8, maxLevel = 4, itemPrefix = "use:" })
		expect(law.slotFor(2, 3)):toBe(6)
		expect(law.slotFor(3, 1)):toBeNil()
		expect(law.slotFor(1, 4)):toBeNil()
		expect(law.itemAction("food")):toBe("use:food")
		expect(law.itemId("use:food")):toBe("food")
		expect(law.itemId("item:food")):toBeNil()
		expect((pcall(law.itemAction, "longitem"))):toBe(false)
		expect(law.project({ custom = true, level = 5, slots = {} })):toBeNil()
		expect(law.project({ custom = true, level = 4, slots = { ["6"] = "use:food" } })):toEqual({
			custom = true,
			level = 4,
			slots = { ["6"] = "use:food" },
		})
		expect(law.encodeWire({ [6] = "food" })):toBe("-|-|-|-|-|food")
	end)
end
