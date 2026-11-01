--!strict

local HasMetatable = require("./value")
local NameRegistry = require("./name-claims")
local Policy = require("./policy")
local Roster = require("./roster")

type NameClaim = NameRegistry.Claim
type RosterCharacter = Roster.CharacterIdentity
export type Completion = {
	[string]: unknown,
	expectedRevision: number,
	expectedFence: number,
	fence: number?,
	leaseRevision: number?,
}
export type Receipt = {
	[string]: unknown,
	operationId: string,
	fingerprint: string,
	characterId: string,
	revision: number,
	fence: number,
	leaseRevision: number?,
}

export type Phase =
	"prepared"
	| "name_owned"
	| "profile_prepared"
	| "committed"
	| "lease_released"
	| "rolling_back"
	| "aborted"
export type State = {
	schemaVersion: number,
	userId: number,
	operationId: string,
	fingerprint: string,
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	createdAtUnix: number,
	phase: Phase,
	revision: number,
	fence: number,
	leaseRevision: number,
	initialFence: number,
	initialLeaseRevision: number,
	rollbackNeedsNameRelease: boolean,
}
export type Prepared = {
	userId: number,
	operationId: string,
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	createdAtUnix: number,
	fence: number,
	leaseRevision: number,
}
export type Rejected = { ok: false, state: State?, reason: string }
export type Accepted = { ok: true, state: State, replayed: boolean, reason: nil }
export type Result = Rejected | Accepted
export type Plan = {
	expectedRevision: number,
	expectedFence: number,
	kind: string,
	claim: NameClaim?,
	character: RosterCharacter?,
}
type RawEvent = {
	expectedRevision: unknown,
	expectedFence: unknown,
	readback: unknown,
	base: unknown,
	fence: unknown,
	leaseRevision: unknown,
	profileReadback: unknown,
	nameReadback: unknown,
	nameReadbackReceived: unknown,
}

local function create(policy: Policy.Policy)
	local rosterRules = Roster.create(policy)
	local nameregistry = NameRegistry.create(policy)

	local SCHEMA_VERSION = 1
	local MAX_REVISION = 1000000000
	local MAX_FENCE = 1000000000
	local MAX_SAFE_INTEGER = 9007199254740991
	local MAX_ID_BYTES = 128
	local MAX_FINGERPRINT_BYTES = 2048
	local KNOWN_STATE_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		userId = true,
		operationId = true,
		fingerprint = true,
		characterId = true,
		displayName = true,
		realmId = true,
		peopleId = true,
		classId = true,
		appearancePresetId = true,
		createdAtUnix = true,
		phase = true,
		revision = true,
		fence = true,
		leaseRevision = true,
		initialFence = true,
		initialLeaseRevision = true,
		rollbackNeedsNameRelease = true,
	}

	local phases: { [string]: boolean } = {
		prepared = true,
		name_owned = true,
		profile_prepared = true,
		committed = true,
		lease_released = true,
		rolling_back = true,
		aborted = true,
	}

	local tableFields = HasMetatable.fields

	local function futureVersion(value: unknown, current: number): boolean
		local readback = tableFields(value)
		return readback ~= nil and type(readback.schemaVersion) == "number" and readback.schemaVersion > current
	end

	local function whole(value: unknown, minimum: number, maximum: number): boolean
		return type(value) == "number"
			and value == value
			and value == math.floor(value)
			and value >= minimum
			and value <= maximum
	end

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_ID_BYTES
	end

	local function fingerprintText(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_FINGERPRINT_BYTES
	end

	local function copy(state: State): State
		return {
			schemaVersion = state.schemaVersion,
			userId = state.userId,
			operationId = state.operationId,
			fingerprint = state.fingerprint,
			characterId = state.characterId,
			displayName = state.displayName,
			realmId = state.realmId,
			peopleId = state.peopleId,
			classId = state.classId,
			appearancePresetId = state.appearancePresetId,
			createdAtUnix = state.createdAtUnix,
			phase = state.phase,
			revision = state.revision,
			fence = state.fence,
			leaseRevision = state.leaseRevision,
			initialFence = state.initialFence,
			initialLeaseRevision = state.initialLeaseRevision,
			rollbackNeedsNameRelease = state.rollbackNeedsNameRelease,
		}
	end

	local function character(state: State): RosterCharacter
		return {
			characterId = state.characterId,
			displayName = state.displayName,
			realmId = state.realmId,
			peopleId = state.peopleId,
			classId = state.classId,
			appearancePresetId = state.appearancePresetId,
			createdAtUnix = state.createdAtUnix,
			lastPlayedAtUnix = state.createdAtUnix,
			level = rosterRules.MIN_LEVEL,
			lastDestinationId = rosterRules.NEVER_DEPARTED,
		}
	end

	local function segment(value: string): string
		return ("%d:%s"):format(#value, value)
	end

	local function fingerprint(candidate: unknown): string?
		local prepared = candidate
		local nameOk, displayName = policy.validateName(prepared.displayName)
		if not nameOk or displayName == nil then
			return nil
		end
		if
			not whole(prepared.userId, 1, MAX_SAFE_INTEGER)
			or not text(prepared.operationId)
			or not text(prepared.characterId)
			or not text(prepared.realmId)
			or not text(prepared.peopleId)
			or not text(prepared.classId)
			or not text(prepared.appearancePresetId)
			or not whole(prepared.createdAtUnix, 0, MAX_SAFE_INTEGER)
			or not whole(prepared.fence, 1, MAX_FENCE)
			or not whole(prepared.leaseRevision, 1, MAX_REVISION)
		then
			return nil
		end
		return segment(tostring(prepared.userId))
			.. segment(prepared.operationId)
			.. segment(prepared.characterId)
			.. segment(displayName)
			.. segment(prepared.realmId)
			.. segment(prepared.peopleId)
			.. segment(prepared.classId)
			.. segment(prepared.appearancePresetId)
			.. segment(tostring(prepared.createdAtUnix))
			.. segment(tostring(prepared.leaseRevision))
	end

	local function validCharacter(prepared: Prepared, displayName: string, stored: boolean?): boolean
		local roster = {
			schemaVersion = rosterRules.SCHEMA_VERSION,
			userId = prepared.userId,
			characters = {},
		}
		local value = {
			characterId = prepared.characterId,
			displayName = displayName,
			realmId = prepared.realmId,
			peopleId = prepared.peopleId,
			classId = prepared.classId,
			appearancePresetId = prepared.appearancePresetId,
			createdAtUnix = prepared.createdAtUnix,
			lastPlayedAtUnix = prepared.createdAtUnix,
			level = rosterRules.MIN_LEVEL,
			lastDestinationId = rosterRules.NEVER_DEPARTED,
		}
		local ok = pcall(function()
			if stored == true then
				rosterRules.validateStored({
					schemaVersion = roster.schemaVersion,
					userId = roster.userId,
					characters = { value },
				})
			else
				rosterRules.add(roster, value)
			end
		end)
		return ok
	end

	local function validate(candidate: unknown, stored: boolean?): State?
		if type(candidate) ~= "table" then
			return nil
		end
		local state = candidate
		for key in state do
			if type(key) ~= "string" or not KNOWN_STATE_FIELDS[key] then
				return nil
			end
		end
		if
			state.schemaVersion ~= SCHEMA_VERSION
			or not whole(state.userId, 1, MAX_SAFE_INTEGER)
			or not text(state.operationId)
			or not fingerprintText(state.fingerprint)
			or not text(state.characterId)
			or not text(state.realmId)
			or not text(state.peopleId)
			or not text(state.classId)
			or not text(state.appearancePresetId)
			or not whole(state.createdAtUnix, 0, MAX_SAFE_INTEGER)
			or not phases[state.phase]
			or not whole(state.revision, 0, MAX_REVISION)
			or not whole(state.fence, 1, MAX_FENCE)
			or not whole(state.leaseRevision, 1, MAX_REVISION)
			or not whole(state.initialFence, 1, MAX_FENCE)
			or not whole(state.initialLeaseRevision, 1, MAX_REVISION)
			or type(state.rollbackNeedsNameRelease) ~= "boolean"
		then
			return nil
		end
		local phase: Phase = state.phase
		if phase ~= "rolling_back" and phase ~= "aborted" and state.rollbackNeedsNameRelease then
			return nil
		end
		local nameOk, displayName = policy.validateName(state.displayName)
		if not nameOk or displayName ~= state.displayName then
			return nil
		end
		local prepared: Prepared = {
			userId = state.userId,
			operationId = state.operationId,
			characterId = state.characterId,
			displayName = state.displayName,
			realmId = state.realmId,
			peopleId = state.peopleId,
			classId = state.classId,
			appearancePresetId = state.appearancePresetId,
			createdAtUnix = state.createdAtUnix,
			fence = state.initialFence,
			leaseRevision = state.initialLeaseRevision,
		}
		if fingerprint(prepared) ~= state.fingerprint or not validCharacter(prepared, state.displayName, stored) then
			return nil
		end
		return copy(state)
	end

	local function rejected(state: State?, reason: string): Rejected
		return { ok = false, state = if state == nil then nil else copy(state), reason = reason }
	end

	local function accepted(state: State, replayed: boolean): Accepted
		return { ok = true, state = copy(state), replayed = replayed, reason = nil }
	end

	local function next(state: State, phase: Phase): State?
		if state.revision >= MAX_REVISION then
			return nil
		end
		local value = copy(state)
		value.phase = phase
		value.revision += 1
		return value
	end

	local function matches(state: State, candidate: unknown): string?
		if type(candidate) ~= "table" then
			return "malformed_event"
		end
		local event = candidate
		if event.expectedRevision ~= state.revision then
			return "stale_revision"
		end
		if event.expectedFence ~= state.fence then
			return "stale_fence"
		end
		return nil
	end

	local function receiptMatches(state: State, candidate: unknown, field: string): string?
		if type(candidate) ~= "table" then
			return "malformed_readback"
		end
		local raw = assert(tableFields(candidate))
		if raw.revision ~= state.revision or raw.fence ~= state.fence then
			if whole(raw.revision, 0, MAX_REVISION) and raw.revision > state.revision then
				return "future_readback"
			end
			if whole(raw.fence, 1, MAX_FENCE) and raw.fence > state.fence then
				return "future_readback"
			end
			return "readback_mismatch"
		end
		if
			raw.operationId ~= state.operationId
			or raw.fingerprint ~= state.fingerprint
			or raw.characterId ~= state.characterId
		then
			return "foreign_collision"
		end
		if raw[field] ~= true then
			return "readback_mismatch"
		end
		return nil
	end

	local function prepare(existing: unknown, request: unknown): Result
		if type(request) ~= "table" then
			return rejected(nil, "malformed_request")
		end
		local candidate = request
		local nameOk, displayName = policy.validateName(candidate.displayName)
		local identity = fingerprint(candidate)
		if not nameOk or displayName == nil or identity == nil or not validCharacter(candidate, displayName) then
			return rejected(nil, "malformed_request")
		end
		local current = validate(existing)
		if existing ~= nil and current == nil then
			return rejected(nil, "malformed_state")
		end
		if current ~= nil then
			if current.operationId == candidate.operationId and current.fingerprint ~= identity then
				return rejected(current, "receipt_conflict")
			end
			if current.operationId ~= candidate.operationId then
				return rejected(current, "creation_in_progress")
			end
			return accepted(current, true)
		end
		return accepted({
			schemaVersion = SCHEMA_VERSION,
			userId = candidate.userId,
			operationId = candidate.operationId,
			fingerprint = identity,
			characterId = candidate.characterId,
			displayName = displayName,
			realmId = candidate.realmId,
			peopleId = candidate.peopleId,
			classId = candidate.classId,
			appearancePresetId = candidate.appearancePresetId,
			createdAtUnix = candidate.createdAtUnix,
			phase = "prepared",
			revision = 0,
			fence = candidate.fence,
			leaseRevision = candidate.leaseRevision,
			initialFence = candidate.fence,
			initialLeaseRevision = candidate.leaseRevision,
			rollbackNeedsNameRelease = false,
		}, false)
	end

	local function plan(raw: unknown): Plan?
		local state = validate(raw)
		if state == nil then
			return nil
		end
		local base: Plan = { expectedRevision = state.revision, expectedFence = state.fence, kind = "" }
		if state.phase == "prepared" then
			base.kind = "claim_name"
			base.claim = {
				displayName = state.displayName,
				userId = state.userId,
				characterId = state.characterId,
				claimedAtUnix = state.createdAtUnix,
				schemaVersion = nameregistry.SCHEMA_VERSION,
			}
			return base
		elseif state.phase == "name_owned" then
			base.kind = "prepare_profile"
		elseif state.phase == "profile_prepared" then
			base.kind = "commit_roster"
			base.character = character(state)
			return base
		elseif state.phase == "committed" then
			base.kind = "release_lease"
			return base
		elseif state.phase == "rolling_back" then
			base.kind = "rollback_precommit"
			base.claim = {
				displayName = state.displayName,
				userId = state.userId,
				characterId = state.characterId,
				claimedAtUnix = state.createdAtUnix,
				schemaVersion = nameregistry.SCHEMA_VERSION,
			}
			return base
		end
		return nil
	end

	local function observeName(raw: unknown, candidate: unknown): Result
		local event = candidate
		local state = validate(raw)
		if state == nil then
			return rejected(nil, "malformed_state")
		end
		if state.phase ~= "prepared" then
			return rejected(state, "phase_order")
		end
		local mismatch = matches(state, event)
		if mismatch ~= nil then
			return rejected(state, mismatch)
		end
		if event.readback == nil then
			return rejected(state, "readback_absent")
		end
		local success, _, status = pcall(function()
			return nameregistry.claim(event.readback, ((plan(state))).claim)
		end)
		if not success then
			if futureVersion(event.readback, nameregistry.SCHEMA_VERSION) then
				return rejected(state, "future_readback")
			end
			return rejected(state, "malformed_readback")
		end
		if status == "owned" then
			local value = next(state, "name_owned")
			if value ~= nil then
				value.rollbackNeedsNameRelease = false
			end
			return if value == nil then rejected(state, "revision_exhausted") else accepted(value, false)
		end
		return rejected(state, "foreign_collision")
	end

	local function observeProfile(raw: unknown, candidate: unknown): Result
		local event = candidate
		local state = validate(raw)
		if state == nil then
			return rejected(nil, "malformed_state")
		end
		if state.phase ~= "name_owned" then
			return rejected(state, "phase_order")
		end
		local mismatch = matches(state, event)
		if mismatch ~= nil then
			return rejected(state, mismatch)
		end
		if event.readback == nil then
			return rejected(state, "readback_absent")
		end
		local receipt = receiptMatches(state, event.readback, "prepared")
		if receipt ~= nil then
			return rejected(state, tostring(receipt))
		end
		local value = next(state, "profile_prepared")
		return if value == nil then rejected(state, "revision_exhausted") else accepted(value, false)
	end

	local function equal(left: unknown, right: unknown): boolean
		if left == right then
			return true
		end
		if type(left) ~= "table" or type(right) ~= "table" then
			return false
		end
		local leftFields = left
		local rightFields = right
		for key, value in leftFields do
			if not equal(value, rightFields[key]) then
				return false
			end
		end
		for key in rightFields do
			if leftFields[key] == nil then
				return false
			end
		end
		return true
	end

	local function observeRoster(raw: unknown, candidate: unknown): Result
		local event = candidate
		local state = validate(raw)
		if state == nil then
			return rejected(nil, "malformed_state")
		end
		if state.phase ~= "profile_prepared" then
			return rejected(state, "phase_order")
		end
		local mismatch = matches(state, event)
		if mismatch ~= nil then
			return rejected(state, mismatch)
		end
		if event.readback == nil then
			return rejected(state, "readback_absent")
		end
		local baseOk, base = pcall(rosterRules.validate, event.base)
		local readbackOk, readback = pcall(rosterRules.validate, event.readback)
		if not baseOk or not readbackOk then
			if futureVersion(event.readback, rosterRules.SCHEMA_VERSION) then
				return rejected(state, "future_readback")
			end
			return rejected(state, "malformed_readback")
		end
		if base.userId ~= state.userId or readback.userId ~= state.userId then
			return rejected(state, "foreign_collision")
		end
		local desiredOk, desired = pcall(rosterRules.add, base, character(state))
		if not desiredOk then
			return rejected(state, "roster_conflict")
		end
		if not equal(desired, readback) then
			return rejected(state, "readback_mismatch")
		end
		local value = next(state, "committed")
		return if value == nil then rejected(state, "revision_exhausted") else accepted(value, false)
	end

	local function requestRollback(raw: unknown, candidate: unknown): Result
		local event = candidate
		local state = validate(raw)
		if state == nil then
			return rejected(nil, "malformed_state")
		end
		if state.phase == "committed" or state.phase == "lease_released" then
			return rejected(state, "postcommit_compensation_forbidden")
		end
		if state.phase ~= "prepared" and state.phase ~= "name_owned" and state.phase ~= "profile_prepared" then
			return rejected(state, "phase_order")
		end
		local mismatch = matches(state, event)
		if mismatch ~= nil then
			return rejected(state, mismatch)
		end
		local receipt = receiptMatches(state, event.readback, "acknowledged")
		if receipt ~= nil then
			return rejected(state, tostring(receipt))
		end
		local value = next(state, "rolling_back")
		if value ~= nil then
			value.rollbackNeedsNameRelease = state.phase ~= "prepared"
		end
		return if value == nil then rejected(state, "revision_exhausted") else accepted(value, false)
	end

	local function observeRollback(raw: unknown, candidate: unknown): Result
		local event = candidate
		local state = validate(raw)
		if state == nil then
			return rejected(nil, "malformed_state")
		end
		if state.phase ~= "rolling_back" then
			return rejected(state, "phase_order")
		end
		local mismatch = matches(state, event)
		if mismatch ~= nil then
			return rejected(state, mismatch)
		end
		local profile = receiptMatches(state, event.profileReadback, "aborted")
		if profile ~= nil then
			return rejected(state, profile)
		end
		if state.rollbackNeedsNameRelease then
			if event.nameReadbackReceived ~= true then
				return rejected(state, "readback_absent")
			end
			if event.nameReadback == nil then
				local value = next(state, "aborted")
				return if value == nil then rejected(state, "revision_exhausted") else accepted(value, false)
			end
			local success, _, status = pcall(function()
				return nameregistry.release(event.nameReadback, state.userId, state.characterId)
			end)
			if not success then
				return rejected(state, "malformed_readback")
			end
			if status == "released" then
				return rejected(state, "name_still_owned")
			end
		end
		local value = next(state, "aborted")
		return if value == nil then rejected(state, "revision_exhausted") else accepted(value, false)
	end

	local function observeLeaseRelease(raw: unknown, candidate: unknown): Result
		local event = candidate
		local state = validate(raw)
		if state == nil then
			return rejected(nil, "malformed_state")
		end
		if state.phase ~= "committed" then
			return rejected(state, "phase_order")
		end
		local mismatch = matches(state, event)
		if mismatch ~= nil then
			return rejected(state, mismatch)
		end
		local released = tableFields(event.readback)
		if released == nil then
			return rejected(state, "readback_absent")
		end
		local receipt = receiptMatches(state, event.readback, "released")
		if receipt ~= nil and released.expired == true then
			receipt = receiptMatches(state, event.readback, "expired")
		end
		if receipt ~= nil then
			return rejected(state, tostring(receipt))
		end
		local value = next(state, "lease_released")
		return if value == nil then rejected(state, "revision_exhausted") else accepted(value, false)
	end

	local function takeover(raw: unknown, candidate: unknown): Result
		local event = candidate
		local state = validate(raw)
		if state == nil then
			return rejected(nil, "malformed_state")
		end
		if state.phase == "lease_released" then
			return rejected(state, "phase_order")
		end
		local mismatch = matches(state, event)
		if mismatch ~= nil then
			return rejected(state, mismatch)
		end
		if state.revision >= MAX_REVISION or not whole(event.fence, state.fence + 1, MAX_FENCE) then
			return rejected(state, "stale_fence")
		end
		local readback = tableFields(event.readback)
		if
			readback == nil
			or readback.operationId ~= state.operationId
			or readback.fingerprint ~= state.fingerprint
			or readback.characterId ~= state.characterId
			or readback.revision ~= state.revision + 1
			or readback.fence ~= event.fence
			or readback.leaseRevision ~= event.leaseRevision
			or readback.acquired ~= true
		then
			return rejected(state, "readback_mismatch")
		end
		if not whole(event.leaseRevision, state.leaseRevision + 1, MAX_REVISION) then
			return rejected(state, "stale_lease_revision")
		end
		local value = copy(state)
		value.revision += 1
		value.fence = event.fence
		value.leaseRevision = event.leaseRevision
		return accepted(value, false)
	end

	return {
		prepare = prepare,
		plan = plan,
		observeName = observeName,
		observeProfile = observeProfile,
		observeRoster = observeRoster,
		requestRollback = requestRollback,
		observeRollback = observeRollback,
		observeLeaseRelease = observeLeaseRelease,
		takeover = takeover,
		validate = function(candidate: unknown): State?
			return validate(candidate)
		end,
		validateStored = function(candidate: unknown): State?
			return validate(candidate, true)
		end,
		fingerprint = fingerprint,
		copy = copy,
		SCHEMA_VERSION = SCHEMA_VERSION,
		MAX_REVISION = MAX_REVISION,
		MAX_FENCE = MAX_FENCE,
		MAX_SAFE_INTEGER = MAX_SAFE_INTEGER,
	}
end

return table.freeze({ create = create })
