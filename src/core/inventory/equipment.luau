--!strict
local Value = require("../internal/value")
export type Requirements = {
	read levelReq: number,
	read classReq: { read [number]: string }?,
	read armorFamily: string?,
	read weaponFamily: string?,
	read handTopology: string?,
}
export type ItemDef = Requirements & {
	read slot: string?,
	read bagSlots: number?,
	read durability: {
		read maximum: number,
		read contactWear: number,
		read damageWear: number,
		read repairCopper: number,
	}?,
}
export type ItemLookup = (string) -> ItemDef?
export type Equipment = { [string]: string }
export type Inventory = { [string]: number }
export type Wear = { equipped: { [string]: number }, bag: { [string]: { number } }, bank: { [string]: { number } } }
export type Decision = { equip: true, slot: string, reason: nil } | { equip: false, slot: nil, reason: string }
export type InventoryPort = {
	read removeFromBag: (Inventory, string, number) -> (Inventory, boolean),
	read addToBag: (Inventory, string, number) -> Inventory,
	read entries: (Inventory) -> number,
	read capacity: (string?) -> number,
	read fits: (Inventory, Inventory, number) -> boolean,
}
export type Config = {
	read inventory: InventoryPort,
	read maxStack: number,
	read decide: (ItemDef, number, string, Equipment, unknown) -> Decision,
	read resolveSlot: (string, Equipment) -> string?,
	read equipDenial: (Requirements, number, string, unknown) -> string?,
}
export type Plan = {
	ok: boolean,
	reason: string?,
	bag: Inventory,
	slots: Equipment,
	slot: string?,
	displaced: string?,
	bagItem: string?,
}

export type API = {
	read defaultWear: () -> Wear,
	read normalizeWear: (unknown, Equipment, Inventory, { read [string]: number? }, ItemLookup) -> Wear?,
	read copyWear: (Wear) -> Wear,
	read equipWear: (Wear, Equipment, string, string) -> Wear,
	read unequipWear: (Wear, Equipment, string) -> Wear,
	read reconcileWear: (Wear, Equipment, Equipment) -> Wear,
	read transferWear: (Wear, string, number, "deposit" | "withdraw") -> Wear,
	read discardWear: (Wear, string, number) -> Wear,
	read applyWear: (Wear, Equipment, "contact" | "damage", ItemLookup, number?) -> Wear,
	read activeEquipment: (Wear, Equipment, ItemLookup) -> Equipment,
	read repairQuote: (Wear, Equipment, ItemLookup) -> number,
	read repairWear: (Wear, Equipment, number, number, ItemLookup) -> (Wear?, number, string?),
	read resolveSlot: (string, Equipment) -> string?,
	read equipDenial: (Requirements, number, string, unknown) -> string?,
	read planEquip: (Inventory, Equipment, string, number, string, ItemLookup, unknown, string?) -> Plan,
	read planUnequip: (Inventory, Equipment, string, string?) -> Plan,
}
local function equipment(config: Config): API
	config = table.freeze(table.clone(config))
	assert(config.maxStack >= 1 and config.maxStack % 1 == 0, "invalid equipment stack limit")
	local function copyWear(wear: Wear): Wear
		local copy: Wear = { equipped = table.clone(wear.equipped), bag = {}, bank = {} }
		for id, copies in wear.bag do
			copy.bag[id] = table.clone(copies)
		end
		for id, copies in wear.bank do
			copy.bank[id] = table.clone(copies)
		end
		return copy
	end

	local function defaultWear(): Wear
		return { equipped = {}, bag = {}, bank = {} }
	end

	local function normalizeWear(
		raw: unknown,
		slots: Equipment,
		bag: Inventory,
		bank: { read [string]: number? },
		getDef: ItemLookup
	): Wear?
		if type(raw) ~= "table" or getmetatable(raw) ~= nil then
			return nil
		end
		local input = assert(Value.raw(raw))
		for key in input do
			if key ~= "equipped" and key ~= "bag" and key ~= "bank" then
				return nil
			end
		end
		local out = defaultWear()
		for _, location in { "equipped", "bag", "bank" } do
			local values = input[location]
			if type(values) ~= "table" or getmetatable(values) ~= nil then
				return nil
			end
			for id, value in values do
				if type(id) ~= "string" then
					return nil
				end
				local itemId = if location == "equipped" then slots[id] else id
				if itemId == nil then
					return nil
				end
				local def = getDef(itemId)
				local rule = if def ~= nil then def.durability else nil
				if rule == nil then
					return nil
				end
				local function valid(amount: unknown): boolean
					return type(amount) == "number"
						and amount == math.floor(amount)
						and amount >= 1
						and amount <= rule.maximum
				end
				if location == "equipped" then
					if type(value) ~= "number" or not valid(value) then
						return nil
					end
					out.equipped[id] = value
				else
					if type(value) ~= "table" or getmetatable(value) ~= nil then
						return nil
					end
					local copies: { number } = {}
					local held = (if location == "bag" then bag else bank)[id] or 0
					for index, amount in value do
						if
							type(amount) ~= "number"
							or type(index) ~= "number"
							or index ~= math.floor(index)
							or index < 1
							or index > #value
							or not valid(amount)
						then
							return nil
						end
						copies[index] = amount
					end
					if #copies > held then
						return nil
					end
					if location == "bag" then
						out.bag[id] = copies
					else
						out.bank[id] = copies
					end
				end
			end
		end
		return out
	end

	local function addStoredWear(copies: { [string]: { number } }, itemId: string, amount: number?)
		if amount == nil or amount <= 0 then
			return
		end
		local list = copies[itemId] or {}
		table.insert(list, amount)
		table.sort(list, function(a: number, b: number): boolean
			return a > b
		end)
		copies[itemId] = list
	end

	local function takeStoredWear(copies: { [string]: { number } }, itemId: string): number?
		local list = copies[itemId]
		if list == nil then
			return nil
		end
		local amount = table.remove(list, 1)
		if #list == 0 then
			copies[itemId] = nil
		end
		return amount
	end

	local function equipWear(wear: Wear, slots: Equipment, slot: string, itemId: string): Wear
		local copy = copyWear(wear)
		local taken = takeStoredWear(copy.bag, itemId)
		local displaced = slots[slot]
		if displaced ~= nil then
			addStoredWear(copy.bag, displaced, copy.equipped[slot])
		end
		if taken ~= nil then
			copy.equipped[slot] = taken
		else
			copy.equipped[slot] = nil
		end
		return copy
	end

	local function unequipWear(wear: Wear, slots: Equipment, slot: string): Wear
		local copy = copyWear(wear)
		local itemId = slots[slot]
		if itemId ~= nil then
			addStoredWear(copy.bag, itemId, copy.equipped[slot])
		end
		copy.equipped[slot] = nil
		return copy
	end

	local function reconcileWear(wear: Wear, before: Equipment, after: Equipment): Wear
		local copy: Wear? = nil
		for slot, itemId in before do
			if after[slot] ~= itemId then
				local updated = copy or copyWear(wear)
				copy = updated
				addStoredWear(updated.bag, itemId, updated.equipped[slot])
				updated.equipped[slot] = nil
			end
		end
		for slot, itemId in after do
			if before[slot] ~= itemId then
				local updated = copy or copyWear(wear)
				copy = updated
				local amount = takeStoredWear(updated.bag, itemId)
				if amount ~= nil then
					updated.equipped[slot] = amount
				end
			end
		end
		return copy or wear
	end

	local function transferWear(wear: Wear, itemId: string, count: number, kind: "deposit" | "withdraw"): Wear
		local copy = copyWear(wear)
		local source = if kind == "deposit" then copy.bag else copy.bank
		local destination = if kind == "deposit" then copy.bank else copy.bag
		for _ = 1, math.min(count, #(source[itemId] or {})) do
			addStoredWear(destination, itemId, takeStoredWear(source, itemId))
		end
		return copy
	end

	local function discardWear(wear: Wear, itemId: string, count: number): Wear
		local copy = copyWear(wear)
		for _ = 1, math.min(count, #(copy.bag[itemId] or {})) do
			takeStoredWear(copy.bag, itemId)
		end
		return copy
	end

	local function applyWear(
		wear: Wear,
		slots: Equipment,
		kind: "contact" | "damage",
		getDef: ItemLookup,
		count: number?
	): Wear
		local copy = copyWear(wear)
		for slot, itemId in slots do
			local def = getDef(itemId)
			local rule = if def ~= nil then def.durability else nil
			if rule ~= nil then
				local amount = if kind == "contact" then rule.contactWear else rule.damageWear
				if amount > 0 then
					copy.equipped[slot] = math.min(rule.maximum, (copy.equipped[slot] or 0) + amount * (count or 1))
				end
			end
		end
		return copy
	end

	local function activeEquipment(wear: Wear, slots: Equipment, getDef: ItemLookup): Equipment
		local active = table.clone(slots)
		for slot, itemId in slots do
			local def = getDef(itemId)
			local rule = if def ~= nil then def.durability else nil
			if rule ~= nil and (wear.equipped[slot] or 0) >= rule.maximum then
				active[slot] = nil
			end
		end
		return active
	end

	local function repairQuote(wear: Wear, slots: Equipment, getDef: ItemLookup): number
		local copper = 0
		for slot, itemId in slots do
			local def = getDef(itemId)
			local rule = if def ~= nil then def.durability else nil
			if rule ~= nil then
				copper += math.min(rule.maximum, wear.equipped[slot] or 0) * rule.repairCopper / rule.maximum
			end
		end
		return math.ceil(copper)
	end

	local function repairWear(
		wear: Wear,
		slots: Equipment,
		funds: number,
		quoted: number,
		getDef: ItemLookup
	): (Wear?, number, string?)
		local cost = repairQuote(wear, slots, getDef)
		if quoted ~= cost then
			return nil, 0, "quote_changed"
		end
		if funds < cost then
			return nil, 0, "cannot_afford"
		end
		if cost == 0 then
			return wear, 0, nil
		end
		local copy = copyWear(wear)
		for slot, itemId in slots do
			local def = getDef(itemId)
			if def ~= nil and def.durability ~= nil then
				copy.equipped[slot] = nil
			end
		end
		return copy, cost, nil
	end

	local function reject(reason: string, bag: Inventory, slots: Equipment): Plan
		return { ok = false, reason = reason, bag = bag, slots = slots }
	end

	local function planEquip(
		bag: Inventory,
		slots: Equipment,
		itemId: string,
		level: number,
		class: string,
		getDef: ItemLookup,
		learnedWeapons: unknown,
		bagItem: string?
	): Plan
		local def = getDef(itemId)
		if def == nil then
			return reject("unknown_item", bag, slots)
		end
		if (bag[itemId] or 0) < 1 then
			return reject("not_owned", bag, slots)
		end
		if def.bagSlots ~= nil then
			local nextBag = config.inventory.removeFromBag(bag, itemId, 1)
			if bagItem ~= nil and bagItem ~= "" then
				if (nextBag[bagItem] or 0) >= config.maxStack then
					return reject("inventory_full", bag, slots)
				end
				nextBag = config.inventory.addToBag(nextBag, bagItem, 1)
			end
			if
				config.inventory.entries(nextBag)
				> math.max(config.inventory.capacity(itemId), config.inventory.entries(bag))
			then
				return reject("inventory_full", bag, slots)
			end
			return { ok = true, bag = nextBag, slots = slots, slot = "bag", bagItem = itemId, displaced = bagItem }
		end
		local decision = config.decide(def, level, class, slots, learnedWeapons)
		if not decision.equip then
			return reject(decision.reason, bag, slots)
		end
		local slot = decision.slot
		local displaced = slots[slot]

		local nextBag, removed = config.inventory.removeFromBag(bag, itemId, 1)
		if not removed then
			return reject("not_owned", bag, slots)
		end
		if displaced ~= nil then
			if (nextBag[displaced] or 0) >= config.maxStack then
				return reject("inventory_full", bag, slots)
			end
			nextBag = config.inventory.addToBag(nextBag, displaced, 1)
		end
		if not config.inventory.fits(bag, nextBag, config.inventory.capacity(bagItem)) then
			return reject("inventory_full", bag, slots)
		end
		local nextSlots = table.clone(slots)
		nextSlots[slot] = itemId
		return { ok = true, bag = nextBag, slots = nextSlots, slot = slot, displaced = displaced }
	end

	local function planUnequip(bag: Inventory, slots: Equipment, slot: string, bagItem: string?): Plan
		local itemId = if slot == "bag" then bagItem else slots[slot]
		if itemId == nil or itemId == "" then
			return reject("empty_slot", bag, slots)
		end
		local nextBag = config.inventory.addToBag(bag, itemId, 1)
		if
			(bag[itemId] or 0) == config.maxStack
			or not config.inventory.fits(
				bag,
				nextBag,
				config.inventory.capacity(if slot == "bag" then nil else bagItem)
			)
		then
			return reject("inventory_full", bag, slots)
		end
		if slot == "bag" then
			return { ok = true, bag = nextBag, slots = slots, slot = slot, bagItem = "" }
		end
		local nextSlots = table.clone(slots)
		nextSlots[slot] = nil
		return { ok = true, bag = nextBag, slots = nextSlots, slot = slot }
	end

	return table.freeze({

		defaultWear = defaultWear,
		normalizeWear = normalizeWear,
		copyWear = copyWear,
		equipWear = equipWear,
		unequipWear = unequipWear,
		reconcileWear = reconcileWear,
		transferWear = transferWear,
		discardWear = discardWear,
		applyWear = applyWear,
		activeEquipment = activeEquipment,
		repairQuote = repairQuote,
		repairWear = repairWear,
		resolveSlot = config.resolveSlot,
		equipDenial = config.equipDenial,
		planEquip = planEquip,
		planUnequip = planUnequip,
	})
end

return table.freeze({ equipment = equipment })
