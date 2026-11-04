--!strict

local Codec = require("../../kernel/codec")
local Shape = require("../internal/shape")
local Value = require("../../kernel/value")

export type Record = CharacterLeaseRecord

export type Retirement = {
	operationId: string,
	fingerprint: string,
	fence: number,
	retiredAtUnix: number,
}

export type Arrival = {
	sessionId: string,
	acquisitionId: string,
	fence: number,
	arrivedAtUnix: number,
}

export type CharacterLeaseRecord = {
	schemaVersion: number,
	revision: number,
	characterId: string,
	zoneId: string?,
	sessionId: string?,
	acquisitionId: string?,
	expiresAt: number,
	retirement: Retirement | false,
	arrival: Arrival | false,
}

export type Witness = {
	characterId: string,
	operationId: string,
	fingerprint: string,
	fence: number,
	atUnix: number,
}

export type Claim = {
	characterId: string,
	sessionId: string,
	acquisitionId: string,
	revision: number,
	fence: number,
	atUnix: number,
}

export type Config = {
	read schemaVersion: number,
	read maxRevision: number,
	read maxTime: number,
	read maxFence: number,
	read characterIdLimit: number,
	read zoneIdLimit: number,
	read sessionIdLimit: number,
	read acquisitionIdLimit: number,
	read operationIdLimit: number,
	read fingerprintLimit: number,
	read migrate: (unknown) -> unknown,
}

export type API = {
	read SCHEMA_VERSION: number,
	read MAX_REVISION: number,
	read MAX_TIME: number,
	read MAX_FENCE: number,
	read retirementOf: (record: CharacterLeaseRecord) -> Retirement?,
	read arrivalOf: (record: CharacterLeaseRecord) -> Arrival?,
	read copy: (stored: unknown) -> (CharacterLeaseRecord?, string?),
	read create: (characterId: string) -> (CharacterLeaseRecord?, string?),
	read equal: (left: unknown, right: unknown) -> boolean,
	read witness: (raw: unknown) -> (Witness?, string?),
	read claim: (raw: unknown) -> (Claim?, string?),
	read retire: (raw: unknown, rawWitness: unknown) -> (CharacterLeaseRecord?, string),
	read restore: (raw: unknown, rawWitness: unknown) -> (CharacterLeaseRecord?, string),
	read arrive: (raw: unknown, rawClaim: unknown) -> (CharacterLeaseRecord?, string),
	read retired: (raw: unknown) -> boolean,
}

local function create(config: Config): API
	config = table.freeze(table.clone(config))
	for _, value in
		{
			config.schemaVersion,
			config.maxRevision,
			config.maxFence,
			config.characterIdLimit,
			config.zoneIdLimit,
			config.sessionIdLimit,
			config.acquisitionIdLimit,
			config.operationIdLimit,
			config.fingerprintLimit,
		}
	do
		assert(Value.whole(value, 1, 9007199254740991) ~= nil, "invalid character lease limit")
	end
	assert(Value.finite(config.maxTime) and config.maxTime > 0, "invalid character lease time limit")
	local Record = {
		SCHEMA_VERSION = config.schemaVersion,
		MAX_REVISION = config.maxRevision,
		MAX_TIME = config.maxTime,
		MAX_FENCE = config.maxFence,
	}
	local RECORD_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		revision = true,
		characterId = true,
		zoneId = true,
		sessionId = true,
		acquisitionId = true,
		expiresAt = true,
		retirement = true,
		arrival = true,
	}

	local RETIREMENT_FIELDS: { [string]: boolean } = {
		operationId = true,
		fingerprint = true,
		fence = true,
		retiredAtUnix = true,
	}

	local ARRIVAL_FIELDS: { [string]: boolean } = {
		sessionId = true,
		acquisitionId = true,
		fence = true,
		arrivedAtUnix = true,
	}

	local WITNESS_FIELDS: { [string]: boolean } = {
		characterId = true,
		operationId = true,
		fingerprint = true,
		fence = true,
		atUnix = true,
	}

	local CLAIM_FIELDS: { [string]: boolean } = {
		characterId = true,
		sessionId = true,
		acquisitionId = true,
		revision = true,
		fence = true,
		atUnix = true,
	}

	local function exact(value: unknown, fields: { [string]: boolean }): Shape.Raw?
		local raw = Shape.raw(value)
		if raw == nil then
			return nil
		end
		for key in raw do
			if type(key) ~= "string" or fields[key] ~= true then
				return nil
			end
		end
		return raw
	end

	local function whole(value: unknown, maximum: number): number?
		if
			type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value >= 0
			and value <= maximum
			and value % 1 == 0
		then
			return value
		end
		return nil
	end

	local function positiveFence(value: unknown): number?
		local fence = whole(value, Record.MAX_FENCE)
		if fence == nil or fence < 1 then
			return nil
		end
		return fence
	end

	local function finiteTime(value: unknown): number?
		if
			type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value >= 0
			and value <= Record.MAX_TIME
		then
			return value
		end
		return nil
	end

	local function text(value: unknown, maximum: number): string?
		if type(value) == "string" and #value > 0 and #value <= maximum then
			return value
		end
		return nil
	end

	local function copyRetirement(raw: unknown): Retirement?
		local source = exact(raw, RETIREMENT_FIELDS)
		if source == nil then
			return nil
		end
		local operationId = text(source.operationId, config.operationIdLimit)
		local fingerprint = text(source.fingerprint, config.fingerprintLimit)
		local fence = positiveFence(source.fence)
		local retiredAtUnix = finiteTime(source.retiredAtUnix)
		if operationId == nil or fingerprint == nil or fence == nil or retiredAtUnix == nil then
			return nil
		end
		return {
			operationId = operationId,
			fingerprint = fingerprint,
			fence = fence,
			retiredAtUnix = retiredAtUnix,
		}
	end

	local function copyArrival(raw: unknown): Arrival?
		local source = exact(raw, ARRIVAL_FIELDS)
		if source == nil then
			return nil
		end
		local sessionId = text(source.sessionId, config.sessionIdLimit)
		local acquisitionId = text(source.acquisitionId, config.acquisitionIdLimit)
		local fence = positiveFence(source.fence)
		local arrivedAtUnix = finiteTime(source.arrivedAtUnix)
		if sessionId == nil or acquisitionId == nil or fence == nil or arrivedAtUnix == nil then
			return nil
		end
		return {
			sessionId = sessionId,
			acquisitionId = acquisitionId,
			fence = fence,
			arrivedAtUnix = arrivedAtUnix,
		}
	end

	local function retirementOf(record: CharacterLeaseRecord): Retirement?
		return if record.retirement == false then nil else record.retirement
	end

	local function arrivalOf(record: CharacterLeaseRecord): Arrival?
		return if record.arrival == false then nil else record.arrival
	end

	function Record.retirementOf(record: CharacterLeaseRecord): Retirement?
		return retirementOf(record)
	end

	function Record.arrivalOf(record: CharacterLeaseRecord): Arrival?
		return arrivalOf(record)
	end

	local copyRecord = Codec.versioned({
		version = Record.SCHEMA_VERSION,
		fields = RECORD_FIELDS,
		migrate = config.migrate,
		decode = function(source: Value.Raw): (CharacterLeaseRecord?, string?)
			local revision = whole(source.revision, Record.MAX_REVISION)
			local characterId = text(source.characterId, config.characterIdLimit)
			if revision == nil or characterId == nil then
				return nil, "record_invalid"
			end
			local sessionId = text(source.sessionId, config.sessionIdLimit)
			if source.sessionId ~= nil and sessionId == nil then
				return nil, "record_invalid"
			end
			local acquisitionId = text(source.acquisitionId, config.acquisitionIdLimit)
			if source.acquisitionId ~= nil and acquisitionId == nil then
				return nil, "record_invalid"
			end
			local zoneId = text(source.zoneId, config.zoneIdLimit)
			if source.zoneId ~= nil and zoneId == nil then
				return nil, "record_invalid"
			end
			local expiresAt = finiteTime(source.expiresAt)
			if expiresAt == nil then
				return nil, "record_invalid"
			end
			local unowned = sessionId == nil and acquisitionId == nil and expiresAt == 0
			local owned = sessionId ~= nil and acquisitionId ~= nil and expiresAt > 0
			if not unowned and not owned then
				return nil, "lease_invalid"
			end
			if source.retirement == nil then
				return nil, "retirement_absent"
			end
			local retirement: Retirement | false = false
			if source.retirement ~= false then
				local copied = copyRetirement(source.retirement)
				if copied == nil then
					return nil, "retirement_invalid"
				end
				retirement = copied
			end
			if source.arrival == nil then
				return nil, "arrival_absent"
			end
			local arrival: Arrival | false = false
			if source.arrival ~= false then
				local copied = copyArrival(source.arrival)
				if copied == nil then
					return nil, "arrival_invalid"
				end
				arrival = copied
			end
			return {
				schemaVersion = Record.SCHEMA_VERSION,
				revision = revision,
				characterId = characterId,
				zoneId = zoneId,
				sessionId = sessionId,
				acquisitionId = acquisitionId,
				expiresAt = expiresAt,
				retirement = retirement,
				arrival = arrival,
			},
				nil
		end,
	})

	function Record.copy(stored: unknown): (CharacterLeaseRecord?, string?)
		return copyRecord(stored)
	end

	function Record.create(characterId: string): (CharacterLeaseRecord?, string?)
		return Record.copy({
			schemaVersion = Record.SCHEMA_VERSION,
			revision = 0,
			characterId = characterId,
			sessionId = nil,
			acquisitionId = nil,
			expiresAt = 0,
			retirement = false,
			arrival = false,
		})
	end

	function Record.equal(left: unknown, right: unknown): boolean
		local a = Record.copy(left)
		local b = Record.copy(right)
		if a == nil or b == nil then
			return false
		end
		if
			a.schemaVersion ~= b.schemaVersion
			or a.revision ~= b.revision
			or a.characterId ~= b.characterId
			or a.zoneId ~= b.zoneId
			or a.sessionId ~= b.sessionId
			or a.acquisitionId ~= b.acquisitionId
			or a.expiresAt ~= b.expiresAt
		then
			return false
		end
		local leftMark = retirementOf(a)
		local rightMark = retirementOf(b)
		if leftMark == nil or rightMark == nil then
			if leftMark ~= rightMark then
				return false
			end
		elseif
			leftMark.operationId ~= rightMark.operationId
			or leftMark.fingerprint ~= rightMark.fingerprint
			or leftMark.fence ~= rightMark.fence
			or leftMark.retiredAtUnix ~= rightMark.retiredAtUnix
		then
			return false
		end
		local leftArrival = arrivalOf(a)
		local rightArrival = arrivalOf(b)
		if leftArrival == nil or rightArrival == nil then
			return leftArrival == rightArrival
		end
		return leftArrival.sessionId == rightArrival.sessionId
			and leftArrival.acquisitionId == rightArrival.acquisitionId
			and leftArrival.fence == rightArrival.fence
			and leftArrival.arrivedAtUnix == rightArrival.arrivedAtUnix
	end

	function Record.witness(raw: unknown): (Witness?, string?)
		local source = exact(raw, WITNESS_FIELDS)
		if source == nil then
			return nil, "witness_invalid"
		end
		local characterId = text(source.characterId, config.characterIdLimit)
		local operationId = text(source.operationId, config.operationIdLimit)
		local fingerprint = text(source.fingerprint, config.fingerprintLimit)
		local fence = positiveFence(source.fence)
		local atUnix = finiteTime(source.atUnix)
		if characterId == nil or operationId == nil or fingerprint == nil or fence == nil or atUnix == nil then
			return nil, "witness_invalid"
		end
		return {
			characterId = characterId,
			operationId = operationId,
			fingerprint = fingerprint,
			fence = fence,
			atUnix = atUnix,
		},
			nil
	end

	function Record.claim(raw: unknown): (Claim?, string?)
		local source = exact(raw, CLAIM_FIELDS)
		if source == nil then
			return nil, "claim_invalid"
		end
		local characterId = text(source.characterId, config.characterIdLimit)
		local sessionId = text(source.sessionId, config.sessionIdLimit)
		local acquisitionId = text(source.acquisitionId, config.acquisitionIdLimit)
		local revision = whole(source.revision, Record.MAX_REVISION)
		local fence = positiveFence(source.fence)
		local atUnix = finiteTime(source.atUnix)
		if
			characterId == nil
			or sessionId == nil
			or acquisitionId == nil
			or revision == nil
			or revision < 1
			or fence == nil
			or atUnix == nil
		then
			return nil, "claim_invalid"
		end
		return {
			characterId = characterId,
			sessionId = sessionId,
			acquisitionId = acquisitionId,
			revision = revision,
			fence = fence,
			atUnix = atUnix,
		},
			nil
	end

	local function subject(raw: unknown, identity: { characterId: string }): (CharacterLeaseRecord?, string?)
		if raw == nil then
			return Record.create(identity.characterId)
		end
		local record, reason = Record.copy(raw)
		if record == nil then
			return nil, reason or "record_invalid"
		end
		if record.characterId ~= identity.characterId then
			return nil, "identity_mismatch"
		end
		return record, nil
	end

	function Record.retire(raw: unknown, rawWitness: unknown): (CharacterLeaseRecord?, string)
		local witness, witnessReason = Record.witness(rawWitness)
		if witness == nil then
			return nil, witnessReason or "witness_invalid"
		end
		local record, reason = subject(raw, witness)
		if record == nil then
			return nil, reason or "record_invalid"
		end
		local current = retirementOf(record)
		if current ~= nil then
			if current.operationId ~= witness.operationId then
				if witness.fence <= current.fence then
					return nil, "stale_fence"
				end
			else
				if current.fingerprint ~= witness.fingerprint then
					return nil, "receipt_conflict"
				end
				if witness.fence < current.fence then
					return nil, "stale_fence"
				end
				if witness.fence == current.fence then
					return record, "replayed"
				end
			end
		end
		record.retirement = {
			operationId = witness.operationId,
			fingerprint = witness.fingerprint,
			fence = witness.fence,
			retiredAtUnix = witness.atUnix,
		}
		local retired, retiredReason = Record.copy(record)
		if retired == nil then
			return nil, retiredReason or "record_invalid"
		end
		return retired, "retired"
	end

	function Record.restore(raw: unknown, rawWitness: unknown): (CharacterLeaseRecord?, string)
		local witness, witnessReason = Record.witness(rawWitness)
		if witness == nil then
			return nil, witnessReason or "witness_invalid"
		end
		local record, reason = subject(raw, witness)
		if record == nil then
			return nil, reason or "record_invalid"
		end
		local current = retirementOf(record)
		if current == nil then
			return record, "replayed"
		end
		if current.operationId ~= witness.operationId then
			return nil, "retirement_not_owned"
		end
		if current.fingerprint ~= witness.fingerprint then
			return nil, "receipt_conflict"
		end
		if witness.fence < current.fence then
			return nil, "stale_fence"
		end
		record.retirement = false
		local restored, restoredReason = Record.copy(record)
		if restored == nil then
			return nil, restoredReason or "record_invalid"
		end
		return restored, "restored"
	end

	function Record.arrive(raw: unknown, rawClaim: unknown): (CharacterLeaseRecord?, string)
		local claim, claimReason = Record.claim(rawClaim)
		if claim == nil then
			return nil, claimReason or "claim_invalid"
		end
		local record, reason = subject(raw, claim)
		if record == nil then
			return nil, reason or "record_invalid"
		end
		if record.retirement ~= false then
			return nil, "character_retired"
		end
		if
			record.sessionId ~= claim.sessionId
			or record.acquisitionId ~= claim.acquisitionId
			or record.revision ~= claim.revision
		then
			return nil, "lease_not_owned"
		end
		if claim.fence >= record.revision then
			return nil, "fence_unacquired"
		end
		local current = arrivalOf(record)
		if current ~= nil then
			if
				current.sessionId == claim.sessionId
				and current.acquisitionId == claim.acquisitionId
				and current.fence == claim.fence
			then
				return record, "replayed"
			end
			if claim.fence <= current.fence then
				return nil, "stale_fence"
			end
		end
		record.arrival = {
			sessionId = claim.sessionId,
			acquisitionId = claim.acquisitionId,
			fence = claim.fence,
			arrivedAtUnix = claim.atUnix,
		}
		local arrived, arrivedReason = Record.copy(record)
		if arrived == nil then
			return nil, arrivedReason or "record_invalid"
		end
		return arrived, "arrived"
	end

	function Record.retired(raw: unknown): boolean
		local record = Record.copy(raw)
		return record ~= nil and record.retirement ~= false
	end

	return table.freeze(Record)
end

return table.freeze({ create = create })
