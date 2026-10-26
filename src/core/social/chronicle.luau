--!strict

local SocialShape = require("./shape")

export type ActiveStatus = "Offered" | "Sworn" | "Witnessed" | "Contested"
export type TerminalStatus = "Fulfilled" | "Expired" | "Abandoned"

export type Definition = {
	id: string,
	witnessedOutcomeId: string,
	contestedOutcomeId: string,
	fulfilledOutcomeId: string,
	expiredOutcomeId: string,
	abandonedOutcomeId: string,
}

export type ActiveVow = {
	vowInstanceId: string,
	definitionId: string,
	holderCharacterId: string,
	counterpartCharacterId: string,
	status: ActiveStatus,
	offeredAtSec: number,
	swornAtSec: number?,
	expiresAtSec: number,
	witnessCharacterId: string?,
	outcomeId: string?,
}

export type Deed = {
	vowInstanceId: string,
	terminalEventId: string,
	definitionId: string,
	holderCharacterId: string,
	counterpartCharacterId: string,
	witnessCharacterId: string?,
	terminalStatus: TerminalStatus,
	outcomeId: string,
	terminalAtSec: number,
	terminalRevision: number,
	contributionReceiptId: string?,
}

export type State = {
	schemaVersion: number,
	characterId: string,
	revision: number,
	lastClockSec: number,
	active: ActiveVow?,
	chronicle: { Deed },
	receipts: { [string]: string },
}

type Fulfillment = {
	vowInstanceId: string,
	definitionId: string,
	outcomeId: string,
	contributionReceiptId: string,
	terminalRevision: number,
}
export type Applied = {
	ok: true,
	state: State,
	replayed: boolean,
	fulfillment: Fulfillment?,
}

export type Rejected = {
	ok: false,
	state: State?,
	reason: string,
}

export type Result = Applied | Rejected
type Raw = { [unknown]: unknown }
export type AccessPolicy = { allows: (string, string?, string, string, string?) -> unknown }
export type ContributionAuthority = { validate: (string, string, string, string, string?, string) -> unknown }
type EventCommon = {
	eventId: string,
	expectedRevision: number,
	actorCharacterId: string?,
}
type OfferEvent = EventCommon & {
	kind: "offer",
	vowInstanceId: string,
	definitionId: string,
	verdict: nil,
	contributionReceiptId: nil,
}
type WitnessEvent = EventCommon & {
	kind: "witness",
	vowInstanceId: nil,
	definitionId: nil,
	verdict: "witnessed" | "contested",
	contributionReceiptId: nil,
}
type FulfillEvent = EventCommon & {
	kind: "fulfill",
	vowInstanceId: nil,
	definitionId: nil,
	verdict: nil,
	contributionReceiptId: string,
}
type OtherEvent = EventCommon & {
	kind: "swear" | "expire" | "abandon",
	vowInstanceId: nil,
	definitionId: nil,
	verdict: nil,
	contributionReceiptId: nil,
}
export type Event = OfferEvent | WitnessEvent | FulfillEvent | OtherEvent

export type Config = {
	offerTtlSec: number,
	swornTtlSec: number,
	chronicleLimit: number,
	maxRevision: number,
	maxTime: number,
	maxId: number,
	maxCharacterId: number,
	maxFingerprint: number,
}

local System = {}

function System.chronicle(config: Config)
	local function readActiveStatus(value: unknown): ActiveStatus?
		return if value == "Offered"
				or value == "Sworn"
				or value == "Witnessed"
				or value == "Contested"
			then value
			else nil
	end
	local function readTerminalStatus(value: unknown): TerminalStatus?
		return if value == "Fulfilled" or value == "Expired" or value == "Abandoned" then value else nil
	end

	local function readDefinition(value: unknown): Definition?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				id = true,
				witnessedOutcomeId = true,
				contestedOutcomeId = true,
				fulfilledOutcomeId = true,
				expiredOutcomeId = true,
				abandonedOutcomeId = true,
			})
		then
			return nil
		end
		local id = SocialShape.string(raw.id)
		if id == nil then
			return nil
		end
		local witnessedOutcomeId = SocialShape.string(raw.witnessedOutcomeId)
		if witnessedOutcomeId == nil then
			return nil
		end
		local contestedOutcomeId = SocialShape.string(raw.contestedOutcomeId)
		if contestedOutcomeId == nil then
			return nil
		end
		local fulfilledOutcomeId = SocialShape.string(raw.fulfilledOutcomeId)
		if fulfilledOutcomeId == nil then
			return nil
		end
		local expiredOutcomeId = SocialShape.string(raw.expiredOutcomeId)
		if expiredOutcomeId == nil then
			return nil
		end
		local abandonedOutcomeId = SocialShape.string(raw.abandonedOutcomeId)
		if abandonedOutcomeId == nil then
			return nil
		end
		return {
			id = id,
			witnessedOutcomeId = witnessedOutcomeId,
			contestedOutcomeId = contestedOutcomeId,
			fulfilledOutcomeId = fulfilledOutcomeId,
			expiredOutcomeId = expiredOutcomeId,
			abandonedOutcomeId = abandonedOutcomeId,
		}
	end

	local function readActiveVow(value: unknown): ActiveVow?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				vowInstanceId = true,
				definitionId = true,
				holderCharacterId = true,
				counterpartCharacterId = true,
				status = true,
				offeredAtSec = true,
				swornAtSec = true,
				expiresAtSec = true,
				witnessCharacterId = true,
				outcomeId = true,
			})
		then
			return nil
		end
		local vowInstanceId = SocialShape.string(raw.vowInstanceId)
		if vowInstanceId == nil then
			return nil
		end
		local definitionId = SocialShape.string(raw.definitionId)
		if definitionId == nil then
			return nil
		end
		local holderCharacterId = SocialShape.string(raw.holderCharacterId)
		if holderCharacterId == nil then
			return nil
		end
		local counterpartCharacterId = SocialShape.string(raw.counterpartCharacterId)
		if counterpartCharacterId == nil then
			return nil
		end
		local status = readActiveStatus(raw.status)
		if status == nil then
			return nil
		end
		local offeredAtSec = SocialShape.number(raw.offeredAtSec)
		if offeredAtSec == nil then
			return nil
		end
		local swornAtSec = SocialShape.number(raw.swornAtSec)
		if raw.swornAtSec ~= nil and swornAtSec == nil then
			return nil
		end
		local expiresAtSec = SocialShape.number(raw.expiresAtSec)
		if expiresAtSec == nil then
			return nil
		end
		local witnessCharacterId = SocialShape.string(raw.witnessCharacterId)
		if raw.witnessCharacterId ~= nil and witnessCharacterId == nil then
			return nil
		end
		local outcomeId = SocialShape.string(raw.outcomeId)
		if raw.outcomeId ~= nil and outcomeId == nil then
			return nil
		end
		return {
			vowInstanceId = vowInstanceId,
			definitionId = definitionId,
			holderCharacterId = holderCharacterId,
			counterpartCharacterId = counterpartCharacterId,
			status = status,
			offeredAtSec = offeredAtSec,
			swornAtSec = swornAtSec,
			expiresAtSec = expiresAtSec,
			witnessCharacterId = witnessCharacterId,
			outcomeId = outcomeId,
		}
	end

	local function readDeed(value: unknown): Deed?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				vowInstanceId = true,
				terminalEventId = true,
				definitionId = true,
				holderCharacterId = true,
				counterpartCharacterId = true,
				witnessCharacterId = true,
				terminalStatus = true,
				outcomeId = true,
				terminalAtSec = true,
				terminalRevision = true,
				contributionReceiptId = true,
			})
		then
			return nil
		end
		local vowInstanceId = SocialShape.string(raw.vowInstanceId)
		if vowInstanceId == nil then
			return nil
		end
		local terminalEventId = SocialShape.string(raw.terminalEventId)
		if terminalEventId == nil then
			return nil
		end
		local definitionId = SocialShape.string(raw.definitionId)
		if definitionId == nil then
			return nil
		end
		local holderCharacterId = SocialShape.string(raw.holderCharacterId)
		if holderCharacterId == nil then
			return nil
		end
		local counterpartCharacterId = SocialShape.string(raw.counterpartCharacterId)
		if counterpartCharacterId == nil then
			return nil
		end
		local witnessCharacterId = SocialShape.string(raw.witnessCharacterId)
		if raw.witnessCharacterId ~= nil and witnessCharacterId == nil then
			return nil
		end
		local terminalStatus = readTerminalStatus(raw.terminalStatus)
		if terminalStatus == nil then
			return nil
		end
		local outcomeId = SocialShape.string(raw.outcomeId)
		if outcomeId == nil then
			return nil
		end
		local terminalAtSec = SocialShape.number(raw.terminalAtSec)
		if terminalAtSec == nil then
			return nil
		end
		local terminalRevision = SocialShape.number(raw.terminalRevision)
		if terminalRevision == nil then
			return nil
		end
		local contributionReceiptId = SocialShape.string(raw.contributionReceiptId)
		if raw.contributionReceiptId ~= nil and contributionReceiptId == nil then
			return nil
		end
		return {
			vowInstanceId = vowInstanceId,
			terminalEventId = terminalEventId,
			definitionId = definitionId,
			holderCharacterId = holderCharacterId,
			counterpartCharacterId = counterpartCharacterId,
			witnessCharacterId = witnessCharacterId,
			terminalStatus = terminalStatus,
			outcomeId = outcomeId,
			terminalAtSec = terminalAtSec,
			terminalRevision = terminalRevision,
			contributionReceiptId = contributionReceiptId,
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
				characterId = true,
				revision = true,
				lastClockSec = true,
				active = true,
				chronicle = true,
				receipts = true,
			})
		then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local characterId = SocialShape.string(raw.characterId)
		if characterId == nil then
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
		local active = readActiveVow(raw.active)
		if raw.active ~= nil and active == nil then
			return nil
		end
		local chronicle = SocialShape.array(raw.chronicle, readDeed)
		if chronicle == nil then
			return nil
		end
		local receipts = SocialShape.map(raw.receipts, SocialShape.string, SocialShape.string)
		if receipts == nil then
			return nil
		end
		return {
			schemaVersion = schemaVersion,
			characterId = characterId,
			revision = revision,
			lastClockSec = lastClockSec,
			active = active,
			chronicle = chronicle,
			receipts = receipts,
		}
	end

	local SCHEMA_VERSION = 1
	local OFFER_TTL_SEC = config.offerTtlSec
	local SWORN_TTL_SEC = config.swornTtlSec
	local CHRONICLE_LIMIT = config.chronicleLimit
	local MAX_REVISION = config.maxRevision
	local MAX_TIME = config.maxTime

	local STATE_FIELDS = {
		schemaVersion = true,
		characterId = true,
		revision = true,
		lastClockSec = true,
		active = true,
		chronicle = true,
		receipts = true,
	}

	local ACTIVE_FIELDS = {
		vowInstanceId = true,
		definitionId = true,
		holderCharacterId = true,
		counterpartCharacterId = true,
		status = true,
		offeredAtSec = true,
		swornAtSec = true,
		expiresAtSec = true,
		witnessCharacterId = true,
		outcomeId = true,
	}

	local DEED_FIELDS = {
		vowInstanceId = true,
		terminalEventId = true,
		definitionId = true,
		holderCharacterId = true,
		counterpartCharacterId = true,
		witnessCharacterId = true,
		terminalStatus = true,
		outcomeId = true,
		terminalAtSec = true,
		terminalRevision = true,
		contributionReceiptId = true,
	}

	local DEFINITION_FIELDS = {
		id = true,
		witnessedOutcomeId = true,
		contestedOutcomeId = true,
		fulfilledOutcomeId = true,
		expiredOutcomeId = true,
		abandonedOutcomeId = true,
	}

	local ACTIVE_STATUSES = { Offered = true, Sworn = true, Witnessed = true, Contested = true }
	local TERMINAL_STATUSES = { Fulfilled = true, Expired = true, Abandoned = true }

	local EVENT_FIELDS: { [string]: { [string]: boolean } } = {
		offer = {
			kind = true,
			eventId = true,
			expectedRevision = true,
			vowInstanceId = true,
			definitionId = true,
			actorCharacterId = true,
		},
		swear = { kind = true, eventId = true, expectedRevision = true, actorCharacterId = true },
		witness = {
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorCharacterId = true,
			verdict = true,
		},
		fulfill = {
			kind = true,
			eventId = true,
			expectedRevision = true,
			actorCharacterId = true,
			contributionReceiptId = true,
		},
		expire = { kind = true, eventId = true, expectedRevision = true },
		abandon = { kind = true, eventId = true, expectedRevision = true, actorCharacterId = true },
	}

	local whole = SocialShape.whole

	local opaqueId = SocialShape.opaque

	local function canonicalId(value: unknown): boolean
		if type(value) ~= "string" or #value == 0 or #value > config.maxId then
			return false
		end
		if string.sub(value, 1, 1) == "." or string.sub(value, -1) == "." or string.find(value, "..", 1, true) then
			return false
		end
		for segment in string.gmatch(value, "[^.]+") do
			if string.match(segment, "^[a-z][a-z0-9_-]*$") == nil then
				return false
			end
		end
		return true
	end

	local onlyFields = SocialShape.onlyFields
	local denseLength = SocialShape.denseLength

	local freezeDeep = SocialShape.freezeDeepWithKeys

	local function definitionIndex(value: unknown): { [string]: Definition }?
		local count = denseLength(value)
		if count == nil or count == 0 then
			return nil
		end
		local index: { [string]: Definition } = {}
		local identities: { [string]: boolean } = {}
		for _, valueRow in assert(SocialShape.raw(value)) do
			if not onlyFields(valueRow, DEFINITION_FIELDS) then
				return nil
			end
			local raw = readDefinition(valueRow)
			if raw == nil then
				return nil
			end
			local fields = {
				raw.id,
				raw.witnessedOutcomeId,
				raw.contestedOutcomeId,
				raw.fulfilledOutcomeId,
				raw.expiredOutcomeId,
				raw.abandonedOutcomeId,
			}
			for _, identity in fields do
				if not canonicalId(identity) or identities[assert(SocialShape.string(identity))] then
					return nil
				end
				identities[assert(SocialShape.string(identity))] = true
			end
			index[assert(SocialShape.string(raw.id))] = {
				id = assert(SocialShape.string(raw.id)),
				witnessedOutcomeId = assert(SocialShape.string(raw.witnessedOutcomeId)),
				contestedOutcomeId = assert(SocialShape.string(raw.contestedOutcomeId)),
				fulfilledOutcomeId = assert(SocialShape.string(raw.fulfilledOutcomeId)),
				expiredOutcomeId = assert(SocialShape.string(raw.expiredOutcomeId)),
				abandonedOutcomeId = assert(SocialShape.string(raw.abandonedOutcomeId)),
			}
		end
		return index
	end

	local function copyActive(
		value: unknown,
		definitions: { [string]: Definition },
		characterId: string,
		clock: number
	): ActiveVow?
		if not onlyFields(value, ACTIVE_FIELDS) then
			return nil
		end
		local raw = readActiveVow(value)
		if raw == nil then
			return nil
		end
		local definition = definitions[assert(SocialShape.string(raw.definitionId))]
		if
			definition == nil
			or not opaqueId(raw.vowInstanceId, config.maxId)
			or raw.holderCharacterId ~= characterId
			or not opaqueId(raw.counterpartCharacterId, config.maxCharacterId)
			or raw.counterpartCharacterId == characterId
			or ACTIVE_STATUSES[assert(SocialShape.string(raw.status))] ~= true
			or not whole(raw.offeredAtSec, 0, MAX_TIME)
			or not whole(raw.expiresAtSec, 0, MAX_TIME)
			or (assert(SocialShape.number(raw.offeredAtSec))) > clock
			or (assert(SocialShape.number(raw.expiresAtSec))) <= (assert(SocialShape.number(raw.offeredAtSec)))
		then
			return nil
		end
		if raw.status == "Offered" then
			if
				raw.swornAtSec ~= nil
				or raw.witnessCharacterId ~= nil
				or raw.outcomeId ~= nil
				or raw.expiresAtSec ~= (assert(SocialShape.number(raw.offeredAtSec))) + OFFER_TTL_SEC
			then
				return nil
			end
		else
			if
				not whole(raw.swornAtSec, 0, MAX_TIME)
				or (assert(SocialShape.number(raw.swornAtSec))) < (assert(SocialShape.number(raw.offeredAtSec)))
				or (assert(SocialShape.number(raw.swornAtSec))) > clock
				or raw.expiresAtSec ~= (assert(SocialShape.number(raw.swornAtSec))) + SWORN_TTL_SEC
			then
				return nil
			end
			if raw.status == "Sworn" then
				if raw.witnessCharacterId ~= nil or raw.outcomeId ~= nil then
					return nil
				end
			else
				if
					not opaqueId(raw.witnessCharacterId, config.maxCharacterId)
					or raw.witnessCharacterId == characterId
					or raw.witnessCharacterId == raw.counterpartCharacterId
				then
					return nil
				end
				local expected = if raw.status == "Witnessed"
					then definition.witnessedOutcomeId
					else definition.contestedOutcomeId
				if raw.outcomeId ~= expected then
					return nil
				end
			end
		end
		return {
			vowInstanceId = assert(SocialShape.string(raw.vowInstanceId)),
			definitionId = assert(SocialShape.string(raw.definitionId)),
			holderCharacterId = assert(SocialShape.string(raw.holderCharacterId)),
			counterpartCharacterId = assert(SocialShape.string(raw.counterpartCharacterId)),
			status = assert(raw.status),
			offeredAtSec = assert(SocialShape.number(raw.offeredAtSec)),
			swornAtSec = raw.swornAtSec,
			expiresAtSec = assert(SocialShape.number(raw.expiresAtSec)),
			witnessCharacterId = raw.witnessCharacterId,
			outcomeId = raw.outcomeId,
		}
	end

	local function copyDeed(value: unknown, definitions: { [string]: Definition }, characterId: string): Deed?
		if not onlyFields(value, DEED_FIELDS) then
			return nil
		end
		local raw = readDeed(value)
		if raw == nil then
			return nil
		end
		local definition = definitions[assert(SocialShape.string(raw.definitionId))]
		if
			definition == nil
			or not opaqueId(raw.vowInstanceId, config.maxId)
			or raw.holderCharacterId ~= characterId
			or not opaqueId(raw.counterpartCharacterId, config.maxCharacterId)
			or raw.counterpartCharacterId == characterId
			or TERMINAL_STATUSES[assert(SocialShape.string(raw.terminalStatus))] ~= true
			or not whole(raw.terminalAtSec, 0, MAX_TIME)
			or not whole(raw.terminalRevision, 1, MAX_REVISION)
		then
			return nil
		end
		local expectedOutcome = if raw.terminalStatus == "Fulfilled"
			then definition.fulfilledOutcomeId
			elseif raw.terminalStatus == "Expired" then definition.expiredOutcomeId
			else definition.abandonedOutcomeId
		if raw.outcomeId ~= expectedOutcome then
			return nil
		end
		if raw.witnessCharacterId ~= nil then
			if
				not opaqueId(raw.witnessCharacterId, config.maxCharacterId)
				or raw.witnessCharacterId == characterId
				or raw.witnessCharacterId == raw.counterpartCharacterId
			then
				return nil
			end
		end
		if raw.terminalStatus == "Fulfilled" then
			if raw.witnessCharacterId == nil or not opaqueId(raw.contributionReceiptId, config.maxId) then
				return nil
			end
		elseif raw.contributionReceiptId ~= nil then
			return nil
		end
		return {
			vowInstanceId = assert(SocialShape.string(raw.vowInstanceId)),
			definitionId = assert(SocialShape.string(raw.definitionId)),
			holderCharacterId = assert(SocialShape.string(raw.holderCharacterId)),
			counterpartCharacterId = assert(SocialShape.string(raw.counterpartCharacterId)),
			witnessCharacterId = raw.witnessCharacterId,
			terminalStatus = assert(raw.terminalStatus),
			outcomeId = assert(SocialShape.string(raw.outcomeId)),
			terminalAtSec = assert(SocialShape.number(raw.terminalAtSec)),
			terminalRevision = assert(SocialShape.number(raw.terminalRevision)),
			terminalEventId = assert(SocialShape.string(raw.terminalEventId)),
			contributionReceiptId = raw.contributionReceiptId,
		}
	end

	local function deedBefore(left: Deed, right: Deed): boolean
		if left.terminalAtSec ~= right.terminalAtSec then
			return left.terminalAtSec > right.terminalAtSec
		end
		if left.terminalRevision ~= right.terminalRevision then
			return left.terminalRevision > right.terminalRevision
		end
		return left.vowInstanceId < right.vowInstanceId
	end

	local function copyState(value: unknown, definitions: { [string]: Definition }): State?
		if not onlyFields(value, STATE_FIELDS) then
			return nil
		end
		local raw = readState(value)
		if raw == nil then
			return nil
		end
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or not opaqueId(raw.characterId, config.maxCharacterId)
			or not whole(raw.revision, 0, MAX_REVISION)
			or not whole(raw.lastClockSec, 0, MAX_TIME)
			or type(raw.receipts) ~= "table"
		then
			return nil
		end
		local receipts: { [string]: string } = {}
		for eventId, fingerprint in raw.receipts do
			if not opaqueId(eventId, config.maxId) or not opaqueId(fingerprint, config.maxFingerprint) then
				return nil
			end
			receipts[assert(SocialShape.string(eventId))] = assert(SocialShape.string(fingerprint))
		end
		local active: ActiveVow? = nil
		if raw.active ~= nil then
			active = copyActive(
				raw.active,
				definitions,
				assert(SocialShape.string(raw.characterId)),
				assert(SocialShape.number(raw.lastClockSec))
			)
			if active == nil then
				return nil
			end
		end
		local count = denseLength(raw.chronicle)
		if count == nil or count > CHRONICLE_LIMIT then
			return nil
		end
		local chronicle: { Deed } = {}
		local instanceIds: { [string]: boolean } = {}
		local terminalEventIds: { [string]: boolean } = {}
		local terminalRevisions: { [number]: boolean } = {}
		if active ~= nil then
			instanceIds[(assert(active)).vowInstanceId] = true
		end
		local prior: Deed? = nil
		for _, candidate in raw.chronicle do
			local deed = copyDeed(candidate, definitions, assert(SocialShape.string(raw.characterId)))
			if
				deed == nil
				or deed.terminalAtSec > (assert(SocialShape.number(raw.lastClockSec)))
				or deed.terminalRevision > (assert(SocialShape.number(raw.revision)))
				or instanceIds[deed.vowInstanceId]
				or terminalEventIds[deed.terminalEventId]
				or terminalRevisions[deed.terminalRevision]
				or (prior ~= nil and not deedBefore(assert(prior), deed))
			then
				return nil
			end
			instanceIds[deed.vowInstanceId] = true
			terminalEventIds[deed.terminalEventId] = true
			terminalRevisions[deed.terminalRevision] = true
			chronicle[#chronicle + 1] = deed
			prior = deed
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			characterId = assert(SocialShape.string(raw.characterId)),
			revision = assert(SocialShape.number(raw.revision)),
			lastClockSec = assert(SocialShape.number(raw.lastClockSec)),
			active = active,
			chronicle = chronicle,
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
			segment(event.vowInstanceId),
			segment(event.definitionId),
			segment(event.actorCharacterId),
			segment(event.verdict),
			segment(event.contributionReceiptId),
		})
	end

	local function validEvent(value: unknown): Event?
		local event = SocialShape.raw(value)
		if event == nil then
			return nil
		end
		local kind = event.kind
		local eventId, expectedRevision = SocialShape.string(event.eventId), SocialShape.number(event.expectedRevision)
		local actorCharacterId = SocialShape.string(event.actorCharacterId)
		if
			type(kind) ~= "string"
			or EVENT_FIELDS[kind] == nil
			or not onlyFields(value, EVENT_FIELDS[kind])
			or eventId == nil
			or not opaqueId(eventId, config.maxId)
			or expectedRevision == nil
			or not whole(expectedRevision, 0, MAX_REVISION)
			or (
				event.actorCharacterId ~= nil
				and (actorCharacterId == nil or not opaqueId(actorCharacterId, config.maxCharacterId))
			)
		then
			return nil
		end
		if kind == "offer" then
			local vowInstanceId, definitionId =
				SocialShape.string(event.vowInstanceId), SocialShape.string(event.definitionId)
			if
				vowInstanceId == nil
				or not opaqueId(vowInstanceId, config.maxId)
				or definitionId == nil
				or not canonicalId(definitionId)
			then
				return nil
			end
			return {
				kind = kind,
				eventId = eventId,
				expectedRevision = expectedRevision,
				actorCharacterId = actorCharacterId,
				vowInstanceId = vowInstanceId,
				definitionId = definitionId,
				verdict = nil,
				contributionReceiptId = nil,
			}
		elseif kind == "witness" then
			local verdict = event.verdict
			if verdict ~= "witnessed" and verdict ~= "contested" then
				return nil
			end
			return {
				kind = kind,
				eventId = eventId,
				expectedRevision = expectedRevision,
				actorCharacterId = actorCharacterId,
				verdict = verdict,
				vowInstanceId = nil,
				definitionId = nil,
				contributionReceiptId = nil,
			}
		elseif kind == "fulfill" then
			local receiptId = SocialShape.string(event.contributionReceiptId)
			if receiptId == nil or not opaqueId(receiptId, config.maxId) then
				return nil
			end
			return {
				kind = kind,
				eventId = eventId,
				expectedRevision = expectedRevision,
				actorCharacterId = actorCharacterId,
				contributionReceiptId = receiptId,
				vowInstanceId = nil,
				definitionId = nil,
				verdict = nil,
			}
		elseif kind == "swear" or kind == "expire" or kind == "abandon" then
			return {
				kind = kind,
				eventId = eventId,
				expectedRevision = expectedRevision,
				actorCharacterId = actorCharacterId,
				vowInstanceId = nil,
				definitionId = nil,
				verdict = nil,
				contributionReceiptId = nil,
			}
		end
		return nil
	end

	local function applied(value: Applied): Applied
		return freezeDeep(value)
	end
	local function rejection(value: Rejected): Rejected
		return freezeDeep(value)
	end

	local function rejected(state: State?, reason: string): Rejected
		if state ~= nil then
			freezeDeep(state)
		end
		return rejection({ ok = false, state = state, reason = reason })
	end

	local function policyAllows(policy: AccessPolicy?, action: string, actor: string?, active: ActiveVow): boolean
		if type(policy) ~= "table" or type(policy.allows) ~= "function" then
			return false
		end
		for key in assert(SocialShape.raw(policy)) do
			if key ~= "allows" then
				return false
			end
		end
		return policy.allows(
			action,
			actor,
			active.holderCharacterId,
			active.counterpartCharacterId,
			active.witnessCharacterId
		) == true
	end

	local function contributionValid(
		authority: ContributionAuthority?,
		receiptId: string,
		definition: Definition,
		active: ActiveVow
	): boolean
		if type(authority) ~= "table" or type(authority.validate) ~= "function" then
			return false
		end
		for key in assert(SocialShape.raw(authority)) do
			if key ~= "validate" then
				return false
			end
		end
		return authority.validate(
			receiptId,
			definition.id,
			active.holderCharacterId,
			active.counterpartCharacterId,
			active.witnessCharacterId,
			definition.fulfilledOutcomeId
		) == true
	end

	local function expiryDue(active: ActiveVow?, nowSec: number, eventKind: string): boolean
		return active ~= nil and nowSec >= active.expiresAtSec and eventKind ~= "expire"
	end

	local function terminalize(
		state: State,
		definition: Definition,
		status: TerminalStatus,
		nowSec: number,
		terminalEventId: string,
		contributionReceiptId: string?
	): Deed
		local active = assert(state.active)
		local outcomeId = if status == "Fulfilled"
			then definition.fulfilledOutcomeId
			elseif status == "Expired" then definition.expiredOutcomeId
			else definition.abandonedOutcomeId
		local deed = {
			vowInstanceId = active.vowInstanceId,
			terminalEventId = terminalEventId,
			definitionId = active.definitionId,
			holderCharacterId = active.holderCharacterId,
			counterpartCharacterId = active.counterpartCharacterId,
			witnessCharacterId = active.witnessCharacterId,
			terminalStatus = status,
			outcomeId = outcomeId,
			terminalAtSec = nowSec,
			terminalRevision = state.revision + 1,
			contributionReceiptId = contributionReceiptId,
		}
		state.chronicle[#state.chronicle + 1] = deed
		table.sort(state.chronicle, deedBefore)
		if #state.chronicle > CHRONICLE_LIMIT then
			table.remove(state.chronicle)
		end
		state.active = nil
		return deed
	end

	local VowChronicleCore = {}

	local function frozenState(value: State): State
		return freezeDeep(value)
	end

	function VowChronicleCore.emptyState(characterId: unknown): State?
		if not opaqueId(characterId, config.maxCharacterId) then
			return nil
		end
		return frozenState({
			schemaVersion = SCHEMA_VERSION,
			characterId = assert(SocialShape.string(characterId)),
			revision = 0,
			lastClockSec = 0,
			active = nil,
			chronicle = {},
			receipts = {},
		})
	end

	function VowChronicleCore.projectState(value: unknown, definitionsValue: unknown): State?
		local definitions = definitionIndex(definitionsValue)
		if definitions == nil then
			return nil
		end
		local state = copyState(value, definitions)
		if state == nil then
			return nil
		end
		return freezeDeep(state)
	end

	function VowChronicleCore.projectChronicle(
		value: unknown,
		definitionsValue: unknown,
		requesterCharacterId: unknown
	): { Deed }?
		local definitions = definitionIndex(definitionsValue)
		if definitions == nil then
			return nil
		end
		local state = copyState(value, definitions)
		if state == nil or requesterCharacterId ~= state.characterId then
			return nil
		end
		return freezeDeep(state.chronicle)
	end

	function VowChronicleCore.transition(
		previousStateValue: unknown,
		definitionsValue: unknown,
		eventValue: unknown,
		nowSecValue: unknown,
		accessPolicy: AccessPolicy?,
		contributionAuthority: ContributionAuthority?
	): Result
		local definitions = definitionIndex(definitionsValue)
		if definitions == nil then
			return rejected(nil, "invalid_catalog")
		end
		local state = copyState(previousStateValue, definitions)
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
		local eventFingerprint = fingerprint(event)
		local priorReceipt = state.receipts[event.eventId]
		if priorReceipt ~= nil then
			if priorReceipt ~= eventFingerprint then
				return rejected(state, "receipt_conflict")
			end
			local replayedFulfillment: Fulfillment? = nil
			if event.kind == "fulfill" then
				for _, deed in state.chronicle do
					if deed.terminalEventId == event.eventId and deed.terminalStatus == "Fulfilled" then
						replayedFulfillment = {
							vowInstanceId = deed.vowInstanceId,
							definitionId = deed.definitionId,
							outcomeId = deed.outcomeId,
							contributionReceiptId = assert(SocialShape.string(deed.contributionReceiptId)),
							terminalRevision = deed.terminalRevision,
						}
						break
					end
				end
				if replayedFulfillment == nil then
					return rejected(state, "receipt_state_mismatch")
				end
			end
			return applied({ ok = true, state = state, replayed = true, fulfillment = replayedFulfillment })
		end
		if event.expectedRevision ~= state.revision then
			return rejected(state, "revision_conflict")
		end
		if state.revision >= MAX_REVISION then
			return rejected(state, "revision_exhausted")
		end
		local active = state.active
		if expiryDue(active, nowSec, event.kind) then
			return rejected(state, "expiry_due")
		end
		local fulfillment: Fulfillment? = nil
		if event.kind == "offer" then
			if active ~= nil then
				return rejected(state, "active_vow_exists")
			end
			local definition = definitions[event.definitionId]
			if definition == nil or event.actorCharacterId == state.characterId then
				return rejected(state, "invalid_offer")
			end
			for _, deed in state.chronicle do
				if deed.vowInstanceId == event.vowInstanceId then
					return rejected(state, "vow_instance_reused")
				end
			end
			local expiresAtSec = nowSec + OFFER_TTL_SEC
			if expiresAtSec > MAX_TIME then
				return rejected(state, "invalid_clock")
			end
			local offered: ActiveVow = {
				vowInstanceId = event.vowInstanceId,
				definitionId = definition.id,
				holderCharacterId = state.characterId,
				counterpartCharacterId = assert(SocialShape.string(event.actorCharacterId)),
				status = "Offered",
				offeredAtSec = nowSec,
				swornAtSec = nil,
				expiresAtSec = expiresAtSec,
				witnessCharacterId = nil,
				outcomeId = nil,
			}
			if not policyAllows(accessPolicy, "offer", event.actorCharacterId, offered) then
				return rejected(state, "access_denied")
			end
			state.active = offered
		elseif active == nil then
			return rejected(state, "active_vow_missing")
		elseif event.kind == "swear" then
			if active.status ~= "Offered" or event.actorCharacterId ~= state.characterId then
				return rejected(state, "invalid_transition")
			end
			if not policyAllows(accessPolicy, "swear", event.actorCharacterId, active) then
				return rejected(state, "access_denied")
			end
			local expiresAtSec = nowSec + SWORN_TTL_SEC
			if expiresAtSec > MAX_TIME then
				return rejected(state, "invalid_clock")
			end
			active.status = "Sworn"
			active.swornAtSec = nowSec
			active.expiresAtSec = expiresAtSec
		elseif event.kind == "witness" then
			if
				active.status ~= "Sworn"
				or event.actorCharacterId == state.characterId
				or event.actorCharacterId == active.counterpartCharacterId
			then
				return rejected(state, "invalid_witness")
			end
			if not policyAllows(accessPolicy, "witness", event.actorCharacterId, active) then
				return rejected(state, "access_denied")
			end
			local definition = definitions[active.definitionId]
			active.status = if event.verdict == "witnessed" then "Witnessed" else "Contested"
			active.witnessCharacterId = event.actorCharacterId
			active.outcomeId = if event.verdict == "witnessed"
				then definition.witnessedOutcomeId
				else definition.contestedOutcomeId
		elseif event.kind == "fulfill" then
			if
				(active.status ~= "Witnessed" and active.status ~= "Contested")
				or event.actorCharacterId ~= state.characterId
			then
				return rejected(state, "invalid_transition")
			end
			if not policyAllows(accessPolicy, "fulfill", event.actorCharacterId, active) then
				return rejected(state, "access_denied")
			end
			local definition = definitions[active.definitionId]
			if not contributionValid(contributionAuthority, event.contributionReceiptId, definition, active) then
				return rejected(state, "contribution_denied")
			end
			local deed = terminalize(state, definition, "Fulfilled", nowSec, event.eventId, event.contributionReceiptId)
			fulfillment = {
				vowInstanceId = deed.vowInstanceId,
				definitionId = deed.definitionId,
				outcomeId = deed.outcomeId,
				contributionReceiptId = event.contributionReceiptId,
				terminalRevision = deed.terminalRevision,
			}
		elseif event.kind == "expire" then
			if nowSec < active.expiresAtSec then
				return rejected(state, "expiry_not_due")
			end
			terminalize(state, definitions[active.definitionId], "Expired", nowSec, event.eventId, nil)
		elseif event.kind == "abandon" then
			if event.actorCharacterId ~= state.characterId then
				return rejected(state, "invalid_transition")
			end
			if not policyAllows(accessPolicy, "abandon", event.actorCharacterId, active) then
				return rejected(state, "access_denied")
			end
			terminalize(state, definitions[active.definitionId], "Abandoned", nowSec, event.eventId, nil)
		else
			return rejected(state, "invalid_transition")
		end
		state.revision += 1
		state.lastClockSec = nowSec
		state.receipts[event.eventId] = eventFingerprint
		return applied({ ok = true, state = state, replayed = false, fulfillment = fulfillment })
	end

	VowChronicleCore.SCHEMA_VERSION = SCHEMA_VERSION
	VowChronicleCore.OFFER_TTL_SEC = OFFER_TTL_SEC
	VowChronicleCore.SWORN_TTL_SEC = SWORN_TTL_SEC
	VowChronicleCore.CHRONICLE_LIMIT = CHRONICLE_LIMIT
	VowChronicleCore.MAX_REVISION = MAX_REVISION
	VowChronicleCore.MAX_TIME = MAX_TIME

	return SocialShape.freezeDeep(VowChronicleCore)
end

return System
