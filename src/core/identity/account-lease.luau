--!strict

local HasMetatable = require("./value")

export type Lease = {
	schemaVersion: number,
	userId: number,
	revision: number,
	fence: number,
	sessionId: string | false,
	acquisitionId: string | false,
	expiresAtUnix: number,
}
type Raw = { [unknown]: unknown }

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

local function whole(value: unknown, minimum: number, maximum: number): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value >= minimum
		and value <= maximum
		and value % 1 == 0
end

local function text(value: unknown): boolean
	return type(value) == "string" and #value > 0 and #value <= Record.MAX_ID_BYTES
end

local function exact(raw: unknown): boolean
	if type(raw) ~= "table" or getmetatable(raw :: HasMetatable.MetatableProbe) ~= nil then
		return false
	end
	for key in raw :: Raw do
		if type(key) ~= "string" or FIELDS[key] ~= true then
			return false
		end
	end
	for key in FIELDS do
		if (raw :: Raw)[key] == nil then
			return false
		end
	end
	return true
end

local function frozen(raw: Lease): Lease
	local value: Lease = {
		schemaVersion = Record.SCHEMA_VERSION,
		userId = raw.userId,
		revision = raw.revision,
		fence = raw.fence,
		sessionId = raw.sessionId,
		acquisitionId = raw.acquisitionId,
		expiresAtUnix = raw.expiresAtUnix,
	}
	return table.freeze(value) :: Lease
end

local function request(userId: unknown, sessionId: unknown, acquisitionId: unknown): boolean
	return whole(userId, 1, Record.MAX_SAFE_INTEGER) and text(sessionId) and text(acquisitionId)
end

local function timeWindow(now: unknown, ttl: unknown): boolean
	return whole(now, 0, Record.MAX_SAFE_INTEGER)
		and whole(ttl, 1, Record.MAX_SAFE_INTEGER)
		and (now :: number) <= Record.MAX_SAFE_INTEGER - (ttl :: number)
end

function Record.validate(raw: unknown): Lease?
	local source = raw :: Raw
	if
		not exact(raw)
		or source.schemaVersion ~= Record.SCHEMA_VERSION
		or not whole(source.userId, 1, Record.MAX_SAFE_INTEGER)
		or not whole(source.revision, 0, Record.MAX_REVISION)
		or not whole(source.fence, 0, Record.MAX_FENCE)
		or not whole(source.expiresAtUnix, 0, Record.MAX_SAFE_INTEGER)
	then
		return nil
	end
	if source.sessionId == false then
		if source.acquisitionId ~= false or source.expiresAtUnix ~= 0 then
			return nil
		end
	elseif
		not text(source.sessionId)
		or not text(source.acquisitionId)
		or (source.fence :: number) < 1
		or (source.expiresAtUnix :: number) < 1
	then
		return nil
	end
	return frozen((raw :: unknown) :: Lease)
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
	userId: unknown,
	sessionId: unknown,
	acquisitionId: unknown,
	now: unknown,
	ttl: unknown
): (Lease?, string)
	if not request(userId, sessionId, acquisitionId) or not timeWindow(now, ttl) then
		return nil, "invalid"
	end
	local current = if currentRaw == nil then Record.empty(userId) else Record.validate(currentRaw)
	if current == nil then
		return nil, "record_invalid"
	end
	if current.userId ~= userId then
		return current, "identity_mismatch"
	end
	if current.sessionId ~= false and current.expiresAtUnix > (now :: number) then
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
		expiresAtUnix = (now :: number) + (ttl :: number),
	}
	return Record.validate(nextRecord), "acquired"
end

function Record.renew(
	currentRaw: unknown,
	userId: unknown,
	sessionId: unknown,
	acquisitionId: unknown,
	expectedRevision: unknown,
	expectedFence: unknown,
	now: unknown,
	ttl: unknown
): (Lease?, string)
	if
		not request(userId, sessionId, acquisitionId)
		or not whole(expectedRevision, 0, Record.MAX_REVISION)
		or not whole(expectedFence, 1, Record.MAX_FENCE)
		or not timeWindow(now, ttl)
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
	if current.expiresAtUnix <= (now :: number) then
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
		expiresAtUnix = (now :: number) + (ttl :: number),
	}
	return Record.validate(nextRecord), "renewed"
end

function Record.release(
	currentRaw: unknown,
	userId: unknown,
	sessionId: unknown,
	acquisitionId: unknown,
	expectedRevision: unknown,
	expectedFence: unknown
): (Lease?, string)
	if
		not request(userId, sessionId, acquisitionId)
		or not whole(expectedRevision, 0, Record.MAX_REVISION)
		or not whole(expectedFence, 1, Record.MAX_FENCE)
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

Record.Types = (nil :: unknown) :: { Lease: Lease }

return table.freeze(Record)
