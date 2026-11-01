--!strict

local Value = require("../value")

export type Inventory = { [string]: number }
export type Account = { gold: number, inventory: Inventory }
export type Ware = { itemId: string, price: number, stock: number? }
export type Vendor = { id: string, npcId: string, wares: { Ware } }
export type Decision = {
	ok: boolean,
	reason: string?,
	itemId: string?,
	quantity: number?,
	price: number?,
	gold: number?,
	action: string?,
}
export type Receipt = { id: number, itemId: string, quantity: number, unitPrice: number, expiresAt: number }
export type State = {
	stock: { [string]: { [string]: number } },
	buyback: { [string]: { Receipt } },
	nextReceipt: number,
}
export type Config = {
	maxQuantity: number,
	maxStack: number,
	exists: (string) -> boolean,
	sellValue: (string) -> number?,
	add: (Inventory, string, number) -> Inventory,
	remove: (Inventory, string, number) -> (Inventory, boolean),
	canCarry: (Inventory, Inventory, string?) -> boolean,
	buybackLimit: number,
	buybackSeconds: number,
}

local Exchange = {}

function Exchange.empty(): State
	return { stock = {}, buyback = {}, nextReceipt = 1 }
end

function Exchange.vendor(config: Config)
	assert(Value.whole(config.maxQuantity, 1, math.huge) ~= nil, "invalid quantity limit")
	assert(Value.whole(config.maxStack, 1, math.huge) ~= nil, "invalid stack limit")
	assert(Value.whole(config.buybackLimit, 0, math.huge) ~= nil, "invalid buyback limit")
	assert(config.buybackSeconds >= 0 and config.buybackSeconds < math.huge, "invalid buyback duration")
	local function validateVendor(value: unknown): (boolean, string?)
		local vendor = Value.raw(value)
		if vendor == nil or type(vendor.id) ~= "string" or vendor.id == "" then
			return false, "invalid_vendor"
		end
		if type(vendor.npcId) ~= "string" or vendor.npcId == "" or type(vendor.wares) ~= "table" then
			return false, "invalid_vendor"
		end
		local wares = assert(Value.raw(vendor.wares))
		local seen: { [string]: boolean } = {}
		for _, raw in wares do
			local ware = Value.raw(raw)
			if ware == nil or type(ware.itemId) ~= "string" or not config.exists(ware.itemId) then
				return false, "unknown_item_def"
			end
			if seen[ware.itemId] then
				return false, "duplicate_ware"
			end
			if Value.whole(ware.price, 1, math.huge) == nil then
				return false, "invalid_price"
			end
			if ware.stock ~= nil and Value.whole(ware.stock, 0, math.huge) == nil then
				return false, "invalid_stock"
			end
			seen[ware.itemId] = true
		end
		if #wares == 0 then
			return false, "empty_wares"
		end
		return true, nil
	end
	local function wareFor(vendor: Vendor, itemId: string): Ware?
		for _, ware in vendor.wares do
			if ware.itemId == itemId then
				return ware
			end
		end
		return nil
	end
	local function request(vendor: Vendor, itemId: unknown, quantity: unknown): (string?, number?, string?)
		local valid, reason = validateVendor(vendor)
		if not valid then
			return nil, nil, reason
		end
		if type(itemId) ~= "string" or itemId == "" then
			return nil, nil, "invalid_item"
		end
		local count = Value.whole(quantity, 1, config.maxQuantity)
		if count == nil then
			return nil, nil, "invalid_quantity"
		end
		return itemId, count, nil
	end
	local function purchase(
		account: Account,
		itemId: string,
		quantity: number,
		price: number,
		bag: string?
	): (Account, Decision)
		if (account.inventory[itemId] or 0) + quantity > config.maxStack then
			return account, { ok = false, reason = "stack_full" }
		end
		local total = price * quantity
		if Value.whole(account.gold, 0, math.huge) == nil or account.gold < total then
			return account, { ok = false, reason = "insufficient_gold", price = total, gold = account.gold }
		end
		local inventory = config.add(account.inventory, itemId, quantity)
		if not config.canCarry(account.inventory, inventory, bag) then
			return account, { ok = false, reason = "inventory_full", price = total, gold = account.gold }
		end
		local gold = account.gold - total
		return { gold = gold, inventory = inventory }, {
			ok = true,
			itemId = itemId,
			quantity = quantity,
			price = total,
			gold = gold,
		}
	end
	local function buy(
		account: Account,
		vendor: Vendor,
		itemId: unknown,
		quantity: unknown,
		bag: string?
	): (Account, Decision)
		local id, count, reason = request(vendor, itemId, quantity)
		if id == nil or count == nil then
			return account, { ok = false, reason = reason }
		end
		local ware = wareFor(vendor, id)
		if ware == nil then
			return account, { ok = false, reason = "not_sold" }
		end
		return purchase(account, id, count, ware.price, bag)
	end
	local function sell(account: Account, vendor: Vendor, itemId: unknown, quantity: unknown): (Account, Decision)
		local id, count, reason = request(vendor, itemId, quantity)
		if id == nil or count == nil then
			return account, { ok = false, reason = reason, action = "sell" }
		end
		local value = config.sellValue(id)
		if value == nil or Value.whole(value, 0, math.huge) == nil then
			return account, { ok = false, reason = "not_sellable", action = "sell" }
		end
		local inventory, removed = config.remove(account.inventory, id, count)
		if not removed or Value.whole(account.gold, 0, math.huge) == nil then
			return account, { ok = false, reason = "not_held", action = "sell" }
		end
		local total = value * count
		local gold = account.gold + total
		if Value.whole(gold, 0, math.huge) == nil then
			return account, { ok = false, reason = "invalid_gold", action = "sell" }
		end
		return { gold = gold, inventory = inventory }, {
			ok = true,
			itemId = id,
			quantity = count,
			price = total,
			gold = gold,
			action = "sell",
		}
	end
	local function buyStock(
		state: State,
		account: Account,
		vendor: Vendor,
		itemId: unknown,
		quantity: unknown,
		bag: string?
	): (State, Account, Decision)
		local id, count, reason = request(vendor, itemId, quantity)
		if id == nil or count == nil then
			return state, account, { ok = false, reason = reason }
		end
		local ware = wareFor(vendor, id)
		local remaining = if ware ~= nil then (state.stock[vendor.id] or {})[id] or ware.stock else nil
		if remaining ~= nil and count > remaining then
			return state, account, { ok = false, reason = "out_of_stock" }
		end
		local updated, decision = buy(account, vendor, id, count, bag)
		if not decision.ok or remaining == nil then
			return state, updated, decision
		end
		local stock = table.clone(state.stock)
		local wares = table.clone(stock[vendor.id] or {})
		wares[id] = remaining - count
		stock[vendor.id] = wares
		return { stock = stock, buyback = state.buyback, nextReceipt = state.nextReceipt }, updated, decision
	end
	local function sellBack(
		state: State,
		account: Account,
		vendor: Vendor,
		sender: string,
		itemId: unknown,
		quantity: unknown,
		now: number
	): (State, Account, Decision)
		if now ~= now or math.abs(now) == math.huge then
			return state, account, { ok = false, reason = "invalid_time", action = "sell" }
		end
		local updated, decision = sell(account, vendor, itemId, quantity)
		if not decision.ok or config.buybackLimit == 0 then
			return state, updated, decision
		end
		local rows: { Receipt } = {}
		for _, receipt in state.buyback[sender] or {} do
			if receipt.expiresAt > now then
				table.insert(rows, receipt)
			end
		end
		local receipt: Receipt = {
			id = state.nextReceipt,
			itemId = assert(decision.itemId),
			quantity = assert(decision.quantity),
			unitPrice = assert(decision.price) / assert(decision.quantity),
			expiresAt = now + config.buybackSeconds,
		}
		table.insert(rows, receipt)
		while #rows > config.buybackLimit do
			table.remove(rows, 1)
		end
		local receipts = table.clone(state.buyback)
		receipts[sender] = rows
		return { stock = state.stock, buyback = receipts, nextReceipt = state.nextReceipt + 1 }, updated, decision
	end
	local function buyBack(
		state: State,
		account: Account,
		sender: string,
		receiptId: number,
		quantity: unknown,
		bag: string?,
		now: number
	): (State, Account, Decision)
		if now ~= now or math.abs(now) == math.huge then
			return state, account, { ok = false, reason = "invalid_time" }
		end
		local count = Value.whole(quantity, 1, config.maxQuantity)
		if count == nil then
			return state, account, { ok = false, reason = "invalid_quantity" }
		end
		local rows = state.buyback[sender] or {}
		for index, receipt in rows do
			if receipt.id ~= receiptId then
				continue
			end
			if now >= receipt.expiresAt then
				return state, account, { ok = false, reason = "buyback_expired" }
			end
			if count > receipt.quantity then
				return state, account, { ok = false, reason = "not_held" }
			end
			local updated, decision = purchase(account, receipt.itemId, count, receipt.unitPrice, bag)
			if not decision.ok then
				return state, account, decision
			end
			local nextRows = table.clone(rows)
			if count == receipt.quantity then
				table.remove(nextRows, index)
			else
				local remaining = table.clone(receipt)
				remaining.quantity -= count
				nextRows[index] = remaining
			end
			local receipts = table.clone(state.buyback)
			receipts[sender] = nextRows
			return { stock = state.stock, buyback = receipts, nextReceipt = state.nextReceipt }, updated, decision
		end
		return state, account, { ok = false, reason = "unknown_buyback" }
	end
	return table.freeze({
		validateVendor = validateVendor,
		buy = buy,
		sell = sell,
		buyStock = buyStock,
		sellBack = sellBack,
		buyBack = buyBack,
	})
end

return table.freeze(Exchange)
