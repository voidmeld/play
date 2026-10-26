--!strict

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
	suite:case(
		"lists configured books in order and classifies slots, prefixes, actions and general goods",
		function(context)
			context
				:expect(goods.bookIds())
				:toEqual({ "wares.weapon", "wares.armor", "wares.trinket", "wares.use", "wares.recipe", "wares.other" })
			context:expect(goods.isCategoryBook("wares.weapon")):toBe(true)
			context:expect(goods.isCategoryBook("other")):toBe(false)
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
				context:expect((goods.bookFor(case.value))):toBe(case.book)
			end
		end
	)

	suite:case("rejects unknown, bound and unsupported items before consulting unbound holdings", function(context)
		local _, reason = goods.bookFor(false)
		context:expect(reason):toBe("item_unknown")
		local cases: { unknown } =
			{ { id = "a", bindRule = "pickup" }, { id = "a", slot = "special" }, { id = "a", slot = "unknown" } }
		for _, value in cases do
			local book, why = goods.bookFor(value)
			context:expect(book):toBeNil()
			context:expect(why):toBe("item_bound")
			context:expect(goods.tradeableCount(value, { free = { a = 3 } })):toBe(0)
		end
		context:expect(goods.tradeableCount({ id = "a" }, { free = { a = 3 } })):toBe(3)
	end)

	suite:case("matches slot, levels, rarity and either family independently", function(context)
		local item: Goods.ItemFacts = { id = "a", slot = "hand", levelReq = 5, rarity = "fine", weaponFamily = "staff" }
		context:expect(goods.matches(item, nil)):toBe(true)
		context
			:expect(
				goods.matches(item, { slot = "hand", minLevel = 5, maxLevel = 5, rarity = "fine", family = "staff" })
			)
			:toBe(true)
		for _, filter in
			{ { slot = "body" }, { minLevel = 6 }, { maxLevel = 4 }, { rarity = "plain" }, { family = "axe" } }
		do
			context:expect(goods.matches(item, filter)):toBe(false)
		end
		context
			:expect(goods.matches({ id = "a", armorFamily = "light" }, { family = "light", minLevel = 0 }))
			:toBe(true)
	end)

	suite:case("uses configured classes, weapon families, armor ranks and class identity aliases", function(context)
		context
			:expect(
				goods.matches(
					{ id = "a", weaponFamily = "staff", armorFamily = "light", classReq = { "Scholar" } },
					{ classId = "scholar" }
				)
			)
			:toBe(true)
		context:expect(goods.matches({ id = "a", classReq = { "scholar" } }, { classId = "scholar" })):toBe(true)
		context:expect(goods.matches({ id = "a" }, { classId = "unknown" })):toBe(false)
		context:expect(goods.matches({ id = "a", weaponFamily = "axe" }, { classId = "scholar" })):toBe(false)
		context:expect(goods.matches({ id = "a", armorFamily = "heavy" }, { classId = "scholar" })):toBe(false)
		context:expect(goods.matches({ id = "a", classReq = { "other" } }, { classId = "scholar" })):toBe(false)
		local cfg = table.clone(settings)
		cfg.armorRanks = { light = 3, heavy = 2 }
		cfg.books = { anything = "single" }
		cfg.order = { "anything" }
		cfg.slots = { special = "anything" }
		cfg.defaultCategory, cfg.recipeCategory, cfg.consumableCategory = "anything", "anything", "anything"
		local changed = Goods.catalog(cfg)
		context:expect(changed.matches({ id = "a", armorFamily = "heavy" }, { classId = "scholar" })):toBe(true)
		context:expect(changed.bookIds()):toEqual({ "single" })
		context:expect((changed.bookFor({ id = "a", slot = "special" }))):toBeNil()
	end)
end
