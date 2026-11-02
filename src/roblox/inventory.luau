--!strict

local Stacks = require("../core/inventory/stacks")

export type Inventory = Stacks.Inventory
export type RewardItem = { id: string, count: number }
export type Reader<R, P> = (R) -> P?
export type Service<S, R, P> = {
	read getItems: (Reader<R, P>, S) -> Inventory,
	read getCount: (Reader<R, P>, S, string) -> number,
	read hasItem: (Reader<R, P>, S, string, number?) -> boolean,
	read addItem: (S, string, number) -> boolean,
	read removeItem: (S, string, number) -> boolean,
	read commitRewardTransaction: (S, string, { RewardItem }, number, number?, string?) -> boolean,
}
export type Config<S, C, R, P> = {
	read context: (S) -> C?,
	read readable: (C) -> R,
	read peek: (R) -> P?,
	read update: (C, (P) -> P) -> (),
	read inventory: (P) -> Inventory,
	read withInventory: (P, Inventory) -> P,
	read capacity: (P) -> number,
	read exists: (string) -> boolean,
	read permanent: (string) -> boolean,
	read maxStack: number,
	read transactionIdLimit: number,
	read copyBag: (Inventory) -> Inventory,
	read validCount: (unknown) -> boolean,
	read addToBag: (Inventory, string, number) -> Inventory,
	read removeFromBag: (Inventory, string, number) -> (Inventory, boolean),
	read fits: (Inventory, Inventory, number) -> boolean,
	read recorded: (P, string) -> boolean,
	read reward: (P, string, Inventory, number, number, string?) -> P,
}

local function validAmount(value: number): boolean
	return value == value and value > -math.huge and value < math.huge and value >= 0 and value == math.floor(value)
end

local function create<S, C, R, P>(config: Config<S, C, R, P>): Service<S, R, P>
	config = table.freeze(table.clone(config))
	assert(config.validCount(config.maxStack), "invalid inventory stack limit")
	assert(validAmount(config.transactionIdLimit) and config.transactionIdLimit > 0, "invalid inventory receipt limit")
	local function current(subject: S, context: C): boolean
		return config.context(subject) == context
	end
	local function readProfile(read: Reader<R, P>, subject: S): P?
		local context = config.context(subject)
		return if context ~= nil then read(config.readable(context)) else nil
	end
	local function getItems(read: Reader<R, P>, subject: S): Inventory
		local profile = readProfile(read, subject)
		return if profile ~= nil then config.copyBag(config.inventory(profile)) else {}
	end
	local function getCount(read: Reader<R, P>, subject: S, id: string): number
		local profile = readProfile(read, subject)
		return if profile ~= nil then config.inventory(profile)[id] or 0 else 0
	end
	local function mutate(subject: S, apply: (P) -> P?): boolean
		local context = config.context(subject)
		if context == nil or config.peek(config.readable(context)) == nil or not current(subject, context) then
			return false
		end
		local accepted = false
		config.update(context, function(profile)
			accepted = false
			if not current(subject, context) then
				return profile
			end
			local updated = apply(profile)
			if updated == nil then
				return profile
			end
			accepted = true
			return updated
		end)
		return accepted
	end
	local function addItem(subject: S, id: string, count: number): boolean
		if not config.exists(id) or config.permanent(id) or not config.validCount(count) then
			return false
		end
		return mutate(subject, function(profile)
			local before = config.inventory(profile)
			if (before[id] or 0) + count > config.maxStack then
				return nil
			end
			local after = config.addToBag(before, id, count)
			if not config.fits(before, after, config.capacity(profile)) then
				return nil
			end
			return config.withInventory(profile, after)
		end)
	end
	local function removeItem(subject: S, id: string, count: number): boolean
		if not config.validCount(count) then
			return false
		end
		return mutate(subject, function(profile)
			local after, accepted = config.removeFromBag(config.inventory(profile), id, count)
			return if accepted then config.withInventory(profile, after) else nil
		end)
	end
	local function commitRewardTransaction(
		subject: S,
		id: string,
		items: { RewardItem },
		experience: number,
		gold: number?,
		season: string?
	): boolean
		local coin = gold or 0
		if
			id == ""
			or #id > config.transactionIdLimit
			or not validAmount(experience)
			or not validAmount(coin)
			or #items == 0 and experience == 0 and coin == 0
		then
			return false
		end
		local seen: { [string]: boolean } = {}
		local admitted: { RewardItem } = {}
		for _, item in items do
			if
				seen[item.id]
				or not config.exists(item.id)
				or config.permanent(item.id)
				or not config.validCount(item.count)
			then
				return false
			end
			seen[item.id] = true
			table.insert(admitted, { id = item.id, count = item.count })
		end
		return mutate(subject, function(profile)
			if config.recorded(profile, id) then
				return nil
			end
			local before = config.inventory(profile)
			local after = before
			for _, item in admitted do
				if (after[item.id] or 0) + item.count > config.maxStack then
					return nil
				end
				after = config.addToBag(after, item.id, item.count)
			end
			if not config.fits(before, after, config.capacity(profile)) then
				return nil
			end
			return config.reward(profile, id, after, experience, coin, season)
		end)
	end
	return table.freeze({
		getItems = getItems,
		getCount = getCount,
		hasItem = function(read: Reader<R, P>, subject: S, id: string, count: number?): boolean
			return getCount(read, subject, id) >= (count or 1)
		end,
		addItem = addItem,
		removeItem = removeItem,
		commitRewardTransaction = commitRewardTransaction,
	})
end

return table.freeze({ create = create })
