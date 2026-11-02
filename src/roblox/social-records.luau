--!strict

local Fellowship = require("../core/social/fellowship")
local Formation = require("../core/social/formation")
local Value = require("../core/value")
local Warband = require("../core/social/warband")

local SocialRecords = {}

export type Outcome = { ok: boolean, value: unknown, reason: string? }
export type Store = {
	getOutcome: (key: string) -> Outcome,
	updateOutcome: (key: string, transform: (unknown) -> unknown) -> Outcome,
}
export type FellowshipPort = {
	create: (unknown, unknown) -> Fellowship.Result,
	createFromFormation: (unknown, unknown) -> Fellowship.Result,
	projectState: (unknown) -> Fellowship.State?,
	transition: (unknown, unknown, unknown) -> Fellowship.Result,
}
export type FormationPort = {
	start: (unknown, unknown) -> Formation.Result,
	projectState: (unknown) -> Formation.State?,
	transition: (unknown, unknown, unknown) -> Formation.Result,
}
export type WarbandPort = {
	project: (unknown) -> Warband.State?,
	found: (string, string, Warband.Party, number, number) -> Warband.Result,
	transition: (Warband.State, Warband.Event, Warband.Parties, number) -> Warband.Result,
}
export type Dependencies = {
	store: Store,
	keyFor: (string) -> string,
	memberKeyFor: (number) -> string,
	formationKeyFor: ((string) -> string)?,
	warbandKeyFor: ((string, string) -> string)?,
	clock: () -> number,
	fellowship: FellowshipPort,
	formation: FormationPort,
	warband: WarbandPort,
}
export type Refusal = { ok: false, state: nil, replayed: boolean, reason: string }
export type RecordResult<T> = { ok: true, state: T, replayed: boolean, reason: nil } | Refusal
export type Result = RecordResult<Fellowship.State>
export type FormationResult = RecordResult<Formation.State>
export type Status = { ok: boolean, reason: string? }
export type ProposerResult = Status & { formationId: string? }
export type Membership = { read fellowshipId: string, read pending: boolean, read revision: number }
export type MembershipResult = { ok: boolean, membership: Membership?, reason: string? }
export type WarbandMembership = { warbandId: string, revision: number, pending: boolean }
export type WarbandMembershipResult = { ok: boolean, membership: WarbandMembership?, reason: string? }
export type Service = {
	read readWarband: (string) -> Warband.Result,
	read foundWarband: (string, string, Warband.Party, number) -> Warband.Result,
	read applyWarband: (string, Warband.Event, Warband.Parties) -> Warband.Result,
	read readWarbandMembership: (string) -> WarbandMembershipResult,
	read claimWarbandMembership: (string, string) -> WarbandMembershipResult,
	read confirmWarbandMembership: (string, WarbandMembership) -> WarbandMembershipResult,
	read releaseWarbandMembership: (string, WarbandMembership) -> WarbandMembershipResult,
	read read: (string) -> Result,
	read found: (Fellowship.FoundRequest) -> Result,
	read apply: (string, unknown) -> Result,
	read readFormation: (string) -> FormationResult,
	read startFormation: (Formation.StartRequest) -> FormationResult,
	read applyFormation: (string, unknown) -> FormationResult,
	read foundFromFormation: (Formation.State) -> Result,
	read readProposerFormation: (number) -> ProposerResult,
	read setProposerFormation: (number, string) -> Status,
	read clearProposerFormation: (number, string) -> Status,
	read readMembership: (number) -> MembershipResult,
	read claimMembership: (number, string) -> MembershipResult,
	read confirmMembership: (number, string) -> MembershipResult,
	read releaseMembership: (number, Membership) -> MembershipResult,
}

type MembershipValue = { schemaVersion: number, fellowshipId: string | false, pending: boolean, revision: number }
type MembershipDecision = (Membership?, number) -> (string?, MembershipValue?)
type CoreResult<S> = { ok: boolean, state: S?, replayed: boolean, reason: string? }
type Kind<S> = {
	absent: string,
	exists: string,
	project: (unknown) -> S?,
	identity: (S) -> string,
	clockOf: (S) -> number,
	transition: (S, unknown, number) -> CoreResult<S>,
}

local MEMBERSHIP_SCHEMA_VERSION = 1
local MAX_ID = 128
local DEPENDENCY_FIELDS = {
	store = true,
	keyFor = true,
	memberKeyFor = true,
	formationKeyFor = true,
	warbandKeyFor = true,
	clock = true,
	fellowship = true,
	formation = true,
	warband = true,
}

local function projectMembership(value: unknown): (boolean, Membership?, number)
	if value == nil then
		return true, nil, 0
	end
	local raw = Value.raw(value)
	if
		raw == nil
		or raw.schemaVersion ~= MEMBERSHIP_SCHEMA_VERSION
		or type(raw.pending) ~= "boolean"
		or type(raw.revision) ~= "number"
		or raw.revision ~= math.floor(raw.revision)
		or raw.revision < 1
	then
		return false, nil, 0
	end
	if raw.fellowshipId == false then
		return true, nil, raw.revision
	end
	if type(raw.fellowshipId) ~= "string" or #raw.fellowshipId == 0 or #raw.fellowshipId > MAX_ID then
		return false, nil, 0
	end
	return true,
		table.freeze({ fellowshipId = raw.fellowshipId, pending = raw.pending, revision = raw.revision }),
		raw.revision
end

local function membershipValue(fellowshipId: string | false, pending: boolean, revision: number): MembershipValue
	return {
		schemaVersion = MEMBERSHIP_SCHEMA_VERSION,
		fellowshipId = fellowshipId,
		pending = pending,
		revision = revision,
	}
end

local function refused(reason: string?): Refusal
	return { ok = false, state = nil, replayed = false, reason = reason or "not_durable" }
end

local function accepted<S>(state: S, replayed: boolean): RecordResult<S>
	return { ok = true, state = state, replayed = replayed, reason = nil }
end

local function warbandMembership(value: unknown, partyId: string): (boolean, WarbandMembership?, number)
	if value == nil then
		return true, nil, 0
	end
	local raw = Value.raw(value)
	if raw == nil then
		return false, nil, 0
	end
	if
		raw.partyId ~= partyId
		or type(raw.revision) ~= "number"
		or raw.revision < 1
		or raw.revision % 1 ~= 0
		or type(raw.pending) ~= "boolean"
	then
		return false, nil, 0
	end
	if raw.warbandId == false then
		return true, nil, raw.revision
	end
	if type(raw.warbandId) ~= "string" or #raw.warbandId == 0 or #raw.warbandId > MAX_ID then
		return false, nil, 0
	end
	return true, { warbandId = raw.warbandId, revision = raw.revision, pending = raw.pending }, raw.revision
end

local function validDependencies(raw: unknown): boolean
	local value = Value.record(raw, DEPENDENCY_FIELDS, false)
	if value == nil then
		return false
	end
	local store = Value.raw(value.store)
	return store ~= nil
		and type(store.getOutcome) == "function"
		and type(store.updateOutcome) == "function"
		and type(value.keyFor) == "function"
		and type(value.memberKeyFor) == "function"
		and type(value.clock) == "function"
		and Value.raw(value.fellowship) ~= nil
		and Value.raw(value.formation) ~= nil
		and Value.raw(value.warband) ~= nil
end

function SocialRecords.create(dependencies: Dependencies): (Service?, string?)
	if not validDependencies(dependencies) then
		return nil, "dependencies_invalid"
	end
	local deps = dependencies
	local clock = deps.clock
	local store = deps.store
	local function formationKey(formationId: string): string
		return if deps.formationKeyFor ~= nil
			then deps.formationKeyFor(formationId)
			else deps.keyFor("formation:" .. formationId)
	end

	local fellowshipKind: Kind<Fellowship.State> = {
		absent = "fellowship_unknown",
		exists = "fellowship_exists",
		project = deps.fellowship.projectState,
		identity = function(state: Fellowship.State): string
			return state.fellowshipId
		end,
		clockOf = function(state: Fellowship.State): number
			return state.lastClockSec
		end,
		transition = deps.fellowship.transition,
	}
	local formationKind: Kind<Formation.State> = {
		absent = "formation_unknown",
		exists = "formation_exists",
		project = deps.formation.projectState,
		identity = function(state: Formation.State): string
			return state.formationId
		end,
		clockOf = function(state: Formation.State): number
			return state.lastClockSec
		end,
		transition = deps.formation.transition,
	}

	local function recordState<S>(kind: Kind<S>, value: unknown, id: string): S?
		local state = kind.project(value)
		return if state ~= nil and kind.identity(state) == id then state else nil
	end

	local function readRecord<S>(kind: Kind<S>, key: string, id: string): RecordResult<S>
		local outcome = store.getOutcome(key)
		if not outcome.ok then
			return refused(outcome.reason)
		end
		if outcome.value == nil then
			return refused(kind.absent)
		end
		local state = recordState(kind, outcome.value, id)
		if state == nil then
			return refused("record_invalid")
		end
		return accepted(state, false)
	end

	local function createRecord<S>(
		kind: Kind<S>,
		key: string,
		id: string,
		build: (number) -> CoreResult<S>
	): RecordResult<S>
		local refusal: string? = nil
		local created: S? = nil
		local outcome = store.updateOutcome(key, function(current: unknown): unknown
			refusal = nil
			created = nil
			if current ~= nil then
				refusal = kind.exists
				return nil
			end
			local result = build(clock())
			if not result.ok then
				refusal = result.reason
				return nil
			end
			created = result.state
			return result.state
		end)
		if not outcome.ok or created == nil then
			return refused(refusal or outcome.reason)
		end
		local record = recordState(kind, outcome.value, id)
		if record == nil then
			return refused("readback_mismatch")
		end
		return accepted(record, false)
	end

	local function applyRecord<S>(kind: Kind<S>, key: string, id: string, event: unknown): RecordResult<S>
		local refusal: string? = nil
		local replayedState: S? = nil
		local outcome = store.updateOutcome(key, function(current: unknown): unknown
			refusal = nil
			replayedState = nil
			local state = recordState(kind, current, id)
			if state == nil then
				refusal = if current == nil then kind.absent else "record_invalid"
				return nil
			end
			local result = kind.transition(state, event, math.max(clock(), kind.clockOf(state)))
			if not result.ok then
				refusal = result.reason
				return nil
			end
			if result.replayed then
				replayedState = result.state
				return nil
			end
			return result.state
		end)
		if replayedState ~= nil then
			return accepted(replayedState, true)
		end
		if not outcome.ok then
			return refused(refusal or outcome.reason)
		end
		local state = recordState(kind, outcome.value, id)
		if state == nil then
			return refused("record_invalid")
		end
		return accepted(state, false)
	end

	local function read(fellowshipId: string): Result
		return readRecord(fellowshipKind, deps.keyFor(fellowshipId), fellowshipId)
	end

	local function found(request: Fellowship.FoundRequest): Result
		return createRecord(
			fellowshipKind,
			deps.keyFor(request.fellowshipId),
			request.fellowshipId,
			function(now: number): Fellowship.Result
				return deps.fellowship.create(request, now)
			end
		)
	end

	local function apply(fellowshipId: string, event: unknown): Result
		return applyRecord(fellowshipKind, deps.keyFor(fellowshipId), fellowshipId, event)
	end

	local function readFormation(formationId: string): FormationResult
		return readRecord(formationKind, formationKey(formationId), formationId)
	end

	local function startFormation(request: Formation.StartRequest): FormationResult
		return createRecord(
			formationKind,
			formationKey(request.formationId),
			request.formationId,
			function(now: number): Formation.Result
				return deps.formation.start(request, now)
			end
		)
	end

	local function applyFormation(formationId: string, event: unknown): FormationResult
		return applyRecord(formationKind, formationKey(formationId), formationId, event)
	end

	local function foundFromFormation(state: Formation.State): Result
		return createRecord(
			fellowshipKind,
			deps.keyFor(state.fellowshipId),
			state.fellowshipId,
			function(now: number): Fellowship.Result
				return deps.fellowship.createFromFormation({
					fellowshipId = state.fellowshipId,
					nameId = state.nameId,
					realmId = state.realmId,
					homeSlotId = state.homeSlotId,
					founders = state.founders,
				}, now)
			end
		)
	end

	local function readProposerFormation(userId: number): ProposerResult
		local outcome = store.getOutcome(formationKey("by:" .. tostring(userId)))
		if not outcome.ok then
			return { ok = false, formationId = nil, reason = outcome.reason or "not_durable" }
		end
		local value = outcome.value
		if value == nil or value == false then
			return { ok = true, formationId = nil, reason = nil }
		end
		local pointer = Value.raw(value)
		local formationId = if pointer ~= nil then pointer.formationId else nil
		if type(formationId) ~= "string" or #formationId == 0 then
			return { ok = false, formationId = nil, reason = "pointer_invalid" }
		end
		return { ok = true, formationId = formationId, reason = nil }
	end

	local function setProposerFormation(userId: number, formationId: string): Status
		local refusal: string? = nil
		local outcome = store.updateOutcome(formationKey("by:" .. tostring(userId)), function(current: unknown): unknown
			refusal = nil
			if current ~= nil and current ~= false then
				local pointer = Value.raw(current)
				refusal = if pointer ~= nil and pointer.formationId == formationId
					then "pointer_exists_same"
					else "pointer_exists"
				return nil
			end
			return { formationId = formationId }
		end)
		if refusal == "pointer_exists_same" then
			return { ok = true, reason = nil }
		end
		return { ok = outcome.ok, reason = refusal or outcome.reason }
	end

	local function clearProposerFormation(userId: number, formationId: string): Status
		local outcome = store.updateOutcome(formationKey("by:" .. tostring(userId)), function(current: unknown): unknown
			local pointer = Value.raw(current)
			if pointer ~= nil and pointer.formationId == formationId then
				return false
			end
			return nil
		end)
		return { ok = outcome.ok, reason = outcome.reason }
	end

	local function readMembership(userId: number): MembershipResult
		local outcome = store.getOutcome(deps.memberKeyFor(userId))
		if not outcome.ok then
			return { ok = false, membership = nil, reason = outcome.reason or "not_durable" }
		end
		local valid, membership = projectMembership(outcome.value)
		if not valid then
			return { ok = false, membership = nil, reason = "membership_invalid" }
		end
		return { ok = true, membership = membership, reason = nil }
	end

	local function writeMembership(userId: number, decide: MembershipDecision): MembershipResult
		local refusal: string? = nil
		local kept: Membership? = nil
		local keep = false
		local outcome = store.updateOutcome(deps.memberKeyFor(userId), function(current: unknown): unknown
			refusal = nil
			keep = false
			kept = nil
			local valid, membership, revision = projectMembership(current)
			if not valid then
				refusal = "membership_invalid"
				return nil
			end
			local reason, nextValue = decide(membership, revision)
			if reason ~= nil then
				refusal = reason
				return nil
			end
			if nextValue == nil then
				keep = true
				kept = membership
				return nil
			end
			return nextValue
		end)
		if keep then
			return { ok = true, membership = kept, reason = nil }
		end
		if not outcome.ok then
			return { ok = false, membership = nil, reason = refusal or outcome.reason or "not_durable" }
		end
		local _, membership = projectMembership(outcome.value)
		return { ok = true, membership = membership, reason = nil }
	end

	local function claimMembership(userId: number, fellowshipId: string): MembershipResult
		return writeMembership(userId, function(current: Membership?, revision: number): (string?, MembershipValue?)
			if current == nil then
				return nil, membershipValue(fellowshipId, true, revision + 1)
			end
			if current.fellowshipId == fellowshipId then
				return nil, nil
			end
			return "membership_held", nil
		end)
	end

	local function confirmMembership(userId: number, fellowshipId: string): MembershipResult
		return writeMembership(userId, function(current: Membership?, revision: number): (string?, MembershipValue?)
			if current == nil or current.fellowshipId ~= fellowshipId then
				return "membership_moved", nil
			end
			if not current.pending then
				return nil, nil
			end
			return nil, membershipValue(fellowshipId, false, revision + 1)
		end)
	end

	local function releaseMembership(userId: number, seen: Membership): MembershipResult
		return writeMembership(userId, function(current: Membership?, revision: number): (string?, MembershipValue?)
			if current == nil or current.fellowshipId ~= seen.fellowshipId or current.revision ~= seen.revision then
				return nil, nil
			end
			return nil, membershipValue(false, false, revision + 1)
		end)
	end

	local function warbandKey(kind: string, id: string): string
		return if deps.warbandKeyFor ~= nil
			then deps.warbandKeyFor(kind, id)
			else deps.keyFor("warband:" .. kind .. ":" .. id)
	end

	local function warbandRead(key: string): Outcome
		local observed = false
		local value: unknown = nil
		local outcome = store.updateOutcome(key, function(current: unknown): unknown
			observed = true
			value = current
			return nil
		end)
		if not observed or (not outcome.ok and outcome.reason ~= "callback_cancelled") then
			return outcome
		end
		return { ok = true, value = value }
	end

	local function readWarband(id: string): Warband.Result
		local outcome = warbandRead(warbandKey("record", id))
		if not outcome.ok then
			return { ok = false, reason = outcome.reason or "not_durable" }
		end
		local state = deps.warband.project(outcome.value)
		if state == nil or state.warbandId ~= id then
			return { ok = false, reason = if outcome.value == nil then "warband_unknown" else "warband_invalid" }
		end
		return { ok = true, state = state }
	end

	local function foundWarband(id: string, partyId: string, party: Warband.Party, revision: number): Warband.Result
		local result: Warband.Result = { ok = false, reason = "not_durable" }
		local outcome = store.updateOutcome(warbandKey("record", id), function(current: unknown): unknown
			if current ~= nil then
				result = { ok = false, reason = "warband_exists" }
				return nil
			end
			result = deps.warband.found(id, partyId, party, revision, clock())
			return if result.ok then result.state else nil
		end)
		if not outcome.ok then
			return { ok = false, reason = if result.ok then outcome.reason or "not_durable" else result.reason }
		end
		return readWarband(id)
	end

	local function applyWarband(id: string, event: Warband.Event, parties: Warband.Parties): Warband.Result
		local result: Warband.Result = { ok = false, reason = "not_durable" }
		local unchanged = false
		local outcome = store.updateOutcome(warbandKey("record", id), function(current: unknown): unknown
			local state = deps.warband.project(current)
			if state == nil or state.warbandId ~= id then
				result = { ok = false, reason = "warband_invalid" }
				return nil
			end
			result = deps.warband.transition(state, event, parties, math.max(clock(), state.lastClockSec))
			unchanged = result.ok and result.state == state
			if unchanged then
				return nil
			end
			return if result.ok then result.state else nil
		end)
		if unchanged and outcome.reason == "callback_cancelled" then
			return result
		end
		if not outcome.ok then
			return { ok = false, reason = if result.ok then outcome.reason or "not_durable" else result.reason }
		end
		return readWarband(id)
	end

	local function readWarbandMembership(partyId: string): WarbandMembershipResult
		local outcome = warbandRead(warbandKey("member", partyId))
		if not outcome.ok then
			return { ok = false, reason = outcome.reason or "not_durable" }
		end
		local valid, membership = warbandMembership(outcome.value, partyId)
		return if valid
			then { ok = true, membership = membership }
			else { ok = false, reason = "warband_membership_invalid" }
	end

	local function writeWarbandMembership(
		partyId: string,
		kind: string,
		seen: WarbandMembership
	): WarbandMembershipResult
		local refusal: string? = nil
		local kept: WarbandMembership? = nil
		local keep = false
		local outcome = store.updateOutcome(warbandKey("member", partyId), function(value: unknown): unknown
			refusal = nil
			keep = false
			kept = nil
			local valid, current, revision = warbandMembership(value, partyId)
			if not valid then
				refusal = "warband_membership_invalid"
				return nil
			end
			if kind == "claim" then
				if current ~= nil then
					if current.warbandId ~= seen.warbandId then
						refusal = "warband_membership_held"
						return nil
					end
					keep = true
					kept = current
					return nil
				end
				return { partyId = partyId, warbandId = seen.warbandId, revision = revision + 1, pending = true }
			end
			if current == nil or current.warbandId ~= seen.warbandId or current.revision ~= seen.revision then
				refusal = "warband_membership_moved"
				return nil
			end
			return {
				partyId = partyId,
				warbandId = if kind == "release" then false else current.warbandId,
				revision = if kind == "release" then revision + 1 else revision,
				pending = false,
			}
		end)
		if keep then
			return { ok = true, membership = kept }
		end
		if not outcome.ok then
			return { ok = false, reason = refusal or outcome.reason or "not_durable" }
		end
		return readWarbandMembership(partyId)
	end

	local service: Service = {
		readWarband = readWarband,
		foundWarband = foundWarband,
		applyWarband = applyWarband,
		readWarbandMembership = readWarbandMembership,
		claimWarbandMembership = function(partyId: string, id: string): WarbandMembershipResult
			return writeWarbandMembership(partyId, "claim", { warbandId = id, revision = 0, pending = true })
		end,
		confirmWarbandMembership = function(partyId: string, seen: WarbandMembership): WarbandMembershipResult
			return writeWarbandMembership(partyId, "confirm", seen)
		end,
		releaseWarbandMembership = function(partyId: string, seen: WarbandMembership): WarbandMembershipResult
			return writeWarbandMembership(partyId, "release", seen)
		end,
		read = read,
		found = found,
		apply = apply,
		readFormation = readFormation,
		startFormation = startFormation,
		applyFormation = applyFormation,
		foundFromFormation = foundFromFormation,
		readProposerFormation = readProposerFormation,
		setProposerFormation = setProposerFormation,
		clearProposerFormation = clearProposerFormation,
		readMembership = readMembership,
		claimMembership = claimMembership,
		confirmMembership = confirmMembership,
		releaseMembership = releaseMembership,
	}
	return table.freeze(service), nil
end

return table.freeze(SocialRecords)
