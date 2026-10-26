--!strict

local Value = require("../internal/value")

export type Pending = {
	kind: "consign" | "buy",
	realmId: string,
	materialId: string,
	bookId: string?,
	count: number,
	hold: number,
	startedAtSec: number,
}

export type State = {
	schemaVersion: number,
	userId: number,
	coin: number,
	goods: { [string]: number },
	pending: { [string]: Pending },
	claimedOrder: { string },
}

export type Ledger = {
	schemaVersion: number,
	pending: { [string]: Pending },
	claimedOrder: { string },
}

export type Result =
	{ ok: true, state: State, replayed: boolean, reason: nil }
	| { ok: false, state: nil, replayed: false, reason: string }

export type Config = {
	claimedWindow: number,
	healRetentionSec: number,
	maxPending: number,
	maxId: number,
	maxCount: number,
	maxCoin: number,
	maxTime: number,
	realms: { [string]: boolean },
}

local Wallets = {}

function Wallets.wallet(config: Config)
	local SCHEMA_VERSION = 1
	local freezeDeep = Value.freezeDeep
	local dense = Value.dense
	local function whole(value: unknown, low: number, high: number): boolean
		return Value.whole(value, low, high) ~= nil
	end
	local function opaque(value: unknown, limit: number): boolean
		return Value.opaque(value, limit) ~= nil
	end

	local STATE_FIELDS = Value.freezeDeep({
		schemaVersion = true,
		userId = true,
		coin = true,
		goods = true,
		pending = true,
		claimedOrder = true,
	})
	local PENDING_FIELDS = Value.freezeDeep({
		kind = true,
		realmId = true,
		materialId = true,
		count = true,
		hold = true,
		startedAtSec = true,
	})
	local PENDING_BOOK_FIELDS = Value.freezeDeep({
		kind = true,
		realmId = true,
		materialId = true,
		bookId = true,
		count = true,
		hold = true,
		startedAtSec = true,
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

	local RECEIPT_ITEM_FIELDS = Value.freezeDeep({
		receiptId = true,
		itemId = true,
		ownerId = true,
		kind = true,
		opId = true,
		coin = true,
		goods = true,
		issuedAtSec = true,
	})

	local function copyState(value: unknown): State?
		local raw = Value.record(value, STATE_FIELDS, true)
		if raw == nil then
			return nil
		end
		local userId = Value.whole(raw.userId, 1, config.maxTime)
		local coin = Value.whole(raw.coin, 0, config.maxCoin)
		local rawGoods, rawPending = Value.raw(raw.goods), Value.raw(raw.pending)
		local rawOrder = dense(raw.claimedOrder, config.claimedWindow)
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or userId == nil
			or coin == nil
			or rawGoods == nil
			or rawPending == nil
			or rawOrder == nil
		then
			return nil
		end
		local goods: { [string]: number } = {}
		for key, value in rawGoods do
			local materialId, count = Value.opaque(key, config.maxId), Value.whole(value, 1, config.maxCount)
			if materialId == nil or count == nil then
				return nil
			end
			goods[materialId] = count
		end
		local pending: { [string]: Pending } = {}
		local pendingCount = 0
		for key, value in rawPending do
			local opId = Value.opaque(key, config.maxId)
			local probe = Value.raw(value)
			local entry = Value.record(
				value,
				if probe ~= nil and probe.bookId ~= nil then PENDING_BOOK_FIELDS else PENDING_FIELDS,
				true
			)
			if opId == nil or entry == nil then
				return nil
			end
			local kind, realmId = entry.kind, entry.realmId
			local materialId = Value.opaque(entry.materialId, config.maxId)
			local bookId = if entry.bookId ~= nil then Value.opaque(entry.bookId, config.maxId) else nil
			local count = Value.whole(entry.count, 0, config.maxCount)
			local hold = Value.whole(entry.hold, 0, config.maxCoin)
			local startedAtSec = Value.whole(entry.startedAtSec, 0, config.maxTime)
			if
				(kind ~= "consign" and kind ~= "buy")
				or type(realmId) ~= "string"
				or config.realms[realmId] ~= true
				or materialId == nil
				or (entry.bookId ~= nil and bookId == nil)
				or count == nil
				or hold == nil
				or startedAtSec == nil
				or (kind == "consign" and (count < 1 or hold ~= 0))
				or (kind == "buy" and (hold < 1 or count ~= 0))
			then
				return nil
			end
			pending[opId] = {
				kind = kind,
				realmId = realmId,
				materialId = materialId,
				bookId = bookId,
				count = count,
				hold = hold,
				startedAtSec = startedAtSec,
			}
			pendingCount += 1
		end
		if pendingCount > config.maxPending then
			return nil
		end
		local claimedOrder: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, value in rawOrder do
			local receiptId = Value.opaque(value, config.maxId * 2)
			if receiptId == nil or seen[receiptId] then
				return nil
			end
			seen[receiptId] = true
			table.insert(claimedOrder, receiptId)
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			userId = userId,
			coin = coin,
			goods = goods,
			pending = pending,
			claimedOrder = claimedOrder,
		}
	end

	local function refused(reason: string): Result
		local result: Result = { ok = false, state = nil, replayed = false, reason = reason }
		return freezeDeep(result)
	end

	local function accepted(state: State, replayed: boolean): Result
		local result: Result = { ok = true, state = state, replayed = replayed, reason = nil }
		return freezeDeep(result)
	end

	local function pendingCount(state: State): number
		local count = 0
		for _ in state.pending do
			count += 1
		end
		return count
	end

	local function addGoods(state: State, materialId: string, count: number)
		local total = (state.goods[materialId] or 0) + count
		if total > 0 then
			state.goods[materialId] = total
		else
			state.goods[materialId] = nil
		end
	end

	local Wallet = {}

	function Wallet.emptyState(userId: unknown, coin: unknown, goods: unknown): State?
		local state = copyState({
			schemaVersion = SCHEMA_VERSION,
			userId = userId,
			coin = coin,
			goods = goods,
			pending = {},
			claimedOrder = {},
		})
		return if state == nil then nil else freezeDeep(state)
	end

	function Wallet.projectState(value: unknown): State?
		local state = copyState(value)
		return if state == nil then nil else freezeDeep(state)
	end

	local function beginOperation(
		previous: unknown,
		kind: "consign" | "buy",
		opId: unknown,
		realmId: unknown,
		materialId: unknown,
		quantity: unknown,
		nowSec: unknown,
		bookId: unknown?
	): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		local book: string? = if type(bookId) == "string" then bookId else nil
		if
			type(opId) ~= "string"
			or not opaque(opId, config.maxId)
			or type(realmId) ~= "string"
			or config.realms[realmId] ~= true
			or type(materialId) ~= "string"
			or not opaque(materialId, config.maxId)
			or (bookId ~= nil and (book == nil or not opaque(book, config.maxId)))
			or type(quantity) ~= "number"
			or not whole(quantity, 1, if kind == "consign" then config.maxCount else config.maxCoin)
			or type(nowSec) ~= "number"
			or not whole(nowSec, 0, config.maxTime)
		then
			return refused("request_invalid")
		end
		local count = if kind == "consign" then quantity else 0
		local hold = if kind == "buy" then quantity else 0
		local existing = state.pending[opId]
		if existing ~= nil then
			return if existing.kind == kind
					and existing.realmId == realmId
					and existing.materialId == materialId
					and existing.bookId == book
					and existing.count == count
					and existing.hold == hold
				then accepted(state, true)
				else refused("operation_conflict")
		end
		if pendingCount(state) >= config.maxPending then
			return refused("pending_full")
		end
		if kind == "consign" then
			if (state.goods[materialId] or 0) < quantity then
				return refused("goods_insufficient")
			end
			addGoods(state, materialId, -quantity)
		else
			if state.coin < quantity then
				return refused("coin_insufficient")
			end
			state.coin -= quantity
		end
		state.pending[opId] = {
			kind = kind,
			realmId = realmId,
			materialId = materialId,
			bookId = book,
			count = count,
			hold = hold,
			startedAtSec = nowSec,
		}
		return accepted(state, false)
	end

	function Wallet.beginConsign(
		previous: unknown,
		opId: unknown,
		realmId: unknown,
		materialId: unknown,
		count: unknown,
		nowSec: unknown,
		bookId: unknown?
	): Result
		return beginOperation(previous, "consign", opId, realmId, materialId, count, nowSec, bookId)
	end

	function Wallet.beginBuy(
		previous: unknown,
		opId: unknown,
		realmId: unknown,
		materialId: unknown,
		hold: unknown,
		nowSec: unknown,
		bookId: unknown?
	): Result
		return beginOperation(previous, "buy", opId, realmId, materialId, hold, nowSec, bookId)
	end

	local function refundPending(state: State, opId: string, pending: Pending): Result
		if pending.kind == "consign" then
			addGoods(state, pending.materialId, pending.count)
		else
			state.coin += pending.hold
		end
		state.pending[opId] = nil
		return accepted(state, false)
	end

	function Wallet.refund(previous: unknown, opId: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		if type(opId) ~= "string" then
			return accepted(state, true)
		end
		local pending = state.pending[opId]
		if pending == nil then
			return accepted(state, true)
		end
		return refundPending(state, opId, pending)
	end

	function Wallet.settleConsign(previous: unknown, opId: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		local pending = if type(opId) == "string" then state.pending[opId] else nil
		if pending == nil then
			return accepted(state, true)
		end
		if pending.kind ~= "consign" then
			return refused("operation_conflict")
		end
		state.pending[assert(Value.opaque(opId, math.huge))] = nil
		return accepted(state, false)
	end

	function Wallet.claim(previous: unknown, receiptValue: unknown, materialId: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		local probe = Value.raw(receiptValue)
		local receipt = Value.record(
			receiptValue,
			if probe ~= nil and probe.itemId ~= nil then RECEIPT_ITEM_FIELDS else RECEIPT_FIELDS,
			true
		)
		local material = Value.opaque(materialId, config.maxId)
		if receipt == nil or material == nil then
			return refused("receipt_invalid")
		end
		local receiptId = receipt.receiptId
		if type(receiptId) ~= "string" then
			return refused("receipt_invalid")
		end
		if receipt.ownerId ~= state.userId then
			return refused("receipt_not_owned")
		end
		if table.find(state.claimedOrder, receiptId) ~= nil then
			return accepted(state, true)
		end
		if receipt.kind == "proceeds" then
			if Value.whole(receipt.coin, 0, config.maxCoin) == nil or receipt.goods ~= 0 then
				return refused("receipt_invalid")
			end
			state.coin += assert(Value.whole(receipt.coin, 0, config.maxCoin))
		elseif receipt.kind == "return" then
			if not whole(receipt.goods, 1, config.maxCount) or receipt.coin ~= 0 then
				return refused("receipt_invalid")
			end
			addGoods(state, material, assert(Value.whole(receipt.goods, 1, config.maxCount)))
		elseif receipt.kind == "purchase" then
			local pending = if type(receipt.opId) == "string" then state.pending[receipt.opId] else nil
			if pending == nil or pending.kind ~= "buy" or pending.materialId ~= materialId then
				return refused("purchase_unmatched")
			end
			if not whole(receipt.coin, 0, pending.hold) or not whole(receipt.goods, 1, config.maxCount) then
				return refused("receipt_invalid")
			end
			state.coin += pending.hold - assert(Value.whole(receipt.coin, 0, pending.hold))
			addGoods(state, material, assert(Value.whole(receipt.goods, 1, config.maxCount)))
			state.pending[assert(Value.opaque(receipt.opId, math.huge))] = nil
		else
			return refused("receipt_invalid")
		end
		state.claimedOrder[#state.claimedOrder + 1] = receiptId
		if #state.claimedOrder > config.claimedWindow then
			table.remove(state.claimedOrder, 1)
		end
		return accepted(state, false)
	end

	function Wallet.heal(previous: unknown, opId: unknown, bookKnowsOperation: unknown, nowSec: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		if type(bookKnowsOperation) ~= "boolean" or not whole(nowSec, 0, config.maxTime) then
			return refused("request_invalid")
		end
		if type(opId) ~= "string" then
			return accepted(state, true)
		end
		local pending = state.pending[opId]
		if pending == nil then
			return accepted(state, true)
		end
		if bookKnowsOperation then
			if pending.kind == "consign" then
				state.pending[opId] = nil
				return accepted(state, false)
			end
			return accepted(state, true)
		end
		if assert(Value.whole(nowSec, 0, config.maxTime)) - pending.startedAtSec >= config.healRetentionSec then
			return refused("heal_ambiguous")
		end
		return refundPending(state, opId, pending)
	end

	function Wallet.npcTrade(
		previous: unknown,
		side: unknown,
		materialId: unknown,
		count: unknown,
		unitPrice: unknown
	): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		local material = Value.opaque(materialId, config.maxId)
		local quantity, price = Value.whole(count, 1, config.maxCount), Value.whole(unitPrice, 1, config.maxCoin)
		if (side ~= "sell" and side ~= "buy") or material == nil or quantity == nil or price == nil then
			return refused("request_invalid")
		end
		local total = quantity * price
		if side == "sell" then
			if (state.goods[material] or 0) < quantity then
				return refused("goods_insufficient")
			end
			if state.coin + total > config.maxCoin then
				return refused("coin_overflow")
			end
			addGoods(state, material, -quantity)
			state.coin += total
		else
			if state.coin < total then
				return refused("coin_insufficient")
			end
			state.coin -= total
			addGoods(state, material, quantity)
		end
		return accepted(state, false)
	end

	function Wallet.emptyLedger(): Ledger
		return freezeDeep({ schemaVersion = SCHEMA_VERSION, pending = {}, claimedOrder = {} })
	end

	function Wallet.compose(userId: unknown, coin: unknown, goods: unknown, ledgerValue: unknown): State?
		local ledger = Value.record(ledgerValue, { schemaVersion = true, pending = true, claimedOrder = true }, true)
		if ledger == nil then
			return nil
		end
		return Wallet.projectState({
			schemaVersion = ledger.schemaVersion,
			userId = userId,
			coin = coin,
			goods = goods,
			pending = ledger.pending,
			claimedOrder = ledger.claimedOrder,
		})
	end

	local function ledgerFrom(state: State): Ledger
		return freezeDeep({
			schemaVersion = state.schemaVersion,
			pending = state.pending,
			claimedOrder = state.claimedOrder,
		})
	end

	function Wallet.projectLedger(userId: unknown, value: unknown): Ledger?
		local state = Wallet.compose(userId, 0, {}, value)
		if state == nil then
			return nil
		end
		return ledgerFrom(state)
	end

	function Wallet.ledgerOf(stateValue: unknown): Ledger?
		local state = copyState(stateValue)
		if state == nil then
			return nil
		end
		return ledgerFrom(state)
	end

	return Wallet
end

return Wallets
