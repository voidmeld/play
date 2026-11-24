--!strict

export type Config = { windowSec: number, maxRequeues: number, minRetrySec: number }
export type Entry<T> = { token: number, payload: T, requeues: number, dueAt: number }
export type State<T> = { nextToken: number, queued: Entry<T>? }
export type Windows = { gcdReadyAt: number, castReadyAt: number, channelReadyAt: number }

local Queue = {}

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function Queue.empty<T>(): State<T>
	return { nextToken = 1 }
end

function Queue.windows(now: number, gcdSec: number, castSec: number, channelSec: number): Windows
	assert(finite(now), "invalid clock")
	assert(finite(gcdSec) and gcdSec >= 0, "invalid global cooldown")
	assert(finite(castSec) and castSec >= 0, "invalid cast duration")
	assert(finite(channelSec) and channelSec >= 0, "invalid channel duration")
	return { gcdReadyAt = now + gcdSec, castReadyAt = now + castSec, channelReadyAt = now + channelSec }
end

function Queue.remaining(windows: Windows, now: number): (number, number, number)
	assert(finite(now), "invalid clock")
	return math.max(0, windows.gcdReadyAt - now),
		math.max(0, windows.castReadyAt - now),
		math.max(0, windows.channelReadyAt - now)
end

function Queue.ready(windows: Windows, now: number): boolean
	local gcd, cast, channel = Queue.remaining(windows, now)
	return gcd == 0 and cast == 0 and channel == 0
end

function Queue.rules(config: Config)
	assert(finite(config.windowSec) and config.windowSec >= 0, "invalid queue window")
	assert(finite(config.minRetrySec) and config.minRetrySec > 0, "invalid retry delay")
	assert(
		finite(config.maxRequeues) and config.maxRequeues >= 0 and config.maxRequeues % 1 == 0,
		"invalid retry bound"
	)
	local windowSec, minRetrySec, maxRequeues = config.windowSec, config.minRetrySec, config.maxRequeues
	local function shouldQueue(reason: string?, remainingSec: number?): boolean
		return reason == "on_gcd"
			and remainingSec ~= nil
			and finite(remainingSec)
			and remainingSec > 0
			and remainingSec <= windowSec
	end
	local function delayFor(remainingSec: number): number
		assert(finite(remainingSec) and remainingSec >= 0, "invalid remaining cooldown")
		return math.max(remainingSec, minRetrySec)
	end
	local function enqueue<T>(
		state: State<T>,
		payload: T,
		requeues: number,
		reason: string?,
		remainingSec: number?,
		now: number
	): (State<T>, Entry<T>?)
		assert(finite(now), "invalid clock")
		if
			not finite(requeues)
			or requeues < 0
			or requeues % 1 ~= 0
			or requeues >= maxRequeues
			or not shouldQueue(reason, remainingSec)
		then
			return state, nil
		end
		local entry: Entry<T> = {
			token = state.nextToken,
			payload = payload,
			requeues = requeues + 1,
			dueAt = now + delayFor(assert(remainingSec)),
		}
		return { nextToken = state.nextToken + 1, queued = entry }, entry
	end
	return table.freeze({
		shouldQueue = shouldQueue,
		delayFor = delayFor,
		minimumCadenceSec = function(gcdSec: number): number
			assert(finite(gcdSec) and gcdSec >= 0, "invalid global cooldown")
			return math.max(gcdSec - windowSec, 0)
		end,
		enqueue = enqueue,
	})
end

function Queue.cancel<T>(state: State<T>, token: number?): State<T>
	local entry = state.queued
	if entry == nil or (token ~= nil and entry.token ~= token) then
		return state
	end
	return { nextToken = state.nextToken }
end

function Queue.take<T>(state: State<T>, token: number, now: number): (State<T>, Entry<T>?)
	assert(finite(now), "invalid clock")
	local entry = state.queued
	if entry == nil or entry.token ~= token or now < entry.dueAt then
		return state, nil
	end
	return { nextToken = state.nextToken }, entry
end

return table.freeze(Queue)
