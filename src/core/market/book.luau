--!strict

local Value = require("../../kernel/value")

export type Listing = {
	listingId: string,
	itemId: string?,
	sellerId: number,
	count: number,
	unitPrice: number,
	listedAtSec: number,
	expiresAtSec: number,
}

export type ReceiptKind = "proceeds" | "purchase" | "return"

export type Receipt = {
	receiptId: string,
	itemId: string?,
	ownerId: number,
	kind: ReceiptKind,
	opId: string,
	coin: number,
	goods: number,
	issuedAtSec: number,
}

export type Operation = { fingerprint: string, atSec: number, actorId: number }

export type State = {
	schemaVersion: number,
	realmId: string,
	materialId: string,
	feeBps: number,
	lastClockSec: number,
	listings: { Listing },
	receipts: { Receipt },
	operations: { [string]: Operation },
	operationOrder: { string },
	burnedCoin: number,
}

export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	receipts: { Receipt }?,
	fence: string?,
}

type Raw = Value.Raw
export type Command =
	{
		kind: "list",
		opId: string,
		itemId: string?,
		actorId: number,
		actorRealmId: string,
		count: number,
		unitPrice: number,
	}
	| { kind: "cancel", opId: string, itemId: string?, actorId: number, listingId: string }
	| {
		kind: "fill",
		opId: string,
		itemId: string?,
		actorId: number,
		actorRealmId: string,
		quantity: number,
		ceilingUnitPrice: number,
		holdCoin: number,
	}
	| { kind: "ack", opId: string, itemId: string?, actorId: number, receiptIds: { string } }
	| { kind: "sweep", opId: string, itemId: string?, actorId: number? }
	| { kind: "void", opId: string, itemId: string?, actorId: number? }
export type Search = { limit: number?, sellerId: number?, itemId: string?, ceilingUnitPrice: number? }
export type Config = {
	listingTtlSec: number,
	minFeeBps: number,
	maxFeeBps: number,
	defaultFeeBps: number,
	maxListings: number,
	maxReceipts: number,
	operationRetentionSec: number,
	actorWindowSec: number,
	maxReceiptsPerOwner: number,
	maxOperations: number,
	maxOperationsPerActor: number,
	maxListingsPerSeller: number,
	maxCount: number,
	maxPrice: number,
	maxId: number,
	maxTime: number,
	maxCoin: number,
	categoryPrefix: string,
	maxSearch: number,
	realms: { [string]: boolean },
}

local Market = {}

function Market.book(config: Config)
	local SCHEMA_VERSION = 1
	local freezeDeep = Value.freezeDeep
	local function whole(value: unknown, low: number, high: number): boolean
		return Value.whole(value, low, high) ~= nil
	end
	local function opaque(value: unknown, limit: number): boolean
		return Value.opaque(value, limit) ~= nil
	end
	local function exact(value: unknown, fields: { [string]: boolean }): boolean
		return Value.record(value, fields, true) ~= nil
	end
	local dense = Value.dense

	local STATE_FIELDS = Value.freezeDeep({
		schemaVersion = true,
		realmId = true,
		materialId = true,
		feeBps = true,
		lastClockSec = true,
		listings = true,
		receipts = true,
		operations = true,
		operationOrder = true,
		burnedCoin = true,
	})
	local LISTING_FIELDS = Value.freezeDeep({
		listingId = true,
		sellerId = true,
		count = true,
		unitPrice = true,
		listedAtSec = true,
		expiresAtSec = true,
	})
	local RECEIPT_FIELDS = Value.freezeDeep({
		receiptId = true,
		ownerId = true,
		kind = true,
		opId = true,
		coin = true,
		goods = true,
		issuedAtSec = true,
	})
	local function withItem(fields: { [string]: boolean }): { [string]: boolean }
		local out = table.clone(fields)
		out.itemId = true
		return Value.freezeDeep(out)
	end

	local function shapeFor(
		value: unknown,
		plain: { [string]: boolean },
		withId: { [string]: boolean }
	): { [string]: boolean }
		return if type(value) == "table" and (assert(Value.raw(value))).itemId ~= nil then withId else plain
	end

	local LISTING_ITEM_FIELDS = withItem(LISTING_FIELDS)
	local RECEIPT_ITEM_FIELDS = withItem(RECEIPT_FIELDS)
	local COMMAND_FIELDS: { [string]: { [string]: boolean } } = Value.freezeDeep({
		list = Value.freezeDeep({
			kind = true,
			opId = true,
			actorId = true,
			actorRealmId = true,
			count = true,
			unitPrice = true,
		}),
		cancel = Value.freezeDeep({ kind = true, opId = true, actorId = true, listingId = true }),
		fill = Value.freezeDeep({
			kind = true,
			opId = true,
			actorId = true,
			actorRealmId = true,
			quantity = true,
			ceilingUnitPrice = true,
			holdCoin = true,
		}),
		ack = Value.freezeDeep({ kind = true, opId = true, actorId = true, receiptIds = true }),
		sweep = Value.freezeDeep({ kind = true, opId = true }),
		void = Value.freezeDeep({ kind = true, opId = true }),
	})

	local function copyListing(value: unknown): Listing?
		local raw = Value.record(value, shapeFor(value, LISTING_FIELDS, LISTING_ITEM_FIELDS), true)
		if raw == nil then
			return nil
		end
		local listingId = Value.opaque(raw.listingId, config.maxId)
		local sellerId = Value.whole(raw.sellerId, 1, config.maxTime)
		local count = Value.whole(raw.count, 1, config.maxCount)
		local unitPrice = Value.whole(raw.unitPrice, 1, config.maxPrice)
		local listedAtSec = Value.whole(raw.listedAtSec, 0, config.maxTime)
		local expiresAtSec = Value.whole(raw.expiresAtSec, 0, config.maxTime)
		local itemId = if raw.itemId ~= nil then Value.opaque(raw.itemId, config.maxId) else nil
		if
			listingId == nil
			or sellerId == nil
			or count == nil
			or unitPrice == nil
			or listedAtSec == nil
			or expiresAtSec == nil
			or (raw.itemId ~= nil and itemId == nil)
			or expiresAtSec < listedAtSec
		then
			return nil
		end
		return {
			listingId = listingId,
			sellerId = sellerId,
			count = count,
			unitPrice = unitPrice,
			listedAtSec = listedAtSec,
			expiresAtSec = expiresAtSec,
			itemId = itemId,
		}
	end

	local function copyReceipt(value: unknown): Receipt?
		local raw = Value.record(value, shapeFor(value, RECEIPT_FIELDS, RECEIPT_ITEM_FIELDS), true)
		if raw == nil then
			return nil
		end
		local receiptId = Value.opaque(raw.receiptId, config.maxId * 2)
		local ownerId = Value.whole(raw.ownerId, 1, config.maxTime)
		local kind = raw.kind
		local opId = Value.opaque(raw.opId, config.maxId)
		local coin = Value.whole(raw.coin, 0, config.maxCoin)
		local goods = Value.whole(raw.goods, 0, config.maxCount * config.maxListings)
		local issuedAtSec = Value.whole(raw.issuedAtSec, 0, config.maxTime)
		local itemId = if raw.itemId ~= nil then Value.opaque(raw.itemId, config.maxId) else nil
		if
			receiptId == nil
			or ownerId == nil
			or (kind ~= "proceeds" and kind ~= "purchase" and kind ~= "return")
			or opId == nil
			or coin == nil
			or goods == nil
			or issuedAtSec == nil
			or (raw.itemId ~= nil and itemId == nil)
		then
			return nil
		end
		return {
			receiptId = receiptId,
			ownerId = ownerId,
			kind = kind,
			opId = opId,
			coin = coin,
			goods = goods,
			issuedAtSec = issuedAtSec,
			itemId = itemId,
		}
	end

	local function copyState(value: unknown): State?
		local raw = Value.record(value, STATE_FIELDS, true)
		if raw == nil then
			return nil
		end
		local realmId = raw.realmId
		local materialId = Value.opaque(raw.materialId, config.maxId)
		local feeBps = Value.whole(raw.feeBps, config.minFeeBps, config.maxFeeBps)
		local lastClockSec = Value.whole(raw.lastClockSec, 0, config.maxTime)
		local burnedCoin = Value.whole(raw.burnedCoin, 0, config.maxCoin)
		local listingRows = dense(raw.listings, config.maxListings)
		local receiptRows = dense(raw.receipts, config.maxReceipts + config.maxListings)
		local orderRows = dense(raw.operationOrder, config.maxOperations)
		local operationRows = Value.raw(raw.operations)
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or type(realmId) ~= "string"
			or config.realms[realmId] ~= true
			or materialId == nil
			or feeBps == nil
			or lastClockSec == nil
			or burnedCoin == nil
			or listingRows == nil
			or receiptRows == nil
			or orderRows == nil
			or operationRows == nil
		then
			return nil
		end
		local listings: { Listing } = {}
		local seenListings: { [string]: boolean } = {}
		for _, entry in listingRows do
			local listing = copyListing(entry)
			if listing == nil or seenListings[listing.listingId] then
				return nil
			end
			seenListings[listing.listingId] = true
			table.insert(listings, listing)
		end
		local receipts: { Receipt } = {}
		local seenReceipts: { [string]: boolean } = {}
		for _, entry in receiptRows do
			local receipt = copyReceipt(entry)
			if receipt == nil or seenReceipts[receipt.receiptId] then
				return nil
			end
			seenReceipts[receipt.receiptId] = true
			table.insert(receipts, receipt)
		end
		local operations: { [string]: Operation } = {}
		local operationOrder: { string } = {}
		for _, candidate in orderRows do
			local opId = Value.opaque(candidate, config.maxId)
			if opId == nil or operations[opId] ~= nil then
				return nil
			end
			local operation =
				Value.record(operationRows[opId], { fingerprint = true, atSec = true, actorId = true }, true)
			if operation == nil then
				return nil
			end
			local fingerprint = Value.opaque(operation.fingerprint, 16)
			local actorId = Value.whole(operation.actorId, 0, config.maxTime)
			local atSec = Value.whole(operation.atSec, 0, config.maxTime)
			if fingerprint == nil or actorId == nil or atSec == nil then
				return nil
			end
			operations[opId] = { fingerprint = fingerprint, actorId = actorId, atSec = atSec }
			table.insert(operationOrder, opId)
		end
		for opId in operationRows do
			if type(opId) ~= "string" or operations[opId] == nil then
				return nil
			end
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			realmId = realmId,
			materialId = materialId,
			feeBps = feeBps,
			lastClockSec = lastClockSec,
			listings = listings,
			receipts = receipts,
			operations = operations,
			operationOrder = operationOrder,
			burnedCoin = burnedCoin,
		}
	end

	local function result(value: Result): Result
		return freezeDeep(value)
	end

	local function refused(reason: string): Result
		return result({ ok = false, state = nil, replayed = false, reason = reason, receipts = nil })
	end

	local function hashText(text: string): string
		local first = 2166136261
		local second = 5381
		for index = 1, #text do
			local byte = string.byte(text, index)
			first = bit32.bxor(first, byte)
			first = (first * 16777619) % 4294967296
			second = (second * 33 + byte) % 4294967296
		end
		return string.format("%08x%08x", first, second)
	end

	local VOID_MARK = "voidvoidvoidvoid"

	local function fingerprint(command: Raw): string
		local keys: { string } = {}
		for key in command do
			assert(type(key) == "string")
			keys[#keys + 1] = key
		end
		table.sort(keys)
		local parts: { string } = {}
		for _, key in keys do
			local value = command[key]
			if type(value) == "table" then
				local items: { string } = {}
				for _, item in assert(Value.dense(value, math.huge, false)) do
					assert(type(item) == "string")
					table.insert(items, item)
				end
				table.sort(items)
				value = table.concat(items, ",")
			end
			parts[#parts + 1] = key .. "=" .. tostring(value)
		end
		return hashText(table.concat(parts, "|"))
	end

	local function listingBefore(left: Listing, right: Listing): boolean
		if left.unitPrice ~= right.unitPrice then
			return left.unitPrice < right.unitPrice
		end
		if left.listedAtSec ~= right.listedAtSec then
			return left.listedAtSec < right.listedAtSec
		end
		return left.listingId < right.listingId
	end

	local function ownerReceipts(state: State, ownerId: number): number
		local count = 0
		for _, receipt in state.receipts do
			if receipt.ownerId == ownerId then
				count += 1
			end
		end
		return count
	end

	local function feeFor(gross: number, feeBps: number): number
		return math.ceil(gross * feeBps / 10000)
	end

	local function categoryBook(materialId: string): boolean
		return string.sub(materialId, 1, #config.categoryPrefix) == config.categoryPrefix
	end

	local function expire(state: State, nowSec: number)
		local open: { Listing } = {}
		for _, listing in state.listings do
			if listing.expiresAtSec <= nowSec then
				state.receipts[#state.receipts + 1] = {
					receiptId = "return:" .. listing.listingId,
					itemId = listing.itemId,
					ownerId = listing.sellerId,
					kind = "return",
					opId = listing.listingId,
					coin = 0,
					goods = listing.count,
					issuedAtSec = nowSec,
				}
			else
				open[#open + 1] = listing
			end
		end
		state.listings = open
	end

	local function actorOperations(state: State, actorId: number, nowSec: number): number
		local count = 0
		for _, operation in state.operations do
			if operation.actorId == actorId and nowSec - operation.atSec < config.actorWindowSec then
				count += 1
			end
		end
		return count
	end

	local function remember(state: State, opId: string, mark: string, nowSec: number, actorId: number): string?
		while #state.operationOrder > 0 do
			local oldest = state.operationOrder[1]
			if nowSec - state.operations[oldest].atSec < config.operationRetentionSec then
				break
			end
			table.remove(state.operationOrder, 1)
			state.operations[oldest] = nil
		end
		if actorId ~= 0 and actorOperations(state, actorId, nowSec) >= config.maxOperationsPerActor then
			return "actor_saturated"
		end
		state.operations[opId] = { fingerprint = mark, atSec = nowSec, actorId = actorId }
		state.operationOrder[#state.operationOrder + 1] = opId
		if #state.operationOrder > config.maxOperations then
			return "book_saturated"
		end
		return nil
	end

	local Book = {}

	function Book.emptyState(realmId: unknown, materialId: unknown, feeBps: unknown): State?
		local fee =
			Value.whole(if feeBps == nil then config.defaultFeeBps else feeBps, config.minFeeBps, config.maxFeeBps)
		local material = Value.opaque(materialId, config.maxId)
		if type(realmId) ~= "string" or config.realms[realmId] ~= true or material == nil or fee == nil then
			return nil
		end
		return freezeDeep({
			schemaVersion = SCHEMA_VERSION,
			realmId = realmId,
			materialId = material,
			feeBps = fee,
			lastClockSec = 0,
			listings = {},
			receipts = {},
			operations = {},
			operationOrder = {},
			burnedCoin = 0,
		})
	end

	function Book.projectState(value: unknown): State?
		local state = copyState(value)
		return if state == nil then nil else freezeDeep(state)
	end

	function Book.knowsOperation(value: unknown, opId: unknown): boolean
		local state = copyState(value)
		return state ~= nil and type(opId) == "string" and state.operations[opId] ~= nil
	end

	function Book.apply(previous: unknown, commandValue: unknown, nowSecValue: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		local command = Value.raw(commandValue)
		if command == nil or type(command.kind) ~= "string" then
			return refused("command_invalid")
		end
		local kind = command.kind
		local fields = COMMAND_FIELDS[kind]
		local opId = Value.opaque(command.opId, config.maxId)
		if
			fields == nil
			or not exact(
				commandValue,
				if command.itemId ~= nil and (kind == "list" or kind == "fill") then withItem(fields) else fields
			)
			or opId == nil
		then
			return refused("command_invalid")
		end
		local nowSec = Value.whole(nowSecValue, 0, config.maxTime)
		if nowSec == nil then
			return refused("clock_invalid")
		end
		local mark = fingerprint(command)
		local prior = state.operations[opId]
		if command.kind == "void" then
			if prior ~= nil then
				return result({
					ok = true,
					state = state,
					replayed = true,
					reason = nil,
					receipts = {},
					fence = if prior.fingerprint == VOID_MARK then "voided" else "known",
				})
			end
		elseif prior ~= nil then
			if prior.fingerprint == mark then
				return result({ ok = true, state = state, replayed = true, reason = nil, receipts = {} })
			end
			return refused(if prior.fingerprint == VOID_MARK then "operation_void" else "operation_conflict")
		end
		if nowSec < state.lastClockSec then
			return refused("clock_regressed")
		end
		expire(state, nowSec)
		local issued: { Receipt } = {}
		local function issue(receipt: Receipt)
			state.receipts[#state.receipts + 1] = receipt
			issued[#issued + 1] = receipt
		end

		if command.kind == "list" then
			local actorId = Value.whole(command.actorId, 1, config.maxTime)
			local count = Value.whole(command.count, 1, config.maxCount)
			local unitPrice = Value.whole(command.unitPrice, 1, config.maxPrice)
			if actorId == nil or count == nil or unitPrice == nil then
				return refused("command_invalid")
			end
			if command.actorRealmId ~= state.realmId then
				return refused("realm_foreign")
			end
			if
				categoryBook(state.materialId) ~= (command.itemId ~= nil)
				or (command.itemId ~= nil and not opaque(command.itemId, config.maxId))
			then
				return refused("command_invalid")
			end
			if #state.listings >= config.maxListings then
				return refused("book_full")
			end
			if ownerReceipts(state, actorId) >= config.maxReceiptsPerOwner then
				return refused("receipts_unclaimed")
			end
			local held = 0
			for _, listing in state.listings do
				if listing.sellerId == actorId then
					held += 1
				end
			end
			if held >= config.maxListingsPerSeller then
				return refused("seller_listing_cap")
			end
			state.listings[#state.listings + 1] = {
				listingId = opId,
				itemId = if type(command.itemId) == "string" then command.itemId else nil,
				sellerId = actorId,
				count = count,
				unitPrice = unitPrice,
				listedAtSec = nowSec,
				expiresAtSec = nowSec + config.listingTtlSec,
			}
		elseif command.kind == "cancel" then
			local index: number? = nil
			for position, listing in state.listings do
				if listing.listingId == command.listingId then
					index = position
				end
			end
			if index == nil then
				return refused("listing_closed")
			end
			local listing = state.listings[index]
			if listing.sellerId ~= command.actorId then
				return refused("listing_not_owned")
			end
			table.remove(state.listings, index)
			issue({
				receiptId = "return:" .. listing.listingId,
				itemId = listing.itemId,
				ownerId = listing.sellerId,
				kind = "return",
				opId = opId,
				coin = 0,
				goods = listing.count,
				issuedAtSec = nowSec,
			})
		elseif command.kind == "fill" then
			local actorId = Value.whole(command.actorId, 1, config.maxTime)
			local quantity = Value.whole(command.quantity, 1, config.maxCount)
			local ceilingUnitPrice = Value.whole(command.ceilingUnitPrice, 1, config.maxPrice)
			local holdCoin = Value.whole(command.holdCoin, 1, config.maxCoin)
			if actorId == nil or quantity == nil or ceilingUnitPrice == nil or holdCoin == nil then
				return refused("command_invalid")
			end
			if command.actorRealmId ~= state.realmId then
				return refused("realm_foreign")
			end
			if
				categoryBook(state.materialId) ~= (command.itemId ~= nil)
				or (command.itemId ~= nil and not opaque(command.itemId, config.maxId))
			then
				return refused("command_invalid")
			end
			if ownerReceipts(state, actorId) >= config.maxReceiptsPerOwner then
				return refused("receipts_unclaimed")
			end
			local eligible: { Listing } = {}
			for _, listing in state.listings do
				if
					listing.sellerId ~= actorId
					and listing.itemId == command.itemId
					and listing.unitPrice <= ceilingUnitPrice
					and ownerReceipts(state, listing.sellerId) < config.maxReceiptsPerOwner
				then
					eligible[#eligible + 1] = listing
				end
			end
			table.sort(eligible, listingBefore)
			local remaining = quantity
			local takes: { { listing: Listing, count: number } } = {}
			local spent = 0
			for _, listing in eligible do
				if remaining == 0 then
					break
				end
				local take = math.min(remaining, listing.count)
				takes[#takes + 1] = { listing = listing, count = take }
				spent += take * listing.unitPrice
				remaining -= take
			end
			local filled = quantity - remaining
			if filled == 0 then
				return refused("no_supply")
			end
			if spent > holdCoin then
				return refused("hold_insufficient")
			end
			for index, take in takes do
				local gross = take.count * take.listing.unitPrice
				local fee = feeFor(gross, state.feeBps)
				state.burnedCoin += fee
				take.listing.count -= take.count
				issue({
					receiptId = ("%s:proceeds:%d"):format(opId, index),
					ownerId = take.listing.sellerId,
					kind = "proceeds",
					opId = opId,
					coin = gross - fee,
					goods = 0,
					issuedAtSec = nowSec,
				})
			end
			local open: { Listing } = {}
			for _, listing in state.listings do
				if listing.count > 0 then
					open[#open + 1] = listing
				end
			end
			state.listings = open
			issue({
				receiptId = opId .. ":purchase",
				itemId = if type(command.itemId) == "string" then command.itemId else nil,
				ownerId = actorId,
				kind = "purchase",
				opId = opId,
				coin = spent,
				goods = filled,
				issuedAtSec = nowSec,
			})
		elseif command.kind == "ack" then
			if
				not whole(command.actorId, 1, config.maxTime)
				or dense(command.receiptIds, config.maxReceipts) == nil
			then
				return refused("command_invalid")
			end
			local acknowledged: { [string]: boolean } = {}
			for _, candidate in assert(dense(command.receiptIds, config.maxReceipts)) do
				local receiptId = Value.opaque(candidate, config.maxId * 2)
				if receiptId == nil then
					return refused("command_invalid")
				end
				acknowledged[receiptId] = true
			end
			local kept: { Receipt } = {}
			for _, receipt in state.receipts do
				if not (acknowledged[receipt.receiptId] and receipt.ownerId == command.actorId) then
					kept[#kept + 1] = receipt
				end
			end
			state.receipts = kept
		end
		local retained = command.kind == "list"
			or command.kind == "cancel"
			or command.kind == "fill"
			or command.kind == "void"
		if retained and command.kind ~= "void" and #state.receipts > config.maxReceipts then
			return refused("book_saturated")
		end
		if retained then
			local actorId = if command.kind == "void"
				then 0
				else assert(Value.whole(command.actorId, 1, config.maxTime))
			local saturated = remember(state, opId, if command.kind == "void" then VOID_MARK else mark, nowSec, actorId)
			if saturated ~= nil then
				return refused(saturated)
			end
		end
		state.lastClockSec = nowSec
		return result({
			ok = true,
			state = state,
			replayed = false,
			reason = nil,
			receipts = issued,
			fence = if command.kind == "void" then "voided" else nil,
		})
	end

	function Book.search(value: unknown, query: unknown, nowSecValue: unknown): { Listing }?
		local state = copyState(value)
		local raw = Value.raw(query)
		local now = Value.whole(nowSecValue, 0, config.maxTime)
		if state == nil or raw == nil or now == nil then
			return nil
		end
		local limit = Value.whole(if raw.limit == nil then config.maxSearch else raw.limit, 1, config.maxSearch)
		if limit == nil then
			return nil
		end
		local ceiling = if type(raw.ceilingUnitPrice) == "number" then raw.ceilingUnitPrice else nil
		if raw.ceilingUnitPrice ~= nil and ceiling == nil then
			return nil
		end
		local rows: { Listing } = {}
		for _, listing in state.listings do
			if
				listing.expiresAtSec > now
				and (raw.sellerId == nil or listing.sellerId == raw.sellerId)
				and (raw.itemId == nil or listing.itemId == raw.itemId)
				and (ceiling == nil or listing.unitPrice <= ceiling)
			then
				table.insert(rows, listing)
			end
		end
		table.sort(rows, listingBefore)
		local page: { Listing } = {}
		for index = 1, math.min(limit, #rows) do
			page[index] = rows[index]
		end
		return freezeDeep(page)
	end

	function Book.receiptsFor(value: unknown, ownerId: unknown): { Receipt }?
		local state = copyState(value)
		if state == nil then
			return nil
		end
		local rows: { Receipt } = {}
		for _, receipt in state.receipts do
			if receipt.ownerId == ownerId then
				rows[#rows + 1] = receipt
			end
		end
		return freezeDeep(rows)
	end

	Book.feeFor = feeFor
	return Book
end

return Market
