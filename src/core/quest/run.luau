--!strict
type Raw = { [unknown]: unknown }

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

export type Config = {
	readPackage: (unknown) -> Package?,
	validCheckpoint: (Package, RunState) -> boolean,
	wipePhase: (Package, RunState) -> number,
	replacementAllowed: (Package, RunState) -> boolean,
	maxMembers: number,
}
local SCHEMA_VERSION = 1
local System = {}
function System.run(config: Config)
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

	local Reason = table.freeze({
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
	})

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function whole(value: unknown): boolean
		return finite(value) and (value :: number) >= 0 and value == math.floor(value :: number)
	end

	local function nonempty(value: unknown): boolean
		return type(value) == "string" and #value > 0
	end

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" then
			return false
		end
		for key in value :: Raw do
			if type(key) ~= "string" or not fields[key] then
				return false
			end
		end
		return true
	end

	local function denseLength(value: unknown): number?
		if type(value) ~= "table" then
			return nil
		end
		local count = 0
		for key in value :: Raw do
			if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
				return nil
			end
			count += 1
		end
		for index = 1, count do
			if (value :: Raw)[index] == nil then
				return nil
			end
		end
		return count
	end

	local function deepFreezeCopy<T>(value: T): T
		local probe: unknown = value
		if type(probe) ~= "table" then
			return value
		end
		local result: { [unknown]: unknown } = {}
		for key, child in (value :: unknown) :: { [unknown]: unknown } do
			result[deepFreezeCopy(key)] = deepFreezeCopy(child)
		end
		return (table.freeze(result) :: unknown) :: T
	end

	local function sortedUniqueStrings(value: unknown, minimum: number?): { string }?
		local count = denseLength(value)
		if count == nil or count < (minimum or 0) then
			return nil
		end
		local result: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, id in value :: { unknown } do
			if not nonempty(id) or seen[id :: string] then
				return nil
			end
			seen[id :: string] = true
			result[#result + 1] = id :: string
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

	local function copyRunState(value: unknown, package: Package): RunState?
		if not hasOnlyFields(value, RUN_FIELDS) then
			return nil
		end
		local source = value :: RunState
		if
			source.schemaVersion ~= SCHEMA_VERSION
			or source.expeditionId ~= package.id
			or not nonempty(source.runId)
			or not whole(source.revision)
			or source.revision < 1
			or not finite(source.startedAtSec)
			or source.startedAtSec < 0
			or not finite(source.lastClockSec)
			or source.lastClockSec < source.startedAtSec
			or (source.status ~= "active" and source.status ~= "completed")
			or not whole(source.phaseIndex)
			or source.phaseIndex < 1
			or source.phaseIndex > #package.phases
			or not whole(source.attempt)
			or source.attempt < 1
			or not nonempty(source.leaderId)
		then
			return nil
		end
		local memberCount = denseLength(source.members)
		if memberCount == nil or memberCount < package.group.minPlayers or memberCount > package.group.maxPlayers then
			return nil
		end
		local members: { Member } = {}
		local priorId: string? = nil
		local leaderConnected = false
		for _, row in source.members do
			if
				not hasOnlyFields(row, MEMBER_FIELDS)
				or not nonempty(row.id)
				or type(row.connected) ~= "boolean"
				or type(row.departed) ~= "boolean"
				or (row.connected and (row.disconnectedAtSec ~= nil or row.departed))
				or (not row.connected and (not finite(row.disconnectedAtSec) or row.disconnectedAtSec == nil or row.disconnectedAtSec < source.startedAtSec or row.disconnectedAtSec > source.lastClockSec))
				or (priorId ~= nil and row.id <= priorId)
			then
				return nil
			end
			priorId = row.id
			if row.id == source.leaderId then
				leaderConnected = row.connected
			end
			members[#members + 1] = {
				id = row.id,
				connected = row.connected,
				disconnectedAtSec = row.disconnectedAtSec,
				departed = row.departed,
			}
		end
		if not leaderConnected or not config.validCheckpoint(package, source) then
			return nil
		end
		if type(source.receipts) ~= "table" then
			return nil
		end
		local receipts: { [string]: string } = {}
		local receiptCount = 0
		for eventId, fingerprint in source.receipts do
			if not nonempty(eventId) or not nonempty(fingerprint) then
				return nil
			end
			local eventIdString = eventId
			local fingerprintString = fingerprint
			receiptCount += 1
			receipts[eventIdString] = fingerprintString
		end
		if receiptCount ~= source.revision then
			return nil
		end
		local expeditionId = source.expeditionId
		local runId = source.runId
		local revision = source.revision
		local startedAtSec = source.startedAtSec
		local lastClockSec = source.lastClockSec
		local status: RunStatus
		if source.status == "active" then
			status = "active"
		else
			status = "completed"
		end
		local phaseIndex = source.phaseIndex
		local checkpointId = source.checkpointId :: string?
		local attempt = source.attempt
		local leaderId = source.leaderId
		local copiedState: RunState = {
			schemaVersion = SCHEMA_VERSION,
			expeditionId = expeditionId,
			runId = runId,
			revision = revision,
			startedAtSec = startedAtSec,
			lastClockSec = lastClockSec,
			status = status,
			phaseIndex = phaseIndex,
			checkpointId = checkpointId,
			attempt = attempt,
			leaderId = leaderId,
			members = members,
			receipts = receipts,
		}
		return copiedState
	end

	local function validEvent(value: unknown): boolean
		if type(value) ~= "table" then
			return false
		end
		local event = value :: Event
		if not nonempty(event.eventId) then
			return false
		end
		if event.kind == "start" then
			local memberIds = sortedUniqueStrings(event.memberIds, 1)
			return hasOnlyFields(event, START_FIELDS)
				and nonempty(event.runId)
				and nonempty(event.leaderId)
				and memberIds ~= nil
				and #memberIds <= config.maxMembers
				and table.find(memberIds, event.leaderId) ~= nil
		elseif event.kind == "complete_phase" then
			return hasOnlyFields(event, COMPLETE_FIELDS) and whole(event.expectedRevision) and nonempty(event.phaseId)
		elseif
			event.kind == "disconnect"
			or event.kind == "reconnect"
			or event.kind == "leader_departure"
			or event.kind == "depart"
		then
			return hasOnlyFields(event, MEMBER_EVENT_FIELDS)
				and whole(event.expectedRevision)
				and nonempty(event.memberId)
		elseif event.kind == "replace" then
			return hasOnlyFields(
				event,
				{ kind = true, eventId = true, expectedRevision = true, memberId = true, replacementId = true }
			) and whole(event.expectedRevision) and nonempty(event.memberId) and nonempty(event.replacementId)
		elseif event.kind == "wipe" then
			return hasOnlyFields(event, WIPE_FIELDS)
				and whole(event.expectedRevision)
				and sortedUniqueStrings(event.memberIds, 1) ~= nil
		end
		return false
	end

	local function eventFingerprint(event: Event): string
		if event.kind == "replace" then
			return segment(event.kind) .. segment(event.memberId) .. segment(event.replacementId :: string)
		elseif event.kind == "start" then
			local members = sortedUniqueStrings(event.memberIds, 1) :: { string }
			return segment(event.kind) .. segment(event.runId) .. segment(event.leaderId) .. stringListSegment(members)
		elseif event.kind == "complete_phase" then
			return segment(event.kind) .. segment(event.phaseId)
		elseif event.kind == "wipe" then
			local members = sortedUniqueStrings(event.memberIds, 1) :: { string }
			return segment(event.kind) .. stringListSegment(members)
		end
		return segment(event.kind) .. segment(event.memberId)
	end

	local function rejectedTransition(state: RunState?, reason: string): TransitionRejected
		return deepFreezeCopy({ ok = false :: false, state = state, reason = reason }) :: TransitionRejected
	end

	local function appliedTransition(state: RunState, replayed: boolean, recovery: Recovery?): TransitionApplied
		return deepFreezeCopy({
			ok = true :: true,
			state = state,
			replayed = replayed,
			recovery = recovery,
		}) :: TransitionApplied
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

	local function recoveryAnchor(package: Package, state: RunState): string
		if state.status == "completed" then
			return package.returnId
		end
		return state.checkpointId or package.entryId
	end

	local function commitEvent(state: RunState, event: Event, fingerprint: string, nowSec: number)
		state.lastClockSec = nowSec
		state.revision += 1
		state.receipts[event.eventId] = fingerprint
	end

	local function startRun(package: Package, event: StartEvent, nowSec: number): TransitionResult
		local memberIds = sortedUniqueStrings(event.memberIds, 1) :: { string }
		if #memberIds < package.group.minPlayers then
			return rejectedTransition(nil, "group_too_small")
		end
		local members: { Member } = {}
		for _, memberId in memberIds do
			members[#members + 1] = { id = memberId, connected = true, disconnectedAtSec = nil, departed = false }
		end
		local fingerprint = eventFingerprint(event)
		local state: RunState = {
			schemaVersion = SCHEMA_VERSION,
			expeditionId = package.id,
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

	local function applyCompletePhase(package: Package, state: RunState, event: CompletePhaseEvent): string?
		if state.status ~= "active" then
			return Reason.runNotActive
		end
		local phase = package.phases[state.phaseIndex]
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

	local function applyReconnect(package: Package, state: RunState, event: MemberEvent, nowSec: number): string?
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
		if disconnectedAtSec == nil or nowSec > disconnectedAtSec + package.recoveryWindowSec then
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

	local function applyWipe(package: Package, state: RunState, event: WipeEvent): string?
		if state.status ~= "active" then
			return Reason.runNotActive
		end
		local wiped = sortedUniqueStrings(event.memberIds, 1) :: { string }
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
		if not validEvent(eventValue) then
			return rejectedTransition(nil, Reason.invalidEvent)
		end
		if not finite(nowSecValue) or (nowSecValue :: number) < 0 then
			return rejectedTransition(nil, Reason.invalidClock)
		end
		local event = eventValue :: Event
		local nowSec = nowSecValue :: number
		if previousStateValue == nil then
			if event.kind ~= "start" then
				return rejectedTransition(nil, Reason.missingState)
			end
			return startRun(package, event :: StartEvent, nowSec)
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
			reason = applyCompletePhase(package, state, event :: CompletePhaseEvent)
		elseif event.kind == "disconnect" then
			reason = applyDisconnect(state, event :: MemberEvent, nowSec)
		elseif event.kind == "replace" then
			local index = memberIndex(state.members, event.memberId)
			local prior = if index ~= nil then state.members[index] else nil
			if not config.replacementAllowed(package, state) then
				reason = "replacement_checkpoint_required"
			elseif
				prior == nil
				or prior.connected
				or prior.disconnectedAtSec == nil
				or nowSec <= prior.disconnectedAtSec + package.recoveryWindowSec
			then
				reason = "replacement_seat_reserved"
			else
				for _, member in state.members do
					if member.id == event.replacementId then
						reason = "duplicate_member"
					end
				end
				if reason == nil then
					state.members[index :: number] =
						{ id = event.replacementId :: string, connected = true, departed = false }
					table.sort(state.members, function(left: Member, right: Member): boolean
						return left.id < right.id
					end)
				end
			end
		elseif event.kind == "depart" then
			reason = applyDepart(state, event :: MemberEvent, nowSec)
		elseif event.kind == "reconnect" then
			reason = applyReconnect(package, state, event :: MemberEvent, nowSec)
			if reason == nil then
				recovery = {
					kind = "reconnect",
					returnAnchorId = recoveryAnchor(package, state),
					memberIds = { event.memberId },
				}
			end
		elseif event.kind == "leader_departure" then
			reason = applyLeaderDeparture(state, event :: MemberEvent, nowSec)
			if reason == nil then
				recovery = {
					kind = "leader_departure",
					returnAnchorId = recoveryAnchor(package, state),
					memberIds = connectedMemberIds(state),
				}
			end
		else
			reason = applyWipe(package, state, event :: WipeEvent)
			if reason == nil then
				recovery = {
					kind = "wipe",
					returnAnchorId = recoveryAnchor(package, state),
					memberIds = connectedMemberIds(state),
				}
			end
		end
		if reason ~= nil then
			return rejectedTransition(state, reason :: string)
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
		return if state == nil then nil else deepFreezeCopy(state)
	end
	return table.freeze({ transition = transition, projectRunState = projectRunState, Reason = Reason })
end
return table.freeze(System)
