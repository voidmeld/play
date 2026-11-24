--!strict

local Codec = require("../../kernel/codec")
local Kernel = require("../../kernel/lease")
local Result = require("../../kernel/result")
local Value = require("../../kernel/value")

export type Lease = {
	schemaVersion: number,
	userId: number,
	revision: number,
	fence: number,
	sessionId: string | false,
	acquisitionId: string | false,
	expiresAtUnix: number,
}

local Record = {}

Record.SCHEMA_VERSION = 1
Record.MAX_REVISION = 1000000000
Record.MAX_FENCE = 1000000000
Record.MAX_SAFE_INTEGER = 9007199254740991
Record.MAX_ID_BYTES = 128

local FIELDS: { [string]: boolean } = {
	schemaVersion = true,
	userId = true,
	revision = true,
	fence = true,
	sessionId = true,
	acquisitionId = true,
	expiresAtUnix = true,
}

local kernel = Kernel.configure({
	maxRevision = Record.MAX_REVISION,
	maxTime = Record.MAX_SAFE_INTEGER,
	sessionIdLimit = Record.MAX_ID_BYTES,
	acquisitionIdLimit = Record.MAX_ID_BYTES,
	integerTime = true,
})

local copyRecord = Codec.versioned({
	version = Record.SCHEMA_VERSION,
	fields = FIELDS,
	required = true,
	decode = function(source: Value.Raw): (Lease?, string?)
		local userId = Value.whole(source.userId, 1, Record.MAX_SAFE_INTEGER)
		local fence = Value.whole(source.fence, 0, Record.MAX_FENCE)
		local copied = kernel.copy({
			revision = source.revision,
			sessionId = if source.sessionId == false then nil else source.sessionId,
			acquisitionId = if source.acquisitionId == false then nil else source.acquisitionId,
			expiresAt = source.expiresAtUnix,
		})
		if userId == nil or fence == nil or not copied.ok or (copied.value.sessionId ~= nil and fence < 1) then
			return nil, "record_invalid"
		end
		local value: Lease = {
			schemaVersion = Record.SCHEMA_VERSION,
			userId = userId,
			revision = copied.value.revision,
			fence = fence,
			sessionId = copied.value.sessionId or false,
			acquisitionId = copied.value.acquisitionId or false,
			expiresAtUnix = copied.value.expiresAt,
		}
		return Value.freezeDeep(value), nil
	end,
})

function Record.validate(raw: unknown): Lease?
	local value = copyRecord(raw)
	return value
end

function Record.empty(userId: unknown): Lease?
	return Record.validate({
		schemaVersion = Record.SCHEMA_VERSION,
		userId = userId,
		revision = 0,
		fence = 0,
		sessionId = false,
		acquisitionId = false,
		expiresAtUnix = 0,
	})
end

function Record.copy(raw: unknown): Lease?
	return Record.validate(raw)
end

function Record.equal(leftRaw: unknown, rightRaw: unknown): boolean
	local left = Record.validate(leftRaw)
	local right = Record.validate(rightRaw)
	return left ~= nil and right ~= nil and Codec.equalData(left, right)
end

local function state(record: Lease): Kernel.State
	return {
		revision = record.revision,
		sessionId = if record.sessionId == false then nil else record.sessionId,
		acquisitionId = if record.acquisitionId == false then nil else record.acquisitionId,
		expiresAt = record.expiresAtUnix,
	}
end
local function withState(record: Lease, nextState: Kernel.State): Lease
	local nextRecord = table.clone(record)
	nextRecord.revision = nextState.revision
	nextRecord.sessionId = nextState.sessionId or false
	nextRecord.acquisitionId = nextState.acquisitionId or false
	nextRecord.expiresAtUnix = nextState.expiresAt
	return nextRecord
end

local function reason(result: Result.Failure): string
	local mapped = {
		identity_invalid = "invalid",
		time_invalid = "invalid",
		revision_invalid = "invalid",
		lease_held = "held",
		lease_not_owned = "not_owned",
		lease_stale = "stale",
		lease_expired = "expired",
		revision_max = "exhausted",
	}
	return mapped[result.reason] or "record_invalid"
end

function Record.acquire(
	currentRaw: unknown,
	userIdValue: unknown,
	sessionIdValue: unknown,
	acquisitionIdValue: unknown,
	nowValue: unknown,
	ttlValue: unknown
): (Lease?, string)
	local userId = Value.whole(userIdValue, 1, Record.MAX_SAFE_INTEGER)
	local sessionId = Value.opaque(sessionIdValue, Record.MAX_ID_BYTES)
	local acquisitionId = Value.opaque(acquisitionIdValue, Record.MAX_ID_BYTES)
	local now = Value.whole(nowValue, 0, Record.MAX_SAFE_INTEGER)
	local ttl = Value.whole(ttlValue, 1, Record.MAX_SAFE_INTEGER)
	if
		userId == nil
		or sessionId == nil
		or acquisitionId == nil
		or now == nil
		or ttl == nil
		or now > Record.MAX_SAFE_INTEGER - ttl
	then
		return nil, "invalid"
	end
	local current = if currentRaw == nil then Record.empty(userId) else Record.validate(currentRaw)
	if current == nil then
		return nil, "record_invalid"
	end
	if current.userId ~= userId then
		return current, "identity_mismatch"
	end
	local acquired =
		kernel.acquire(state(current), { sessionId = sessionId, acquisitionId = acquisitionId, now = now, ttl = ttl })
	if not acquired.ok then
		return current, reason(acquired)
	end
	if acquired.value.kind == "owned" then
		return current, "owned"
	end
	if current.fence >= Record.MAX_FENCE then
		return current, "exhausted"
	end
	local nextRecord = withState(current, acquired.value.state)
	nextRecord.fence += 1
	return Record.validate(nextRecord), "acquired"
end

function Record.renew(
	currentRaw: unknown,
	userIdValue: unknown,
	sessionIdValue: unknown,
	acquisitionIdValue: unknown,
	expectedRevisionValue: unknown,
	expectedFenceValue: unknown,
	nowValue: unknown,
	ttlValue: unknown
): (Lease?, string)
	local userId = Value.whole(userIdValue, 1, Record.MAX_SAFE_INTEGER)
	local sessionId = Value.opaque(sessionIdValue, Record.MAX_ID_BYTES)
	local acquisitionId = Value.opaque(acquisitionIdValue, Record.MAX_ID_BYTES)
	local expectedRevision = Value.whole(expectedRevisionValue, 0, Record.MAX_REVISION)
	local expectedFence = Value.whole(expectedFenceValue, 1, Record.MAX_FENCE)
	local now = Value.whole(nowValue, 0, Record.MAX_SAFE_INTEGER)
	local ttl = Value.whole(ttlValue, 1, Record.MAX_SAFE_INTEGER)
	if
		userId == nil
		or sessionId == nil
		or acquisitionId == nil
		or expectedRevision == nil
		or expectedFence == nil
		or now == nil
		or ttl == nil
		or now > Record.MAX_SAFE_INTEGER - ttl
	then
		return nil, "invalid"
	end
	local current = Record.validate(currentRaw)
	if current == nil then
		return nil, "absent"
	end
	if current.userId ~= userId then
		return current, "identity_mismatch"
	end
	if current.fence ~= expectedFence then
		return current, "not_owned"
	end
	local renewed = kernel.renew(
		state(current),
		{ sessionId = sessionId, acquisitionId = acquisitionId, revision = expectedRevision, now = now, ttl = ttl }
	)
	if not renewed.ok then
		return current, reason(renewed)
	end
	return Record.validate(withState(current, renewed.value.state)), "renewed"
end

function Record.release(
	currentRaw: unknown,
	userIdValue: unknown,
	sessionIdValue: unknown,
	acquisitionIdValue: unknown,
	expectedRevisionValue: unknown,
	expectedFenceValue: unknown
): (Lease?, string)
	local userId = Value.whole(userIdValue, 1, Record.MAX_SAFE_INTEGER)
	local sessionId = Value.opaque(sessionIdValue, Record.MAX_ID_BYTES)
	local acquisitionId = Value.opaque(acquisitionIdValue, Record.MAX_ID_BYTES)
	local expectedRevision = Value.whole(expectedRevisionValue, 0, Record.MAX_REVISION)
	local expectedFence = Value.whole(expectedFenceValue, 1, Record.MAX_FENCE)
	if userId == nil or sessionId == nil or acquisitionId == nil or expectedRevision == nil or expectedFence == nil then
		return nil, "invalid"
	end
	local current = Record.validate(currentRaw)
	if current == nil then
		return nil, "absent"
	end
	if current.userId ~= userId then
		return current, "identity_mismatch"
	end
	if current.sessionId == false then
		return current, "absent"
	end
	if current.fence ~= expectedFence then
		return current, "not_owned"
	end
	local released = kernel.release(
		state(current),
		{ sessionId = sessionId, acquisitionId = acquisitionId, revision = expectedRevision }
	)
	if not released.ok then
		return current, reason(released)
	end
	return Record.validate(withState(current, released.value.state)), "released"
end

return table.freeze(Record)
