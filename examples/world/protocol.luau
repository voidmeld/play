--!strict

local Content = require("./content")
local Trade = require("../../src/core/trade/exchange")
local Value = require("../../src/kernel/value")

export type EquipRequest = { read kind: "equip", read itemId: string }
export type ChatRequest = { read kind: "chat", read text: string }
export type Request =
	{ read kind: "snapshot" | "accept" | "claim" }
	| EquipRequest
	| { read kind: "loot", read defeatId: string }
	| { read kind: "trade", read targetId: number }
	| { read kind: "offer", read revision: number, read offer: Trade.Offer }
	| { read kind: "lock" | "confirm", read revision: number }
	| ChatRequest
export type View = {
	characterId: string,
	displayName: string,
	level: number,
	xp: number,
	coin: number,
	inventory: { [string]: number },
	equipment: { [string]: string },
	questStatus: string,
	counts: { [string]: number },
	loot: { string },
}
export type Line = { senderId: number, text: string, at: number }
export type TradeView = {
	tradeId: string,
	revision: number,
	phase: string,
	players: { number },
	offers: { [string]: Trade.Offer },
	locks: { [string]: boolean },
	confirms: { [string]: boolean },
}
export type Response = { ok: boolean, reason: string?, view: View?, trade: TradeView?, line: Line? }
export type ServerPorts<P> = {
	connectRequest: ((P, ...unknown) -> ()) -> () -> (),
	sendResponse: (P, Response) -> (),
}
export type ClientPorts = {
	fireRequest: (Request) -> (),
	connectResponse: ((unknown) -> ()) -> () -> (),
}

local function decode(raw: unknown): Request?
	local row = Value.raw(raw)
	if row == nil then
		return nil
	end
	local kind = row.kind
	local fields: { [string]: boolean } = { kind = true }
	if kind == "snapshot" or kind == "accept" or kind == "claim" then
		if Value.record(raw, fields) == nil then
			return nil
		end
		return { kind = kind }
	elseif kind == "equip" or kind == "loot" then
		local key = if kind == "equip" then "itemId" else "defeatId"
		fields[key] = true
		local id = Value.opaque(row[key], 64)
		if id == nil or Value.record(raw, fields) == nil then
			return nil
		end
		return if kind == "equip" then { kind = kind, itemId = id } else { kind = kind, defeatId = id }
	elseif kind == "trade" then
		fields.targetId = true
		local targetId = Value.whole(row.targetId, 1, 9007199254740991)
		if targetId == nil or Value.record(raw, fields) == nil then
			return nil
		end
		return { kind = kind, targetId = targetId }
	elseif kind == "offer" or kind == "lock" or kind == "confirm" then
		fields.revision = true
		local revision = Value.whole(row.revision, 0, 10000)
		if kind == "offer" then
			fields.offer = true
		end
		if revision == nil or Value.record(raw, fields) == nil then
			return nil
		end
		if kind == "offer" then
			local offer = Content.exchange.offer(row.offer)
			return if offer ~= nil then { kind = kind, revision = revision, offer = offer } else nil
		end
		return { kind = kind, revision = revision }
	elseif kind == "chat" then
		fields.text = true
		if type(row.text) ~= "string" or #row.text == 0 or #row.text > 120 or Value.record(raw, fields) == nil then
			return nil
		end
		return { kind = kind, text = row.text }
	end
	return nil
end

local function tradeView(state: Trade.State): TradeView
	local offers: { [string]: Trade.Offer } = {}
	local locks: { [string]: boolean } = {}
	local confirms: { [string]: boolean } = {}
	for _, id in state.players do
		offers[tostring(id)] = assert(Content.exchange.offer(state.offers[id]))
		locks[tostring(id)] = state.locks[id] == true
		confirms[tostring(id)] = state.confirms[id] == true
	end
	return {
		tradeId = state.tradeId,
		revision = state.revision,
		phase = state.phase,
		players = table.clone(state.players),
		offers = offers,
		locks = locks,
		confirms = confirms,
	}
end

local function numbers(raw: unknown, maximum: number): { [string]: number }?
	local row = Value.raw(raw)
	if row == nil then
		return nil
	end
	local result: { [string]: number } = {}
	local total = 0
	for key, value in row do
		if type(key) ~= "string" or #key > 64 or type(value) ~= "number" or Value.whole(value, 0, maximum) == nil then
			return nil
		end
		total += 1
		if total > 8 then
			return nil
		end
		result[key] = value
	end
	return result
end

local function decodeView(raw: unknown): View?
	local row = Value.record(raw, {
		characterId = true,
		displayName = true,
		level = true,
		xp = true,
		coin = true,
		inventory = true,
		equipment = true,
		questStatus = true,
		counts = true,
		loot = true,
	}, true)
	if
		row == nil
		or type(row.characterId) ~= "string"
		or type(row.displayName) ~= "string"
		or type(row.questStatus) ~= "string"
		or #row.characterId > 64
		or #row.displayName > 32
	then
		return nil
	end
	local level, xp, coin =
		Value.whole(row.level, 1, 3), Value.whole(row.xp, 0, 100000), Value.whole(row.coin, 0, 100000)
	local inventory, counts = numbers(row.inventory, 99), numbers(row.counts, 1)
	local slots = Value.record(row.equipment, { hand = true })
	local lootRows = Value.dense(row.loot, 32, false)
	if
		level == nil
		or xp == nil
		or coin == nil
		or inventory == nil
		or counts == nil
		or slots == nil
		or lootRows == nil
	then
		return nil
	end
	local equipment: { [string]: string } = {}
	if slots.hand ~= nil then
		if type(slots.hand) ~= "string" then
			return nil
		end
		equipment.hand = slots.hand
	end
	local loot: { string } = {}
	for _, value in lootRows do
		if type(value) ~= "string" or #value > 64 then
			return nil
		end
		table.insert(loot, value)
	end
	return {
		characterId = row.characterId,
		displayName = row.displayName,
		level = level,
		xp = xp,
		coin = coin,
		inventory = inventory,
		equipment = equipment,
		questStatus = row.questStatus,
		counts = counts,
		loot = loot,
	}
end

local function decodeTrade(raw: unknown): TradeView?
	local row = Value.record(
		raw,
		{ tradeId = true, revision = true, phase = true, players = true, offers = true, locks = true, confirms = true },
		true
	)
	if row == nil or type(row.tradeId) ~= "string" or type(row.phase) ~= "string" then
		return nil
	end
	local revision = Value.whole(row.revision, 0, 10000)
	local players = Value.dense(row.players, 2, false)
	local sourceOffers, sourceLocks, sourceConfirms =
		Value.raw(row.offers), Value.raw(row.locks), Value.raw(row.confirms)
	if
		revision == nil
		or players == nil
		or #players ~= 2
		or sourceOffers == nil
		or sourceLocks == nil
		or sourceConfirms == nil
	then
		return nil
	end
	local ids: { number } = {}
	local offers: { [string]: Trade.Offer } = {}
	local locks: { [string]: boolean } = {}
	local confirms: { [string]: boolean } = {}
	for _, value in players do
		local id = Value.whole(value, 1, 9007199254740991)
		if id == nil then
			return nil
		end
		local key = tostring(id)
		local offer = Content.exchange.offer(sourceOffers[key])
		if offer == nil or type(sourceLocks[key]) ~= "boolean" or type(sourceConfirms[key]) ~= "boolean" then
			return nil
		end
		table.insert(ids, id)
		offers[key], locks[key], confirms[key] = offer, sourceLocks[key] == true, sourceConfirms[key] == true
	end
	return {
		tradeId = row.tradeId,
		revision = revision,
		phase = row.phase,
		players = ids,
		offers = offers,
		locks = locks,
		confirms = confirms,
	}
end

local function decodeResponse(raw: unknown): Response?
	local row = Value.record(raw, { ok = true, reason = true, view = true, trade = true, line = true })
	if row == nil or type(row.ok) ~= "boolean" or (row.reason ~= nil and type(row.reason) ~= "string") then
		return nil
	end
	local view = if row.view ~= nil then decodeView(row.view) else nil
	local trade = if row.trade ~= nil then decodeTrade(row.trade) else nil
	local line: Line? = nil
	if (row.view ~= nil and view == nil) or (row.trade ~= nil and trade == nil) then
		return nil
	end
	if row.line ~= nil then
		local fields = Value.record(row.line, { senderId = true, text = true, at = true }, true)
		if fields == nil or type(fields.text) ~= "string" or #fields.text > 120 then
			return nil
		end
		local id, at = Value.whole(fields.senderId, 1, 9007199254740991), Value.whole(fields.at, 0, 9007199254740991)
		if id == nil or at == nil then
			return nil
		end
		line = { senderId = id, text = fields.text, at = at }
	end
	return {
		ok = row.ok,
		reason = if type(row.reason) == "string" then row.reason else nil,
		view = view,
		trade = trade,
		line = line,
	}
end

return table.freeze({ decode = decode, decodeResponse = decodeResponse, tradeView = tradeView })
