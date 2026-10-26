--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Goods = require("./goods")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type Profile = { free: { [string]: number } }
local settings: Goods.Config<Profile> = {
	books = {
		weapon = "wares.weapon",
		armor = "wares.armor",
		trinket = "wares.trinket",
		recipe = "wares.recipe",
		consumable = "wares.use",
		goods = "wares.other",
	},
	order = { "weapon", "armor", "trinket", "consumable", "recipe", "goods" },
	slots = { hand = "weapon", body = "armor", neck = "trinket" },
	bindRules = { free = true, equip = true },
	boundSlots = { special = true },
	recipePrefixes = { "recipe.", "plan_" },
	consumablePrefix = "made_",
	recipeCategory = "recipe",
	consumableCategory = "consumable",
	defaultCategory = "goods",
	armorRanks = { light = 1, heavy = 2 },
	classOf = function(id: string): Goods.Class?
		return if id == "scholar"
			then { id = id, displayName = "Scholar", weaponFamilies = { "staff" }, armorCeiling = "light" }
			else nil
	end,
	unboundCount = function(profile: Profile, itemId: string): number
		return profile.free[itemId] or 0
	end,
}
local goods = Goods.catalog(settings)

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("goods", function()
		it("lists configured books in order and classifies slots, prefixes, actions and general goods", function(own)
			expect(goods.bookIds()):toEqual({
				"wares.weapon",
				"wares.armor",
				"wares.trinket",
				"wares.use",
				"wares.recipe",
				"wares.other",
			})
			expect(goods.isCategoryBook("wares.weapon")):toBe(true)
			expect(goods.isCategoryBook("other")):toBe(false)
			local cases: { { value: unknown, book: string } } = {
				{ value = { id = "a", slot = "hand" }, book = "wares.weapon" },
				{ value = { id = "a", slot = "body" }, book = "wares.armor" },
				{ value = { id = "a", slot = "neck" }, book = "wares.trinket" },
				{ value = { id = "recipe.a" }, book = "wares.recipe" },
				{ value = { id = "plan_a" }, book = "wares.recipe" },
				{ value = { id = "made_a", stackable = true }, book = "wares.use" },
				{ value = { id = "a", useAction = false }, book = "wares.use" },
				{ value = { id = "made_a", stackable = false }, book = "wares.other" },
				{ value = { id = "a", bindRule = "free" }, book = "wares.other" },
				{ value = { id = "a", bindRule = "equip" }, book = "wares.other" },
			}
			for _, case in cases do
				expect((goods.bookFor(case.value))):toBe(case.book)
			end
		end)

		it("rejects unknown, bound and unsupported items before consulting unbound holdings", function()
			local _, reason = goods.bookFor(false)
			expect(reason):toBe("item_unknown")
			local cases: { unknown } =
				{ { id = "a", bindRule = "pickup" }, { id = "a", slot = "special" }, { id = "a", slot = "unknown" } }
			for _, value in cases do
				local book, why = goods.bookFor(value)
				expect(book):toBeNil()
				expect(why):toBe("item_bound")
				expect(goods.tradeableCount(value, { free = { a = 3 } })):toBe(0)
			end
			expect(goods.tradeableCount({ id = "a" }, { free = { a = 3 } })):toBe(3)
		end)

		it("matches slot, levels, rarity and either family independently", function()
			local item: Goods.ItemFacts =
				{ id = "a", slot = "hand", levelReq = 5, rarity = "fine", weaponFamily = "staff" }
			expect(goods.matches(item, nil)):toBe(true)
			expect(
				goods.matches(item, { slot = "hand", minLevel = 5, maxLevel = 5, rarity = "fine", family = "staff" })
			):toBe(true)
			for _, filter in
				{ { slot = "body" }, { minLevel = 6 }, { maxLevel = 4 }, { rarity = "plain" }, { family = "axe" } }
			do
				expect(goods.matches(item, filter)):toBe(false)
			end
			expect(goods.matches({ id = "a", armorFamily = "light" }, { family = "light", minLevel = 0 })):toBe(true)
		end)

		it("uses configured classes, weapon families, armor ranks and class identity aliases", function()
			expect(
				goods.matches(
					{ id = "a", weaponFamily = "staff", armorFamily = "light", classReq = { "Scholar" } },
					{ classId = "scholar" }
				)
			):toBe(true)
			expect(goods.matches({ id = "a", classReq = { "scholar" } }, { classId = "scholar" })):toBe(true)
			expect(goods.matches({ id = "a" }, { classId = "unknown" })):toBe(false)
			expect(goods.matches({ id = "a", weaponFamily = "axe" }, { classId = "scholar" })):toBe(false)
			expect(goods.matches({ id = "a", armorFamily = "heavy" }, { classId = "scholar" })):toBe(false)
			expect(goods.matches({ id = "a", classReq = { "other" } }, { classId = "scholar" })):toBe(false)
			local cfg = table.clone(settings)
			cfg.armorRanks = { light = 3, heavy = 2 }
			cfg.books = { anything = "single" }
			cfg.order = { "anything" }
			cfg.slots = { special = "anything" }
			cfg.defaultCategory, cfg.recipeCategory, cfg.consumableCategory = "anything", "anything", "anything"
			local changed = Goods.catalog(cfg)
			expect(changed.matches({ id = "a", armorFamily = "heavy" }, { classId = "scholar" })):toBe(true)
			expect(changed.bookIds()):toEqual({ "single" })
			expect((changed.bookFor({ id = "a", slot = "special" }))):toBeNil()
		end)
	end)
end
