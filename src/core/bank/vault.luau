--!strict

export type Inventory = { [string]: number }
export type Request =
	{ kind: "deposit" | "withdraw", itemId: string, count: number, bankerId: string, requestId: string }
export type State = { items: Inventory, receipts: { [string]: Request }, receiptOrder: { string } }
export type Config<T> = {
	maxStack: number,
	maxBagSlots: number,
	maxBankSlots: number,
	maxReceipts: number,
	itemIdLimit: number,
	bankerIdLimit: number,
	requestIdLimit: number,
	readProfile: (T) -> unknown,
	writeProfile: (T, Inventory, State) -> T,
	permanent: (string) -> boolean,
	fits: (T, Inventory, Inventory) -> boolean,
	transfer: (T, Request) -> T,
}
export type Vault<T> = {
	sameRequest: (Request, Request) -> boolean,
	default: () -> State,
	request: (unknown) -> Request?,
	project: (unknown) -> State?,
	apply: (T, unknown) -> (T?, string?),
}

type Raw = { [unknown]: unknown }

local function whole(value: unknown, low: number, high: number): number?
	return if type(value) == "number"
			and value == math.floor(value)
			and value >= low
			and value <= high
		then value
		else nil
end

local function identifier(value: unknown, limit: number): string?
	return if type(value) == "string"
			and #value > 0
			and #value <= limit
			and string.match(value, "^[%w%.%-_:]+$") ~= nil
		then value
		else nil
end

local function raw(value: unknown): Raw?
	if type(value) ~= "table" then
		return nil
	end
	local out: Raw = {}
	for key, entry in value do
		out[key] = entry
	end
	return out
end

local function plain(value: unknown): Raw?
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return nil
	end
	return raw(value)
end

local function exact(value: unknown, fields: { [string]: boolean }): Raw?
	local found = plain(value)
	if found == nil then
		return nil
	end
	for key in found do
		if type(key) ~= "string" or fields[key] ~= true then
			return nil
		end
	end
	return found
end

local function sameRequest(first: Request, second: Request): boolean
	return first.kind == second.kind
		and first.itemId == second.itemId
		and first.count == second.count
		and first.bankerId == second.bankerId
end

local function default(): State
	return { items = {}, receipts = {}, receiptOrder = {} }
end

local Bank = {}

function Bank.adjust(
	inventory: Inventory,
	itemId: string,
	delta: number,
	maxCount: number,
	maxEntries: number
): (Inventory?, string?)
	local current = inventory[itemId] or 0
	local total = current + delta
	if total < 0 then
		return nil, "goods_insufficient"
	end
	if total > maxCount then
		return nil, "inventory_full"
	end
	local updated = table.clone(inventory)
	updated[itemId] = if total > 0 then total else nil
	if current == 0 and total > 0 then
		local entries = 0
		for _ in updated do
			entries += 1
		end
		if entries > maxEntries then
			return nil, "inventory_full"
		end
	end
	return updated, nil
end

function Bank.vault<T>(config: Config<T>): Vault<T>
	local function items(value: unknown, maxSlots: number): Inventory?
		local found = plain(value)
		if found == nil then
			return nil
		end
		local slots = 0
		local out: Inventory = {}
		for key, value in found do
			local itemId = identifier(key, config.itemIdLimit)
			local count = whole(value, 1, config.maxStack)
			if itemId == nil or count == nil then
				return nil
			end
			slots += 1
			out[itemId] = count
		end
		return if slots <= maxSlots then out else nil
	end

	local function request(value: unknown): Request?
		local found = exact(value, { kind = true, itemId = true, count = true, bankerId = true, requestId = true })
		if found == nil then
			return nil
		end
		local kind = found.kind
		local itemId = identifier(found.itemId, config.itemIdLimit)
		local count = whole(found.count, 1, config.maxStack)
		local bankerId = identifier(found.bankerId, config.bankerIdLimit)
		local requestId = identifier(found.requestId, config.requestIdLimit)
		if
			(kind ~= "deposit" and kind ~= "withdraw")
			or itemId == nil
			or count == nil
			or bankerId == nil
			or requestId == nil
		then
			return nil
		end
		return { kind = kind, itemId = itemId, count = count, bankerId = bankerId, requestId = requestId }
	end

	local function project(value: unknown): State?
		if value == nil then
			return default()
		end
		local found = exact(value, { items = true, receipts = true, receiptOrder = true })
		if found == nil then
			return nil
		end
		local inventory = items(found.items, config.maxBankSlots)
		local candidates = plain(found.receipts)
		local authoredOrder: Raw? = if found.receiptOrder ~= nil then plain(found.receiptOrder) else nil
		if inventory == nil or candidates == nil or (found.receiptOrder ~= nil and authoredOrder == nil) then
			return nil
		end
		local receipts: { [string]: Request } = {}
		local order: { string } = {}
		local rawOrder: { unknown } = {}
		if authoredOrder == nil then
			for requestId in candidates do
				if #rawOrder == config.maxReceipts then
					break
				end
				table.insert(rawOrder, requestId)
			end
		else
			local length = #authoredOrder
			if length > config.maxReceipts then
				return nil
			end
			local entries = 0
			for index in authoredOrder do
				entries += 1
				if entries > config.maxReceipts or whole(index, 1, length) == nil then
					return nil
				end
			end
			if entries ~= length then
				return nil
			end
			for index = 1, length do
				rawOrder[index] = authoredOrder[index]
			end
		end
		for _, candidate in rawOrder do
			local requestId = identifier(candidate, config.requestIdLimit)
			if requestId == nil then
				return nil
			end
			local normalized = request(candidates[requestId])
			if normalized == nil or normalized.requestId ~= requestId or receipts[requestId] ~= nil then
				return nil
			end
			receipts[requestId] = normalized
			table.insert(order, requestId)
		end
		if authoredOrder ~= nil then
			local entries = 0
			for requestId in candidates do
				entries += 1
				if entries > config.maxReceipts or type(requestId) ~= "string" or receipts[requestId] == nil then
					return nil
				end
			end
		end
		return { items = inventory, receipts = receipts, receiptOrder = order }
	end

	return {
		sameRequest = sameRequest,
		default = default,
		request = request,
		project = project,
		apply = function(profile: T, value: unknown): (T?, string?)
			local normalized = request(value)
			local found = raw(config.readProfile(profile))
			local inventory: Inventory? = if found ~= nil then items(found.inventory, config.maxBagSlots) else nil
			if normalized == nil or found == nil or inventory == nil then
				return nil, "bank_request_invalid"
			end
			if config.permanent(normalized.itemId) then
				return nil, "item_permanent"
			end
			local bank = if found.bank ~= nil then project(found.bank) else nil
			if bank == nil then
				return nil, "bank_state_invalid"
			end
			local previous = bank.receipts[normalized.requestId]
			if previous ~= nil then
				if sameRequest(previous, normalized) then
					return profile, nil
				end
				return nil, "request_conflict"
			end
			local source = if normalized.kind == "deposit" then inventory else bank.items
			local destination = if normalized.kind == "deposit" then bank.items else inventory
			local held = source[normalized.itemId] or 0
			local current = destination[normalized.itemId] or 0
			if held < normalized.count then
				return nil, "item_insufficient"
			end
			if current + normalized.count > config.maxStack then
				return nil, "destination_full"
			end
			local sourceCopy =
				assert(Bank.adjust(source, normalized.itemId, -normalized.count, config.maxStack, math.huge))
			local destinationCopy =
				assert(Bank.adjust(destination, normalized.itemId, normalized.count, config.maxStack, math.huge))
			bank.items = if normalized.kind == "deposit" then destinationCopy else sourceCopy
			local destinationSlots = if normalized.kind == "deposit" then config.maxBankSlots else config.maxBagSlots
			if items(destinationCopy, destinationSlots) == nil then
				return nil, "destination_full"
			end
			if normalized.kind == "withdraw" and not config.fits(profile, destination, destinationCopy) then
				return nil, "destination_full"
			end
			if #bank.receiptOrder == config.maxReceipts then
				local evicted = assert(table.remove(bank.receiptOrder, 1))
				bank.receipts[evicted] = nil
			end
			table.insert(bank.receiptOrder, normalized.requestId)
			bank.receipts[normalized.requestId] = normalized
			local updated =
				config.writeProfile(profile, if normalized.kind == "deposit" then sourceCopy else destinationCopy, bank)
			return config.transfer(updated, normalized), nil
		end,
	}
end

return Bank
