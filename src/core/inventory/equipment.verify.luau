--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Equipment = require("./equipment")
local Stacks = require("./stacks")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local inventory = Stacks.stacks({ maxStack = 3, baseCapacity = 2, permanentItems = {}, bagBonus = { pack = 2 } })
local rules = Equipment.equipment({
	inventory = inventory,
	maxStack = 3,
	decide = function(
		item: Equipment.ItemDef,
		level: number,
		_class: string,
		_slots: Equipment.Equipment,
		_learned: unknown
	): Equipment.Decision
		if item.slot == nil then
			return { equip = false, reason = "not_equippable" }
		end
		if level < item.levelReq then
			return { equip = false, reason = "level" }
		end
		return { equip = true, slot = item.slot }
	end,
	resolveSlot = function(category: string, _slots: Equipment.Equipment): string?
		return category
	end,
	equipDenial = function(item: Equipment.Requirements, level: number, _class: string, _learned: unknown): string?
		return if level < item.levelReq then "level" else nil
	end,
})
local defs: { [string]: Equipment.ItemDef } = {
	blade = {
		slot = "hand",
		levelReq = 2,
		durability = { maximum = 10, contactWear = 2, damageWear = 0, repairCopper = 8 },
	},
	shield = {
		slot = "hand",
		levelReq = 1,
		durability = { maximum = 20, contactWear = 0, damageWear = 1, repairCopper = 8 },
	},
	pack = { bagSlots = 2, levelReq = 1 },
}
local function lookup(id: string): Equipment.ItemDef?
	return defs[id]
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("equipment inventory and wear", function()
		it("plans atomic bag exchanges with injected eligibility and capacity", function()
			local bag = { blade = 1, shield = 1 }
			local slots = { hand = "shield" }
			expect(rules.planEquip(bag, slots, "blade", 1, "class_a", lookup, nil, nil).reason):toBe("level")
			local plan = rules.planEquip(bag, slots, "blade", 2, "class_a", lookup, nil, nil)
			expect(plan.ok):toBe(true)
			expect(plan.bag):toEqual({ shield = 2 })
			expect(plan.slots.hand):toBe("blade")
			expect(bag):toEqual({ blade = 1, shield = 1 })
			expect(slots.hand):toBe("shield")
			expect(rules.planUnequip({ blade = 3 }, { hand = "blade" }, "hand", nil).reason):toBe("inventory_full")
		end)
		it("preserves per-copy wear through equip bank transfer and discard", function()
			local wear: Equipment.Wear = { equipped = { hand = 5 }, bag = { blade = { 8, 3 } }, bank = {} }
			local equipped = rules.equipWear(wear, { hand = "shield" }, "hand", "blade")
			expect(equipped.equipped.hand):toBe(8)
			expect(equipped.bag.shield):toEqual({ 5 })
			local stored = rules.transferWear(equipped, "blade", 1, "deposit")
			expect(stored.bank.blade):toEqual({ 3 })
			expect(equipped.bag.blade):toEqual({ 3 })
			local returned = rules.transferWear(stored, "blade", 1, "withdraw")
			expect(rules.discardWear(returned, "blade", 1).bag.blade):toBeNil()
			expect(wear.bag.blade):toEqual({ 8, 3 })
		end)
		it("suppresses broken equipment and repairs only after the current quote is funded", function()
			local wear = rules.applyWear(rules.defaultWear(), { hand = "blade" }, "contact", lookup, 5)
			expect(rules.activeEquipment(wear, { hand = "blade" }, lookup).hand):toBeNil()
			expect(rules.repairQuote(wear, { hand = "blade" }, lookup)):toBe(8)
			local changed, _, refusal = rules.repairWear(wear, { hand = "blade" }, 8, 7, lookup)
			expect(changed):toBeNil()
			expect(refusal):toBe("quote_changed")
			local poor, _, insufficient = rules.repairWear(wear, { hand = "blade" }, 7, 8, lookup)
			expect(poor):toBeNil()
			expect(insufficient):toBe("cannot_afford")
			local repaired, cost = rules.repairWear(wear, { hand = "blade" }, 8, 8, lookup)
			assert(repaired ~= nil)
			expect(cost):toBe(8)
			expect(rules.activeEquipment(repaired, { hand = "blade" }, lookup).hand):toBe("blade")
			expect(wear.equipped.hand):toBe(10)
		end)
		it("refuses wear for missing copies slots and out-of-range amounts", function()
			expect(rules.normalizeWear({ equipped = { hand = 2 }, bag = {}, bank = {} }, {}, {}, {}, lookup)):toBeNil()
			expect(
				rules.normalizeWear(
					{ equipped = {}, bag = { blade = { 3, 2 } }, bank = {} },
					{},
					{ blade = 1 },
					{},
					lookup
				)
			):toBeNil()
			expect(
				rules.normalizeWear(
					{ equipped = { hand = 11 }, bag = {}, bank = {} },
					{ hand = "blade" },
					{},
					{},
					lookup
				)
			):toBeNil()
		end)
	end)
end
