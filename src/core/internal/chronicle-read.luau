--!strict

local SocialShape = require("../social/shape")

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

export type Fulfillment = {
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

local function readActiveStatus(value: unknown): ActiveStatus?
	return if value == "Offered" or value == "Sworn" or value == "Witnessed" or value == "Contested" then value else nil
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
	local witnessedOutcomeId = SocialShape.string(raw.witnessedOutcomeId)
	local contestedOutcomeId = SocialShape.string(raw.contestedOutcomeId)
	local fulfilledOutcomeId = SocialShape.string(raw.fulfilledOutcomeId)
	local expiredOutcomeId = SocialShape.string(raw.expiredOutcomeId)
	local abandonedOutcomeId = SocialShape.string(raw.abandonedOutcomeId)
	if
		id == nil
		or witnessedOutcomeId == nil
		or contestedOutcomeId == nil
		or fulfilledOutcomeId == nil
		or expiredOutcomeId == nil
		or abandonedOutcomeId == nil
	then
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
	local definitionId = SocialShape.string(raw.definitionId)
	local holderCharacterId = SocialShape.string(raw.holderCharacterId)
	local counterpartCharacterId = SocialShape.string(raw.counterpartCharacterId)
	local status = readActiveStatus(raw.status)
	local offeredAtSec = SocialShape.number(raw.offeredAtSec)
	if
		vowInstanceId == nil
		or definitionId == nil
		or holderCharacterId == nil
		or counterpartCharacterId == nil
		or status == nil
		or offeredAtSec == nil
	then
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
	local terminalEventId = SocialShape.string(raw.terminalEventId)
	local definitionId = SocialShape.string(raw.definitionId)
	local holderCharacterId = SocialShape.string(raw.holderCharacterId)
	local counterpartCharacterId = SocialShape.string(raw.counterpartCharacterId)
	if
		vowInstanceId == nil
		or terminalEventId == nil
		or definitionId == nil
		or holderCharacterId == nil
		or counterpartCharacterId == nil
	then
		return nil
	end
	local witnessCharacterId = SocialShape.string(raw.witnessCharacterId)
	if raw.witnessCharacterId ~= nil and witnessCharacterId == nil then
		return nil
	end
	local terminalStatus = readTerminalStatus(raw.terminalStatus)
	local outcomeId = SocialShape.string(raw.outcomeId)
	local terminalAtSec = SocialShape.number(raw.terminalAtSec)
	local terminalRevision = SocialShape.number(raw.terminalRevision)
	if terminalStatus == nil or outcomeId == nil or terminalAtSec == nil or terminalRevision == nil then
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
	local characterId = SocialShape.string(raw.characterId)
	local revision = SocialShape.number(raw.revision)
	local lastClockSec = SocialShape.number(raw.lastClockSec)
	if schemaVersion == nil or characterId == nil or revision == nil or lastClockSec == nil then
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

return {
	readDefinition = readDefinition,
	readActiveVow = readActiveVow,
	readDeed = readDeed,
	readState = readState,
}
