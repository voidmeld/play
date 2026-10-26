--!strict

local SocialShape = require("./shape")

export type QualificationKind = string

export type Entry = {
	allyUserId: number,
	qualificationKind: QualificationKind,
	qualificationReceiptId: string,
	lastQualifiedAtSec: number,
	expiresAtSec: number,
}

export type State = {
	schemaVersion: number,
	userId: number,
	revision: number,
	lastClockSec: number,
	policyRevision: number,
	entries: { Entry },
	receipts: { [string]: string },
}

type PolicyFlags = {
	revision: number,
	ownerOptedOut: boolean,
	ownerModerationEligible: boolean,
}

export type Policy = PolicyFlags & {
	blockedUserIds: { number },
	optedOutUserIds: { number },
	moderationDeniedUserIds: { number },
}

export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
}

type Raw = { [unknown]: unknown }
export type QualifyEvent = {
	kind: "qualify",
	eventId: string,
	expectedRevision: number,
	allyUserId: number,
	qualificationKind: QualificationKind,
	qualificationReceiptId: string,
}
export type ReconcileEvent = {
	kind: "reconcile",
	eventId: string,
	expectedRevision: number,
	allyUserId: nil,
	qualificationKind: nil,
	qualificationReceiptId: nil,
}
export type Event = QualifyEvent | ReconcileEvent
export type Authority = { validate: (string, QualificationKind, number, number, number) -> unknown }
export type Config = {
	retentionSec: number,
	maxAllies: number,
	maxRevision: number,
	maxTime: number,
	maxId: number,
	maxFingerprint: number,
	qualificationKinds: { [string]: boolean },
}

local System = {}

function System.allies(config: Config)
	local function readEntry(value: unknown): Entry?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				allyUserId = true,
				qualificationKind = true,
				qualificationReceiptId = true,
				lastQualifiedAtSec = true,
				expiresAtSec = true,
			})
		then
			return nil
		end
		local allyUserId = SocialShape.number(raw.allyUserId)
		if allyUserId == nil then
			return nil
		end
		local qualificationKind = SocialShape.string(raw.qualificationKind)
		if qualificationKind == nil then
			return nil
		end
		local qualificationReceiptId = SocialShape.string(raw.qualificationReceiptId)
		if qualificationReceiptId == nil then
			return nil
		end
		local lastQualifiedAtSec = SocialShape.number(raw.lastQualifiedAtSec)
		if lastQualifiedAtSec == nil then
			return nil
		end
		local expiresAtSec = SocialShape.number(raw.expiresAtSec)
		if expiresAtSec == nil then
			return nil
		end
		return {
			allyUserId = allyUserId,
			qualificationKind = qualificationKind,
			qualificationReceiptId = qualificationReceiptId,
			lastQualifiedAtSec = lastQualifiedAtSec,
			expiresAtSec = expiresAtSec,
		}
	end

	local function readState(value: unknown): State?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				schemaVersion = true,
				userId = true,
				revision = true,
				lastClockSec = true,
				policyRevision = true,
				entries = true,
				receipts = true,
			})
		then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local userId = SocialShape.number(raw.userId)
		if userId == nil then
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
		local policyRevision = SocialShape.number(raw.policyRevision)
		if policyRevision == nil then
			return nil
		end
		local entries = SocialShape.array(raw.entries, readEntry)
		if entries == nil then
			return nil
		end
		local receipts = SocialShape.map(raw.receipts, SocialShape.string, SocialShape.string)
		if receipts == nil then
			return nil
		end
		return {
			schemaVersion = schemaVersion,
			userId = userId,
			revision = revision,
			lastClockSec = lastClockSec,
			policyRevision = policyRevision,
			entries = entries,
			receipts = receipts,
		}
	end

	local function readPolicy(value: unknown): Policy?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				revision = true,
				ownerOptedOut = true,
				ownerModerationEligible = true,
				blockedUserIds = true,
				optedOutUserIds = true,
				moderationDeniedUserIds = true,
			})
		then
			return nil
		end
		local revision = SocialShape.number(raw.revision)
		if revision == nil then
			return nil
		end
		local ownerOptedOut = SocialShape.boolean(raw.ownerOptedOut)
		if ownerOptedOut == nil then
			return nil
		end
		local ownerModerationEligible = SocialShape.boolean(raw.ownerModerationEligible)
		if ownerModerationEligible == nil then
			return nil
		end
		local blockedUserIds = SocialShape.array(raw.blockedUserIds, SocialShape.number)
		if blockedUserIds == nil then
			return nil
		end
		local optedOutUserIds = SocialShape.array(raw.optedOutUserIds, SocialShape.number)
		if optedOutUserIds == nil then
			return nil
		end
		local moderationDeniedUserIds = SocialShape.array(raw.moderationDeniedUserIds, SocialShape.number)
		if moderationDeniedUserIds == nil then
			return nil
		end
		return {
			revision = revision,
			ownerOptedOut = ownerOptedOut,
			ownerModerationEligible = ownerModerationEligible,
			blockedUserIds = blockedUserIds,
			optedOutUserIds = optedOutUserIds,
			moderationDeniedUserIds = moderationDeniedUserIds,
		}
	end

	local SCHEMA_VERSION = 1
	local RETENTION_SEC = config.retentionSec
	local MAX_ALLIES = config.maxAllies
	local MAX_REVISION = config.maxRevision
	local MAX_TIME = config.maxTime

	local QUALIFICATION_KINDS = config.qualificationKinds

	local STATE_FIELDS = {
		schemaVersion = true,
		userId = true,
		revision = true,
		lastClockSec = true,
		policyRevision = true,
		entries = true,
		receipts = true,
	}

	local ENTRY_FIELDS = {
		allyUserId = true,
		qualificationKind = true,
		qualificationReceiptId = true,
		lastQualifiedAtSec = true,
		expiresAtSec = true,
	}

	local POLICY_FIELDS = {
		revision = true,
		ownerOptedOut = true,
		ownerModerationEligible = true,
		blockedUserIds = true,
		optedOutUserIds = true,
		moderationDeniedUserIds = true,
	}

	local EVENT_FIELDS: { [string]: { [string]: boolean } } = {
		qualify = {
			kind = true,
			eventId = true,
			expectedRevision = true,
			allyUserId = true,
			qualificationKind = true,
			qualificationReceiptId = true,
		},
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

	local function entryBefore(left: Entry, right: Entry): boolean
		if left.lastQualifiedAtSec ~= right.lastQualifiedAtSec then
			return left.lastQualifiedAtSec > right.lastQualifiedAtSec
		end
		return left.allyUserId < right.allyUserId
	end

	local function copyEntry(value: unknown): Entry?
		local raw = readEntry(value)
		if raw == nil then
			return nil
		end
		if
			not onlyFields(raw, ENTRY_FIELDS)
			or not positiveUserId(raw.allyUserId)
			or QUALIFICATION_KINDS[raw.qualificationKind] ~= true
			or not opaqueId(raw.qualificationReceiptId, config.maxId)
			or not whole(raw.lastQualifiedAtSec, 0, MAX_TIME)
			or not whole(raw.expiresAtSec, 0, MAX_TIME)
			or raw.expiresAtSec ~= raw.lastQualifiedAtSec + RETENTION_SEC
		then
			return nil
		end
		return {
			allyUserId = raw.allyUserId,
			qualificationKind = raw.qualificationKind,
			qualificationReceiptId = raw.qualificationReceiptId,
			lastQualifiedAtSec = raw.lastQualifiedAtSec,
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
			or not positiveUserId(raw.userId)
			or not whole(raw.revision, 0, MAX_REVISION)
			or not whole(raw.lastClockSec, 0, MAX_TIME)
			or not whole(raw.policyRevision, 0, MAX_REVISION)
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
		local count = denseLength(raw.entries)
		if count == nil or count > MAX_ALLIES then
			return nil
		end
		local entries: { Entry } = {}
		local seen: { [number]: boolean } = {}
		local prior: Entry? = nil
		for _, candidate in raw.entries do
			local entry = copyEntry(candidate)
			if
				entry == nil
				or entry.allyUserId == raw.userId
				or entry.lastQualifiedAtSec > raw.lastClockSec
				or seen[entry.allyUserId]
				or (prior ~= nil and not entryBefore(assert(prior), entry))
			then
				return nil
			end
			seen[entry.allyUserId] = true
			entries[#entries + 1] = entry
			prior = entry
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			userId = raw.userId,
			revision = raw.revision,
			lastClockSec = raw.lastClockSec,
			policyRevision = raw.policyRevision,
			entries = entries,
			receipts = receipts,
		}
	end

	local function denySortedUserIds(value: unknown, denied: { [number]: boolean }): boolean
		local count = denseLength(value)
		if count == nil then
			return false
		end
		local previous = 0
		for _, userId in assert(SocialShape.array(value, SocialShape.number)) do
			if not positiveUserId(userId) or userId <= previous then
				return false
			end
			denied[userId] = true
			previous = userId
		end
		return true
	end

	local function copyPolicy(value: unknown): (PolicyFlags?, { [number]: boolean }?)
		if not onlyFields(value, POLICY_FIELDS) then
			return nil, nil
		end
		local raw = readPolicy(value)
		if raw == nil then
			return nil, nil
		end
		if
			not whole(raw.revision, 0, MAX_REVISION)
			or type(raw.ownerOptedOut) ~= "boolean"
			or type(raw.ownerModerationEligible) ~= "boolean"
		then
			return nil, nil
		end
		local denied: { [number]: boolean } = {}
		local blocked = denySortedUserIds(raw.blockedUserIds, denied)
		local optedOut = denySortedUserIds(raw.optedOutUserIds, denied)
		local moderationDenied = denySortedUserIds(raw.moderationDeniedUserIds, denied)
		if not blocked or not optedOut or not moderationDenied then
			return nil, nil
		end
		return {
			revision = raw.revision,
			ownerOptedOut = raw.ownerOptedOut,
			ownerModerationEligible = raw.ownerModerationEligible,
		},
			denied
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
			segment(event.allyUserId),
			segment(event.qualificationKind),
			segment(event.qualificationReceiptId),
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
			return { kind = "reconcile", eventId = eventId, expectedRevision = expectedRevision }
		end
		if kind ~= "qualify" then
			return nil
		end
		local allyUserId = SocialShape.number(event.allyUserId)
		local qualificationKind = SocialShape.string(event.qualificationKind)
		local qualificationReceiptId = SocialShape.string(event.qualificationReceiptId)
		if
			allyUserId == nil
			or not positiveUserId(allyUserId)
			or qualificationKind == nil
			or QUALIFICATION_KINDS[qualificationKind] ~= true
			or qualificationReceiptId == nil
			or not opaqueId(qualificationReceiptId, config.maxId)
		then
			return nil
		end
		return {
			kind = "qualify",
			eventId = eventId,
			expectedRevision = expectedRevision,
			allyUserId = allyUserId,
			qualificationKind = qualificationKind,
			qualificationReceiptId = qualificationReceiptId,
		}
	end

	local function prune(state: State, nowSec: number, policy: PolicyFlags, denied: { [number]: boolean })
		local entries: { Entry } = {}
		if not policy.ownerOptedOut and policy.ownerModerationEligible then
			for _, entry in state.entries do
				if nowSec < entry.expiresAtSec and not denied[entry.allyUserId] then
					entries[#entries + 1] = entry
				end
			end
		end
		state.entries = entries
		state.policyRevision = policy.revision
	end

	local function authorityValid(
		authority: Authority?,
		event: QualifyEvent,
		ownerUserId: number,
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
		return validate(event.qualificationReceiptId, event.qualificationKind, ownerUserId, event.allyUserId, nowSec)
			== true
	end

	local function outcome(value: Result): Result
		return SocialShape.freezeDeep(value)
	end

	local function rejected(state: State?, reason: string): Result
		if state ~= nil then
			freezeDeep(state)
		end
		return outcome({ ok = false, state = state, replayed = false, reason = reason })
	end

	local RecentAlliesCore = {}

	function RecentAlliesCore.emptyState(userId: unknown): State?
		if not positiveUserId(userId) then
			return nil
		end
		return freezeDeep({
			schemaVersion = SCHEMA_VERSION,
			userId = assert(SocialShape.number(userId)),
			revision = 0,
			lastClockSec = 0,
			policyRevision = 0,
			entries = {},
			receipts = {},
		})
	end

	function RecentAlliesCore.projectState(value: unknown): State?
		local state = copyState(value)
		if state == nil then
			return nil
		end
		return freezeDeep(state)
	end

	function RecentAlliesCore.projectPrivate(
		value: unknown,
		policyValue: unknown,
		requesterUserId: unknown,
		nowSecValue: unknown
	): { Entry }?
		local state = copyState(value)
		local policy, denied = copyPolicy(policyValue)
		if
			state == nil
			or policy == nil
			or denied == nil
			or requesterUserId ~= state.userId
			or policy.revision < state.policyRevision
			or not whole(nowSecValue, 0, MAX_TIME)
			or (assert(SocialShape.number(nowSecValue))) < state.lastClockSec
		then
			return nil
		end
		prune(state, assert(SocialShape.number(nowSecValue)), policy, denied)
		return freezeDeep(state.entries)
	end

	function RecentAlliesCore.transition(
		previousStateValue: unknown,
		eventValue: unknown,
		nowSecValue: unknown,
		policyValue: unknown,
		qualificationAuthority: Authority?
	): Result
		local state = copyState(previousStateValue)
		if state == nil then
			return rejected(nil, "invalid_state")
		end
		local event = validEvent(eventValue)
		if event == nil then
			return rejected(state, "invalid_event")
		end
		local policy, denied = copyPolicy(policyValue)
		if policy == nil or denied == nil then
			return rejected(state, "invalid_policy")
		end
		if policy.revision < state.policyRevision then
			return rejected(state, "stale_policy")
		end
		if not whole(nowSecValue, 0, MAX_TIME) or (assert(SocialShape.number(nowSecValue))) < state.lastClockSec then
			return rejected(state, "invalid_clock")
		end
		local nowSec = assert(SocialShape.number(nowSecValue))
		local eventFingerprint = fingerprint(event)
		local priorReceipt = state.receipts[event.eventId]
		if priorReceipt ~= nil then
			if priorReceipt ~= eventFingerprint then
				return rejected(state, "receipt_conflict")
			end
			return outcome({ ok = true, state = state, replayed = true, reason = nil })
		end
		if event.expectedRevision ~= state.revision then
			return rejected(state, "revision_conflict")
		end
		if state.revision >= MAX_REVISION then
			return rejected(state, "revision_exhausted")
		end
		if event.kind == "qualify" then
			if
				policy.ownerOptedOut
				or not policy.ownerModerationEligible
				or event.allyUserId == state.userId
				or denied[event.allyUserId]
			then
				return rejected(state, "privacy_denied")
			end
			if not authorityValid(qualificationAuthority, event, state.userId, nowSec) then
				return rejected(state, "qualification_denied")
			end
			local expiresAtSec = nowSec + RETENTION_SEC
			if expiresAtSec > MAX_TIME then
				return rejected(state, "invalid_clock")
			end
			prune(state, nowSec, policy, denied)
			local target = #state.entries + 1
			for index, entry in state.entries do
				if entry.allyUserId == event.allyUserId then
					target = index
					break
				end
			end
			state.entries[target] = {
				allyUserId = event.allyUserId,
				qualificationKind = event.qualificationKind,
				qualificationReceiptId = event.qualificationReceiptId,
				lastQualifiedAtSec = nowSec,
				expiresAtSec = expiresAtSec,
			}
			table.sort(state.entries, entryBefore)
			if #state.entries > MAX_ALLIES then
				table.remove(state.entries)
			end
		else
			prune(state, nowSec, policy, denied)
		end
		state.revision += 1
		state.lastClockSec = nowSec
		state.policyRevision = policy.revision
		state.receipts[event.eventId] = eventFingerprint
		return outcome({ ok = true, state = state, replayed = false, reason = nil })
	end

	RecentAlliesCore.SCHEMA_VERSION = SCHEMA_VERSION
	RecentAlliesCore.RETENTION_SEC = RETENTION_SEC
	RecentAlliesCore.MAX_ALLIES = MAX_ALLIES
	RecentAlliesCore.MAX_REVISION = MAX_REVISION
	RecentAlliesCore.MAX_TIME = MAX_TIME
	RecentAlliesCore.QUALIFICATION_KINDS = QUALIFICATION_KINDS

	return SocialShape.freezeDeep(RecentAlliesCore)
end

return System
