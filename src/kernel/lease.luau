--!strict

local Result = require("./result")
local Value = require("./value")

export type State = {
	revision: number,
	sessionId: string?,
	acquisitionId: string?,
	expiresAt: number,
}
export type Grant = { read state: State, read kind: "acquired" | "owned" | "renewed" | "released" }
export type Liveness = "alive" | "dead" | "unknown"
export type Acquire = {
	read sessionId: string,
	read acquisitionId: string,
	read now: number,
	read ttl: number,
	read liveness: Liveness?,
}
export type Expected = { read sessionId: string, read acquisitionId: string, read revision: number }
export type Renewal = Expected & { read now: number, read ttl: number }
export type Config = {
	read maxRevision: number,
	read maxTime: number,
	read sessionIdLimit: number,
	read acquisitionIdLimit: number,
	read integerTime: boolean,
}
export type Service = {
	read copy: (unknown) -> Result.Result<State>,
	read acquire: (unknown, Acquire) -> Result.Result<Grant>,
	read renew: (unknown, Renewal) -> Result.Result<Grant>,
	read release: (unknown, Expected) -> Result.Result<Grant>,
}

local function withState<T>(record: T & State, state: State): T & State
	local result = table.clone(record)
	result.revision = state.revision
	result.sessionId = state.sessionId
	result.acquisitionId = state.acquisitionId
	result.expiresAt = state.expiresAt
	return result
end
local function same(left: State, right: State): boolean
	return left.revision == right.revision
		and left.sessionId == right.sessionId
		and left.acquisitionId == right.acquisitionId
		and left.expiresAt == right.expiresAt
end
local function nextState(revision: number, sessionId: string?, acquisitionId: string?, expiresAt: number): State
	local state: State =
		{ revision = revision, sessionId = sessionId, acquisitionId = acquisitionId, expiresAt = expiresAt }
	return state
end

local function configure(config: Config): Service
	config = table.freeze(table.clone(config))
	assert(Value.whole(config.maxRevision, 1, 9007199254740991) ~= nil, "invalid lease revision limit")
	assert(Value.finite(config.maxTime) and config.maxTime > 0, "invalid lease time limit")
	assert(Value.whole(config.sessionIdLimit, 1, 9007199254740991) ~= nil, "invalid lease session limit")
	assert(Value.whole(config.acquisitionIdLimit, 1, 9007199254740991) ~= nil, "invalid lease acquisition limit")
	assert(type(config.integerTime) == "boolean", "invalid lease time policy")
	local function time(value: unknown): boolean
		return type(value) == "number"
			and Value.finite(value)
			and value >= 0
			and value <= config.maxTime
			and (not config.integerTime or value % 1 == 0)
	end
	local function identity(sessionId: unknown, acquisitionId: unknown): boolean
		return Value.opaque(sessionId, config.sessionIdLimit) ~= nil
			and Value.opaque(acquisitionId, config.acquisitionIdLimit) ~= nil
	end
	local function duration(now: number, ttl: number): boolean
		return time(now) and time(ttl) and ttl > 0 and now <= config.maxTime - ttl
	end
	local function copy(raw: unknown): Result.Result<State>
		local fields = if Value.hasMetatable(raw) then nil else Value.raw(raw)
		if fields == nil then
			return Result.fail("record_invalid")
		end
		local revision = Value.whole(fields.revision, 0, config.maxRevision)
		local expiresAt = fields.expiresAt
		if revision == nil or type(expiresAt) ~= "number" or not time(expiresAt) then
			return Result.fail("record_invalid")
		end
		local sessionId, acquisitionId = fields.sessionId, fields.acquisitionId
		if sessionId == nil and acquisitionId == nil and expiresAt == 0 then
			return Result.ok(nextState(revision, nil, nil, 0))
		end
		if
			(sessionId ~= nil and Value.opaque(sessionId, config.sessionIdLimit) == nil)
			or (acquisitionId ~= nil and Value.opaque(acquisitionId, config.acquisitionIdLimit) == nil)
		then
			return Result.fail("record_invalid")
		end
		if type(sessionId) ~= "string" or type(acquisitionId) ~= "string" or expiresAt <= 0 then
			return Result.fail("lease_invalid")
		end
		return Result.ok(nextState(revision, sessionId, acquisitionId, expiresAt))
	end
	local function grant(state: State, kind: "acquired" | "owned" | "renewed" | "released"): Result.Result<Grant>
		return Result.ok(table.freeze({ state = state, kind = kind }))
	end
	local function acquire(raw: unknown, request: Acquire): Result.Result<Grant>
		if not identity(request.sessionId, request.acquisitionId) then
			return Result.fail("identity_invalid")
		end
		if not duration(request.now, request.ttl) then
			return Result.fail("time_invalid")
		end
		if
			request.liveness ~= nil
			and request.liveness ~= "alive"
			and request.liveness ~= "dead"
			and request.liveness ~= "unknown"
		then
			return Result.fail("liveness_invalid")
		end
		local copied = copy(raw)
		if not copied.ok then
			return copied
		end
		local state = copied.value
		if
			state.sessionId == request.sessionId
			and state.acquisitionId == request.acquisitionId
			and state.expiresAt > request.now
		then
			return grant(state, "owned")
		end
		if
			state.sessionId ~= nil
			and (request.liveness == "alive" or (request.liveness ~= "dead" and state.expiresAt > request.now))
		then
			return Result.fail("lease_held")
		end
		if state.revision >= config.maxRevision then
			return Result.fail("revision_max")
		end
		return grant(
			nextState(state.revision + 1, request.sessionId, request.acquisitionId, request.now + request.ttl),
			"acquired"
		)
	end
	local function expected(raw: unknown, request: Expected): Result.Result<State>
		if not identity(request.sessionId, request.acquisitionId) then
			return Result.fail("identity_invalid")
		end
		if Value.whole(request.revision, 0, config.maxRevision) == nil then
			return Result.fail("revision_invalid")
		end
		local copied = copy(raw)
		if not copied.ok then
			return copied
		end
		if copied.value.sessionId ~= request.sessionId or copied.value.acquisitionId ~= request.acquisitionId then
			return Result.fail("lease_not_owned")
		end
		if copied.value.revision ~= request.revision then
			return Result.fail("lease_stale")
		end
		return copied
	end
	local function renew(raw: unknown, request: Renewal): Result.Result<Grant>
		if not duration(request.now, request.ttl) then
			return Result.fail("time_invalid")
		end
		local matched = expected(raw, request)
		if not matched.ok then
			return matched
		end
		local state = matched.value
		if state.expiresAt <= request.now then
			return Result.fail("lease_expired")
		end
		if state.revision >= config.maxRevision then
			return Result.fail("revision_max")
		end
		return grant(
			nextState(state.revision + 1, state.sessionId, state.acquisitionId, request.now + request.ttl),
			"renewed"
		)
	end
	local function release(raw: unknown, request: Expected): Result.Result<Grant>
		local matched = expected(raw, request)
		if not matched.ok then
			return matched
		end
		if matched.value.revision >= config.maxRevision then
			return Result.fail("revision_max")
		end
		return grant(nextState(matched.value.revision + 1, nil, nil, 0), "released")
	end
	return table.freeze({ copy = copy, acquire = acquire, renew = renew, release = release })
end

export type API = { read configure: typeof(configure), read withState: typeof(withState), read same: typeof(same) }
local api: API = { configure = configure, withState = withState, same = same }
return table.freeze(api)
