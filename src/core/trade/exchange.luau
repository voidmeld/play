--!strict

local Value = require("../value")

export type Stack = { itemId: string, count: number }
export type Offer = { coin: number, items: { Stack } }
export type Phase = "open" | "locked" | "confirmed" | "settled" | "cancelled"
export type State = {
	tradeId: string,
	expiresAt: number,
	players: { number },
	phase: Phase,
	revision: number,
	offers: { [number]: Offer },
	locks: { [number]: boolean },
	confirms: { [number]: boolean },
}
export type Config = {
	maxItems: number,
	maxCount: number,
	maxCoin: number,
	maxUserId: number,
	maxRevision: number,
	idLimit: number,
}

local Trade = {}

function Trade.exchange(config: Config)
	local function whole(value: unknown, low: number, high: number): boolean
		return Value.whole(value, low, high) ~= nil
	end
	local function id(value: unknown): boolean
		return Value.identifier(value, config.idLimit) ~= nil
	end
	local Core = {}
	function Core.offer(value: unknown): Offer?
		local raw = Value.record(value, { coin = true, items = true })
		if raw == nil then
			return nil
		end
		local coin = Value.whole(raw.coin, 0, config.maxCoin)
		local candidates = Value.dense(raw.items, config.maxItems, false)
		if coin == nil or candidates == nil then
			return nil
		end
		local items: { Stack } = {}
		local seen: { [string]: boolean } = {}
		for _, candidate in candidates do
			local stack = Value.record(candidate, { itemId = true, count = true })
			if stack == nil then
				return nil
			end
			local itemId = Value.identifier(stack.itemId, config.idLimit)
			local count = Value.whole(stack.count, 1, config.maxCount)
			if itemId == nil or count == nil or seen[itemId] then
				return nil
			end
			seen[itemId] = true
			table.insert(items, { itemId = itemId, count = count })
		end
		return Value.freezeDeep({ coin = coin, items = items })
	end

	function Core.empty(tradeId: string, firstUserId: number, secondUserId: number): State?
		if
			not id(tradeId)
			or not whole(firstUserId, 1, config.maxUserId)
			or not whole(secondUserId, 1, config.maxUserId)
			or firstUserId == secondUserId
		then
			return nil
		end
		local emptyOffer = Value.freezeDeep({ coin = 0, items = Value.freezeDeep({}) })
		return {
			tradeId = tradeId,
			expiresAt = 0,
			players = { firstUserId, secondUserId },
			phase = "open",
			revision = 0,
			offers = { [firstUserId] = emptyOffer, [secondUserId] = emptyOffer },
			locks = {},
			confirms = {},
		}
	end

	function Core.step(state: State, actorId: number, commandValue: unknown): (State?, string?)
		local command = Value.record(commandValue, { kind = true, revision = true, offer = true })
		if type(state) ~= "table" or command == nil then
			return nil, "request_invalid"
		end
		if actorId ~= state.players[1] and actorId ~= state.players[2] then
			return nil, "not_participant"
		end
		if not whole(command.revision, 0, config.maxRevision) or command.revision ~= state.revision then
			return nil, "revision_stale"
		end
		local kind = command.kind
		if kind == "cancel" then
			if command.offer ~= nil or state.phase == "settled" or state.phase == "confirmed" then
				return nil, "trade_locked"
			end
			local nextState = table.clone(state)
			nextState.phase = "cancelled"
			return nextState, nil
		end
		if state.phase == "cancelled" or state.phase == "settled" or state.phase == "confirmed" then
			return nil, "trade_locked"
		end
		if kind == "offer" then
			local offer = Core.offer(command.offer)
			if offer == nil or state.revision == config.maxRevision then
				return nil, "offer_invalid"
			end
			local nextState = table.clone(state)
			nextState.offers = table.clone(state.offers)
			nextState.offers[actorId] = offer
			nextState.revision += 1
			nextState.phase = "open"
			nextState.locks = {}
			nextState.confirms = {}
			return nextState, nil
		end
		if command.offer ~= nil then
			return nil, "request_invalid"
		end
		if kind == "lock" then
			local nextState = table.clone(state)
			nextState.locks = table.clone(state.locks)
			nextState.locks[actorId] = true
			if nextState.locks[state.players[1]] and nextState.locks[state.players[2]] then
				nextState.phase = "locked"
			end
			return nextState, nil
		end
		if kind == "confirm" then
			if state.phase ~= "locked" then
				return nil, "not_locked"
			end
			local nextState = table.clone(state)
			nextState.confirms = table.clone(state.confirms)
			nextState.confirms[actorId] = true
			if nextState.confirms[state.players[1]] and nextState.confirms[state.players[2]] then
				nextState.phase = "confirmed"
			end
			return nextState, nil
		end
		return nil, "request_invalid"
	end

	function Core.settled(state: State): State?
		if state.phase ~= "confirmed" then
			return nil
		end
		local nextState = table.clone(state)
		nextState.phase = "settled"
		return nextState
	end

	return Core
end

return Trade
