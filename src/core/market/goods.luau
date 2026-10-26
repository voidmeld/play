--!strict

local Value = require("../internal/value")

export type ItemFacts = {
	id: string,
	slot: string?,
	levelReq: number?,
	rarity: string?,
	weaponFamily: string?,
	armorFamily: string?,
	classReq: { string }?,
}
export type Class = { id: string, displayName: string, weaponFamilies: { string }, armorCeiling: string }
export type Config<T> = {
	books: { [string]: string },
	order: { string },
	slots: { [string]: string },
	bindRules: { [string]: boolean },
	boundSlots: { [string]: boolean },
	recipePrefixes: { string },
	consumablePrefix: string,
	recipeCategory: string,
	consumableCategory: string,
	defaultCategory: string,
	armorRanks: { [string]: number },
	classOf: (string) -> Class?,
	unboundCount: (T, string) -> number,
}
export type Filters = {
	slot: string?,
	minLevel: number?,
	maxLevel: number?,
	rarity: string?,
	family: string?,
	classId: string?,
}

local Goods = {}

function Goods.catalog<T>(config: Config<T>)
	local catalog = {}
	function catalog.bookIds(): { string }
		local out: { string } = {}
		for _, key in config.order do
			table.insert(out, config.books[key])
		end
		return out
	end
	function catalog.isCategoryBook(bookId: unknown): boolean
		for _, id in config.books do
			if id == bookId then
				return true
			end
		end
		return false
	end
	function catalog.bookFor(value: unknown): (string?, string?)
		local def = Value.raw(value)
		if def == nil or type(def.id) ~= "string" then
			return nil, "item_unknown"
		end
		local rule, slot = def.bindRule, def.slot
		if
			(rule ~= nil and (type(rule) ~= "string" or config.bindRules[rule] ~= true))
			or (type(slot) == "string" and config.boundSlots[slot])
		then
			return nil, "item_bound"
		end
		if slot ~= nil then
			local category = if type(slot) == "string" then config.slots[slot] else nil
			if category == nil then
				return nil, "item_bound"
			end
			return config.books[category], nil
		end
		for _, prefix in config.recipePrefixes do
			if string.sub(def.id, 1, #prefix) == prefix then
				return config.books[config.recipeCategory], nil
			end
		end
		if
			def.useAction ~= nil
			or (string.sub(def.id, 1, #config.consumablePrefix) == config.consumablePrefix and def.stackable == true)
		then
			return config.books[config.consumableCategory], nil
		end
		return config.books[config.defaultCategory], nil
	end
	function catalog.tradeableCount(def: unknown, profile: T): number
		if catalog.bookFor(def) == nil then
			return 0
		end
		local raw = Value.raw(def)
		if raw == nil or type(raw.id) ~= "string" then
			return 0
		end
		return config.unboundCount(profile, raw.id)
	end
	function catalog.matches(def: ItemFacts, value: unknown): boolean
		local filters = Value.raw(value)
		if filters == nil then
			return true
		end
		if filters.slot ~= nil and def.slot ~= filters.slot then
			return false
		end
		if
			filters.minLevel ~= nil and (type(filters.minLevel) ~= "number" or (def.levelReq or 0) < filters.minLevel)
		then
			return false
		end
		if
			filters.maxLevel ~= nil and (type(filters.maxLevel) ~= "number" or (def.levelReq or 0) > filters.maxLevel)
		then
			return false
		end
		if filters.rarity ~= nil and def.rarity ~= filters.rarity then
			return false
		end
		if filters.family ~= nil and def.weaponFamily ~= filters.family and def.armorFamily ~= filters.family then
			return false
		end
		if filters.classId ~= nil then
			if type(filters.classId) ~= "string" then
				return false
			end
			local class = config.classOf(filters.classId)
			if class == nil then
				return false
			end
			if def.weaponFamily ~= nil and table.find(class.weaponFamilies, def.weaponFamily) == nil then
				return false
			end
			local rank = if def.armorFamily ~= nil then config.armorRanks[def.armorFamily] else nil
			if rank ~= nil and rank > (config.armorRanks[class.armorCeiling] or 0) then
				return false
			end
			if
				def.classReq ~= nil
				and table.find(def.classReq, class.id) == nil
				and table.find(def.classReq, class.displayName) == nil
			then
				return false
			end
		end
		return true
	end
	return catalog
end

return Goods
