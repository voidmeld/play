--!strict

local SocialShape = require("./shape")

export type Founder = { userId: number, name: string }
export type State = {
	schemaVersion: number,
	formationId: string,
	fellowshipId: string,
	nameId: string,
	realmId: string,
	homeSlotId: string,
	initiatorId: number,
	expiresAtSec: number,
	founders: { Founder },
	invited: { number },
	feeCopper: number,
	feeState: string,
	phase: string,
	revision: number,
	lastClockSec: number,
	receipts: { [string]: string },
	receiptOrder: { string },
}
export type EventDraft = {
	kind: string,
	eventId: string?,
	expectedRevision: number?,
	actorUserId: number?,
	targetUserId: number?,
	targetRealmId: string?,
	actorRealmId: string?,
	actorName: string?,
}
export type Event = EventDraft & { eventId: string, expectedRevision: number }

export type StartRequest = {
	formationId: string,
	nameId: string,
	realmId: string,
	homeSlotId: string,
	initiatorId: number,
	initiatorName: string,
}

export type Result = { ok: boolean, state: State?, replayed: boolean, reason: string? }

export type Config = {
	requiredFounders: number,
	fee: number,
	formationTtlSec: number,
	maxReceipts: number,
	maxTime: number,
	maxNameLength: number,
	realms: { [string]: boolean },
	nameIds: { [string]: boolean },
	fellowshipPrefix: string,
	maxFormationId: number,
	maxId: number,
	maxRevision: number,
	maxFingerprint: number,
}

local System = {}

function System.formation(config: Config)
	local function readFounder(value: unknown): Founder?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { userId = true, name = true }) then
			return nil
		end
		local userId = SocialShape.number(raw.userId)
		if userId == nil then
			return nil
		end
		local name = SocialShape.string(raw.name)
		if name == nil then
			return nil
		end
		return { userId = userId, name = name }
	end

	local function readState(value: unknown): State?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				schemaVersion = true,
				formationId = true,
				fellowshipId = true,
				nameId = true,
				realmId = true,
				homeSlotId = true,
				initiatorId = true,
				expiresAtSec = true,
				founders = true,
				invited = true,
				feeCopper = true,
				feeState = true,
				phase = true,
				revision = true,
				lastClockSec = true,
				receipts = true,
				receiptOrder = true,
			})
		then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local formationId = SocialShape.string(raw.formationId)
		if formationId == nil then
			return nil
		end
		local fellowshipId = SocialShape.string(raw.fellowshipId)
		if fellowshipId == nil then
			return nil
		end
		local nameId = SocialShape.string(raw.nameId)
		if nameId == nil then
			return nil
		end
		local realmId = SocialShape.string(raw.realmId)
		if realmId == nil then
			return nil
		end
		local homeSlotId = SocialShape.string(raw.homeSlotId)
		if homeSlotId == nil then
			return nil
		end
		local initiatorId = SocialShape.number(raw.initiatorId)
		if initiatorId == nil then
			return nil
		end
		local expiresAtSec = SocialShape.number(raw.expiresAtSec)
		if expiresAtSec == nil then
			return nil
		end
		local founders = SocialShape.array(raw.founders, readFounder)
		if founders == nil then
			return nil
		end
		local invited = SocialShape.array(raw.invited, SocialShape.number)
		if invited == nil then
			return nil
		end
		local feeCopper = SocialShape.number(raw.feeCopper)
		if feeCopper == nil then
			return nil
		end
		local feeState = SocialShape.string(raw.feeState)
		if feeState == nil then
			return nil
		end
		local phase = SocialShape.string(raw.phase)
		if phase == nil then
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
		local receipts = SocialShape.map(raw.receipts, SocialShape.string, SocialShape.string)
		if receipts == nil then
			return nil
		end
		local receiptOrder = SocialShape.array(raw.receiptOrder, SocialShape.string)
		if receiptOrder == nil then
			return nil
		end
		return {
			schemaVersion = schemaVersion,
			formationId = formationId,
			fellowshipId = fellowshipId,
			nameId = nameId,
			realmId = realmId,
			homeSlotId = homeSlotId,
			initiatorId = initiatorId,
			expiresAtSec = expiresAtSec,
			founders = founders,
			invited = invited,
			feeCopper = feeCopper,
			feeState = feeState,
			phase = phase,
			revision = revision,
			lastClockSec = lastClockSec,
			receipts = receipts,
			receiptOrder = receiptOrder,
		}
	end

	local function readStartRequest(value: unknown): StartRequest?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				formationId = true,
				nameId = true,
				realmId = true,
				homeSlotId = true,
				initiatorId = true,
				initiatorName = true,
			})
		then
			return nil
		end
		local formationId = SocialShape.string(raw.formationId)
		if formationId == nil then
			return nil
		end
		local nameId = SocialShape.string(raw.nameId)
		if nameId == nil then
			return nil
		end
		local realmId = SocialShape.string(raw.realmId)
		if realmId == nil then
			return nil
		end
		local homeSlotId = SocialShape.string(raw.homeSlotId)
		if homeSlotId == nil then
			return nil
		end
		local initiatorId = SocialShape.number(raw.initiatorId)
		if initiatorId == nil then
			return nil
		end
		local initiatorName = SocialShape.string(raw.initiatorName)
		if initiatorName == nil then
			return nil
		end
		return {
			formationId = formationId,
			nameId = nameId,
			realmId = realmId,
			homeSlotId = homeSlotId,
			initiatorId = initiatorId,
			initiatorName = initiatorName,
		}
	end

	local SCHEMA_VERSION = 1
	local REQUIRED_FOUNDERS = config.requiredFounders
	local FEE_COPPER = config.fee
	local FORMATION_TTL_SEC = config.formationTtlSec
	local MAX_RECEIPTS = config.maxReceipts
	local MAX_TIME = config.maxTime
	local MAX_NAME_LENGTH = config.maxNameLength
	local REALMS = config.realms
	local NAME_IDS = config.nameIds
	local FEE_STATES = SocialShape.freezeDeep({ none = true, held = true, refunded = true, consumed = true })
	local PHASES = SocialShape.freezeDeep({ forming = true, completed = true, cancelled = true })

	local whole = SocialShape.whole
	local opaque = SocialShape.opaque
	local exact = SocialShape.exact
	local dense = SocialShape.dense
	local freezeDeep = SocialShape.freezeDeep

	local STATE_FIELDS = SocialShape.freezeDeep({
		schemaVersion = true,
		formationId = true,
		fellowshipId = true,
		nameId = true,
		realmId = true,
		homeSlotId = true,
		initiatorId = true,
		expiresAtSec = true,
		founders = true,
		invited = true,
		feeCopper = true,
		feeState = true,
		phase = true,
		revision = true,
		lastClockSec = true,
		receipts = true,
		receiptOrder = true,
	})

	local EVENT_FIELDS: { [string]: { [string]: boolean } } = SocialShape.freezeDeep({
		invite = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			targetUserId = true,
			targetRealmId = true,
		}),
		consent = SocialShape.freezeDeep({
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorUserId = true,
			actorRealmId = true,
			actorName = true,
		}),
		decline = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		withdraw = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		cancel = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		fee_held = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		fee_refunded = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true }),
		complete = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true, actorUserId = true }),
		sweep = SocialShape.freezeDeep({ kind = true, eventId = true, expectedRevision = true }),
	})

	local function founderIndex(state: State, userId: number): number?
		for index, founder in state.founders do
			if founder.userId == userId then
				return index
			end
		end
		return nil
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
			or not opaque(raw.formationId, config.maxId)
			or not opaque(raw.fellowshipId, config.maxId)
			or NAME_IDS[raw.nameId] ~= true
			or REALMS[raw.realmId] ~= true
			or not opaque(raw.homeSlotId, config.maxId)
			or not whole(raw.initiatorId, 1, MAX_TIME)
			or not whole(raw.expiresAtSec, 0, MAX_TIME)
			or raw.feeCopper ~= FEE_COPPER
			or FEE_STATES[raw.feeState] ~= true
			or PHASES[raw.phase] ~= true
			or not whole(raw.revision, 0, config.maxRevision)
			or not whole(raw.lastClockSec, 0, MAX_TIME)
			or dense(raw.founders, REQUIRED_FOUNDERS) == nil
			or dense(raw.invited, REQUIRED_FOUNDERS) == nil
			or dense(raw.receiptOrder, MAX_RECEIPTS) == nil
			or type(raw.receipts) ~= "table"
		then
			return nil
		end
		local founders: { Founder } = {}
		local seen: { [number]: boolean } = {}
		for _, founder in raw.founders do
			if
				not exact(founder, { userId = true, name = true })
				or not whole(founder.userId, 1, MAX_TIME)
				or not opaque(founder.name, MAX_NAME_LENGTH)
				or seen[founder.userId]
			then
				return nil
			end
			seen[founder.userId] = true
			founders[#founders + 1] = { userId = founder.userId, name = founder.name }
		end
		if #founders == 0 or founders[1].userId ~= raw.initiatorId then
			return nil
		end
		local invited: { number } = {}
		for _, userId in raw.invited do
			if not whole(userId, 1, MAX_TIME) or seen[userId] or #founders + #invited >= REQUIRED_FOUNDERS then
				return nil
			end
			seen[userId] = true
			invited[#invited + 1] = userId
		end
		if raw.phase == "completed" and (#founders ~= REQUIRED_FOUNDERS or raw.feeState ~= "consumed") then
			return nil
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
			formationId = raw.formationId,
			fellowshipId = raw.fellowshipId,
			nameId = raw.nameId,
			realmId = raw.realmId,
			homeSlotId = raw.homeSlotId,
			initiatorId = raw.initiatorId,
			expiresAtSec = raw.expiresAtSec,
			founders = founders,
			invited = invited,
			feeCopper = FEE_COPPER,
			feeState = assert(SocialShape.string(raw.feeState)),
			phase = assert(SocialShape.string(raw.phase)),
			revision = raw.revision,
			lastClockSec = raw.lastClockSec,
			receipts = receipts,
			receiptOrder = receiptOrder,
		}
	end

	local function outcome(value: Result): Result
		return SocialShape.freezeDeep(value)
	end

	local function rejected(state: State?, reason: string): Result
		return outcome({ ok = false, state = state, replayed = false, reason = reason })
	end

	local function fingerprint(event: SocialShape.Raw): string
		local parts = { event.kind, tostring(event.expectedRevision) }
		for _, key in { "actorUserId", "targetUserId", "targetRealmId", "actorRealmId" } do
			if assert(SocialShape.raw(event))[key] ~= nil then
				parts[#parts + 1] = key .. "=" .. tostring(assert(SocialShape.raw(event))[key])
			end
		end
		return table.concat(parts, "|")
	end

	local FellowshipFormationCore = {}

	function FellowshipFormationCore.start(request: unknown, nowSec: unknown): Result
		if
			not exact(request, {
				formationId = true,
				nameId = true,
				realmId = true,
				homeSlotId = true,
				initiatorId = true,
				initiatorName = true,
			}) or not whole(nowSec, 0, MAX_TIME)
		then
			return rejected(nil, "invalid_request")
		end
		local value = readStartRequest(request)
		if value == nil then
			return rejected(nil, "invalid_request")
		end
		if
			not opaque(value.formationId, config.maxFormationId)
			or NAME_IDS[value.nameId] ~= true
			or REALMS[value.realmId] ~= true
			or not opaque(value.homeSlotId, config.maxId)
			or not whole(value.initiatorId, 1, MAX_TIME)
			or not opaque(value.initiatorName, MAX_NAME_LENGTH)
		then
			return rejected(nil, "invalid_request")
		end
		return outcome({
			ok = true,
			state = {
				schemaVersion = SCHEMA_VERSION,
				formationId = value.formationId,
				fellowshipId = config.fellowshipPrefix .. value.formationId,
				nameId = value.nameId,
				realmId = value.realmId,
				homeSlotId = value.homeSlotId,
				initiatorId = value.initiatorId,
				expiresAtSec = (assert(SocialShape.number(nowSec))) + FORMATION_TTL_SEC,
				founders = { { userId = value.initiatorId, name = value.initiatorName } },
				invited = {},
				feeCopper = FEE_COPPER,
				feeState = "none",
				phase = "forming",
				revision = 0,
				lastClockSec = assert(SocialShape.number(nowSec)),
				receipts = {},
				receiptOrder = {},
			},
			replayed = false,
			reason = nil,
		})
	end

	function FellowshipFormationCore.projectState(value: unknown): State?
		local state = copyState(value)
		return if state == nil then nil else freezeDeep(state)
	end

	local function cancel(state: State)
		state.phase = "cancelled"
		state.invited = {}
	end

	function FellowshipFormationCore.transition(previous: unknown, eventValue: unknown, nowSecValue: unknown): Result
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
		local eventKind = event.kind
		if type(eventKind) ~= "string" then
			return rejected(state, "invalid_event")
		end
		local fields = EVENT_FIELDS[eventKind]
		if
			fields == nil
			or not exact(event, fields)
			or not opaque(event.eventId, config.maxId)
			or not whole(event.expectedRevision, 0, config.maxRevision)
			or not whole(nowSecValue, state.lastClockSec, MAX_TIME)
		then
			return rejected(state, "invalid_event")
		end
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
		local kind = event.kind
		local actor = event.actorUserId
		if kind == "fee_refunded" then
			if state.phase ~= "cancelled" or state.feeState ~= "held" then
				return rejected(state, "nothing_to_refund")
			end
			state.feeState = "refunded"
		elseif state.phase == "completed" then
			return rejected(state, "formation_closed")
		elseif state.phase == "cancelled" then
			return rejected(state, "formation_closed")
		elseif nowSec >= state.expiresAtSec and kind ~= "sweep" then
			cancel(state)
		elseif kind == "sweep" then
			if nowSec >= state.expiresAtSec then
				cancel(state)
			end
		elseif kind == "invite" then
			if actor ~= state.initiatorId then
				return rejected(state, "forged_membership")
			end
			if event.targetRealmId ~= state.realmId then
				return rejected(state, "realm_mismatch")
			end
			if not whole(event.targetUserId, 1, MAX_TIME) then
				return rejected(state, "invalid_event")
			end
			if
				founderIndex(state, assert(SocialShape.number(event.targetUserId))) ~= nil
				or table.find(state.invited, assert(SocialShape.number(event.targetUserId))) ~= nil
			then
				return rejected(state, "already_listed")
			end
			if #state.founders + #state.invited >= REQUIRED_FOUNDERS then
				return rejected(state, "formation_full")
			end
			state.invited[#state.invited + 1] = assert(SocialShape.number(event.targetUserId))
		elseif kind == "consent" then
			if not whole(actor, 1, MAX_TIME) or event.actorRealmId ~= state.realmId then
				return rejected(state, "realm_mismatch")
			end
			if not opaque(event.actorName, MAX_NAME_LENGTH) then
				return rejected(state, "invalid_event")
			end
			if founderIndex(state, assert(SocialShape.number(actor))) ~= nil then
				return rejected(state, "already_consented")
			end
			local index = table.find(state.invited, assert(SocialShape.number(actor)))
			if index == nil then
				return rejected(state, "invite_unknown")
			end
			table.remove(state.invited, index)
			state.founders[#state.founders + 1] =
				{ userId = assert(SocialShape.number(actor)), name = assert(SocialShape.string(event.actorName)) }
		elseif kind == "decline" then
			if not whole(actor, 1, MAX_TIME) or table.find(state.invited, assert(SocialShape.number(actor))) == nil then
				return rejected(state, "invite_unknown")
			end
			cancel(state)
		elseif kind == "withdraw" then
			if not whole(actor, 1, MAX_TIME) or founderIndex(state, assert(SocialShape.number(actor))) == nil then
				return rejected(state, "forged_membership")
			end
			cancel(state)
		elseif kind == "cancel" then
			if actor ~= state.initiatorId then
				return rejected(state, "forged_membership")
			end
			cancel(state)
		elseif kind == "fee_held" then
			if actor ~= state.initiatorId then
				return rejected(state, "forged_membership")
			end
			if state.feeState ~= "none" then
				return rejected(state, "fee_already_held")
			end
			state.feeState = "held"
		elseif kind == "complete" then
			if actor ~= state.initiatorId then
				return rejected(state, "forged_membership")
			end
			if #state.founders ~= REQUIRED_FOUNDERS then
				return rejected(state, "founders_missing")
			end
			if state.feeState ~= "held" then
				return rejected(state, "fee_unpaid")
			end
			state.phase = "completed"
			state.feeState = "consumed"
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

	FellowshipFormationCore.REQUIRED_FOUNDERS = REQUIRED_FOUNDERS
	FellowshipFormationCore.FEE_COPPER = FEE_COPPER
	FellowshipFormationCore.FORMATION_TTL_SEC = FORMATION_TTL_SEC

	return SocialShape.freezeDeep(FellowshipFormationCore)
end

return System
