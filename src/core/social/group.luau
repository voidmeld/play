--!strict

local SocialShape = require("./shape")

export type Relations = {
	readAtSec: number,
	memberUserId: number,
	moderationEligible: boolean,
	blockedUserIds: { number },
	moderationDeniedUserIds: { number },
	optedOutUserIds: { number },
}

export type Admission = {
	members: { Relations },
	subject: Relations?,
}

export type Ticket = {
	userId: number,
	departedAtSec: number,
	expiresAtSec: number,
}

export type State = {
	schemaVersion: number,
	groupId: string,
	revision: number,
	lastClockSec: number,
	relationsReadAtSec: number,
	tickets: { Ticket },
	receipts: { [string]: string },
}

export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	recoveredUserId: number?,
}

export type Decision = {
	ok: boolean,
	reason: string?,
}

type Raw = { [unknown]: unknown }
export type Request = { groupId: string, inviterUserId: number, candidateUserId: number }
export type Authority = { validate: (string, string, number, number, number) -> unknown }
export type MemberEvent = { kind: "depart" | "recover", eventId: string, expectedRevision: number, userId: number }
export type ReconcileEvent = { kind: "reconcile", eventId: string, expectedRevision: number, userId: nil }
export type Event = MemberEvent | ReconcileEvent
export type Config = {
	recoveryTtlSec: number,
	relationsMaxAgeSec: number,
	maxTickets: number,
	maxRoster: number,
	maxRevision: number,
	maxTime: number,
	maxId: number,
	maxFingerprint: number,
}

local System = {}

function System.group(config: Config)
	local function readRelations(value: unknown): Relations?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				readAtSec = true,
				memberUserId = true,
				moderationEligible = true,
				blockedUserIds = true,
				moderationDeniedUserIds = true,
				optedOutUserIds = true,
			})
		then
			return nil
		end
		local readAtSec = SocialShape.number(raw.readAtSec)
		if readAtSec == nil then
			return nil
		end
		local memberUserId = SocialShape.number(raw.memberUserId)
		if memberUserId == nil then
			return nil
		end
		local moderationEligible = SocialShape.boolean(raw.moderationEligible)
		if moderationEligible == nil then
			return nil
		end
		local blockedUserIds = SocialShape.array(raw.blockedUserIds, SocialShape.number)
		if blockedUserIds == nil then
			return nil
		end
		local moderationDeniedUserIds = SocialShape.array(raw.moderationDeniedUserIds, SocialShape.number)
		if moderationDeniedUserIds == nil then
			return nil
		end
		local optedOutUserIds = SocialShape.array(raw.optedOutUserIds, SocialShape.number)
		if optedOutUserIds == nil then
			return nil
		end
		return {
			readAtSec = readAtSec,
			memberUserId = memberUserId,
			moderationEligible = moderationEligible,
			blockedUserIds = blockedUserIds,
			moderationDeniedUserIds = moderationDeniedUserIds,
			optedOutUserIds = optedOutUserIds,
		}
	end

	local function readTicket(value: unknown): Ticket?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { userId = true, departedAtSec = true, expiresAtSec = true }) then
			return nil
		end
		local userId = SocialShape.number(raw.userId)
		if userId == nil then
			return nil
		end
		local departedAtSec = SocialShape.number(raw.departedAtSec)
		if departedAtSec == nil then
			return nil
		end
		local expiresAtSec = SocialShape.number(raw.expiresAtSec)
		if expiresAtSec == nil then
			return nil
		end
		return { userId = userId, departedAtSec = departedAtSec, expiresAtSec = expiresAtSec }
	end

	local function readState(value: unknown): State?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				schemaVersion = true,
				groupId = true,
				revision = true,
				lastClockSec = true,
				relationsReadAtSec = true,
				tickets = true,
				receipts = true,
			})
		then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local groupId = SocialShape.string(raw.groupId)
		if groupId == nil then
			return nil
		end
		local revision = SocialShape.number(raw.revision)
		if revision == nil then
			return nil
		end
		local lastClockSec = SocialShape.number(raw.lastClockSec)
		if lastClockSec == nil then
			return nil
		end
		local relationsReadAtSec = SocialShape.number(raw.relationsReadAtSec)
		if relationsReadAtSec == nil then
			return nil
		end
		local tickets = SocialShape.array(raw.tickets, readTicket)
		if tickets == nil then
			return nil
		end
		local receipts = SocialShape.map(raw.receipts, SocialShape.string, SocialShape.string)
		if receipts == nil then
			return nil
		end
		return {
			schemaVersion = schemaVersion,
			groupId = groupId,
			revision = revision,
			lastClockSec = lastClockSec,
			relationsReadAtSec = relationsReadAtSec,
			tickets = tickets,
			receipts = receipts,
		}
	end

	local function readRequest(value: unknown): Request?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { groupId = true, inviterUserId = true, candidateUserId = true }) then
			return nil
		end
		local groupId = SocialShape.string(raw.groupId)
		if groupId == nil then
			return nil
		end
		local inviterUserId = SocialShape.number(raw.inviterUserId)
		if inviterUserId == nil then
			return nil
		end
		local candidateUserId = SocialShape.number(raw.candidateUserId)
		if candidateUserId == nil then
			return nil
		end
		return { groupId = groupId, inviterUserId = inviterUserId, candidateUserId = candidateUserId }
	end

	local SCHEMA_VERSION = 1
	local RECOVERY_TTL_SEC = config.recoveryTtlSec
	local RELATIONS_MAX_AGE_SEC = config.relationsMaxAgeSec
	local MAX_TICKETS = config.maxTickets
	local MAX_ROSTER = config.maxRoster
	local MAX_REVISION = config.maxRevision
	local MAX_TIME = config.maxTime

	local REASONS: { string } = {
		"invalid_state",
		"invalid_event",
		"invalid_request",
		"invalid_clock",
		"invalid_relations",
		"relations_missing",
		"relations_unread",
		"relations_stale",
		"relations_conflict",
		"relations_regressed",
		"revision_conflict",
		"revision_exhausted",
		"receipt_conflict",
		"inviter_unknown",
		"already_member",
		"self_target",
		"blocked",
		"moderation_denied",
		"privacy_denied",
		"admission_denied",
		"ticket_unknown",
	}

	local STATE_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		groupId = true,
		revision = true,
		lastClockSec = true,
		relationsReadAtSec = true,
		tickets = true,
		receipts = true,
	}

	local TICKET_FIELDS: { [string]: boolean } = {
		userId = true,
		departedAtSec = true,
		expiresAtSec = true,
	}

	local RELATIONS_FIELDS: { [string]: boolean } = {
		readAtSec = true,
		memberUserId = true,
		moderationEligible = true,
		blockedUserIds = true,
		moderationDeniedUserIds = true,
		optedOutUserIds = true,
	}

	local ADMISSION_FIELDS: { [string]: boolean } = {
		members = true,
		subject = true,
	}

	local ADMIT_REQUEST_FIELDS: { [string]: boolean } = {
		groupId = true,
		inviterUserId = true,
		candidateUserId = true,
	}

	local EVENT_FIELDS: { [string]: { [string]: boolean } } = {
		depart = { kind = true, eventId = true, expectedRevision = true, userId = true },
		recover = { kind = true, eventId = true, expectedRevision = true, userId = true },
		reconcile = { kind = true, eventId = true, expectedRevision = true },
	}

	local whole = SocialShape.whole

	local function positiveUserId(value: unknown): boolean
		return whole(value, 1, MAX_TIME)
	end

	local opaqueId = SocialShape.opaque

	local onlyFields = SocialShape.onlyFields
	local denseLength = SocialShape.denseLength

	local freezeDeep = SocialShape.freezeDeepWithKeys

	local function copySortedUserIds(value: unknown): ({ number }?, { [number]: boolean }?)
		local count = denseLength(value)
		if count == nil then
			return nil, nil
		end
		local rows: { number } = {}
		local index: { [number]: boolean } = {}
		local previous = 0
		for _, candidate in assert(SocialShape.raw(value)) do
			local userId = SocialShape.number(candidate)
			if userId == nil then
				return nil, nil
			end
			if not positiveUserId(userId) or userId <= previous then
				return nil, nil
			end
			rows[#rows + 1] = userId
			index[userId] = true
			previous = userId
		end
		return rows, index
	end

	type Snapshot = {
		relations: Relations,
		blocked: { [number]: boolean },
		moderationDenied: { [number]: boolean },
		optedOut: { [number]: boolean },
	}

	local function copyRelations(value: unknown, nowSec: number): (Snapshot?, string?)
		if not onlyFields(value, RELATIONS_FIELDS) then
			return nil, "invalid_relations"
		end
		local raw = readRelations(value)
		if raw == nil then
			return nil, "invalid_relations"
		end
		if
			not positiveUserId(raw.memberUserId)
			or type(raw.moderationEligible) ~= "boolean"
			or not whole(raw.readAtSec, 0, MAX_TIME)
		then
			return nil, "invalid_relations"
		end
		local blocked, blockedIndex = copySortedUserIds(raw.blockedUserIds)
		local moderationDenied, moderationDeniedIndex = copySortedUserIds(raw.moderationDeniedUserIds)
		local optedOut, optedOutIndex = copySortedUserIds(raw.optedOutUserIds)
		if blocked == nil or moderationDenied == nil or optedOut == nil then
			return nil, "invalid_relations"
		end
		if raw.readAtSec > nowSec then
			return nil, "relations_unread"
		end
		if nowSec - raw.readAtSec > RELATIONS_MAX_AGE_SEC then
			return nil, "relations_stale"
		end
		return {
			relations = {
				readAtSec = raw.readAtSec,
				memberUserId = raw.memberUserId,
				moderationEligible = raw.moderationEligible,
				blockedUserIds = blocked,
				moderationDeniedUserIds = moderationDenied,
				optedOutUserIds = optedOut,
			},
			blocked = assert(blockedIndex),
			moderationDenied = assert(moderationDeniedIndex),
			optedOut = assert(optedOutIndex),
		},
			nil
	end

	local function copyAdmission(value: unknown, nowSec: number): ({ Snapshot }?, Snapshot?, string?)
		if not onlyFields(value, ADMISSION_FIELDS) then
			return nil, nil, "invalid_relations"
		end
		local raw = assert(SocialShape.raw(value))
		local count = denseLength(raw.members)
		if count == nil or count > MAX_ROSTER then
			return nil, nil, "invalid_relations"
		end
		if count == 0 then
			return nil, nil, "relations_missing"
		end
		local members: { Snapshot } = {}
		local seen: { [number]: boolean } = {}
		for _, candidate in assert(SocialShape.raw(raw.members)) do
			local snapshot, reason = copyRelations(candidate, nowSec)
			if snapshot == nil then
				return nil, nil, reason
			end
			local live = assert(snapshot)
			if seen[live.relations.memberUserId] then
				return nil, nil, "relations_conflict"
			end
			seen[live.relations.memberUserId] = true
			members[#members + 1] = live
		end
		if raw.subject == nil then
			return members, nil, nil
		end
		local subject, subjectReason = copyRelations(raw.subject, nowSec)
		if subject == nil then
			return nil, nil, subjectReason
		end
		return members, assert(subject), nil
	end

	local function earliestRead(members: { Snapshot }, subject: Snapshot?): number
		local earliest = MAX_TIME
		for _, member in members do
			if member.relations.readAtSec < earliest then
				earliest = member.relations.readAtSec
			end
		end
		if subject ~= nil and (assert(subject)).relations.readAtSec < earliest then
			earliest = (assert(subject)).relations.readAtSec
		end
		return earliest
	end

	local function evaluate(
		members: { Snapshot },
		subject: Snapshot,
		candidateUserId: number,
		inviterUserId: number?
	): string?
		if subject.relations.memberUserId ~= candidateUserId then
			return "relations_conflict"
		end
		local present = false
		for _, member in members do
			if member.relations.memberUserId == candidateUserId then
				return "already_member"
			end
			if inviterUserId ~= nil and member.relations.memberUserId == inviterUserId then
				present = true
			end
		end
		if inviterUserId ~= nil then
			if inviterUserId == candidateUserId then
				return "self_target"
			end
			if not present then
				return "inviter_unknown"
			end
		end
		for _, member in members do
			if member.blocked[candidateUserId] or subject.blocked[member.relations.memberUserId] then
				return "blocked"
			end
		end
		if not subject.relations.moderationEligible then
			return "moderation_denied"
		end
		for _, member in members do
			if member.moderationDenied[candidateUserId] or subject.moderationDenied[member.relations.memberUserId] then
				return "moderation_denied"
			end
		end
		for _, member in members do
			if member.optedOut[candidateUserId] or subject.optedOut[member.relations.memberUserId] then
				return "privacy_denied"
			end
		end
		return nil
	end

	local function authorityValid(
		authority: Authority?,
		groupId: string,
		operation: string,
		actorUserId: number,
		subjectUserId: number,
		nowSec: number
	): boolean
		if type(authority) ~= "table" or type((assert(SocialShape.raw(authority))).validate) ~= "function" then
			return false
		end
		for key in assert(SocialShape.raw(authority)) do
			if key ~= "validate" then
				return false
			end
		end
		local validate = authority.validate
		if type(validate) ~= "function" then
			return false
		end
		return validate(groupId, operation, actorUserId, subjectUserId, nowSec) == true
	end

	local function ticketBefore(left: Ticket, right: Ticket): boolean
		if left.expiresAtSec ~= right.expiresAtSec then
			return left.expiresAtSec < right.expiresAtSec
		end
		return left.userId < right.userId
	end

	local function copyTicket(value: unknown): Ticket?
		local raw = readTicket(value)
		if raw == nil then
			return nil
		end
		if
			not onlyFields(raw, TICKET_FIELDS)
			or not positiveUserId(raw.userId)
			or not whole(raw.departedAtSec, 0, MAX_TIME)
			or not whole(raw.expiresAtSec, 0, MAX_TIME)
			or raw.expiresAtSec ~= raw.departedAtSec + RECOVERY_TTL_SEC
		then
			return nil
		end
		return {
			userId = raw.userId,
			departedAtSec = raw.departedAtSec,
			expiresAtSec = raw.expiresAtSec,
		}
	end

	local function copyState(value: unknown): State?
		if not onlyFields(value, STATE_FIELDS) then
			return nil
		end
		local raw = readState(value)
		if raw == nil then
			return nil
		end
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or not opaqueId(raw.groupId, config.maxId)
			or not whole(raw.revision, 0, MAX_REVISION)
			or not whole(raw.lastClockSec, 0, MAX_TIME)
			or not whole(raw.relationsReadAtSec, 0, MAX_TIME)
			or type(raw.receipts) ~= "table"
		then
			return nil
		end
		local receipts: { [string]: string } = {}
		for eventId, fingerprint in raw.receipts do
			if not opaqueId(eventId, config.maxId) or not opaqueId(fingerprint, config.maxFingerprint) then
				return nil
			end
			receipts[eventId] = fingerprint
		end
		local count = denseLength(raw.tickets)
		if count == nil or count > MAX_TICKETS then
			return nil
		end
		local tickets: { Ticket } = {}
		local seen: { [number]: boolean } = {}
		local prior: Ticket? = nil
		for _, candidate in raw.tickets do
			local ticket = copyTicket(candidate)
			if
				ticket == nil
				or seen[ticket.userId]
				or ticket.departedAtSec > raw.lastClockSec
				or (prior ~= nil and not ticketBefore(assert(prior), ticket))
			then
				return nil
			end
			seen[ticket.userId] = true
			tickets[#tickets + 1] = ticket
			prior = ticket
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			groupId = raw.groupId,
			revision = raw.revision,
			lastClockSec = raw.lastClockSec,
			relationsReadAtSec = raw.relationsReadAtSec,
			tickets = tickets,
			receipts = receipts,
		}
	end

	local function segment(value: unknown): string
		if value == nil then
			return "0:"
		end
		local text = tostring(value)
		return tostring(#text) .. ":" .. text
	end

	local function fingerprint(event: Event): string
		return table.concat({
			segment(event.kind),
			segment(event.expectedRevision),
			segment(event.userId),
		})
	end

	local function validEvent(value: unknown): Event?
		local event = SocialShape.raw(value)
		if event == nil then
			return nil
		end
		local kind = event.kind
		local eventId = SocialShape.string(event.eventId)
		local expectedRevision = SocialShape.number(event.expectedRevision)
		if
			type(kind) ~= "string"
			or EVENT_FIELDS[kind] == nil
			or not onlyFields(value, EVENT_FIELDS[kind])
			or eventId == nil
			or not opaqueId(eventId, config.maxId)
			or expectedRevision == nil
			or not whole(expectedRevision, 0, MAX_REVISION)
		then
			return nil
		end
		if kind == "reconcile" then
			return { kind = "reconcile", eventId = eventId, expectedRevision = expectedRevision, userId = nil }
		end
		if kind ~= "depart" and kind ~= "recover" then
			return nil
		end
		local userId = SocialShape.number(event.userId)
		if userId == nil or not positiveUserId(userId) then
			return nil
		end
		return { kind = kind, eventId = eventId, expectedRevision = expectedRevision, userId = userId }
	end

	local function denied(members: { Snapshot }, userId: number): boolean
		for _, member in members do
			if member.blocked[userId] or member.moderationDenied[userId] or member.optedOut[userId] then
				return true
			end
		end
		return false
	end

	local function prune(state: State, nowSec: number, members: { Snapshot })
		local tickets: { Ticket } = {}
		for _, ticket in state.tickets do
			if nowSec < ticket.expiresAtSec and not denied(members, ticket.userId) then
				tickets[#tickets + 1] = ticket
			end
		end
		state.tickets = tickets
	end

	local function outcome(value: Result): Result
		return SocialShape.freezeDeep(value)
	end

	local function rejected(state: State?, reason: string): Result
		if state ~= nil then
			freezeDeep(state)
		end
		return outcome({ ok = false, state = state, replayed = false, reason = reason, recoveredUserId = nil })
	end

	local GroupCore = {}

	function GroupCore.emptyState(groupId: unknown): State?
		if not opaqueId(groupId, config.maxId) then
			return nil
		end
		return freezeDeep({
			schemaVersion = SCHEMA_VERSION,
			groupId = assert(SocialShape.string(groupId)),
			revision = 0,
			lastClockSec = 0,
			relationsReadAtSec = 0,
			tickets = {},
			receipts = {},
		})
	end

	function GroupCore.projectState(value: unknown): State?
		local state = copyState(value)
		if state == nil then
			return nil
		end
		return freezeDeep(state)
	end

	function GroupCore.projectRelations(value: unknown, nowSecValue: unknown): Relations?
		if not whole(nowSecValue, 0, MAX_TIME) then
			return nil
		end
		local snapshot = copyRelations(value, assert(SocialShape.number(nowSecValue)))
		if snapshot == nil then
			return nil
		end
		return freezeDeep((assert(snapshot)).relations)
	end

	local function decision(value: Decision): Decision
		return SocialShape.freezeDeep(value)
	end

	function GroupCore.admit(
		admissionValue: unknown,
		requestValue: unknown,
		nowSecValue: unknown,
		groupAuthority: Authority?
	): Decision
		if not whole(nowSecValue, 0, MAX_TIME) then
			return decision({ ok = false, reason = "invalid_clock" })
		end
		if not onlyFields(requestValue, ADMIT_REQUEST_FIELDS) then
			return decision({ ok = false, reason = "invalid_request" })
		end
		local request = readRequest(requestValue)
		if request == nil then
			return decision({ ok = false, reason = "invalid_request" })
		end
		if
			not opaqueId(request.groupId, config.maxId)
			or not positiveUserId(request.inviterUserId)
			or not positiveUserId(request.candidateUserId)
		then
			return decision({ ok = false, reason = "invalid_request" })
		end
		local nowSec = assert(SocialShape.number(nowSecValue))
		local members, subject, reason = copyAdmission(admissionValue, nowSec)
		if members == nil then
			return decision({ ok = false, reason = reason })
		end
		if subject == nil then
			return decision({ ok = false, reason = "relations_missing" })
		end
		local refusal = evaluate(members, assert(subject), request.candidateUserId, request.inviterUserId)
		if refusal ~= nil then
			return decision({ ok = false, reason = refusal })
		end
		if
			not authorityValid(
				groupAuthority,
				request.groupId,
				"admit",
				request.inviterUserId,
				request.candidateUserId,
				nowSec
			)
		then
			return decision({ ok = false, reason = "admission_denied" })
		end
		return decision({ ok = true, reason = nil })
	end

	function GroupCore.visibleRoster(relationsValue: unknown, rosterValue: unknown, nowSecValue: unknown): { number }?
		if not whole(nowSecValue, 0, MAX_TIME) then
			return nil
		end
		local snapshot = copyRelations(relationsValue, assert(SocialShape.number(nowSecValue)))
		if snapshot == nil then
			return nil
		end
		local viewer = assert(snapshot)
		local count = denseLength(rosterValue)
		if count == nil or count > MAX_ROSTER then
			return nil
		end
		local rows: { number } = {}
		local seen: { [number]: boolean } = {}
		for _, candidate in assert(SocialShape.raw(rosterValue)) do
			local userId = SocialShape.number(candidate)
			if userId == nil then
				return nil
			end
			if not positiveUserId(userId) then
				return nil
			end
			if seen[userId] then
				return nil
			end
			seen[userId] = true
			if not viewer.relations.moderationEligible then
				continue
			end
			if userId == viewer.relations.memberUserId then
				rows[#rows + 1] = userId
				continue
			end
			if viewer.blocked[userId] or viewer.moderationDenied[userId] or viewer.optedOut[userId] then
				continue
			end
			rows[#rows + 1] = userId
		end
		return freezeDeep(rows)
	end

	function GroupCore.transition(
		previousStateValue: unknown,
		eventValue: unknown,
		nowSecValue: unknown,
		admissionValue: unknown,
		groupAuthority: Authority?
	): Result
		local state = copyState(previousStateValue)
		if state == nil then
			return rejected(nil, "invalid_state")
		end
		local event = validEvent(eventValue)
		if event == nil then
			return rejected(state, "invalid_event")
		end
		if not whole(nowSecValue, 0, MAX_TIME) or (assert(SocialShape.number(nowSecValue))) < state.lastClockSec then
			return rejected(state, "invalid_clock")
		end
		local nowSec = assert(SocialShape.number(nowSecValue))
		local members, subject, reason = copyAdmission(admissionValue, nowSec)
		if members == nil then
			return rejected(state, assert(SocialShape.string(reason)))
		end
		local liveMembers = members
		if earliestRead(liveMembers, subject) < state.relationsReadAtSec then
			return rejected(state, "relations_regressed")
		end
		local eventFingerprint = fingerprint(event)
		local priorReceipt = state.receipts[event.eventId]
		if priorReceipt ~= nil then
			if priorReceipt ~= eventFingerprint then
				return rejected(state, "receipt_conflict")
			end
			return outcome({ ok = true, state = state, replayed = true, reason = nil, recoveredUserId = nil })
		end
		if event.expectedRevision ~= state.revision then
			return rejected(state, "revision_conflict")
		end
		if state.revision >= MAX_REVISION then
			return rejected(state, "revision_exhausted")
		end

		local recoveredUserId: number? = nil
		if event.kind == "depart" then
			if subject == nil then
				return rejected(state, "relations_missing")
			end
			if (assert(subject)).relations.memberUserId ~= event.userId then
				return rejected(state, "relations_conflict")
			end
			if not authorityValid(groupAuthority, state.groupId, "depart", event.userId, event.userId, nowSec) then
				return rejected(state, "admission_denied")
			end
			local expiresAtSec = nowSec + RECOVERY_TTL_SEC
			if expiresAtSec > MAX_TIME then
				return rejected(state, "invalid_clock")
			end
			local target = #state.tickets + 1
			for index, ticket in state.tickets do
				if ticket.userId == event.userId then
					target = index
					break
				end
			end
			state.tickets[target] = {
				userId = event.userId,
				departedAtSec = nowSec,
				expiresAtSec = expiresAtSec,
			}
			prune(state, nowSec, liveMembers)
			table.sort(state.tickets, ticketBefore)
			if #state.tickets > MAX_TICKETS then
				table.remove(state.tickets, 1)
			end
		elseif event.kind == "recover" then
			if subject == nil then
				return rejected(state, "relations_missing")
			end
			local refusal = evaluate(liveMembers, assert(subject), event.userId, nil)
			if refusal ~= nil then
				return rejected(state, refusal)
			end
			prune(state, nowSec, liveMembers)
			local index: number? = nil
			for position, ticket in state.tickets do
				if ticket.userId == event.userId then
					index = position
					break
				end
			end
			if index == nil then
				return rejected(state, "ticket_unknown")
			end
			if not authorityValid(groupAuthority, state.groupId, "recover", event.userId, event.userId, nowSec) then
				return rejected(state, "admission_denied")
			end
			table.remove(state.tickets, assert(SocialShape.number(index)))
			recoveredUserId = event.userId
		else
			prune(state, nowSec, liveMembers)
		end

		state.revision += 1
		state.lastClockSec = nowSec
		state.relationsReadAtSec = earliestRead(liveMembers, subject)
		state.receipts[event.eventId] = eventFingerprint
		return outcome({
			ok = true,
			state = state,
			replayed = false,
			reason = nil,
			recoveredUserId = recoveredUserId,
		})
	end

	GroupCore.SCHEMA_VERSION = SCHEMA_VERSION
	GroupCore.RECOVERY_TTL_SEC = RECOVERY_TTL_SEC
	GroupCore.RELATIONS_MAX_AGE_SEC = RELATIONS_MAX_AGE_SEC
	GroupCore.MAX_TICKETS = MAX_TICKETS
	GroupCore.MAX_ROSTER = MAX_ROSTER
	GroupCore.MAX_REVISION = MAX_REVISION
	GroupCore.MAX_TIME = MAX_TIME
	GroupCore.REASONS = freezeDeep(REASONS)

	return SocialShape.freezeDeep(GroupCore)
end

return System
