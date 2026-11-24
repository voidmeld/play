--!strict

local Exchange = require("./exchange")
local Value = require("../../kernel/value")

export type Record<K> = {
	tradeId: string,
	players: { number },
	offers: { [K]: Exchange.Offer },
	characters: { [K]: string },
	revision: number,
	expiresAt: number,
	phase: "prepared" | "committed" | "resolved" | "cancelled",
	grants: { [K]: boolean? },
}
export type Projected = Record<number>
export type Wire = Record<string>
export type Pointer = { tradeId: string, receipt: Wire }
export type Config = {
	offer: (unknown) -> Exchange.Offer?,
	tradeIdLimit: number,
	characterIdLimit: number,
	maxUserId: number,
	maxRevision: number,
	maxTimestamp: number,
	maxPointers: number,
}

local Receipts = {}

function Receipts.receipts(config: Config)
	local Receipt = {}
	function Receipt.project(value: unknown): Projected?
		local raw = Value.record(value, {
			tradeId = true,
			players = true,
			offers = true,
			characters = true,
			revision = true,
			expiresAt = true,
			phase = true,
			grants = true,
		})
		if raw == nil then
			return nil
		end
		local tradeId = Value.identifier(raw.tradeId, config.tradeIdLimit)
		local players = Value.dense(raw.players, 2, false)
		local revision = Value.whole(raw.revision, 0, config.maxRevision)
		local expiresAt = Value.whole(raw.expiresAt, 1, config.maxTimestamp)
		local phase = raw.phase
		local rawOffers, rawCharacters, rawGrants =
			Value.raw(raw.offers), Value.raw(raw.characters), Value.raw(raw.grants)
		if
			tradeId == nil
			or players == nil
			or #players ~= 2
			or players[1] == players[2]
			or revision == nil
			or expiresAt == nil
			or (phase ~= "prepared" and phase ~= "committed" and phase ~= "resolved" and phase ~= "cancelled")
			or rawOffers == nil
			or rawCharacters == nil
			or rawGrants == nil
		then
			return nil
		end
		local offers: { [number]: Exchange.Offer } = {}
		local characters: { [number]: string } = {}
		local grants: { [number]: boolean? } = {}
		local ids: { number } = {}
		local allowed: { [unknown]: boolean } = {}
		for _, candidate in players do
			local userId = Value.whole(candidate, 1, config.maxUserId)
			if userId == nil then
				return nil
			end
			table.insert(ids, userId)
			local key = tostring(userId)
			allowed[key], allowed[userId] = true, true
			for _, map in { rawOffers, rawCharacters, rawGrants } do
				if map[key] ~= nil and map[userId] ~= nil then
					return nil
				end
			end
			local offer = config.offer(rawOffers[key] or rawOffers[userId])
			local character = Value.opaque(rawCharacters[key] or rawCharacters[userId], config.characterIdLimit)
			local grant = if rawGrants[key] ~= nil then rawGrants[key] else rawGrants[userId]
			if offer == nil or character == nil or (grant ~= nil and grant ~= true) then
				return nil
			end
			offers[userId], characters[userId] = offer, character
			grants[userId] = if grant == true then true else nil
		end
		for _, map in { rawOffers, rawCharacters, rawGrants } do
			for key in map do
				if not allowed[key] then
					return nil
				end
			end
		end
		return {
			tradeId = tradeId,
			players = ids,
			offers = offers,
			characters = characters,
			revision = revision,
			expiresAt = expiresAt,
			phase = phase,
			grants = grants,
		}
	end

	function Receipt.wire(raw: unknown): Wire?
		local value = Receipt.project(raw)
		if value == nil then
			return nil
		end
		local offers: { [string]: Exchange.Offer } = {}
		local characters: { [string]: string } = {}
		local grants: { [string]: boolean? } = {}
		for _, userId in value.players do
			local key = tostring(userId)
			offers[key], characters[key], grants[key] =
				value.offers[userId], value.characters[userId], value.grants[userId]
		end
		return {
			tradeId = value.tradeId,
			players = value.players,
			offers = offers,
			characters = characters,
			revision = value.revision,
			expiresAt = value.expiresAt,
			phase = value.phase,
			grants = grants,
		}
	end

	function Receipt.pointers(value: unknown): { [string]: Pointer }?
		if value == nil then
			return {}
		end
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return nil
		end
		local raw = Value.raw(value)
		if raw == nil then
			return nil
		end
		local out: { [string]: Pointer } = {}
		local count = 0
		for tradeId, value in raw do
			count += 1
			local pointer = Value.record(value, { tradeId = true, receipt = true }, false, false)
			if
				count > config.maxPointers
				or type(tradeId) ~= "string"
				or pointer == nil
				or pointer.tradeId ~= tradeId
			then
				return nil
			end
			local receipt = Receipt.wire(pointer.receipt)
			if receipt == nil or receipt.tradeId ~= tradeId then
				return nil
			end
			out[tradeId] = { tradeId = tradeId, receipt = receipt }
		end
		return out
	end
	return Receipt
end

return Receipts
