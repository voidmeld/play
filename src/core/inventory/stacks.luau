--!strict

local Value = require("../value")
local Vault = require("../bank/vault")

export type Inventory = { [string]: number }
export type Holdings = {
	read inventory: Inventory,
	read equipment: { [string]: string },
	read bank: unknown,
	read itemWear: { equipped: { [string]: number }, bag: { [string]: { number } }, bank: { [string]: { number } } }?,
	read boundItems: Inventory?,
}

export type Config = {
	maxStack: number,
	baseCapacity: number,
	permanentItems: { [string]: boolean },
	bagBonus: {
		[string]: number,
	},
}
local System = {}
function System.stacks(config: Config)
	local MAX_STACK = config.maxStack
	local BASE_CAPACITY = config.baseCapacity
	local function permanent(itemId: string): boolean
		return config.permanentItems[itemId] == true
	end
	local function isValidCount(count: unknown): boolean
		return type(count) == "number"
			and count == count
			and count >= 1
			and count == math.floor(count)
			and count < math.huge
	end

	local function capacity(bagItem: string?): number
		return BASE_CAPACITY + (if bagItem ~= nil then config.bagBonus[bagItem] or 0 else 0)
	end

	local function entries(bag: Inventory): number
		local count = 0
		for itemId in bag do
			if not permanent(itemId) then
				count += 1
			end
		end
		return count
	end

	local function fits(before: Inventory, after: Inventory, limit: number): boolean
		local used = entries(after)
		return used <= limit or used <= entries(before)
	end

	local function equippedCount(equipment: { [string]: string }, itemId: string): number
		local count = 0
		for _, id in equipment do
			if id == itemId then
				count += 1
			end
		end
		return count
	end

	local function ownedCount(profile: Holdings, itemId: string): number
		local bankCount = 0
		if type(profile.bank) == "table" then
			local items = Value.raw(assert(Value.raw(profile.bank)).items)
			local count = if items ~= nil then items[itemId] else nil
			bankCount = if type(count) == "number" then count else 0
		end
		return (profile.inventory[itemId] or 0) + equippedCount(profile.equipment, itemId) + bankCount
	end

	local function normalizeBindings(raw: unknown, profile: Holdings): Inventory
		local out: Inventory = {}
		if raw ~= nil then
			assert(type(raw) == "table", "invalid item bindings")
			for id, count in assert(Value.raw(raw)) do
				assert(type(id) == "string" and isValidCount(count), "invalid item binding")
				local kept = math.min(assert(Value.whole(count, 1, math.huge)), ownedCount(profile, id))
				if kept > 0 then
					out[id] = kept
				end
			end
		end
		for _, id in profile.equipment do
			out[id] = math.max(out[id] or 0, equippedCount(profile.equipment, id))
		end
		for id, count in profile.inventory do
			if permanent(id) then
				assert(count == 1, "invalid permanent item count")
				out[id] = 1
			end
		end
		return out
	end

	local function unboundCount(profile: Holdings, itemId: string): number
		if permanent(itemId) then
			return 0
		end
		local bound = math.max((profile.boundItems or {})[itemId] or 0, equippedCount(profile.equipment, itemId))
		local worn = if profile.itemWear ~= nil then #(profile.itemWear.bag[itemId] or {}) else 0
		return math.max(0, math.min((profile.inventory[itemId] or 0) - worn, ownedCount(profile, itemId) - bound))
	end

	local function addToBag(bag: Inventory, itemId: string, count: number): Inventory
		assert(not permanent(itemId), "permanent items are provisioned with the character")
		if not isValidCount(count) then
			return table.clone(bag)
		end
		local added = math.min(MAX_STACK, (bag[itemId] or 0) + count) - (bag[itemId] or 0)
		return assert(Vault.adjust(bag, itemId, added, MAX_STACK, math.huge))
	end

	local function removeFromBag(bag: Inventory, itemId: string, count: number): (Inventory, boolean)
		if permanent(itemId) or not isValidCount(count) then
			return bag, false
		end
		local held = bag[itemId] or 0
		if held < count then
			return bag, false
		end
		return assert(Vault.adjust(bag, itemId, -count, math.huge, math.huge)), true
	end

	local function hasItem(bag: Inventory, itemId: string, count: number?): boolean
		return (bag[itemId] or 0) >= (count or 1)
	end

	local function copyBag(bag: Inventory): Inventory
		return table.clone(bag)
	end

	return {
		isValidCount = isValidCount,
		addToBag = addToBag,
		removeFromBag = removeFromBag,
		hasItem = hasItem,
		copyBag = copyBag,
		MAX_STACK = MAX_STACK,
		BASE_CAPACITY = BASE_CAPACITY,
		permanent = permanent,
		capacity = capacity,
		entries = entries,
		fits = fits,
		normalizeBindings = normalizeBindings,
		unboundCount = unboundCount,
	}
end
return System
