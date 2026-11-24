--!strict

local SocialShape = require("../social/shape")

type Raw = { [unknown]: unknown }

export type Order = {
	orderId: string,
	realmId: string,
	itemId: string,
	count: number,
	payout: number,
	label: string,
}

export type Catalog = {
	weeklyCoinCap: number,
	orders: { [string]: Order },
	ordered: { Order },
}

type Receipt = { turnInId: string, payout: number }

export type State = {
	schemaVersion: number,
	weekIndex: number,
	paidThisWeek: number,
	carry: number,
	receiptOrder: { { turnInId: string, payout: number } },
}

export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	payout: number,
	consume: number,
	itemId: string?,
}

export type Config = {
	weekSec: number,
	weekAnchorSec: number,
	receiptWindow: number,
	maxId: number,
	maxOrders: number,
	maxCount: number,
	maxCoin: number,
	maxTime: number,
	realms: { [string]: boolean },
}

local System = {}

function System.patron(config: Config)
	local function readOrder(value: unknown): Order?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(
				value,
				{ orderId = true, realmId = true, itemId = true, count = true, payout = true, label = true }
			)
		then
			return nil
		end
		local orderId = SocialShape.string(raw.orderId)
		if orderId == nil then
			return nil
		end
		local realmId = SocialShape.string(raw.realmId)
		if realmId == nil then
			return nil
		end
		local itemId = SocialShape.string(raw.itemId)
		if itemId == nil then
			return nil
		end
		local count = SocialShape.number(raw.count)
		if count == nil then
			return nil
		end
		local payout = SocialShape.number(raw.payout)
		if payout == nil then
			return nil
		end
		local label = SocialShape.string(raw.label)
		if label == nil then
			return nil
		end
		return { orderId = orderId, realmId = realmId, itemId = itemId, count = count, payout = payout, label = label }
	end

	local function readReceipt(value: unknown): Receipt?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { turnInId = true, payout = true }) then
			return nil
		end
		local turnInId = SocialShape.string(raw.turnInId)
		if turnInId == nil then
			return nil
		end
		local payout = SocialShape.number(raw.payout)
		if payout == nil then
			return nil
		end
		return { turnInId = turnInId, payout = payout }
	end

	local function readState(value: unknown): State?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(
				value,
				{ schemaVersion = true, weekIndex = true, paidThisWeek = true, carry = true, receiptOrder = true }
			)
		then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local weekIndex = SocialShape.number(raw.weekIndex)
		if weekIndex == nil then
			return nil
		end
		local paidThisWeek = SocialShape.number(raw.paidThisWeek)
		if paidThisWeek == nil then
			return nil
		end
		local carry = SocialShape.number(raw.carry)
		if carry == nil then
			return nil
		end
		local receiptOrder = SocialShape.array(raw.receiptOrder, readReceipt)
		if receiptOrder == nil then
			return nil
		end
		return {
			schemaVersion = schemaVersion,
			weekIndex = weekIndex,
			paidThisWeek = paidThisWeek,
			carry = carry,
			receiptOrder = receiptOrder,
		}
	end

	local SCHEMA_VERSION = 1
	local WEEK_SEC = config.weekSec
	local WEEK_ANCHOR_SEC = config.weekAnchorSec
	local RECEIPT_WINDOW = config.receiptWindow
	local MAX_ID = config.maxId
	local MAX_ORDERS = config.maxOrders
	local MAX_COUNT = config.maxCount
	local MAX_COIN = config.maxCoin
	local MAX_TIME = config.maxTime
	local MAX_WEEK = math.floor(MAX_TIME / WEEK_SEC)
	local REALMS = config.realms

	local whole = SocialShape.whole
	local opaque = SocialShape.opaque
	local exact = SocialShape.exact
	local dense = SocialShape.dense
	local freezeDeep = SocialShape.freezeDeep

	local ORDER_FIELDS = SocialShape.freezeDeep({
		orderId = true,
		realmId = true,
		itemId = true,
		count = true,
		payout = true,
		label = true,
	})
	local STATE_FIELDS = SocialShape.freezeDeep({
		schemaVersion = true,
		weekIndex = true,
		paidThisWeek = true,
		carry = true,
		receiptOrder = true,
	})
	local RECEIPT_FIELDS = SocialShape.freezeDeep({ turnInId = true, payout = true })
	local TURN_IN_FIELDS =
		SocialShape.freezeDeep({ turnInId = true, orderId = true, realmId = true, held = true, atSec = true })

	local PatronOrderCore = {}

	local function outcome(state: State?, replayed: boolean, reason: string?, order: Order?): Result
		local paid = order ~= nil and not replayed
		return freezeDeep({
			ok = reason == nil,
			state = state,
			replayed = replayed,
			reason = reason,
			payout = if paid then assert(order).payout else 0,
			consume = if paid then assert(order).count else 0,
			itemId = if paid then assert(order).itemId else nil,
		})
	end

	local function refused(reason: string): Result
		return outcome(nil, false, reason, nil)
	end

	function PatronOrderCore.catalog(value: unknown): (Catalog?, string?)
		if type(value) ~= "table" then
			return nil, "catalog_invalid"
		end
		local raw = assert(SocialShape.raw(value))
		if
			not whole(raw.weeklyCoinCap, 1, MAX_COIN)
			or dense(raw.orders, MAX_ORDERS) == nil
			or #(assert(SocialShape.raw(raw.orders))) == 0
		then
			return nil, "catalog_invalid"
		end
		local orders: { [string]: Order } = {}
		local ordered: { Order } = {}
		for _, orderValue in assert(SocialShape.raw(raw.orders)) do
			local order = readOrder(orderValue)
			if order == nil then
				return nil, "order_invalid"
			end
			if
				not exact(order, ORDER_FIELDS)
				or not opaque(order.orderId, MAX_ID)
				or REALMS[order.realmId] ~= true
				or not opaque(order.itemId, MAX_ID)
				or not whole(order.count, 1, MAX_COUNT)
				or not whole(order.payout, 1, assert(SocialShape.number(raw.weeklyCoinCap)))
				or not opaque(order.label, MAX_ID)
				or orders[assert(SocialShape.string(order.orderId))] ~= nil
			then
				return nil, "order_invalid"
			end
			local copy = freezeDeep(order)
			orders[assert(SocialShape.string(order.orderId))] = copy
			ordered[#ordered + 1] = copy
		end
		return SocialShape.freezeDeep({
			weeklyCoinCap = assert(SocialShape.number(raw.weeklyCoinCap)),
			orders = SocialShape.freezeDeep(orders),
			ordered = SocialShape.freezeDeep(ordered),
		}),
			nil
	end

	local function copyState(value: unknown): State?
		if not exact(value, STATE_FIELDS) then
			return nil
		end
		local raw = readState(value)
		if raw == nil then
			return nil
		end
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or not whole(raw.weekIndex, 0, MAX_WEEK)
			or not whole(raw.paidThisWeek, 0, MAX_COIN * 2)
			or not whole(raw.carry, 0, MAX_COIN)
			or dense(raw.receiptOrder, RECEIPT_WINDOW) == nil
		then
			return nil
		end
		local receipts: { { turnInId: string, payout: number } } = {}
		local seen: { [string]: boolean } = {}
		for _, receiptValue in raw.receiptOrder do
			local receipt = receiptValue
			if
				not exact(receipt, RECEIPT_FIELDS)
				or not opaque(receipt.turnInId, MAX_ID)
				or not whole(receipt.payout, 1, MAX_COIN)
				or seen[assert(SocialShape.string(receipt.turnInId))]
			then
				return nil
			end
			seen[assert(SocialShape.string(receipt.turnInId))] = true
			receipts[#receipts + 1] = {
				turnInId = assert(SocialShape.string(receipt.turnInId)),
				payout = assert(SocialShape.number(receipt.payout)),
			}
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			weekIndex = assert(SocialShape.number(raw.weekIndex)),
			paidThisWeek = assert(SocialShape.number(raw.paidThisWeek)),
			carry = assert(SocialShape.number(raw.carry)),
			receiptOrder = receipts,
		}
	end

	function PatronOrderCore.emptyState(): State
		return freezeDeep({
			schemaVersion = SCHEMA_VERSION,
			weekIndex = 0,
			paidThisWeek = 0,
			carry = 0,
			receiptOrder = {},
		})
	end

	function PatronOrderCore.projectState(value: unknown): State?
		local state = copyState(value)
		return if state == nil then nil else freezeDeep(state)
	end

	function PatronOrderCore.weekOf(atSec: number): number
		return math.max(0, math.floor((atSec - WEEK_ANCHOR_SEC) / WEEK_SEC))
	end

	local function rolled(state: State, catalog: Catalog, week: number): State
		if week <= state.weekIndex then
			return state
		end
		local cap = catalog.weeklyCoinCap
		if state.weekIndex == 0 and state.paidThisWeek == 0 and state.carry == 0 then
			state.carry = 0
		elseif week == state.weekIndex + 1 then
			state.carry = math.clamp(cap + state.carry - state.paidThisWeek, 0, cap)
		else
			state.carry = cap
		end
		state.weekIndex = week
		state.paidThisWeek = 0
		return state
	end

	function PatronOrderCore.allowance(value: unknown, catalogValue: Catalog, atSec: number): number?
		local state = copyState(value)
		if state == nil or type(catalogValue) ~= "table" or not whole(atSec, 0, MAX_TIME) then
			return nil
		end
		local current = rolled(state, catalogValue, PatronOrderCore.weekOf(atSec))
		return math.max(0, catalogValue.weeklyCoinCap + current.carry - current.paidThisWeek)
	end

	function PatronOrderCore.turnIn(previous: unknown, catalog: Catalog, turnInValue: unknown): Result
		local state = copyState(previous)
		if state == nil or type(catalog) ~= "table" then
			return refused("state_invalid")
		end
		local turnIn = SocialShape.raw(turnInValue)
		if
			turnIn == nil
			or not exact(turnInValue, TURN_IN_FIELDS)
			or not opaque(turnIn.turnInId, MAX_ID)
			or not whole(turnIn.held, 0, MAX_COIN)
			or not whole(turnIn.atSec, 0, MAX_TIME)
		then
			return refused("turn_in_invalid")
		end
		for _, receipt in state.receiptOrder do
			if receipt.turnInId == turnIn.turnInId then
				return outcome(state, true, nil, nil)
			end
		end
		local order = catalog.orders[assert(SocialShape.string(turnIn.orderId))]
		if order == nil then
			return refused("order_unknown")
		end
		if order.realmId ~= turnIn.realmId then
			return refused("realm_foreign")
		end
		if (assert(SocialShape.number(turnIn.held))) < order.count then
			return refused("goods_insufficient")
		end
		state = rolled(state, catalog, PatronOrderCore.weekOf(assert(SocialShape.number(turnIn.atSec))))
		if state.paidThisWeek + order.payout > catalog.weeklyCoinCap + state.carry then
			return refused("weekly_cap_reached")
		end
		state.paidThisWeek += order.payout
		state.receiptOrder[#state.receiptOrder + 1] =
			{ turnInId = assert(SocialShape.string(turnIn.turnInId)), payout = order.payout }
		if #state.receiptOrder > RECEIPT_WINDOW then
			table.remove(state.receiptOrder, 1)
		end
		return outcome(state, false, nil, order)
	end

	return SocialShape.freezeDeep(PatronOrderCore)
end

return System
