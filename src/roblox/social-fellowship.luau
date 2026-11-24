--!strict

local FellowshipTypes = require("../core/social/fellowship")
local GroupCoreTypes = require("../core/social/group")
local Homes = require("../core/social/guildhome")
local RecordsTypes = require("./social-records")
local SocialHost = require("./social-host")
local Value = require("../kernel/value")
local Views = require("./internal/social-views")

export type BankMembership = { fellowshipId: string, role: "member" | "steward", memberIds: { number } }
export type FellowshipMemberView = Views.FellowshipMemberView
export type StewardAuditView = Views.StewardAuditView
export type PendingFellowshipInviteView = Views.PendingFellowshipInviteView
export type FellowshipView = Views.FellowshipView

type RecordService = RecordsTypes.Service
type Membership = RecordsTypes.Membership
type FellowshipState = FellowshipTypes.State
export type FellowshipResponse = {
	read ok: boolean,
	read state: FellowshipState?,
	read replayed: boolean,
	read reason: string?,
}
export type Dependencies = {
	read fellowshipRecords: RecordService?,
	read realmFor: (number) -> string?,
	read clock: () -> number,
	read guildHomeCatalog: (() -> unknown)?,
	read relationsFor: ((number, { number }, number) -> GroupCoreTypes.Relations?)?,
}

export type Service = {
	read createFellowship: (number, string) -> FellowshipResponse,
	read fellowshipInvite: (number, number) -> FellowshipResponse,
	read pendingFellowshipInvite: (number) -> PendingFellowshipInviteView | false,
	read answerFellowshipInvite: (number, boolean) -> FellowshipResponse,
	read fellowshipMemberIntent: (number, string, number?, unknown?) -> FellowshipResponse,
	read bankMembership: (number, boolean) -> (BankMembership?, string?),
	read fellowshipProjection: (number) -> FellowshipView | false,
	read fellowshipAudience: (number) -> { number },
	read fellowshipNoticed: (string) -> { number },
	read fellowshipSeen: (number) -> FellowshipResponse,
	read fellowshipSettle: (number) -> string?,
	read fellowshipEnsureSettled: (number) -> (),
	read forgetPlayer: (number) -> (),
}

export type Config = {
	read slots: (unknown) -> { Homes.Slot }?,
	read slotFor: (unknown, unknown) -> Homes.Slot?,
	read admit: (unknown, unknown, unknown, GroupCoreTypes.Authority?) -> GroupCoreTypes.Decision,
	read visibleRoster: (unknown, unknown, unknown) -> { number }?,
	read inviteTtlSec: number,
	read stewardAbsenceSec: number,
	read seenRefreshSec: number,
	read fellowshipId: (string) -> string,
	read memberFallback: (number) -> string,
}
export type API = {
	read create: (Dependencies, SocialHost.Host, (number) -> string?, () -> string, (string) -> ()) -> Service,
}
local function configure(config: Config): API
	config = table.freeze(table.clone(config))
	for _, value in { config.inviteTtlSec, config.stewardAbsenceSec, config.seenRefreshSec } do
		assert(Value.finite(value) and value > 0, "invalid fellowship lifetime")
	end
	local GuildHomeCore = { slots = config.slots, slotFor = config.slotFor }
	local GroupCore = { admit = config.admit, visibleRoster = config.visibleRoster }
	local FellowshipCore = { INVITE_TTL_SEC = config.inviteTtlSec, STEWARD_ABSENCE_SEC = config.stewardAbsenceSec }
	local FELLOWSHIP_SEEN_REFRESH_SEC = config.seenRefreshSec
	local HasMetatable = { fields = Value.raw }

	local function create(
		deps: Dependencies,
		host: SocialHost.Host,
		memberNameFor: (number) -> string?,
		newEventId: () -> string,
		notifyFellowship: (string) -> ()
	): Service
		local pendingGuildInviteByUser: { [number]: { fellowshipId: string, invitedByUserId: number, expiresAtSec: number } } =
			{}
		local reconciledUsers: { [number]: boolean } = {}
		local function unavailable(): RecordsTypes.Refusal
			return { ok = false, state = nil, replayed = false, reason = "fellowship_unavailable" }
		end
		local serially = host.serially
		local loadRecord = host.loadRecord
		local isMember = host.isMember
		local membershipOf = host.membershipOf
		local settle = host.settle
		local settleUnlessBusy = host.settleUnlessBusy
		local commitRecord = host.commitRecord
		local claimThenCommit = host.claimThenCommit
		local function homeLabel(slotId: string): string?
			local slots = if deps.guildHomeCatalog ~= nil then GuildHomeCore.slots(deps.guildHomeCatalog()) else nil
			for _, slot in (slots or {}) do
				if slot.id == slotId then
					return slot.label
				end
			end
			return nil
		end

		local function createFellowship(actorUserId: number, nameId: string): FellowshipResponse
			if deps.fellowshipRecords == nil then
				return unavailable()
			end
			return serially(actorUserId, function(): FellowshipResponse
				local realmId = deps.realmFor(actorUserId)
				local name = memberNameFor(actorUserId)
				if realmId == nil or name == nil then
					return { ok = false, state = nil, replayed = false, reason = "creation_denied" }
				end
				if settle(actorUserId) ~= nil then
					return { ok = false, state = nil, replayed = false, reason = "creation_denied" }
				end
				local slot = if deps.guildHomeCatalog ~= nil
					then GuildHomeCore.slotFor(deps.guildHomeCatalog(), realmId)
					else nil
				if slot == nil then
					return { ok = false, state = nil, replayed = false, reason = "charter_requires_home_hub" }
				end
				local fellowshipId = config.fellowshipId(newEventId())
				return claimThenCommit(actorUserId, fellowshipId, function()
					local result = assert(deps.fellowshipRecords).found({
						fellowshipId = fellowshipId,
						nameId = nameId,
						realmId = realmId,
						homeSlotId = slot.id,
						stewardUserId = actorUserId,
						stewardName = name,
					})
					if result.ok then
						host.remember(result.state)
					end
					return result
				end)
			end)
		end

		local function relationsFor(userId: number, others: { number }, nowSec: number): GroupCoreTypes.Relations?
			if deps.relationsFor == nil then
				return nil
			end
			return deps.relationsFor(userId, others, nowSec)
		end

		local function fellowshipInvite(actorUserId: number, targetUserId: number): FellowshipResponse
			if deps.fellowshipRecords == nil then
				return unavailable()
			end
			return serially(actorUserId, function(): FellowshipResponse
				local fellowshipId = settle(actorUserId)
				if fellowshipId == nil then
					return { ok = false, state = nil, replayed = false, reason = "fellowship_unknown" }
				end
				local outcome = loadRecord(fellowshipId, true)
				if not outcome.ok then
					return outcome
				end
				local state = outcome.state
				if deps.realmFor(targetUserId) ~= state.realmId then
					return { ok = false, state = state, replayed = false, reason = "realm_mismatch" }
				end
				local nowSec = deps.clock()
				local memberRelations: { GroupCoreTypes.Relations } = {}
				local memberIds: { number } = {}
				for _, member in state.members do
					memberIds[#memberIds + 1] = member.userId
					local relations = relationsFor(member.userId, { targetUserId }, nowSec)
					if relations ~= nil then
						memberRelations[#memberRelations + 1] = relations
					end
				end
				local decision = GroupCore.admit(
					{
						members = memberRelations,
						subject = relationsFor(targetUserId, memberIds, nowSec),
					},
					{
						groupId = state.fellowshipId,
						inviterUserId = actorUserId,
						candidateUserId = targetUserId,
					},
					nowSec,
					{
						validate = function(
							groupId: string,
							operation: string,
							inviter: number,
							candidate: number,
							_at: number
						): boolean
							return groupId == state.fellowshipId
								and operation == "admit"
								and (inviter == state.stewardUserId or table.find(state.officers, inviter) ~= nil)
								and deps.realmFor(inviter) == state.realmId
								and deps.realmFor(candidate) == state.realmId
						end,
					}
				)
				if not decision.ok then
					local refused: FellowshipResponse = {
						ok = false,
						state = state,
						replayed = false,
						reason = decision.reason,
					}
					return refused
				end
				local result = commitRecord(state.fellowshipId, {
					kind = "invite",
					eventId = newEventId(),
					expectedRevision = state.revision,
					actorUserId = actorUserId,
					targetUserId = targetUserId,
					targetRealmId = state.realmId,
				})
				if result.ok then
					pendingGuildInviteByUser[targetUserId] = {
						fellowshipId = state.fellowshipId,
						invitedByUserId = actorUserId,
						expiresAtSec = nowSec + FellowshipCore.INVITE_TTL_SEC,
					}
				end
				return result
			end)
		end

		local function pendingFellowshipInvite(actorUserId: number): PendingFellowshipInviteView | false
			local pending = pendingGuildInviteByUser[actorUserId]
			if pending == nil then
				return false
			end
			if pending.expiresAtSec <= deps.clock() then
				pendingGuildInviteByUser[actorUserId] = nil
				return false
			end
			local state = host.cachedRecord(pending.fellowshipId)
			local view: PendingFellowshipInviteView = {
				fellowshipId = pending.fellowshipId,
				nameId = if state ~= nil then state.nameId else false,
				creed = if state ~= nil and next(assert(HasMetatable.fields(state.creed))) ~= nil
					then state.creed
					else false,
				inviterDisplayName = memberNameFor(pending.invitedByUserId)
					or config.memberFallback(pending.invitedByUserId),
			}
			return table.freeze(view)
		end

		local function answerFellowshipInvite(actorUserId: number, accept: boolean): FellowshipResponse
			if deps.fellowshipRecords == nil then
				return unavailable()
			end
			return serially(actorUserId, function(): FellowshipResponse
				if pendingFellowshipInvite(actorUserId) == false then
					return { ok = false, state = nil, replayed = false, reason = "invite_unknown" }
				end
				local pending = pendingGuildInviteByUser[actorUserId]
				local outcome = loadRecord(pending.fellowshipId, true)
				if not outcome.ok then
					return outcome
				end
				local result: FellowshipResponse
				if accept then
					local name = memberNameFor(actorUserId)
					if name == nil or settle(actorUserId) ~= nil then
						return { ok = false, state = outcome.state, replayed = false, reason = "already_member" }
					end
					result = claimThenCommit(actorUserId, pending.fellowshipId, function()
						return commitRecord(pending.fellowshipId, {
							kind = "accept",
							eventId = newEventId(),
							expectedRevision = outcome.state.revision,
							actorUserId = actorUserId,
							actorRealmId = deps.realmFor(actorUserId),
							actorName = name,
						})
					end)
				else
					result = commitRecord(pending.fellowshipId, {
						kind = "decline",
						eventId = newEventId(),
						expectedRevision = outcome.state.revision,
						actorUserId = actorUserId,
					})
				end
				if result.ok or result.reason == "invite_unknown" then
					pendingGuildInviteByUser[actorUserId] = nil
				end
				if result.ok then
					notifyFellowship(pending.fellowshipId)
				end
				return result
			end)
		end

		local function fellowshipMemberIntent(
			actorUserId: number,
			kind: string,
			targetUserId: number?,
			extra: unknown
		): FellowshipResponse
			if deps.fellowshipRecords == nil then
				return unavailable()
			end
			return serially(actorUserId, function(): FellowshipResponse
				local fellowshipId = settle(actorUserId)
				if fellowshipId == nil then
					return { ok = false, state = nil, replayed = false, reason = "fellowship_unknown" }
				end
				local outcome = loadRecord(fellowshipId, true)
				if not outcome.ok then
					return outcome
				end
				local event: FellowshipTypes.EventDraft = {
					kind = kind,
					eventId = newEventId(),
					expectedRevision = outcome.state.revision,
					actorUserId = actorUserId,
				}
				if kind ~= "leave" and kind ~= "claim" and kind ~= "seen" and kind ~= "creed" then
					event.targetUserId = targetUserId
				end
				if kind == "creed" and type(extra) == "table" then
					local creed = assert(HasMetatable.fields(extra))
					event.pursuits, event.pace, event.welcome = creed.pursuits, creed.pace, creed.welcome
				end
				local result = commitRecord(fellowshipId, event)
				if not result.ok then
					return result
				end
				if kind == "leave" then
					settle(actorUserId)
				elseif kind == "remove" and targetUserId ~= nil and deps.realmFor(targetUserId) ~= nil then
					settleUnlessBusy(targetUserId)
				end
				notifyFellowship(fellowshipId)
				return result
			end)
		end

		local function bankMembership(userId: number, fresh: boolean): (BankMembership?, string?)
			if deps.fellowshipRecords == nil then
				return nil, "guild_bank_unavailable"
			end
			local membership: Membership? = nil
			if fresh then
				local outcome = assert(deps.fellowshipRecords).readMembership(userId)
				if not outcome.ok then
					return nil, "guild_bank_unavailable"
				end
				host.adopt(userId, outcome.membership)
				membership = outcome.membership
			else
				membership = membershipOf(userId, false)
			end
			if membership == nil then
				return nil, "fellowship_unknown"
			end
			local record = loadRecord(membership.fellowshipId, fresh)
			if not record.ok and fresh then
				return nil, "guild_bank_unavailable"
			end
			local state = record.state
			if
				not record.ok
				or state == nil
				or not isMember(state, userId)
				or deps.realmFor(userId) ~= state.realmId
			then
				return nil, "fellowship_unknown"
			end
			local memberIds: { number } = {}
			for _, member in state.members do
				memberIds[#memberIds + 1] = member.userId
			end
			return {
				fellowshipId = state.fellowshipId,
				role = if state.stewardUserId == userId then "steward" else "member",
				memberIds = memberIds,
			},
				nil
		end

		local function fellowshipProjection(viewerUserId: number): FellowshipView | false
			local membership = membershipOf(viewerUserId, false)
			if membership == nil then
				return false
			end
			local outcome = loadRecord(membership.fellowshipId, false)
			if
				not outcome.ok
				or outcome.state == nil
				or not isMember(outcome.state, viewerUserId)
				or deps.realmFor(viewerUserId) ~= outcome.state.realmId
			then
				return false
			end
			local state: FellowshipState = outcome.state
			local rosterIds: { number } = {}
			for _, member in state.members do
				rosterIds[#rosterIds + 1] = member.userId
			end
			local nowSec = deps.clock()
			local visible = GroupCore.visibleRoster(relationsFor(viewerUserId, rosterIds, nowSec), rosterIds, nowSec)
			local shown: { [number]: boolean } = { [viewerUserId] = true }
			for _, userId in (visible or {}) do
				shown[userId] = true
			end
			local isSteward = viewerUserId == state.stewardUserId
			local viewerOfficer = table.find(state.officers, viewerUserId) ~= nil
			local members: { FellowshipMemberView } = {}
			for _, member in state.members do
				if shown[member.userId] then
					local officer = table.find(state.officers, member.userId) ~= nil
					local other = member.userId ~= viewerUserId and member.userId ~= state.stewardUserId
					members[#members + 1] = table.freeze({
						userId = member.userId,
						displayName = member.name,
						steward = member.userId == state.stewardUserId,
						officer = officer,
						present = deps.realmFor(member.userId) ~= nil,
						canRemove = (isSteward and member.userId ~= viewerUserId)
							or (viewerOfficer and other and not officer),
						canPromote = isSteward and member.userId ~= viewerUserId,
						canAppoint = isSteward and other and not officer,
						canDemote = isSteward and other and officer,
					})
				end
			end
			local audit: { StewardAuditView } = {}
			for _, entry in state.audit do
				audit[#audit + 1] =
					table.freeze({ userId = entry.userId, fromUserId = entry.fromUserId, atSec = entry.atSec })
			end
			local label: string | false = homeLabel(state.homeSlotId) or false
			local view: FellowshipView = {
				fellowshipId = state.fellowshipId,
				nameId = state.nameId,
				realmId = state.realmId,
				home = table.freeze({ slotId = state.homeSlotId, label = label }),
				foundedAtSec = state.foundedAtSec,
				stewardUserId = state.stewardUserId,
				viewerUserId = viewerUserId,
				isSteward = isSteward,
				isOfficer = viewerOfficer,
				creed = if next(assert(HasMetatable.fields(state.creed))) ~= nil
					then { pursuits = state.creed.pursuits, pace = state.creed.pace, welcome = state.creed.welcome }
					else false,
				canSetCreed = isSteward or viewerOfficer,
				canClaim = viewerOfficer and nowSec - state.stewardSeenAtSec >= FellowshipCore.STEWARD_ABSENCE_SEC,
				audit = table.freeze(audit),
				revision = state.revision,
				members = table.freeze(members),
			}
			return table.freeze(view)
		end

		local function fellowshipAudience(userId: number): { number }
			local audience: { number } = { userId }
			local projected: FellowshipView | false = fellowshipProjection(userId)
			if projected ~= false then
				for _, member in projected.members do
					if member.userId ~= userId then
						audience[#audience + 1] = member.userId
					end
				end
			end
			return audience
		end

		local function fellowshipNoticed(fellowshipId: string): { number }
			local affected: { [number]: boolean } = {}
			local before = host.cachedRecord(fellowshipId)
			if before ~= nil then
				for _, member in before.members do
					affected[member.userId] = true
				end
			end
			local after = loadRecord(fellowshipId, true)
			if after.ok and after.state ~= nil then
				for _, member in after.state.members do
					affected[member.userId] = true
				end
			end
			local rows: { number } = {}
			for userId in affected do
				if deps.realmFor(userId) ~= nil then
					settleUnlessBusy(userId)
					rows[#rows + 1] = userId
				end
			end
			table.sort(rows)
			return rows
		end

		return table.freeze({
			createFellowship = createFellowship,
			fellowshipInvite = fellowshipInvite,
			pendingFellowshipInvite = pendingFellowshipInvite,
			answerFellowshipInvite = answerFellowshipInvite,
			fellowshipMemberIntent = fellowshipMemberIntent,
			bankMembership = bankMembership,
			fellowshipProjection = fellowshipProjection,
			fellowshipAudience = fellowshipAudience,
			fellowshipNoticed = fellowshipNoticed,
			fellowshipSeen = function(actorUserId: number): FellowshipResponse
				local membership = membershipOf(actorUserId, false)
				local cached = if membership ~= nil then host.cachedRecord(membership.fellowshipId) else nil
				if membership ~= nil and cached == nil then
					local loaded = loadRecord(membership.fellowshipId, false)
					cached = if loaded.ok then loaded.state else nil
				end
				if
					cached == nil
					or cached.stewardUserId ~= actorUserId
					or deps.clock() - cached.stewardSeenAtSec < FELLOWSHIP_SEEN_REFRESH_SEC
				then
					return { ok = true, state = nil, replayed = false, reason = nil }
				end
				return fellowshipMemberIntent(actorUserId, "seen", nil)
			end,
			fellowshipSettle = function(userId: number): string?
				if deps.fellowshipRecords == nil or deps.realmFor(userId) == nil then
					return nil
				end
				reconciledUsers[userId] = true
				return settleUnlessBusy(userId)
			end,
			fellowshipEnsureSettled = function(userId: number)
				if deps.fellowshipRecords == nil or reconciledUsers[userId] or deps.realmFor(userId) == nil then
					return
				end
				reconciledUsers[userId] = true
				settleUnlessBusy(userId)
			end,
			forgetPlayer = function(userId: number)
				reconciledUsers[userId] = nil
				pendingGuildInviteByUser[userId] = nil
				host.forget(userId)
			end,
		})
	end

	return table.freeze({ create = create })
end

return table.freeze({ configure = configure })
