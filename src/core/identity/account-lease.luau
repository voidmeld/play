--!strict

local Value = require("../internal/value")

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

local function readOwner(value: unknown): (string | false)?
	if value == false then
		return false
	end
	return Value.opaque(value, Record.MAX_ID_BYTES)
end

function Record.validate(raw: unknown): Lease?
	local source = Value.record(raw, FIELDS, true)
	if source == nil or source.schemaVersion ~= Record.SCHEMA_VERSION then
		return nil
	end
	local userId = Value.whole(source.userId, 1, Record.MAX_SAFE_INTEGER)
	local revision = Value.whole(source.revision, 0, Record.MAX_REVISION)
	local fence = Value.whole(source.fence, 0, Record.MAX_FENCE)
	local expires = Value.whole(source.expiresAtUnix, 0, Record.MAX_SAFE_INTEGER)
	if userId == nil or revision == nil or fence == nil or expires == nil then
		return nil
	end
	local session, acquisition = readOwner(source.sessionId), readOwner(source.acquisitionId)
	if session == nil or acquisition == nil then
		return nil
	end
	if session == false then
		if acquisition ~= false or expires ~= 0 then
			return nil
		end
	elseif
		type(session) ~= "string"
		or Value.opaque(session, Record.MAX_ID_BYTES) == nil
		or type(acquisition) ~= "string"
		or Value.opaque(acquisition, Record.MAX_ID_BYTES) == nil
		or fence < 1
		or expires < 1
	then
		return nil
	end
	local value: Lease = {
		schemaVersion = Record.SCHEMA_VERSION,
		userId = userId,
		revision = revision,
		fence = fence,
		sessionId = session,
		acquisitionId = acquisition,
		expiresAtUnix = expires,
	}
	return Value.freezeDeep(value)
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
	return left ~= nil
		and right ~= nil
		and left.userId == right.userId
		and left.revision == right.revision
		and left.fence == right.fence
		and left.sessionId == right.sessionId
		and left.acquisitionId == right.acquisitionId
		and left.expiresAtUnix == right.expiresAtUnix
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
	if current.sessionId ~= false and current.expiresAtUnix > now then
		if current.sessionId == sessionId and current.acquisitionId == acquisitionId then
			return current, "owned"
		end
		return current, "held"
	end
	if current.revision >= Record.MAX_REVISION or current.fence >= Record.MAX_FENCE then
		return current, "exhausted"
	end
	local nextRecord = {
		schemaVersion = Record.SCHEMA_VERSION,
		userId = current.userId,
		revision = current.revision + 1,
		fence = current.fence + 1,
		sessionId = sessionId,
		acquisitionId = acquisitionId,
		expiresAtUnix = now + ttl,
	}
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
	if current.sessionId ~= sessionId or current.acquisitionId ~= acquisitionId or current.fence ~= expectedFence then
		return current, "not_owned"
	end
	if current.revision ~= expectedRevision then
		return current, "stale"
	end
	if current.expiresAtUnix <= now then
		return current, "expired"
	end
	if current.revision >= Record.MAX_REVISION then
		return current, "exhausted"
	end
	local nextRecord = {
		schemaVersion = Record.SCHEMA_VERSION,
		userId = current.userId,
		revision = current.revision + 1,
		fence = current.fence,
		sessionId = current.sessionId,
		acquisitionId = current.acquisitionId,
		expiresAtUnix = now + ttl,
	}
	return Record.validate(nextRecord), "renewed"
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
	if current.sessionId ~= sessionId or current.acquisitionId ~= acquisitionId or current.fence ~= expectedFence then
		return current, "not_owned"
	end
	if current.revision ~= expectedRevision then
		return current, "stale"
	end
	if current.revision >= Record.MAX_REVISION then
		return current, "exhausted"
	end
	local nextRecord = {
		schemaVersion = Record.SCHEMA_VERSION,
		userId = current.userId,
		revision = current.revision + 1,
		fence = current.fence,
		sessionId = false,
		acquisitionId = false,
		expiresAtUnix = 0,
	}
	return Record.validate(nextRecord), "released"
end

return table.freeze(Record)
