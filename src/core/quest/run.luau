--!strict
local Value = require("../../kernel/value")
type Raw = Value.Raw

export type Package = {
	id: string,
	entryId: string,
	returnId: string,
	recoveryWindowSec: number,
	group: { minPlayers: number, maxPlayers: number },
	phases: { { id: string, kind: string, contentId: string } },
}
export type RunStatus = "active" | "completed"
export type Member = {
	id: string,
	connected: boolean,
	disconnectedAtSec: number?,
	departed: boolean,
}

export type RunState = {
	schemaVersion: number,
	expeditionId: string,
	runId: string,
	revision: number,
	startedAtSec: number,
	lastClockSec: number,
	status: RunStatus,
	phaseIndex: number,
	checkpointId: string?,
	attempt: number,
	leaderId: string,
	members: { Member },
	receipts: { [string]: string },
}

export type StartEvent = {
	kind: "start",
	eventId: string,
	runId: string,
	leaderId: string,
	memberIds: { string },
}

export type CompletePhaseEvent = {
	kind: "complete_phase",
	eventId: string,
	expectedRevision: number,
	phaseId: string,
}

export type MemberEvent = {
	kind: "disconnect" | "reconnect" | "leader_departure" | "depart" | "replace",
	replacementId: string?,
	eventId: string,
	expectedRevision: number,
	memberId: string,
}

export type WipeEvent = {
	kind: "wipe",
	eventId: string,
	expectedRevision: number,
	memberIds: { string },
}

export type Event = StartEvent | CompletePhaseEvent | MemberEvent | WipeEvent

export type Recovery = {
	kind: "wipe" | "reconnect" | "leader_departure",
	returnAnchorId: string,
	memberIds: { string },
}

export type TransitionApplied = {
	ok: true,
	state: RunState,
	replayed: boolean,
	recovery: Recovery?,
}

export type TransitionRejected = {
	ok: false,
	state: RunState?,
	reason: string,
}

export type TransitionResult = TransitionApplied | TransitionRejected

export type Core = {
	transition: (unknown, unknown, unknown, unknown) -> TransitionResult,
	projectRunState: (unknown, unknown) -> RunState?,
	Reason: { [string]: string },
}

export type Config<P> = {
	readPackage: (unknown) -> P?,
	describe: (P) -> Package,
	validCheckpoint: (P, RunState) -> boolean,
	wipePhase: (P, RunState) -> number,
	replacementAllowed: (P, RunState) -> boolean,
	maxMembers: number,
}
local SCHEMA_VERSION = 1
local System = {}
function System.run<P>(config: Config<P>): Core
	local RUN_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		expeditionId = true,
		runId = true,
		revision = true,
		startedAtSec = true,
		lastClockSec = true,
		status = true,
		phaseIndex = true,
		checkpointId = true,
		attempt = true,
		leaderId = true,
		members = true,
		receipts = true,
	}

	local MEMBER_FIELDS: { [string]: boolean } = {
		id = true,
		connected = true,
		disconnectedAtSec = true,
		departed = true,
	}

	local START_FIELDS: { [string]: boolean } = {
		kind = true,
		eventId = true,
		runId = true,
		leaderId = true,
		memberIds = true,
	}

	local COMPLETE_FIELDS: { [string]: boolean } = {
		kind = true,
		eventId = true,
		expectedRevision = true,
		phaseId = true,
	}

	local MEMBER_EVENT_FIELDS: { [string]: boolean } = {
		kind = true,
		eventId = true,
		expectedRevision = true,
		memberId = true,
	}

	local WIPE_FIELDS: { [string]: boolean } = {
		kind = true,
		eventId = true,
		expectedRevision = true,
		memberIds = true,
	}

	local Reason: { [string]: string } = {
		invalidPackage = "invalid_package",
		invalidState = "invalid_state",
		invalidEvent = "invalid_event",
		invalidClock = "invalid_clock",
		missingState = "missing_state",
		runAlreadyStarted = "run_already_started",
		receiptConflict = "receipt_conflict",
		revisionConflict = "revision_conflict",
		runNotActive = "run_not_active",
		phaseConflict = "phase_conflict",
		unknownMember = "unknown_member",
		alreadyDisconnected = "already_disconnected",
		alreadyConnected = "already_connected",
		memberDeparted = "member_departed",
		recoveryWindowExpired = "recovery_window_expired",
		leaderDepartureRequired = "leader_departure_required",
		leaderMismatch = "leader_mismatch",
		noConnectedSuccessor = "no_connected_successor",
		wipeRosterMismatch = "wipe_roster_mismatch",
		invalidHistory = "invalid_history",
		invalidPersonalState = "invalid_personal_state",
		invalidRewardRequest = "invalid_reward_request",
		runNotCompleted = "run_not_completed",
		characterNotInRun = "character_not_in_run",
		unknownRole = "unknown_role",
		runAlreadyRewarded = "run_already_rewarded",
		receiptStateMismatch = "receipt_state_mismatch",
		personalTransactionRejected = "personal_transaction_rejected",
	}
	table.freeze(Reason)

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function whole(value: unknown): boolean
		return (type(value) == "number" and finite(value)) and value >= 0 and value == math.floor(value)
	end

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" then
			return false
		end
		for key in value do
			if type(key) ~= "string" or not fields[key] then
				return false
			end
		end
		return true
	end

	local function sortedUniqueStrings(value: unknown, minimum: number?): { string }?
		local rows = Value.dense(value, math.huge, false)
		if rows == nil or #rows < (minimum or 0) then
			return nil
		end
		local result: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, id in rows do
			if type(id) ~= "string" or id == "" or seen[id] then
				return nil
			end
			seen[id] = true
			table.insert(result, id)
		end
		table.sort(result)
		return result
	end

	local function sameStrings(left: { string }, right: { string }): boolean
		if #left ~= #right then
			return false
		end
		for index, value in left do
			if right[index] ~= value then
				return false
			end
		end
		return true
	end

	local function segment(value: string): string
		return ("%d:%s"):format(#value, value)
	end

	local function numberSegment(value: number): string
		return segment(("%d"):format(value))
	end

	local function stringListSegment(values: { string }): string
		local parts = { numberSegment(#values) }
		for _, value in values do
			parts[#parts + 1] = segment(value)
		end
		return table.concat(parts)
	end

	local function memberIndex(members: { Member }, memberId: string): number?
		for index, member in members do
			if member.id == memberId then
				return index
			end
		end
		return nil
	end

	local function copyRunState(value: unknown, package: P): RunState?
		local source = Value.record(value, RUN_FIELDS, false, false)
		if source == nil then
			return nil
		end
		local runId = source.runId
		local revision = source.revision
		local started = source.startedAtSec
		local clock = source.lastClockSec
		local status = source.status
		local phase = source.phaseIndex
		local checkpoint = source.checkpointId
		local attempt = source.attempt
		local leader = source.leaderId
		local description = config.describe(package)
		if
			source.schemaVersion ~= SCHEMA_VERSION
			or source.expeditionId ~= description.id
			or type(runId) ~= "string"
			or runId == ""
			or type(revision) ~= "number"
			or not (type(revision) == "number" and whole(revision))
			or revision < 1
			or type(started) ~= "number"
			or not (type(started) == "number" and finite(started))
			or started < 0
			or type(clock) ~= "number"
			or not (type(clock) == "number" and finite(clock))
			or clock < started
			or (status ~= "active" and status ~= "completed")
			or type(phase) ~= "number"
			or not (type(phase) == "number" and whole(phase))
			or phase < 1
			or phase > #description.phases
			or (checkpoint ~= nil and type(checkpoint) ~= "string")
			or type(attempt) ~= "number"
			or not (type(attempt) == "number" and whole(attempt))
			or attempt < 1
			or type(leader) ~= "string"
			or leader == ""
		then
			return nil
		end
		local rows = Value.dense(source.members, description.group.maxPlayers, false)
		if rows == nil or #rows < description.group.minPlayers then
			return nil
		end
		local members: { Member } = {}
		local priorId: string? = nil
		local leaderConnected = false
		for _, raw in rows do
			local row = Value.record(raw, MEMBER_FIELDS, false, false)
			if row == nil then
				return nil
			end
			local id, connected, departed, disconnected = row.id, row.connected, row.departed, row.disconnectedAtSec
			if
				type(id) ~= "string"
				or id == ""
				or type(connected) ~= "boolean"
				or type(departed) ~= "boolean"
				or (disconnected ~= nil and type(disconnected) ~= "number")
				or (connected and (disconnected ~= nil or departed))
				or (not connected and (disconnected == nil or not (type(disconnected) == "number" and finite(
					disconnected
				)) or disconnected < started or disconnected > clock))
				or (priorId ~= nil and id <= priorId)
			then
				return nil
			end
			priorId = id
			if id == leader then
				leaderConnected = connected
			end
			table.insert(
				members,
				{ id = id, connected = connected, departed = departed, disconnectedAtSec = disconnected }
			)
		end
		local rawReceipts = Value.raw(source.receipts)
		if rawReceipts == nil then
			return nil
		end
		local receipts: { [string]: string } = {}
		local count = 0
		for id, fingerprint in rawReceipts do
			if type(id) ~= "string" or id == "" or type(fingerprint) ~= "string" or fingerprint == "" then
				return nil
			end
			receipts[id] = fingerprint
			count += 1
		end
		if count ~= revision or not leaderConnected then
			return nil
		end
		local state: RunState = {
			schemaVersion = SCHEMA_VERSION,
			expeditionId = description.id,
			runId = runId,
			revision = revision,
			startedAtSec = started,
			lastClockSec = clock,
			status = status,
			phaseIndex = phase,
			checkpointId = checkpoint,
			attempt = attempt,
			leaderId = leader,
			members = members,
			receipts = receipts,
		}
		return if config.validCheckpoint(package, state) then state else nil
	end

	local function readEvent(value: unknown): Event?
		local event = Value.raw(value)
		if event == nil then
			return nil
		end
		local eventId = event.eventId
		if type(eventId) ~= "string" or eventId == "" then
			return nil
		end
		local kind = event.kind
		if kind == "start" then
			local members = sortedUniqueStrings(event.memberIds, 1)
			local runId, leader = event.runId, event.leaderId
			if
				not hasOnlyFields(value, START_FIELDS)
				or type(runId) ~= "string"
				or runId == ""
				or type(leader) ~= "string"
				or leader == ""
				or members == nil
				or #members > config.maxMembers
				or table.find(members, leader) == nil
			then
				return nil
			end
			local result: StartEvent =
				{ kind = "start", eventId = eventId, runId = runId, leaderId = leader, memberIds = members }
			return result
		end
		local revision = event.expectedRevision
		if type(revision) ~= "number" or not (type(revision) == "number" and whole(revision)) then
			return nil
		end
		if kind == "complete_phase" then
			local phase = event.phaseId
			if not hasOnlyFields(value, COMPLETE_FIELDS) or type(phase) ~= "string" or phase == "" then
				return nil
			end
			local result: CompletePhaseEvent =
				{ kind = "complete_phase", eventId = eventId, expectedRevision = revision, phaseId = phase }
			return result
		elseif kind == "wipe" then
			local members = sortedUniqueStrings(event.memberIds, 1)
			if not hasOnlyFields(value, WIPE_FIELDS) or members == nil then
				return nil
			end
			local result: WipeEvent =
				{ kind = "wipe", eventId = eventId, expectedRevision = revision, memberIds = members }
			return result
		elseif
			kind == "disconnect"
			or kind == "reconnect"
			or kind == "leader_departure"
			or kind == "depart"
			or kind == "replace"
		then
			local member = event.memberId
			local replacement = event.replacementId
			local fields = if kind == "replace"
				then { kind = true, eventId = true, expectedRevision = true, memberId = true, replacementId = true }
				else MEMBER_EVENT_FIELDS
			if
				not hasOnlyFields(value, fields)
				or type(member) ~= "string"
				or member == ""
				or (replacement ~= nil and type(replacement) ~= "string")
				or (kind == "replace" and (replacement == nil or replacement == ""))
			then
				return nil
			end
			local result: MemberEvent = {
				kind = kind,
				eventId = eventId,
				expectedRevision = revision,
				memberId = member,
				replacementId = replacement,
			}
			return result
		end
		return nil
	end

	local function eventFingerprint(event: Event): string
		if event.kind == "replace" then
			return segment(event.kind) .. segment(event.memberId) .. segment(assert(event.replacementId))
		elseif event.kind == "start" then
			local members = assert(sortedUniqueStrings(event.memberIds, 1))
			return segment(event.kind) .. segment(event.runId) .. segment(event.leaderId) .. stringListSegment(members)
		elseif event.kind == "complete_phase" then
			return segment(event.kind) .. segment(event.phaseId)
		elseif event.kind == "wipe" then
			local members = assert(sortedUniqueStrings(event.memberIds, 1))
			return segment(event.kind) .. stringListSegment(members)
		end
		return segment(event.kind) .. segment(event.memberId)
	end

	local function rejectedTransition(state: RunState?, reason: string): TransitionRejected
		return (Value.freezeDeep({ ok = false, state = state, reason = reason }))
	end

	local function appliedTransition(state: RunState, replayed: boolean, recovery: Recovery?): TransitionApplied
		return (Value.freezeDeep({
			ok = true,
			state = state,
			replayed = replayed,
			recovery = recovery,
		}))
	end

	local function connectedMemberIds(state: RunState): { string }
		local result: { string } = {}
		for _, member in state.members do
			if member.connected then
				result[#result + 1] = member.id
			end
		end
		return result
	end

	local function recoveryAnchor(package: P, state: RunState): string
		if state.status == "completed" then
			return config.describe(package).returnId
		end
		return state.checkpointId or config.describe(package).entryId
	end

	local function commitEvent(state: RunState, event: Event, fingerprint: string, nowSec: number)
		state.lastClockSec = nowSec
		state.revision += 1
		state.receipts[event.eventId] = fingerprint
	end

	local function startRun(package: P, event: StartEvent, nowSec: number): TransitionResult
		local memberIds = assert(sortedUniqueStrings(event.memberIds, 1))
		if #memberIds < config.describe(package).group.minPlayers then
			return rejectedTransition(nil, "group_too_small")
		end
		local members: { Member } = {}
		for _, memberId in memberIds do
			members[#members + 1] = { id = memberId, connected = true, disconnectedAtSec = nil, departed = false }
		end
		local fingerprint = eventFingerprint(event)
		local state: RunState = {
			schemaVersion = SCHEMA_VERSION,
			expeditionId = config.describe(package).id,
			runId = event.runId,
			revision = 1,
			startedAtSec = nowSec,
			lastClockSec = nowSec,
			status = "active",
			phaseIndex = 1,
			checkpointId = nil,
			attempt = 1,
			leaderId = event.leaderId,
			members = members,
			receipts = { [event.eventId] = fingerprint },
		}
		return appliedTransition(state, false, nil)
	end

	local function applyCompletePhase(package: P, state: RunState, event: CompletePhaseEvent): string?
		if state.status ~= "active" then
			return Reason.runNotActive
		end
		local phase = config.describe(package).phases[state.phaseIndex]
		if phase.id ~= event.phaseId then
			return Reason.phaseConflict
		end
		if phase.kind == "boss" then
			state.status = "completed"
		elseif phase.kind == "checkpoint" then
			state.checkpointId = phase.contentId
			state.phaseIndex += 1
		else
			state.phaseIndex += 1
		end
		return nil
	end

	local function applyDisconnect(state: RunState, event: MemberEvent, nowSec: number): string?
		if state.status ~= "active" then
			return Reason.runNotActive
		end
		local index = memberIndex(state.members, event.memberId)
		if index == nil then
			return Reason.unknownMember
		end
		if event.memberId == state.leaderId then
			return Reason.leaderDepartureRequired
		end
		if not state.members[index].connected then
			return Reason.alreadyDisconnected
		end
		state.members[index].connected = false
		state.members[index].disconnectedAtSec = nowSec
		return nil
	end

	local function applyDepart(state: RunState, event: MemberEvent, nowSec: number): string?
		if state.status ~= "active" then
			return Reason.runNotActive
		end
		local index = memberIndex(state.members, event.memberId)
		if index == nil then
			return Reason.unknownMember
		end
		if event.memberId == state.leaderId then
			return Reason.leaderDepartureRequired
		end
		local member = state.members[index]
		if member.departed then
			return Reason.memberDeparted
		end
		if member.connected then
			member.disconnectedAtSec = nowSec
		end
		member.connected = false
		member.departed = true
		return nil
	end

	local function applyReconnect(package: P, state: RunState, event: MemberEvent, nowSec: number): string?
		local index = memberIndex(state.members, event.memberId)
		if index == nil then
			return Reason.unknownMember
		end
		if state.members[index].connected then
			return Reason.alreadyConnected
		end
		if state.members[index].departed then
			return Reason.memberDeparted
		end
		local disconnectedAtSec = state.members[index].disconnectedAtSec
		if disconnectedAtSec == nil or nowSec > disconnectedAtSec + config.describe(package).recoveryWindowSec then
			return Reason.recoveryWindowExpired
		end
		state.members[index].connected = true
		state.members[index].disconnectedAtSec = nil
		return nil
	end

	local function applyLeaderDeparture(state: RunState, event: MemberEvent, nowSec: number): string?
		if state.status ~= "active" then
			return Reason.runNotActive
		end
		if event.memberId ~= state.leaderId then
			return Reason.leaderMismatch
		end
		local index = memberIndex(state.members, event.memberId)
		if index == nil or not state.members[index].connected then
			return Reason.unknownMember
		end
		local successor: string? = nil
		for _, member in state.members do
			if member.id ~= event.memberId and member.connected then
				successor = member.id
				break
			end
		end
		if successor == nil then
			return Reason.noConnectedSuccessor
		end
		state.members[index].connected = false
		state.members[index].disconnectedAtSec = nowSec
		state.members[index].departed = true
		state.leaderId = successor
		return nil
	end

	local function applyWipe(package: P, state: RunState, event: WipeEvent): string?
		if state.status ~= "active" then
			return Reason.runNotActive
		end
		local wiped = assert(sortedUniqueStrings(event.memberIds, 1))
		if not sameStrings(wiped, connectedMemberIds(state)) then
			return Reason.wipeRosterMismatch
		end
		state.attempt += 1
		state.phaseIndex = config.wipePhase(package, state)
		return nil
	end

	local function transition(
		packageValue: unknown,
		previousStateValue: unknown,
		eventValue: unknown,
		nowSecValue: unknown
	): TransitionResult
		local package = config.readPackage(packageValue)
		if package == nil then
			return rejectedTransition(nil, Reason.invalidPackage)
		end
		local event = readEvent(eventValue)
		if event == nil then
			return rejectedTransition(nil, Reason.invalidEvent)
		end
		if
			type(nowSecValue) ~= "number"
			or not (type(nowSecValue) == "number" and finite(nowSecValue))
			or nowSecValue < 0
		then
			return rejectedTransition(nil, Reason.invalidClock)
		end
		local nowSec = nowSecValue
		if previousStateValue == nil then
			if event.kind ~= "start" then
				return rejectedTransition(nil, Reason.missingState)
			end
			return startRun(package, event, nowSec)
		end

		local state = copyRunState(previousStateValue, package)
		if state == nil then
			return rejectedTransition(nil, Reason.invalidState)
		end
		if nowSec < state.lastClockSec then
			return rejectedTransition(state, Reason.invalidClock)
		end
		local fingerprint = eventFingerprint(event)
		local priorReceipt = state.receipts[event.eventId]
		if priorReceipt ~= nil then
			if priorReceipt ~= fingerprint then
				return rejectedTransition(state, Reason.receiptConflict)
			end
			return appliedTransition(state, true, nil)
		end
		if event.kind == "start" then
			return rejectedTransition(state, Reason.runAlreadyStarted)
		end
		if event.expectedRevision ~= state.revision then
			return rejectedTransition(state, Reason.revisionConflict)
		end

		local reason: string? = nil
		local recovery: Recovery? = nil
		if event.kind == "complete_phase" then
			reason = applyCompletePhase(package, state, event)
		elseif event.kind == "disconnect" then
			reason = applyDisconnect(state, event, nowSec)
		elseif event.kind == "replace" then
			local index = memberIndex(state.members, event.memberId)
			local prior = if index ~= nil then state.members[index] else nil
			if not config.replacementAllowed(package, state) then
				reason = "replacement_checkpoint_required"
			elseif
				prior == nil
				or prior.connected
				or prior.disconnectedAtSec == nil
				or nowSec <= prior.disconnectedAtSec + config.describe(package).recoveryWindowSec
			then
				reason = "replacement_seat_reserved"
			else
				for _, member in state.members do
					if member.id == event.replacementId then
						reason = "duplicate_member"
					end
				end
				if reason == nil then
					state.members[assert(index)] = {
						id = event.replacementId or error("validated replacement missing"),
						connected = true,
						departed = false,
					}
					table.sort(state.members, function(left: Member, right: Member): boolean
						return left.id < right.id
					end)
				end
			end
		elseif event.kind == "depart" then
			reason = applyDepart(state, event, nowSec)
		elseif event.kind == "reconnect" then
			reason = applyReconnect(package, state, event, nowSec)
			if reason == nil then
				recovery = {
					kind = "reconnect",
					returnAnchorId = recoveryAnchor(package, state),
					memberIds = { event.memberId },
				}
			end
		elseif event.kind == "leader_departure" then
			reason = applyLeaderDeparture(state, event, nowSec)
			if reason == nil then
				recovery = {
					kind = "leader_departure",
					returnAnchorId = recoveryAnchor(package, state),
					memberIds = connectedMemberIds(state),
				}
			end
		else
			reason = applyWipe(package, state, event)
			if reason == nil then
				recovery = {
					kind = "wipe",
					returnAnchorId = recoveryAnchor(package, state),
					memberIds = connectedMemberIds(state),
				}
			end
		end
		if reason ~= nil then
			local rejected: TransitionRejected = { ok = false, state = state, reason = tostring(reason) }
			return Value.freezeDeep(rejected)
		end
		commitEvent(state, event, fingerprint, nowSec)
		return appliedTransition(state, false, recovery)
	end

	local function projectRunState(packageValue: unknown, stateValue: unknown): RunState?
		local package = config.readPackage(packageValue)
		if package == nil then
			return nil
		end
		local state = copyRunState(stateValue, package)
		return if state == nil then nil else Value.freezeDeep(state)
	end
	local core: Core = { transition = transition, projectRunState = projectRunState, Reason = Reason }
	return Value.freezeDeep(core)
end
export type Tracker = {
	runId: string,
	attempt: number,
	phaseIndex: number,
	waveIndex: number,
	addsSpawned: boolean,
	spawned: { [string]: string },
	defeated: { [string]: boolean },
	pending: { [string]: boolean },
	calledSequences: { [string]: number },
}

export type WaveReading = {
	read hp: number,
	read maxHp: number,
	read resolvedAbilitySequence: number?,
	read resolvedReinforcementCount: number?,
}
type Readings = { read [string]: WaveReading? }
type Horizontal = { read x: number, read z: number }
export type WaveRoom = {
	read kind: string,
	read position: Horizontal,
	read waves: { read [number]: { read [number]: { read placementId: string } } },
	read adds: { read atHealthFraction: number }?,
}
export type WaveConfig<I, R, S> = {
	room: (I, number) -> R?,
	describe: (R) -> WaveRoom,
	wave: (R, Tracker, number) -> { S },
	adds: (R, Tracker) -> { S },
	call: (R, Tracker, string, number, number) -> S?,
	ids: (S) -> (string, string),
	isCall: (string) -> boolean,
	isCallerSpawn: (string, string) -> boolean,
	perCast: number,
	liveCap: number,
	checkpointRadius: number,
}
export type Decision =
	{ kind: "wait" }
	| { kind: "spawn_wave", waveIndex: number }
	| { kind: "spawn_adds" }
	| { kind: "room_cleared" }

local function copyTracker(tracker: Tracker): Tracker
	return {
		runId = tracker.runId,
		attempt = tracker.attempt,
		phaseIndex = tracker.phaseIndex,
		waveIndex = tracker.waveIndex,
		addsSpawned = tracker.addsSpawned,
		spawned = table.clone(tracker.spawned),
		defeated = table.clone(tracker.defeated),
		pending = table.clone(tracker.pending),
		calledSequences = table.clone(tracker.calledSequences),
	}
end

function System.newTracker(runId: string, attempt: number, phaseIndex: number): Tracker
	return Value.freezeDeep({
		runId = runId,
		attempt = attempt,
		phaseIndex = phaseIndex,
		waveIndex = 0,
		addsSpawned = false,
		spawned = {},
		defeated = {},
		pending = {},
		calledSequences = {},
	})
end

local function decide(room: WaveRoom, tracker: Tracker, readings: Readings): Decision
	if room.kind == "boss" then
		local bossPlacementId = room.waves[1][1].placementId
		if tracker.defeated[bossPlacementId] then
			return { kind = "room_cleared" }
		end
		local reading = readings[bossPlacementId]
		if
			not tracker.addsSpawned
			and reading ~= nil
			and reading.maxHp > 0
			and reading.hp / reading.maxHp <= assert(room.adds).atHealthFraction
		then
			return { kind = "spawn_adds" }
		end
		return { kind = "wait" }
	end
	for placementId in tracker.pending do
		if not tracker.defeated[placementId] then
			return { kind = "wait" }
		end
	end
	if tracker.waveIndex < #room.waves then
		return { kind = "spawn_wave", waveIndex = tracker.waveIndex + 1 }
	end
	return { kind = "room_cleared" }
end

function System.encounters<I, R, S>(config: WaveConfig<I, R, S>)
	local encounters = {}

	local function trackSpawn(tracker: Tracker, spawn: S, pending: boolean)
		local placementId, instanceId = config.ids(spawn)
		tracker.spawned[placementId] = instanceId
		if pending then
			tracker.pending[placementId] = true
		end
	end

	function encounters.waveSpawns(integration: I, tracker: Tracker, index: number): (Tracker, { S })
		local room = config.room(integration, tracker.phaseIndex)
		if room == nil then
			return tracker, {}
		end
		local spawns = config.wave(room, tracker, index)
		local updated = copyTracker(tracker)
		updated.waveIndex = index
		updated.pending = {}
		for _, spawn in spawns do
			trackSpawn(updated, spawn, true)
		end
		return Value.freezeDeep(updated), spawns
	end

	function encounters.addSpawns(integration: I, tracker: Tracker): (Tracker, { S })
		local room = config.room(integration, tracker.phaseIndex)
		if room == nil or config.describe(room).adds == nil or tracker.addsSpawned then
			return tracker, {}
		end
		local spawns = config.adds(room, tracker)
		local updated = copyTracker(tracker)
		updated.addsSpawned = true
		for _, spawn in spawns do
			trackSpawn(updated, spawn, false)
		end
		return Value.freezeDeep(updated), spawns
	end

	function encounters.calledSpawns(integration: I, tracker: Tracker, readings: Readings): (Tracker, { S })
		local room = config.room(integration, tracker.phaseIndex)
		local updated = copyTracker(tracker)
		local spawns: { S } = {}
		for caller, mob in readings do
			if mob == nil or mob.hp <= 0 then
				continue
			end
			local sequence, count = mob.resolvedAbilitySequence, mob.resolvedReinforcementCount
			if sequence == nil or count == nil or sequence <= (tracker.calledSequences[caller] or 0) then
				continue
			end
			updated.calledSequences[caller] = sequence
			local living, callerLiving = 0, 0
			for id in tracker.spawned do
				local other = readings[id]
				if other ~= nil and other.hp > 0 then
					if config.isCall(id) then
						living += 1
					end
					if config.isCallerSpawn(id, caller) then
						callerLiving += 1
					end
				end
			end
			for index = 1, math.min(count, config.perCast, config.liveCap - living, count - callerLiving) do
				local spawn = config.call(assert(room), tracker, caller, sequence, index)
				if spawn ~= nil then
					spawns[#spawns + 1] = spawn
					trackSpawn(updated, spawn, true)
				end
			end
		end
		return Value.freezeDeep(updated), spawns
	end

	function encounters.observe(integration: I, tracker: Tracker, readings: Readings): (Tracker, Decision)
		local source = config.room(integration, tracker.phaseIndex)
		local room = if source ~= nil then config.describe(source) else nil
		if room == nil or (room.kind ~= "encounter" and room.kind ~= "boss") or tracker.waveIndex == 0 then
			return tracker, { kind = "wait" }
		end
		local updated = copyTracker(tracker)
		for id in updated.spawned do
			local mob = readings[id]
			if mob ~= nil and mob.hp <= 0 then
				updated.defeated[id] = true
			end
		end
		return Value.freezeDeep(updated), decide(room, updated, readings)
	end

	function encounters.reachedCheckpoint(
		integration: I,
		index: number,
		positions: { read [number]: Horizontal }
	): boolean
		local source = config.room(integration, index)
		local room = if source ~= nil then config.describe(source) else nil
		if room == nil or room.kind ~= "checkpoint" then
			return false
		end
		for _, position in positions do
			local dx, dz = position.x - room.position.x, position.z - room.position.z
			if math.sqrt(dx * dx + dz * dz) <= config.checkpointRadius then
				return true
			end
		end
		return false
	end

	function encounters.enterRoom(integration: I, runId: string, attempt: number, index: number): (Tracker, { S })
		local tracker = System.newTracker(runId, attempt, index)
		local room = config.describe(assert(config.room(integration, index)))
		if room.kind == "encounter" or room.kind == "boss" then
			return encounters.waveSpawns(integration, tracker, 1)
		end
		return tracker, {}
	end

	function encounters.advance(
		integration: I,
		tracker: Tracker,
		readings: Readings,
		spawn: ({ S }) -> (),
		track: (Tracker) -> ()
	): boolean
		local withCalls, called = encounters.calledSpawns(integration, tracker, readings)
		spawn(called)
		local observed, decision = encounters.observe(integration, withCalls, readings)
		track(observed)
		if decision.kind == "spawn_wave" then
			local nextTracker, wave = encounters.waveSpawns(integration, observed, decision.waveIndex)
			track(nextTracker)
			spawn(wave)
		elseif decision.kind == "spawn_adds" then
			local nextTracker, adds = encounters.addSpawns(integration, observed)
			track(nextTracker)
			spawn(adds)
		end
		return decision.kind == "room_cleared"
	end

	return table.freeze(encounters)
end

type Point = { x: number, y: number?, z: number }
export type Health = { hp: number, maxHp: number }
export type Reinforcement = { hp: number, resolvedAbilitySequence: number?, resolvedReinforcementCount: number? }
export type Repopulation = { dueAt: number?, phase: string?, warnedAt: number? }
export type Retreat = { position: Point, radius: number }
export type CycleConfig = {
	warningSeconds: number,
	perCast: number,
	liveCap: number,
	pocketRadius: number,
	heightTolerance: number,
}

function System.sharedCycle(config: CycleConfig)
	local cycle = {}
	function cycle.respawnAt(defeatedAt: number, isBoss: boolean, bossSeconds: number, trashSeconds: number): number
		return defeatedAt + (if isBoss then bossSeconds else trashSeconds)
	end

	function cycle.callDue(alreadyCalled: boolean, mob: Health?, fraction: number): boolean
		return not alreadyCalled and mob ~= nil and mob.hp > 0 and mob.maxHp > 0 and mob.hp / mob.maxHp <= fraction
	end

	function cycle.rollCount(sequence: number, mob: Reinforcement, living: number, liveCap: number?): (number, number)
		local latest, count = mob.resolvedAbilitySequence, mob.resolvedReinforcementCount
		if mob.hp <= 0 or latest == nil or count == nil or latest <= sequence then
			return 0, sequence
		end
		return math.max(
			0,
			math.min(count, config.perCast, math.min(liveCap or config.liveCap, config.liveCap) - living)
		),
			latest
	end

	function cycle.repopulation<T>(
		row: T & Repopulation,
		now: number,
		occupied: boolean,
		delayCap: number?
	): (T & Repopulation, boolean)
		local nextRow = table.clone(row)
		local dueAt = row.dueAt
		if dueAt == nil then
			nextRow.phase = "active"
			return nextRow, false
		end
		if occupied and delayCap ~= nil and now >= dueAt + delayCap then
			occupied = false
		end
		if occupied or now < dueAt - config.warningSeconds then
			nextRow.phase = "returning"
			nextRow.warnedAt = nil
			return nextRow, false
		end
		nextRow.phase = "warned"
		local warnedAt: number = row.warnedAt or now
		nextRow.warnedAt = warnedAt
		if now >= dueAt and now - warnedAt >= config.warningSeconds then
			nextRow.phase = "active"
			return nextRow, true
		end
		return nextRow, false
	end

	function cycle.occupiedRetreat(placement: { position: Point }, room: Retreat?, positions: { Point }): boolean
		for _, position in positions do
			if math.abs((position.y or 0) - (placement.position.y or 0)) > config.heightTolerance then
				continue
			end
			local dx, dz = position.x - placement.position.x, position.z - placement.position.z
			if dx * dx + dz * dz <= config.pocketRadius * config.pocketRadius then
				return true
			end
			if room ~= nil then
				local rx, rz = position.x - room.position.x, position.z - room.position.z
				if rx * rx + rz * rz <= room.radius * room.radius then
					return true
				end
			end
		end
		return false
	end

	function cycle.presenceActive(lastActiveAt: number, now: number, idleSeconds: number): boolean
		return now - lastActiveAt <= idleSeconds
	end

	function cycle.moved(from: Point, to: Point, studs: number): boolean
		local dx, dy, dz = to.x - from.x, (to.y or 0) - (from.y or 0), to.z - from.z
		return dx * dx + dy * dy + dz * dz >= studs * studs
	end

	return table.freeze(cycle)
end

return table.freeze(System)
