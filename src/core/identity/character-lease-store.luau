--!strict

local Atomic = require("../../kernel/store")
local CharacterLease = require("./character-lease")
local Kernel = require("../../kernel/lease")
local Result = require("../../kernel/result")
local Value = require("../../kernel/value")

type Lease = CharacterLease.Record

type CharacterIdentity = { characterId: string }
export type StoreOutcome = Result.Result<Atomic.Readback>
export type Store = Atomic.Port
export type Accepted = { ok: true, value: Lease, reason: string?, takeoverPrior: Lease? }
export type Refused = { ok: false, value: nil, reason: string, takeoverPrior: Lease? }
export type Outcome = Accepted | Refused

export type Config = {
	read record: CharacterLease.API,
	read identityLimit: number,
	read zoneIdLimit: number,
}

export type API = {
	read acquire: (
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		now: number,
		ttl: number,
		sessionLive: ((string) -> boolean)?,
		lapsedLive: ((string) -> boolean)?,
		zoneId: string?
	) -> Outcome,
	read renew: (
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		expectedRevision: number,
		now: number,
		ttl: number
	) -> Outcome,
	read release: (
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		expectedRevision: number
	) -> Outcome,
	read retire: (store: Store, keyForCharacter: (string) -> string, rawWitness: unknown) -> Outcome,
	read restore: (store: Store, keyForCharacter: (string) -> string, rawWitness: unknown) -> Outcome,
	read arrive: (store: Store, keyForCharacter: (string) -> string, rawClaim: unknown) -> Outcome,
}

local function create(config: Config): API
	config = table.freeze(table.clone(config))
	assert(Value.whole(config.identityLimit, 1, 9007199254740991) ~= nil, "invalid lease identity limit")
	assert(Value.whole(config.zoneIdLimit, 1, 9007199254740991) ~= nil, "invalid lease zone limit")
	local Record = config.record
	local kernel = Kernel.configure({
		maxRevision = Record.MAX_REVISION,
		maxTime = Record.MAX_TIME,
		sessionIdLimit = config.identityLimit,
		acquisitionIdLimit = config.identityLimit,
		integerTime = false,
	})
	local Repository = {}
	local function finiteTime(value: unknown): boolean
		return type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value >= 0
			and value <= Record.MAX_TIME
	end

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= config.identityLimit
	end

	local function failed(reason: string): Refused
		return { ok = false, value = nil, reason = reason }
	end
	local function confirm(store: Store, key: string, expected: Lease, absent: boolean?): Outcome
		local read = store.read(key)
		if not read.ok then
			return failed(read.reason)
		end
		if absent and read.value == nil then
			return { ok = true, value = expected }
		end
		local value = Record.copy(read.value)
		if value == nil or not Record.equal(value, expected) then
			return failed("readback_mismatch")
		end
		return { ok = true, value = value }
	end

	function Repository.acquire(
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		now: number,
		ttl: number,
		sessionLive: ((string) -> boolean)?,
		lapsedLive: ((string) -> boolean)?,
		zoneId: string?
	): Outcome
		if not text(characterId) or not text(sessionId) or not text(acquisitionId) then
			return failed("identity_invalid")
		end
		if zoneId ~= nil and (type(zoneId) ~= "string" or #zoneId == 0 or #zoneId > config.zoneIdLimit) then
			return failed("zone_invalid")
		end
		if not finiteTime(now) or not finiteTime(ttl) or ttl <= 0 or now + ttl > Record.MAX_TIME then
			return failed("time_invalid")
		end
		local function heldByLiveSession(holderSessionId: string?, expiresAt: number): boolean
			if holderSessionId == nil then
				return false
			end
			if expiresAt <= now then
				return lapsedLive ~= nil and lapsedLive(holderSessionId) == true
			end
			if sessionLive == nil then
				return true
			end
			return sessionLive(holderSessionId) == true
		end
		local satisfied: Lease? = nil
		local invalid: string? = nil
		local takeoverPrior: Lease? = nil
		local key = keyForCharacter(characterId)
		local result = store.update(key, function(current)
			satisfied = nil
			invalid = nil
			takeoverPrior = nil
			local prior: Lease?
			if current == nil then
				prior = Record.create(characterId)
			else
				prior, invalid = Record.copy(current)
			end
			if prior == nil then
				return nil
			end
			if prior.retirement ~= false then
				return (Record.copy(prior))
			end
			if prior.revision >= Record.MAX_REVISION then
				return (Record.copy(prior))
			end
			local owned = prior.characterId == characterId
				and prior.sessionId == sessionId
				and prior.acquisitionId == acquisitionId
			if not (owned and prior.expiresAt > now) and heldByLiveSession(prior.sessionId, prior.expiresAt) then
				return (Record.copy(prior))
			end
			local held: Kernel.State = if owned then prior else { revision = prior.revision, expiresAt = 0 }
			local acquired = kernel.acquire(
				held,
				{ sessionId = sessionId, acquisitionId = acquisitionId, now = now, ttl = ttl, liveness = "dead" }
			)
			if not acquired.ok then
				return (Record.copy(prior))
			end
			if acquired.value.kind == "owned" then
				satisfied = Record.copy(prior)
				return nil
			end
			if prior.sessionId ~= nil and (prior.sessionId ~= sessionId or prior.acquisitionId ~= acquisitionId) then
				takeoverPrior = Record.copy(prior)
			end
			prior.characterId = characterId
			prior.zoneId = zoneId or prior.zoneId
			prior = Kernel.withState(prior, acquired.value.state)
			return (Record.copy(prior))
		end)
		if not result.ok then
			if result.reason ~= "callback_cancelled" then
				return failed(result.reason or "store_failure")
			end
			if satisfied ~= nil then
				return confirm(store, key, satisfied)
			end
			return failed(invalid or "store_failure")
		end
		local readback, readbackReason = Record.copy(result.value)
		if readback == nil then
			return failed(readbackReason or "readback_mismatch")
		end
		if readback.retirement ~= false then
			return failed("character_retired")
		end
		if readback.characterId ~= characterId then
			return failed("identity_mismatch")
		end
		if readback.sessionId == sessionId and readback.acquisitionId == acquisitionId and readback.expiresAt > now then
			return { ok = true, value = readback, reason = nil, takeoverPrior = takeoverPrior }
		end
		if readback.revision >= Record.MAX_REVISION then
			return failed("revision_max")
		end
		if heldByLiveSession(readback.sessionId, readback.expiresAt) then
			return failed("lease_held")
		end
		return failed("readback_mismatch")
	end

	function Repository.renew(
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		expectedRevision: number,
		now: number,
		ttl: number
	): Outcome
		if not text(characterId) or not text(sessionId) or not text(acquisitionId) then
			return failed("identity_invalid")
		end
		if
			type(expectedRevision) ~= "number"
			or expectedRevision % 1 ~= 0
			or expectedRevision < 0
			or expectedRevision > Record.MAX_REVISION
		then
			return failed("revision_invalid")
		end
		if not finiteTime(now) or not finiteTime(ttl) or ttl <= 0 or now + ttl > Record.MAX_TIME then
			return failed("time_invalid")
		end
		if expectedRevision >= Record.MAX_REVISION - 1 then
			return failed("revision_max")
		end
		local missing = false
		local invalid: string? = nil
		local result = store.update(keyForCharacter(characterId), function(current)
			missing = false
			invalid = nil
			if current == nil then
				missing = true
				return nil
			end
			local prior, priorReason = Record.copy(current)
			if prior == nil then
				invalid = priorReason or "record_invalid"
				return nil
			end
			if prior.retirement ~= false then
				return (Record.copy(prior))
			end
			if prior.characterId ~= characterId then
				return (Record.copy(prior))
			end
			local renewed = kernel.renew(
				prior,
				{
					sessionId = sessionId,
					acquisitionId = acquisitionId,
					revision = expectedRevision,
					now = now,
					ttl = ttl,
				}
			)
			if not renewed.ok then
				return (Record.copy(prior))
			end
			return (Record.copy(Kernel.withState(prior, renewed.value.state)))
		end)
		if not result.ok then
			if result.reason ~= "callback_cancelled" then
				return failed(result.reason or "store_failure")
			end
			if missing then
				return failed("lease_missing")
			end
			return failed(invalid or "record_invalid")
		end
		local readback, readbackReason = Record.copy(result.value)
		if readback == nil then
			return failed(readbackReason or "readback_mismatch")
		end
		if readback.retirement ~= false then
			return failed("character_retired")
		end
		if readback.characterId ~= characterId then
			return failed("identity_mismatch")
		end
		if readback.sessionId ~= sessionId or readback.acquisitionId ~= acquisitionId then
			return failed("lease_not_owned")
		end
		if readback.revision == expectedRevision then
			if readback.revision >= Record.MAX_REVISION then
				return failed("revision_max")
			end
			if readback.expiresAt <= now then
				return failed("lease_expired")
			end
			return failed("readback_mismatch")
		end
		if readback.revision ~= expectedRevision + 1 then
			return failed("lease_stale")
		end
		if readback.expiresAt ~= now + ttl then
			return failed("readback_mismatch")
		end
		return { ok = true, value = readback, reason = nil }
	end

	function Repository.release(
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		expectedRevision: number
	): Outcome
		if not text(characterId) or not text(sessionId) or not text(acquisitionId) then
			return failed("identity_invalid")
		end
		if
			type(expectedRevision) ~= "number"
			or expectedRevision % 1 ~= 0
			or expectedRevision < 0
			or expectedRevision > Record.MAX_REVISION
		then
			return failed("revision_invalid")
		end
		local missing = false
		local invalid: string? = nil
		local result = store.update(keyForCharacter(characterId), function(current)
			missing = false
			invalid = nil
			if current == nil then
				missing = true
				return nil
			end
			local prior, priorReason = Record.copy(current)
			if prior == nil then
				invalid = priorReason or "record_invalid"
				return nil
			end
			if prior.characterId ~= characterId then
				return (Record.copy(prior))
			end
			local released = kernel.release(
				prior,
				{ sessionId = sessionId, acquisitionId = acquisitionId, revision = expectedRevision }
			)
			if not released.ok then
				return (Record.copy(prior))
			end
			return (Record.copy(Kernel.withState(prior, released.value.state)))
		end)
		if not result.ok then
			if result.reason ~= "callback_cancelled" then
				return failed(result.reason or "store_failure")
			end
			if missing then
				return failed("lease_missing")
			end
			return failed(invalid or "record_invalid")
		end
		local readback = Record.copy(result.value)
		if readback == nil then
			return failed("readback_mismatch")
		end
		if readback.characterId ~= characterId then
			return failed("identity_mismatch")
		end
		if
			readback.sessionId == nil
			and readback.acquisitionId == nil
			and readback.expiresAt == 0
			and readback.revision == expectedRevision + 1
		then
			return { ok = true, value = readback, reason = nil }
		end
		if readback.sessionId ~= sessionId or readback.acquisitionId ~= acquisitionId then
			return failed("lease_not_owned")
		end
		if readback.revision ~= expectedRevision then
			return failed("lease_stale")
		end
		if readback.revision >= Record.MAX_REVISION then
			return failed("revision_max")
		end
		return failed("readback_mismatch")
	end

	local function transition<W>(
		store: Store,
		keyForCharacter: (string) -> string,
		rawWitness: unknown,
		validate: (unknown) -> ((W & CharacterIdentity)?, string?),
		apply: (unknown, W & CharacterIdentity) -> (Lease?, string),
		settled: (Lease, W & CharacterIdentity) -> boolean,
		conflict: string,
		allowAbsent: boolean?
	): Outcome
		local witness, witnessReason = validate(rawWitness)
		if witness == nil then
			return failed(witnessReason or "witness_invalid")
		end
		local satisfied: Lease? = nil
		local satisfiedAbsent = false
		local rejected: string? = nil
		local key = keyForCharacter(witness.characterId)
		local result = store.update(key, function(current)
			satisfied = nil
			satisfiedAbsent = false
			rejected = nil
			local nextRecord, status = apply(current, witness)
			if nextRecord == nil then
				rejected = status
				return current
			end
			if status == "replayed" then
				satisfied = nextRecord
				satisfiedAbsent = allowAbsent == true and current == nil
				return nil
			end
			return nextRecord
		end)
		if not result.ok then
			if result.reason ~= "callback_cancelled" then
				return failed(result.reason or "store_failure")
			end
			if rejected ~= nil then
				return failed(rejected)
			end
			if satisfied ~= nil then
				return confirm(store, key, satisfied, satisfiedAbsent)
			end
			return failed("store_failure")
		end
		if rejected ~= nil then
			return failed(rejected)
		end
		local readback, readbackReason = Record.copy(result.value)
		if readback == nil then
			return failed(readbackReason or "readback_mismatch")
		end
		if readback.characterId ~= witness.characterId then
			return failed("identity_mismatch")
		end
		if not settled(readback, witness) then
			return failed(conflict)
		end
		return { ok = true, value = readback, reason = nil }
	end

	function Repository.retire(store: Store, keyForCharacter: (string) -> string, rawWitness: unknown): Outcome
		return transition(
			store,
			keyForCharacter,
			rawWitness,
			Record.witness,
			Record.retire,
			function(readback, witness: CharacterLease.Witness)
				local retirement = Record.retirementOf(readback)
				return retirement ~= nil
					and retirement.operationId == witness.operationId
					and retirement.fingerprint == witness.fingerprint
					and retirement.fence == witness.fence
			end,
			"retirement_conflict"
		)
	end

	function Repository.restore(store: Store, keyForCharacter: (string) -> string, rawWitness: unknown): Outcome
		return transition(store, keyForCharacter, rawWitness, Record.witness, Record.restore, function(readback)
			return readback.retirement == false
		end, "retirement_conflict", true)
	end

	function Repository.arrive(store: Store, keyForCharacter: (string) -> string, rawClaim: unknown): Outcome
		return transition(
			store,
			keyForCharacter,
			rawClaim,
			Record.claim,
			Record.arrive,
			function(readback, claim: CharacterLease.Claim)
				local arrival = Record.arrivalOf(readback)
				return arrival ~= nil
					and arrival.sessionId == claim.sessionId
					and arrival.acquisitionId == claim.acquisitionId
					and arrival.fence == claim.fence
			end,
			"arrival_conflict"
		)
	end

	return table.freeze(Repository)
end

return table.freeze({ create = create })
