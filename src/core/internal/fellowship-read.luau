--!strict

local SocialShape = require("../social/shape")

export type Member = { userId: number, joinedAtSec: number, name: string }
export type Invite = { userId: number, invitedByUserId: number, expiresAtSec: number }
export type Creed = { pursuits: { string }, pace: string, welcome: string }
export type CreedDraft = { pursuits: { string }?, pace: string?, welcome: string? }
type Founder = { userId: number, name: string }

export type FormationRequest = {
	fellowshipId: string,
	nameId: string,
	realmId: string,
	homeSlotId: string,
	founders: { { userId: number, name: string } },
}
export type Event = {
	kind: string,
	eventId: string,
	expectedRevision: number,
	actorUserId: number,
	targetUserId: number,
	targetRealmId: string,
	actorRealmId: string,
	actorName: string,
	pursuits: { string }?,
	pace: string,
	welcome: string,
}
export type EventDraft = {
	kind: string,
	eventId: string,
	expectedRevision: number,
	actorUserId: number,
	targetUserId: number?,
	pursuits: unknown,
	pace: unknown,
	welcome: unknown,
}
export type Audit = { kind: string, userId: number, fromUserId: number, atSec: number }
export type State = {
	schemaVersion: number,
	fellowshipId: string,
	nameId: string,
	realmId: string,
	homeSlotId: string,
	foundedAtSec: number,
	stewardUserId: number,
	members: { Member },
	invites: { Invite },
	officers: { number },
	stewardSeenAtSec: number,
	audit: { Audit },
	creed: CreedDraft,
	revision: number,
	lastClockSec: number,
	receipts: { [string]: string },
	receiptOrder: { string },
}
export type FoundRequest = {
	fellowshipId: string,
	nameId: string,
	realmId: string,
	homeSlotId: string,
	stewardUserId: number,
	stewardName: string,
}

export type Result = { ok: boolean, state: State?, replayed: boolean, reason: string? }

export type Config = {
	inviteTtlSec: number,
	maxMembers: number,
	maxOfficers: number,
	maxAudit: number,
	stewardAbsenceSec: number,
	maxInvites: number,
	maxReceipts: number,
	maxTime: number,
	maxNameLength: number,
	realms: { [string]: boolean },
	nameIds: { [string]: boolean },
	pursuits: { [string]: boolean },
	paces: { [string]: boolean },
	welcomes: { [string]: boolean },
	maxId: number,
	maxRevision: number,
	maxFingerprint: number,
	maxPursuits: number,
	requiredFounders: number,
}

local function readMember(value: unknown): Member?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if not SocialShape.onlyFields(value, { userId = true, joinedAtSec = true, name = true }) then
		return nil
	end
	local userId = SocialShape.number(raw.userId)
	local joinedAtSec = SocialShape.number(raw.joinedAtSec)
	local name = SocialShape.string(raw.name)
	if userId == nil or joinedAtSec == nil or name == nil then
		return nil
	end
	return { userId = userId, joinedAtSec = joinedAtSec, name = name }
end

local function readInvite(value: unknown): Invite?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if not SocialShape.onlyFields(value, { userId = true, invitedByUserId = true, expiresAtSec = true }) then
		return nil
	end
	local userId = SocialShape.number(raw.userId)
	local invitedByUserId = SocialShape.number(raw.invitedByUserId)
	local expiresAtSec = SocialShape.number(raw.expiresAtSec)
	if userId == nil or invitedByUserId == nil or expiresAtSec == nil then
		return nil
	end
	return { userId = userId, invitedByUserId = invitedByUserId, expiresAtSec = expiresAtSec }
end

local function readAudit(value: unknown): Audit?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if not SocialShape.onlyFields(value, { kind = true, userId = true, fromUserId = true, atSec = true }) then
		return nil
	end
	local kind = SocialShape.string(raw.kind)
	local userId = SocialShape.number(raw.userId)
	local fromUserId = SocialShape.number(raw.fromUserId)
	local atSec = SocialShape.number(raw.atSec)
	if kind == nil or userId == nil or fromUserId == nil or atSec == nil then
		return nil
	end
	return { kind = kind, userId = userId, fromUserId = fromUserId, atSec = atSec }
end

local function readCreedDraft(value: unknown): CreedDraft?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if not SocialShape.onlyFields(value, { pursuits = true, pace = true, welcome = true }) then
		return nil
	end
	local pursuits = SocialShape.array(raw.pursuits, SocialShape.string)
	if raw.pursuits ~= nil and pursuits == nil then
		return nil
	end
	local pace = SocialShape.string(raw.pace)
	if raw.pace ~= nil and pace == nil then
		return nil
	end
	local welcome = SocialShape.string(raw.welcome)
	if raw.welcome ~= nil and welcome == nil then
		return nil
	end
	return { pursuits = pursuits, pace = pace, welcome = welcome }
end

local function readState(value: unknown): State?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if
		not SocialShape.onlyFields(value, {
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
	then
		return nil
	end
	local schemaVersion = SocialShape.number(raw.schemaVersion)
	local fellowshipId = SocialShape.string(raw.fellowshipId)
	local nameId = SocialShape.string(raw.nameId)
	local realmId = SocialShape.string(raw.realmId)
	local homeSlotId = SocialShape.string(raw.homeSlotId)
	local foundedAtSec = SocialShape.number(raw.foundedAtSec)
	local stewardUserId = SocialShape.number(raw.stewardUserId)
	if
		schemaVersion == nil
		or fellowshipId == nil
		or nameId == nil
		or realmId == nil
		or homeSlotId == nil
		or foundedAtSec == nil
		or stewardUserId == nil
	then
		return nil
	end
	local members = SocialShape.array(raw.members, readMember)
	if members == nil then
		return nil
	end
	local invites = SocialShape.array(raw.invites, readInvite)
	if invites == nil then
		return nil
	end
	local officers = SocialShape.array(raw.officers, SocialShape.number)
	if officers == nil then
		return nil
	end
	local stewardSeenAtSec = SocialShape.number(raw.stewardSeenAtSec)
	if stewardSeenAtSec == nil then
		return nil
	end
	local audit = SocialShape.array(raw.audit, readAudit)
	if audit == nil then
		return nil
	end
	local creed = readCreedDraft(raw.creed)
	if creed == nil then
		return nil
	end
	local revision = SocialShape.number(raw.revision)
	local lastClockSec = SocialShape.number(raw.lastClockSec)
	if revision == nil or lastClockSec == nil then
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
		fellowshipId = fellowshipId,
		nameId = nameId,
		realmId = realmId,
		homeSlotId = homeSlotId,
		foundedAtSec = foundedAtSec,
		stewardUserId = stewardUserId,
		members = members,
		invites = invites,
		officers = officers,
		stewardSeenAtSec = stewardSeenAtSec,
		audit = audit,
		creed = creed,
		revision = revision,
		lastClockSec = lastClockSec,
		receipts = receipts,
		receiptOrder = receiptOrder,
	}
end

local function readFoundRequest(value: unknown): FoundRequest?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if
		not SocialShape.onlyFields(value, {
			fellowshipId = true,
			nameId = true,
			realmId = true,
			homeSlotId = true,
			stewardUserId = true,
			stewardName = true,
		})
	then
		return nil
	end
	local fellowshipId = SocialShape.string(raw.fellowshipId)
	local nameId = SocialShape.string(raw.nameId)
	local realmId = SocialShape.string(raw.realmId)
	local homeSlotId = SocialShape.string(raw.homeSlotId)
	local stewardUserId = SocialShape.number(raw.stewardUserId)
	local stewardName = SocialShape.string(raw.stewardName)
	if
		fellowshipId == nil
		or nameId == nil
		or realmId == nil
		or homeSlotId == nil
		or stewardUserId == nil
		or stewardName == nil
	then
		return nil
	end
	return {
		fellowshipId = fellowshipId,
		nameId = nameId,
		realmId = realmId,
		homeSlotId = homeSlotId,
		stewardUserId = stewardUserId,
		stewardName = stewardName,
	}
end

local function readFounder(value: unknown): Founder?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if not SocialShape.onlyFields(value, { userId = true, name = true }) then
		return nil
	end
	local userId = SocialShape.number(raw.userId)
	local name = SocialShape.string(raw.name)
	if userId == nil or name == nil then
		return nil
	end
	return { userId = userId, name = name }
end

local function readFormationRequest(value: unknown): FormationRequest?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if
		not SocialShape.onlyFields(
			value,
			{ fellowshipId = true, nameId = true, realmId = true, homeSlotId = true, founders = true }
		)
	then
		return nil
	end
	local fellowshipId = SocialShape.string(raw.fellowshipId)
	local nameId = SocialShape.string(raw.nameId)
	local realmId = SocialShape.string(raw.realmId)
	local homeSlotId = SocialShape.string(raw.homeSlotId)
	if fellowshipId == nil or nameId == nil or realmId == nil or homeSlotId == nil then
		return nil
	end
	local founders = SocialShape.array(raw.founders, readFounder)
	if founders == nil then
		return nil
	end
	return {
		fellowshipId = fellowshipId,
		nameId = nameId,
		realmId = realmId,
		homeSlotId = homeSlotId,
		founders = founders,
	}
end

return {
	readState = readState,
	readFoundRequest = readFoundRequest,
	readFormationRequest = readFormationRequest,
}
