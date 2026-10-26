--!strict

local Read = require("../internal/fellowship-read")
local SocialShape = require("./shape")

export type Member = Read.Member
export type Invite = Read.Invite
export type Creed = Read.Creed
export type CreedDraft = Read.CreedDraft
export type FormationRequest = Read.FormationRequest
export type Event = Read.Event
export type EventDraft = Read.EventDraft
export type Audit = Read.Audit
export type State = Read.State
export type FoundRequest = Read.FoundRequest
export type Result = Read.Result
export type Config = Read.Config

local System = {}

function System.fellowship(config: Config)
	local readState = Read.readState
	local readFoundRequest = Read.readFoundRequest
	local readFormationRequest = Read.readFormationRequest

	local function creedDraft(value: Creed): CreedDraft
		return { pursuits = value.pursuits, pace = value.pace, welcome = value.welcome }
	end

	local SCHEMA_VERSION = 4
	local INVITE_TTL_SEC = config.inviteTtlSec
	local MAX_MEMBERS = config.maxMembers
	local MAX_OFFICERS = config.maxOfficers
	local MAX_AUDIT = config.maxAudit
	local STEWARD_ABSENCE_SEC = config.stewardAbsenceSec
	local MAX_INVITES = config.maxInvites
	local MAX_RECEIPTS = config.maxReceipts
	local MAX_TIME = config.maxTime
	local MAX_NAME_LENGTH = config.maxNameLength
	local REALMS = config.realms
	local NAME_IDS = config.nameIds

	local PURSUITS = config.pursuits
	local PACES = config.paces
	local WELCOMES = config.welcomes

	local STATE_FIELDS = SocialShape.freezeDeep({
		schemaVersion = true,
		fellowshipId = true,
		nameId = true,
		realmId = true,
		homeSlotId = true,
		foundedAtSec = true,
		stewardUserId = true,
		members = true,
		invites = true,
		officers = true,
		stewardSeenAtSec = true,
		audit = true,
		creed = true,
		revision = true,
		lastClockSec = true,
		receipts = true,
		receiptOrder = true,
	})

	local EVENT_FIELDS: { [string]: { [string]: boolean } } = SocialShape.freezeDeep({
		creed = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			pursuits = true,
			pace = true,
			welcome = true,
		}),
		promote = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			targetUserId = true,
		}),
		demote = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			targetUserId = true,
		}),
		claim = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		seen = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		invite = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			targetUserId = true,
			targetRealmId = true,
		}),
		accept = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			actorRealmId = true,
			actorName = true,
		}),
		decline = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		leave = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		remove = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			targetUserId = true,
		}),
		transfer = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			targetUserId = true,
		}),
		sweep = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true }),
	})

	local whole = SocialShape.whole
	local opaque = SocialShape.opaque
	local exact = SocialShape.exact
	local dense = SocialShape.dense
	local freezeDeep = SocialShape.freezeDeep

	local function memberIndex(state: State, userId: number): number?
		for index, member in state.members do
			if member.userId == userId then
				return index
			end
		end
		return nil
	end

	local function inviteIndex(state: State, userId: number): number?
		for index, invite in state.invites do
			if invite.userId == userId then
				return index
			end
		end
		return nil
	end

	local FellowshipCore = {}

	function FellowshipCore.validCreed(pursuits: unknown, pace: unknown, welcome: unknown): Creed?
		if
			dense(pursuits, config.maxPursuits) == nil
			or #(assert(SocialShape.raw(pursuits))) < 1
			or type(pace) ~= "string"
			or PACES[pace] ~= true
			or type(welcome) ~= "string"
			or WELCOMES[welcome] ~= true
		then
			return nil
		end
		local chosen: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, id in assert(SocialShape.raw(pursuits)) do
			if type(id) ~= "string" or PURSUITS[id] ~= true or seen[id] then
				return nil
			end
			seen[id] = true
			chosen[#chosen + 1] = id
		end
		table.sort(chosen)
		return { pursuits = chosen, pace = pace, welcome = welcome }
	end

	local function copyState(value: unknown): State?
		if not exact(value, STATE_FIELDS) then
			return nil
		end
		local raw = readState(value)
		if raw == nil then
			return nil
		end
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or not opaque(raw.fellowshipId, config.maxId)
			or NAME_IDS[raw.nameId] ~= true
			or REALMS[raw.realmId] ~= true
			or not opaque(raw.homeSlotId, config.maxId)
			or not whole(raw.foundedAtSec, 0, MAX_TIME)
			or not whole(raw.stewardUserId, 1, MAX_TIME)
			or not whole(raw.revision, 0, config.maxRevision)
			or not whole(raw.lastClockSec, 0, MAX_TIME)
			or dense(raw.members, MAX_MEMBERS) == nil
			or dense(raw.invites, MAX_INVITES) == nil
			or dense(raw.receiptOrder, MAX_RECEIPTS) == nil
			or type(raw.receipts) ~= "table"
		then
			return nil
		end
		local members: { Member } = {}
		local seen: { [number]: boolean } = {}
		for _, member in raw.members do
			if
				not exact(member, { userId = true, joinedAtSec = true, name = true })
				or not whole(member.userId, 1, MAX_TIME)
				or not whole(member.joinedAtSec, 0, MAX_TIME)
				or not opaque(member.name, MAX_NAME_LENGTH)
				or seen[member.userId]
			then
				return nil
			end
			seen[member.userId] = true
			members[#members + 1] = { userId = member.userId, joinedAtSec = member.joinedAtSec, name = member.name }
		end
		if #members == 0 or not seen[raw.stewardUserId] then
			return nil
		end
		local officers: { number } = {}
		local audit: { Audit } = {}
		if
			dense(raw.officers, MAX_OFFICERS) == nil
			or dense(raw.audit, MAX_AUDIT) == nil
			or not whole(raw.stewardSeenAtSec, 0, MAX_TIME)
		then
			return nil
		end
		local listed: { [number]: boolean } = {}
		for _, userId in raw.officers do
			if not whole(userId, 1, MAX_TIME) or not seen[userId] or userId == raw.stewardUserId or listed[userId] then
				return nil
			end
			listed[userId] = true
			officers[#officers + 1] = userId
		end
		for _, entry in raw.audit do
			if
				not exact(entry, { kind = true, userId = true, fromUserId = true, atSec = true })
				or entry.kind ~= "claim"
				or not whole(entry.userId, 1, MAX_TIME)
				or not whole(entry.fromUserId, 1, MAX_TIME)
				or not whole(entry.atSec, 0, MAX_TIME)
			then
				return nil
			end
			audit[#audit + 1] =
				{ kind = entry.kind, userId = entry.userId, fromUserId = entry.fromUserId, atSec = entry.atSec }
		end
		if type(raw.creed) ~= "table" then
			return nil
		end
		local creed: CreedDraft = {}
		if next(assert(SocialShape.raw(raw.creed))) ~= nil then
			local read = FellowshipCore.validCreed(raw.creed.pursuits, raw.creed.pace, raw.creed.welcome)
			if read == nil or not exact(raw.creed, { pursuits = true, pace = true, welcome = true }) then
				return nil
			end
			creed = creedDraft(read)
		end
		local invites: { Invite } = {}
		for _, invite in raw.invites do
			if
				not exact(invite, { userId = true, invitedByUserId = true, expiresAtSec = true })
				or not whole(invite.userId, 1, MAX_TIME)
				or not whole(invite.invitedByUserId, 1, MAX_TIME)
				or not whole(invite.expiresAtSec, 0, MAX_TIME)
				or seen[invite.userId]
				or invite.userId == invite.invitedByUserId
			then
				return nil
			end
			invites[#invites + 1] = {
				userId = invite.userId,
				invitedByUserId = invite.invitedByUserId,
				expiresAtSec = invite.expiresAtSec,
			}
		end
		local receipts: { [string]: string } = {}
		local receiptOrder: { string } = {}
		for _, eventId in raw.receiptOrder do
			if
				not opaque(eventId, config.maxId)
				or receipts[eventId] ~= nil
				or not opaque(raw.receipts[eventId], config.maxFingerprint)
			then
				return nil
			end
			receipts[eventId] = raw.receipts[eventId]
			receiptOrder[#receiptOrder + 1] = eventId
		end
		for eventId in raw.receipts do
			if receipts[eventId] == nil then
				return nil
			end
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			fellowshipId = raw.fellowshipId,
			nameId = raw.nameId,
			realmId = raw.realmId,
			homeSlotId = raw.homeSlotId,
			foundedAtSec = raw.foundedAtSec,
			stewardUserId = raw.stewardUserId,
			members = members,
			invites = invites,
			officers = officers,
			stewardSeenAtSec = raw.stewardSeenAtSec,
			audit = audit,
			creed = creed,
			revision = raw.revision,
			lastClockSec = raw.lastClockSec,
			receipts = receipts,
			receiptOrder = receiptOrder,
		}
	end

	local function isOfficer(state: State, userId: number): boolean
		return table.find(state.officers, userId) ~= nil
	end

	local function dropOfficer(state: State, userId: number)
		local index = table.find(state.officers, userId)
		if index ~= nil then
			table.remove(state.officers, index)
		end
	end

	local outcome: (Result) -> Result = freezeDeep

	local function rejected(state: State?, reason: string): Result
		return outcome({ ok = false, state = state, replayed = false, reason = reason })
	end

	local function pruneInvites(state: State, nowSec: number)
		local kept: { Invite } = {}
		for _, invite in state.invites do
			if invite.expiresAtSec > nowSec then
				kept[#kept + 1] = invite
			end
		end
		state.invites = kept
	end

	local function fingerprint(event: SocialShape.Raw): string
		local parts = { event.kind, tostring(event.expectedRevision) }
		for _, key in { "actorUserId", "targetUserId", "targetRealmId", "actorRealmId", "pace", "welcome" } do
			if assert(SocialShape.raw(event))[key] ~= nil then
				parts[#parts + 1] = key .. "=" .. tostring(assert(SocialShape.raw(event))[key])
			end
		end
		if type(event.pursuits) == "table" then
			local listed = assert(SocialShape.array(event.pursuits, SocialShape.string))
			table.sort(listed)
			parts[#parts + 1] = "pursuits=" .. table.concat(listed, ",")
		end
		return table.concat(parts, "|")
	end

	function FellowshipCore.create(request: unknown, nowSec: unknown): Result
		if
			not exact(request, {
				fellowshipId = true,
				nameId = true,
				realmId = true,
				homeSlotId = true,
				stewardUserId = true,
				stewardName = true,
			}) or not whole(nowSec, 0, MAX_TIME)
		then
			return rejected(nil, "invalid_request")
		end
		local value = readFoundRequest(request)
		if value == nil then
			return rejected(nil, "invalid_request")
		end
		if
			not opaque(value.fellowshipId, config.maxId)
			or NAME_IDS[value.nameId] ~= true
			or REALMS[value.realmId] ~= true
			or not opaque(value.homeSlotId, config.maxId)
			or not whole(value.stewardUserId, 1, MAX_TIME)
			or not opaque(value.stewardName, MAX_NAME_LENGTH)
		then
			return rejected(nil, "invalid_request")
		end
		return outcome({
			ok = true,
			state = {
				schemaVersion = SCHEMA_VERSION,
				fellowshipId = value.fellowshipId,
				nameId = value.nameId,
				realmId = value.realmId,
				homeSlotId = value.homeSlotId,
				foundedAtSec = assert(SocialShape.number(nowSec)),
				stewardUserId = value.stewardUserId,
				members = {
					{
						userId = value.stewardUserId,
						joinedAtSec = assert(SocialShape.number(nowSec)),
						name = value.stewardName,
					},
				},
				invites = {},
				officers = {},
				stewardSeenAtSec = assert(SocialShape.number(nowSec)),
				audit = {},
				creed = {},
				revision = 0,
				lastClockSec = assert(SocialShape.number(nowSec)),
				receipts = {},
				receiptOrder = {},
			},
			replayed = false,
			reason = nil,
		})
	end

	function FellowshipCore.createFromFormation(request: unknown, nowSec: unknown): Result
		if
			not exact(request, {
				fellowshipId = true,
				nameId = true,
				realmId = true,
				homeSlotId = true,
				founders = true,
			}) or not whole(nowSec, 0, MAX_TIME)
		then
			return rejected(nil, "invalid_request")
		end
		local value = readFormationRequest(request)
		if value == nil then
			return rejected(nil, "invalid_request")
		end
		if dense(value.founders, config.requiredFounders) == nil or #value.founders ~= config.requiredFounders then
			return rejected(nil, "invalid_request")
		end
		local members: { Member } = {}
		local seen: { [number]: boolean } = {}
		for _, founder in value.founders do
			if
				not exact(founder, { userId = true, name = true })
				or not whole(founder.userId, 1, MAX_TIME)
				or not opaque(founder.name, MAX_NAME_LENGTH)
				or seen[founder.userId]
			then
				return rejected(nil, "invalid_request")
			end
			seen[founder.userId] = true
			members[#members + 1] =
				{ userId = founder.userId, joinedAtSec = assert(SocialShape.number(nowSec)), name = founder.name }
		end
		local created = FellowshipCore.create({
			fellowshipId = value.fellowshipId,
			nameId = value.nameId,
			realmId = value.realmId,
			homeSlotId = value.homeSlotId,
			stewardUserId = members[1].userId,
			stewardName = members[1].name,
		}, nowSec)
		if not created.ok or created.state == nil then
			return created
		end
		local state: State = table.clone(created.state)
		state.members = members
		return outcome({ ok = true, state = state, replayed = false, reason = nil })
	end

	function FellowshipCore.projectState(value: unknown): State?
		local state = copyState(value)
		return if state == nil then nil else freezeDeep(state)
	end

	function FellowshipCore.transition(previous: unknown, eventValue: unknown, nowSecValue: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return rejected(nil, "invalid_state")
		end
		if type(eventValue) ~= "table" or type((assert(SocialShape.raw(eventValue))).kind) ~= "string" then
			return rejected(state, "invalid_event")
		end
		local event = SocialShape.raw(eventValue)
		if event == nil then
			return rejected(state, "invalid_event")
		end
		local kind = event.kind
		if type(kind) ~= "string" then
			return rejected(state, "invalid_event")
		end
		local fields = EVENT_FIELDS[kind]
		if
			fields == nil
			or not exact(event, fields)
			or not opaque(event.eventId, config.maxId)
			or not whole(event.expectedRevision, 0, config.maxRevision)
			or not whole(nowSecValue, state.lastClockSec, MAX_TIME)
		then
			return rejected(state, "invalid_event")
		end
		local actor = SocialShape.number(event.actorUserId)
		local target = SocialShape.number(event.targetUserId)
		local actorName = SocialShape.string(event.actorName)
		local nowSec = assert(SocialShape.number(nowSecValue))
		local mark = fingerprint(event)
		local prior = state.receipts[assert(SocialShape.string(event.eventId))]
		if prior ~= nil then
			return if prior == mark
				then outcome({ ok = true, state = state, replayed = true, reason = nil })
				else rejected(state, "receipt_conflict")
		end
		if event.expectedRevision ~= state.revision then
			return rejected(state, "revision_conflict")
		end
		pruneInvites(state, nowSec)
		if event.kind == "invite" then
			if
				not whole(actor, 1, MAX_TIME)
				or not whole(target, 1, MAX_TIME)
				or (actor ~= state.stewardUserId and not isOfficer(state, assert(actor)))
			then
				return rejected(state, "forged_membership")
			end
			if event.targetRealmId ~= state.realmId then
				return rejected(state, "realm_mismatch")
			end
			if memberIndex(state, assert(target)) ~= nil then
				return rejected(state, "already_member")
			end
			if inviteIndex(state, assert(target)) == nil then
				if #state.invites >= MAX_INVITES or #state.members >= MAX_MEMBERS then
					return rejected(state, "fellowship_full")
				end
				state.invites[#state.invites + 1] = {
					userId = assert(target),
					invitedByUserId = assert(actor),
					expiresAtSec = nowSec + INVITE_TTL_SEC,
				}
			end
		elseif event.kind == "accept" then
			if not whole(actor, 1, MAX_TIME) or event.actorRealmId ~= state.realmId then
				return rejected(state, "realm_mismatch")
			end
			if not opaque(actorName, MAX_NAME_LENGTH) then
				return rejected(state, "invalid_event")
			end
			local index = inviteIndex(state, assert(actor))
			if index == nil then
				return rejected(state, "invite_unknown")
			end
			table.remove(state.invites, assert(SocialShape.number(index)))
			state.members[#state.members + 1] =
				{ userId = assert(actor), joinedAtSec = nowSec, name = assert(actorName) }
		elseif event.kind == "decline" then
			local index = if whole(actor, 1, MAX_TIME) then inviteIndex(state, assert(actor)) else nil
			if index == nil then
				return rejected(state, "invite_unknown")
			end
			table.remove(state.invites, assert(SocialShape.number(index)))
		elseif event.kind == "leave" then
			local index = if whole(actor, 1, MAX_TIME) then memberIndex(state, assert(actor)) else nil
			if index == nil then
				return rejected(state, "forged_membership")
			end
			if #state.members == 1 then
				return rejected(state, "last_member")
			end
			table.remove(state.members, assert(SocialShape.number(index)))
			dropOfficer(state, assert(actor))
			if actor == state.stewardUserId then
				local successor = state.members[1].userId
				for _, member in state.members do
					if isOfficer(state, member.userId) then
						successor = member.userId
						break
					end
				end
				state.stewardUserId = successor
				dropOfficer(state, successor)
				state.stewardSeenAtSec = nowSec
			end
		elseif event.kind == "remove" or event.kind == "transfer" then
			local actorIsSteward = actor == state.stewardUserId
			local targetIndex = if whole(target, 1, MAX_TIME) then memberIndex(state, assert(target)) else nil
			if
				not actorIsSteward
				and (event.kind == "transfer" or not whole(actor, 1, MAX_TIME) or not isOfficer(state, assert(actor)))
			then
				return rejected(state, "forged_membership")
			end
			if targetIndex == nil or target == state.stewardUserId then
				return rejected(state, "target_invalid")
			end
			if event.kind == "remove" then
				if not actorIsSteward and isOfficer(state, assert(target)) then
					return rejected(state, "target_invalid")
				end
				table.remove(state.members, assert(SocialShape.number(targetIndex)))
				dropOfficer(state, assert(target))
			else
				dropOfficer(state, assert(target))
				state.stewardUserId = assert(target)
				state.stewardSeenAtSec = nowSec
			end
		elseif event.kind == "promote" or event.kind == "demote" then
			if actor ~= state.stewardUserId then
				return rejected(state, "forged_membership")
			end
			local targetIndex = if whole(target, 1, MAX_TIME) then memberIndex(state, assert(target)) else nil
			if targetIndex == nil or target == state.stewardUserId then
				return rejected(state, "target_invalid")
			end
			if event.kind == "promote" then
				if isOfficer(state, assert(target)) then
					return rejected(state, "already_officer")
				end
				if #state.officers >= MAX_OFFICERS then
					return rejected(state, "officers_full")
				end
				state.officers[#state.officers + 1] = assert(target)
			else
				if not isOfficer(state, assert(target)) then
					return rejected(state, "not_officer")
				end
				dropOfficer(state, assert(target))
			end
		elseif event.kind == "creed" then
			if
				not whole(actor, 1, MAX_TIME)
				or (actor ~= state.stewardUserId and not isOfficer(state, assert(actor)))
			then
				return rejected(state, "forged_membership")
			end
			local creed = FellowshipCore.validCreed(event.pursuits, event.pace, event.welcome)
			if creed == nil then
				return rejected(state, "creed_invalid")
			end
			state.creed = creedDraft(creed)
		elseif event.kind == "seen" then
			if actor ~= state.stewardUserId then
				return rejected(state, "forged_membership")
			end
			state.stewardSeenAtSec = nowSec
		elseif event.kind == "claim" then
			if not whole(actor, 1, MAX_TIME) or not isOfficer(state, assert(actor)) then
				return rejected(state, "forged_membership")
			end
			if nowSec - state.stewardSeenAtSec < STEWARD_ABSENCE_SEC then
				return rejected(state, "steward_present")
			end
			local fromUserId = state.stewardUserId
			dropOfficer(state, assert(actor))
			state.stewardUserId = assert(actor)
			state.stewardSeenAtSec = nowSec
			state.audit[#state.audit + 1] =
				{ kind = "claim", userId = assert(actor), fromUserId = fromUserId, atSec = nowSec }
			if #state.audit > MAX_AUDIT then
				table.remove(state.audit, 1)
			end
		end
		if event.kind ~= "claim" and event.kind ~= "leave" and actor == state.stewardUserId then
			state.stewardSeenAtSec = nowSec
		end
		state.revision += 1
		state.lastClockSec = nowSec
		state.receipts[assert(SocialShape.string(event.eventId))] = mark
		state.receiptOrder[#state.receiptOrder + 1] = assert(SocialShape.string(event.eventId))
		if #state.receiptOrder > MAX_RECEIPTS then
			local evicted = table.remove(state.receiptOrder, 1)
			if evicted ~= nil then
				state.receipts[evicted] = nil
			end
		end
		return outcome({ ok = true, state = state, replayed = false, reason = nil })
	end

	FellowshipCore.SCHEMA_VERSION = SCHEMA_VERSION
	FellowshipCore.INVITE_TTL_SEC = INVITE_TTL_SEC
	FellowshipCore.MAX_MEMBERS = MAX_MEMBERS
	FellowshipCore.PURSUITS = PURSUITS
	FellowshipCore.PACES = PACES
	FellowshipCore.WELCOMES = WELCOMES
	FellowshipCore.MAX_OFFICERS = MAX_OFFICERS
	FellowshipCore.STEWARD_ABSENCE_SEC = STEWARD_ABSENCE_SEC
	FellowshipCore.MAX_NAME_LENGTH = MAX_NAME_LENGTH
	FellowshipCore.NAME_IDS = NAME_IDS
	FellowshipCore.REALMS = REALMS

	return SocialShape.freezeDeep(FellowshipCore)
end

return System
