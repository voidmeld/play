--!strict

local Codec = require("./codec")
local Result = require("./result")
local Value = require("./value")

export type State<E> = { events: { E } }
export type Projection<E, P> = { state: State<E>, value: P }
export type Change<E, P> = { state: State<E>, value: P, replayed: boolean }
export type Config<E, P> = {
	maxEvents: number,
	maxId: number,
	decode: Codec.Decoder<E>,
	identity: (E) -> string,
	equal: (E, E) -> boolean,
	seed: () -> P,
	apply: (P, E, { read [number]: E }) -> (P?, string?),
}

local function create<E, P>(config: Config<E, P>)
	assert(Value.whole(config.maxEvents, 1, 1000000) ~= nil, "invalid event bound")
	assert(Value.whole(config.maxId, 1, 1000000) ~= nil, "invalid identity bound")
	local function replay(raw: unknown): Result.Result<Projection<E, P>>
		local source = Value.dense(raw, config.maxEvents)
		if source == nil then
			return Result.fail("events_invalid")
		end
		local rows: { E } = {}
		local ids: { [string]: E } = {}
		local value = config.seed()
		for _, item in source do
			local event, problem = config.decode(item)
			if event == nil then
				return Result.fail(problem or "event_invalid")
			end
			local id = config.identity(event)
			if Value.opaque(id, config.maxId) == nil then
				return Result.fail("event_id_invalid")
			end
			local prior = ids[id]
			if prior ~= nil then
				if not config.equal(prior, event) then
					return Result.fail("event_id_conflict")
				end
			else
				local nextValue, reason = config.apply(value, event, rows)
				if nextValue == nil then
					return Result.fail(reason or "event_rejected")
				end
				value = nextValue
				ids[id] = event
				table.insert(rows, event)
			end
		end
		return Result.ok({ state = { events = rows }, value = value })
	end
	local function project(raw: unknown): Result.Result<Projection<E, P>>
		local record = Value.record(raw, { events = true }, true)
		return if record == nil then Result.fail("state_invalid") else replay(record.events)
	end
	local function append(state: State<E>, raw: unknown): Result.Result<Change<E, P>>
		local current = project(state)
		if not current.ok then
			return Result.fail(current.reason)
		end
		local event, problem = config.decode(raw)
		if event == nil then
			return Result.fail(problem or "event_invalid")
		end
		local id = config.identity(event)
		if Value.opaque(id, config.maxId) == nil then
			return Result.fail("event_id_invalid")
		end
		local owned = current.value
		for _, prior in owned.state.events do
			if config.identity(prior) == id then
				return if config.equal(prior, event)
					then Result.ok({ state = owned.state, value = owned.value, replayed = true })
					else Result.fail("event_id_conflict")
			end
		end
		if #owned.state.events >= config.maxEvents then
			return Result.fail("events_full")
		end
		local value, reason = config.apply(owned.value, event, owned.state.events)
		if value == nil then
			return Result.fail(reason or "event_rejected")
		end
		table.insert(owned.state.events, event)
		return Result.ok({ state = owned.state, value = value, replayed = false })
	end
	local function snapshot(state: State<E>): Result.Result<State<E>>
		local projected = project(state)
		return if projected.ok then Result.ok(projected.value.state) else Result.fail(projected.reason)
	end
	return table.freeze({ append = append, project = project, replay = replay, snapshot = snapshot })
end

return table.freeze({ create = create })
