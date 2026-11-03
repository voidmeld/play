--!strict

local PartyHost = require("./party")
local PartyTypes = require("../core/social/membership")
local Rally = require("../core/social/rally")
local Value = require("../core/internal/value")

type PartyOutcome = PartyHost.PartyOutcome
export type Handle = {
	read open: (unknown) -> PartyOutcome,
	read invite: (unknown) -> PartyOutcome,
	read accept: (unknown) -> PartyOutcome,
	read decline: (unknown) -> PartyOutcome,
	read leave: (unknown) -> PartyOutcome,
	read kick: (unknown) -> PartyOutcome,
	read transferLeader: (unknown) -> PartyOutcome,
	read acceptLeaderTransfer: (unknown) -> PartyOutcome,
	read disband: (unknown) -> PartyOutcome,
	read setLootMode: (unknown) -> PartyOutcome,
	read markAbsent: (unknown) -> PartyOutcome,
	read markPresent: (unknown) -> PartyOutcome,
	read sweep: (unknown) -> PartyOutcome,
	read read: (unknown) -> PartyOutcome,
}
type PartyHandle = Handle

export type RallyJoinResult = { ok: false, reason: string } | { ok: true, objectiveId: string, replayed: boolean }

export type Dependencies = {
	read projectPartyMembership: (string, string?) -> string?,
	read projectPartySnapshot: ((PartyTypes.State) -> string?)?,
	read partyMembership: (string) -> unknown,
	read candidateRows: (number) -> unknown,
	read realmFor: (number) -> string?,
	read characterFor: (number) -> string?,
	read displayNameFor: (number) -> string?,
	read clock: () -> number,
	read projectRallyJoin: (number, string?) -> (),
	read objectiveRows: () -> unknown,
}

export type PartyResponse = {
	read ok: boolean,
	read reason: string?,
	read party: PartyTypes.State?,
	read replayed: boolean?,
	read found: boolean?,
	read boundary: string?,
	read dissolved: boolean?,
	read strandedUserIds: { number }?,
}

export type CandidateView = { read userId: number, read displayName: string, read source: "nearby" | "recent" }
export type PartyMemberView = {
	read userId: number,
	read displayName: string,
	read leader: boolean,
	read present: boolean,
	read canRemove: boolean,
	read canPromote: boolean,
}
export type PendingPartyInvite = { read partyId: string, read inviterUserId: number?, read inviterName: string }
export type PartyLeaderTransferView = {
	read recipientUserId: number?,
	read fromUserId: number?,
	read expiresAtSec: number,
	read canAccept: boolean,
}
export type PartyView = {
	read partyId: string,
	read viewerUserId: number,
	read leaderUserId: number?,
	read members: { PartyMemberView },
	read leaderTransfer: PartyLeaderTransferView | false,
}
export type PartyProjection = {
	read candidates: { CandidateView },
	read incoming: PendingPartyInvite | false,
	read party: PartyView | false,
	read joinedRallyObjectiveId: string | false,
}

export type ProjectionRefusal = { accountId: string, reason: string }
export type Config = {
	read lootMode: PartyTypes.LootMode,
	read rally: (unknown, string, string, number) -> { Rally.Row }?,
	read inviteTtlSec: number,
	read leaderTransferTtlSec: number,
	read maxProjectionRefusals: number,
	read maxDisplayName: number,
	read maxCandidates: number,
	read partyId: (number, number, number) -> string,
	read memberFallback: (string) -> string,
	read inviterFallback: string,
	read reportProjectionRefusal: (string, string) -> (),
}
export type Service = {
	read party: Handle,
	read partyInvite: (number, number) -> PartyResponse,
	read partyAccept: (number) -> PartyResponse,
	read partyDecline: (number) -> PartyResponse,
	read partyLeave: (number) -> PartyResponse,
	read partyRemove: (number, number) -> PartyResponse,
	read partyTransferLeader: (number, number) -> PartyResponse,
	read partyAcceptLeaderTransfer: (number) -> PartyResponse,
	read partyDisband: (number) -> PartyResponse,
	read partyDisconnect: (number) -> PartyResponse,
	read partyReconnect: (number) -> PartyResponse,
	read partySweep: (string) -> PartyResponse,
	read partyProjection: (number) -> PartyProjection,
	read candidateProjection: (number) -> { CandidateView },
	read candidateNamed: (number, number) -> boolean,
	read partyAudience: (number) -> { number },
	read pendingInviteCount: () -> number,
	read rallyBoard: (string, string) -> { Rally.Row }?,
	read joinRally: (number, string, string) -> RallyJoinResult,
	read leaveRally: (number) -> { ok: boolean, replayed: boolean },
}
export type Host = {
	read create: (Dependencies, Handle) -> Service,
	read projectionRefusals: () -> { ProjectionRefusal },
}

local function configure(config: Config): Host
	config = table.freeze(table.clone(config))
	for _, bound in { config.maxProjectionRefusals, config.maxDisplayName, config.maxCandidates } do
		assert(Value.whole(bound, 1, 9007199254740991) ~= nil, "invalid party projection bound")
	end
	assert(Value.finite(config.inviteTtlSec) and config.inviteTtlSec > 0, "invalid party invitation lifetime")
	assert(
		Value.finite(config.leaderTransferTtlSec) and config.leaderTransferTtlSec > 0,
		"invalid party transfer lifetime"
	)
	local PartyService = { INVITE_TTL_SEC = config.inviteTtlSec, LEADER_TRANSFER_TTL_SEC = config.leaderTransferTtlSec }
	local RallyBoardCore = { project = config.rally }
	local HasMetatable = {
		check = function(value: unknown): boolean
			return type(value) == "table" and getmetatable(value) ~= nil
		end,
		fields = Value.raw,
	}

	local function leftParty(outcome: PartyOutcome, dissolved: boolean, stranded: { number })
		return {
			ok = outcome.ok,
			reason = outcome.reason,
			replayed = outcome.replayed,
			found = outcome.found,
			party = outcome.party,
			boundary = outcome.boundary,
			dissolved = dissolved,
			strandedUserIds = stranded,
		}
	end
	local PROJECTION_REFUSAL_LOG_MAX = config.maxProjectionRefusals
	local projectionRefusals: { { accountId: string, reason: string } } = {}

	local function recordProjectionRefusal(accountId: string, reason: string?)
		if reason == nil then
			return
		end
		table.insert(projectionRefusals, { accountId = accountId, reason = reason })
		if #projectionRefusals > PROJECTION_REFUSAL_LOG_MAX then
			table.remove(projectionRefusals, 1)
		end
		config.reportProjectionRefusal(accountId, reason)
	end

	local function create(deps: Dependencies, partySource: PartyHandle): Service
		local partyMembers: { [string]: { [string]: boolean } } = {}
		local pendingPartyByUser: { [number]: string } = {}
		local pendingInviterByUser: { [number]: number } = {}
		local pendingTargetsByInviter: { [number]: { [number]: boolean } } = {}
		local pendingInviteCount = 0
		local joinedRallyByUser: { [number]: string } = {}
		local nextPartySequence = 0

		local function syncParty(outcome: PartyOutcome): PartyOutcome
			if not outcome.ok or outcome.party == nil then
				return outcome
			end
			local partyId = outcome.party.partyId
			local previous: { [string]: boolean } = partyMembers[partyId] or {}
			local current: { [string]: boolean } = {}
			if outcome.party.disbandedAt == nil then
				for _, member in outcome.party.members do
					current[member.accountId] = true
				end
			end
			for accountId in previous do
				if not current[accountId] then
					recordProjectionRefusal(accountId, deps.projectPartyMembership(accountId, nil))
				end
			end
			for accountId in current do
				recordProjectionRefusal(accountId, deps.projectPartyMembership(accountId, partyId))
			end
			partyMembers[partyId] = current
			if deps.projectPartySnapshot ~= nil then
				local refusal = deps.projectPartySnapshot(outcome.party)
				for accountId in current do
					recordProjectionRefusal(accountId, refusal)
				end
			end
			return outcome
		end

		local party: PartyHandle = {
			read = partySource.read,
			open = function(request: unknown): PartyOutcome
				return syncParty(partySource.open(request))
			end,
			invite = function(request: unknown): PartyOutcome
				return syncParty(partySource.invite(request))
			end,
			accept = function(request: unknown): PartyOutcome
				return syncParty(partySource.accept(request))
			end,
			decline = function(request: unknown): PartyOutcome
				return syncParty(partySource.decline(request))
			end,
			leave = function(request: unknown): PartyOutcome
				return syncParty(partySource.leave(request))
			end,
			kick = function(request: unknown): PartyOutcome
				return syncParty(partySource.kick(request))
			end,
			transferLeader = function(request: unknown): PartyOutcome
				return syncParty(partySource.transferLeader(request))
			end,
			acceptLeaderTransfer = function(request: unknown): PartyOutcome
				return syncParty(partySource.acceptLeaderTransfer(request))
			end,
			disband = function(request: unknown): PartyOutcome
				return syncParty(partySource.disband(request))
			end,
			setLootMode = function(request: unknown): PartyOutcome
				return syncParty(partySource.setLootMode(request))
			end,
			markAbsent = function(request: unknown): PartyOutcome
				return syncParty(partySource.markAbsent(request))
			end,
			markPresent = function(request: unknown): PartyOutcome
				return syncParty(partySource.markPresent(request))
			end,
			sweep = function(request: unknown): PartyOutcome
				return syncParty(partySource.sweep(request))
			end,
		}
		table.freeze(party)

		local function membershipFor(userId: number): string?
			local ok, value = pcall(deps.partyMembership, tostring(userId))
			if not ok or (value ~= nil and type(value) ~= "string") then
				return nil
			end
			return if type(value) == "string" then value else nil
		end

		local function candidateProjection(actorUserId: number): { CandidateView }
			local rawValue = deps.candidateRows(actorUserId)
			if type(rawValue) ~= "table" then
				return {}
			end
			if HasMetatable.check(rawValue) then
				return {}
			end
			local raw = assert(HasMetatable.fields(rawValue))
			local actorRealm = deps.realmFor(actorUserId)
			local rows: { CandidateView } = {}
			local seen: { [number]: boolean } = {}
			for _, candidate in raw do
				local row = if HasMetatable.check(candidate) then nil else HasMetatable.fields(candidate)
				if
					type(row) == "table"
					and getmetatable(row) == nil
					and type(row.userId) == "number"
					and row.userId > 0
					and row.userId ~= actorUserId
					and type(row.displayName) == "string"
					and #row.displayName > 0
					and #row.displayName <= config.maxDisplayName
					and (row.source == "nearby" or row.source == "recent")
					and deps.realmFor(row.userId) == actorRealm
					and not seen[row.userId]
				then
					seen[row.userId] = true
					rows[#rows + 1] = table.freeze({
						userId = row.userId,
						displayName = row.displayName,
						source = row.source,
					})
					if #rows == config.maxCandidates then
						break
					end
				end
			end
			return table.freeze(rows)
		end

		local function candidateNamed(actorUserId: number, targetUserId: number): boolean
			for _, row in candidateProjection(actorUserId) do
				if row.userId == targetUserId then
					return true
				end
			end
			return false
		end

		local function partyCharacter(userId: number): (string?, string?)
			local characterId = deps.characterFor(userId)
			if type(characterId) ~= "string" or #characterId == 0 then
				return nil, "character_unavailable"
			end
			return characterId, nil
		end

		local function partyProjection(actorUserId: number): PartyProjection
			local partyId = membershipFor(actorUserId)
			local state: PartyTypes.State? = nil
			if partyId ~= nil then
				local before = party.read(partyId)
				if before.ok and before.found and before.party ~= nil then
					syncParty(before)
					local outcome = if before.party.disbandedAt == nil
						then party.sweep({ partyId = partyId, at = deps.clock() })
						else before
					state = if outcome.ok
							and outcome.found
							and assert(outcome.party).disbandedAt == nil
						then outcome.party
						else nil
					local seated = false
					if state ~= nil then
						for _, member in state.members do
							seated = seated or member.accountId == tostring(actorUserId)
						end
					end
					if not seated then
						recordProjectionRefusal(
							tostring(actorUserId),
							deps.projectPartyMembership(tostring(actorUserId), nil)
						)
						state = nil
					end
				end
			end
			local members: { PartyMemberView } = {}
			if state ~= nil then
				for _, member in state.members do
					local memberUserId = tonumber(member.accountId)
					if memberUserId ~= nil then
						members[#members + 1] = table.freeze({
							userId = memberUserId,
							displayName = deps.displayNameFor(memberUserId) or config.memberFallback(member.accountId),
							leader = member.accountId == state.leaderId,
							present = member.absentSince == nil,
							canRemove = tostring(actorUserId) == state.leaderId and memberUserId ~= actorUserId,
							canPromote = tostring(actorUserId) == state.leaderId
								and memberUserId ~= actorUserId
								and member.absentSince == nil,
						})
					end
				end
			end
			local incoming: PendingPartyInvite | false = false
			local pendingPartyId = pendingPartyByUser[actorUserId]
			if pendingPartyId ~= nil then
				local outcome = party.read(pendingPartyId)
				if outcome.ok and outcome.found and outcome.party ~= nil then
					for _, invite in outcome.party.invites do
						if
							invite.accountId == tostring(actorUserId)
							and deps.clock() - invite.at < PartyService.INVITE_TTL_SEC
						then
							local inviterUserId = tonumber(invite.invitedBy)
							incoming = table.freeze({
								partyId = pendingPartyId,
								inviterUserId = inviterUserId,
								inviterName = if inviterUserId == nil
									then config.inviterFallback
									else deps.displayNameFor(inviterUserId) or config.inviterFallback,
							})
							break
						end
					end
				end
			end
			local canAcceptTransfer = false
			if
				state ~= nil
				and state.leaderTransfer ~= nil
				and state.leaderTransfer.accountId == tostring(actorUserId)
			then
				local characterId, characterReason = partyCharacter(actorUserId)
				for _, member in state.members do
					if member.accountId == tostring(actorUserId) then
						canAcceptTransfer = characterReason == nil
							and (member.characterId == nil or characterId == nil or member.characterId == characterId)
					end
				end
			end
			local view: PartyView | false = false
			if state ~= nil then
				local transfer: PartyLeaderTransferView | false = false
				if state.leaderTransfer ~= nil then
					local offered: PartyLeaderTransferView = {
						recipientUserId = tonumber(state.leaderTransfer.accountId),
						fromUserId = tonumber(state.leaderTransfer.by),
						expiresAtSec = state.leaderTransfer.at + PartyService.LEADER_TRANSFER_TTL_SEC,
						canAccept = canAcceptTransfer,
					}
					table.freeze(offered)
					transfer = offered
				end
				local active: PartyView = {
					partyId = state.partyId,
					viewerUserId = actorUserId,
					leaderUserId = tonumber(state.leaderId),
					members = members,
					leaderTransfer = transfer,
				}
				table.freeze(active)
				view = active
			end
			local projection: PartyProjection = {
				candidates = candidateProjection(actorUserId),
				incoming = incoming,
				party = view,
				joinedRallyObjectiveId = joinedRallyByUser[actorUserId] or false,
			}
			table.freeze(projection)
			return projection
		end

		local function ensureParty(actorUserId: number): (string?, PartyResponse?)
			local held = membershipFor(actorUserId)
			if held ~= nil then
				return held, nil
			end
			local realmId = deps.realmFor(actorUserId)
			if realmId == nil then
				return nil, { ok = false, reason = "realm_unknown" }
			end
			local characterId, characterReason = partyCharacter(actorUserId)
			if characterReason ~= nil then
				return nil, { ok = false, reason = characterReason }
			end
			nextPartySequence += 1
			local partyId = config.partyId(actorUserId, deps.clock(), nextPartySequence)
			local opened = party.open({
				partyId = partyId,
				realmId = realmId,
				founderId = tostring(actorUserId),
				founderCharacterId = characterId,
				lootMode = config.lootMode,
				at = deps.clock(),
			})
			return if opened.ok then partyId else nil, opened
		end

		local clearPendingInvite: (number) -> string?

		local function partyInvite(actorUserId: number, targetUserId: number): PartyResponse
			if not candidateNamed(actorUserId, targetUserId) then
				return { ok = false, reason = "candidate_unknown" }
			end
			local partyId, refusal = ensureParty(actorUserId)
			if partyId == nil then
				return assert(refusal)
			end
			local outcome = party.invite({
				partyId = partyId,
				accountId = tostring(targetUserId),
				invitedBy = tostring(actorUserId),
				targetRealmId = deps.realmFor(targetUserId),
				at = deps.clock(),
			})
			if outcome.ok then
				local previousPartyId = clearPendingInvite(targetUserId)
				if previousPartyId ~= nil and previousPartyId ~= partyId then
					party.decline({ partyId = previousPartyId, accountId = tostring(targetUserId), at = deps.clock() })
				end
				pendingPartyByUser[targetUserId] = partyId
				pendingInviterByUser[targetUserId] = actorUserId
				pendingInviteCount += 1
				local targets = pendingTargetsByInviter[actorUserId]
				if targets == nil then
					targets = {}
					pendingTargetsByInviter[actorUserId] = targets
				end
				targets[targetUserId] = true
			end
			return outcome
		end

		clearPendingInvite = function(targetUserId: number): string?
			local partyId = pendingPartyByUser[targetUserId]
			local inviterUserId = pendingInviterByUser[targetUserId]
			pendingPartyByUser[targetUserId] = nil
			pendingInviterByUser[targetUserId] = nil
			if partyId ~= nil then
				pendingInviteCount -= 1
			end
			if inviterUserId ~= nil then
				local targets = pendingTargetsByInviter[inviterUserId]
				if targets ~= nil then
					targets[targetUserId] = nil
					if next(targets) == nil then
						pendingTargetsByInviter[inviterUserId] = nil
					end
				end
			end
			return partyId
		end

		local function partyAccept(actorUserId: number): PartyResponse
			local partyId = pendingPartyByUser[actorUserId]
			if partyId == nil then
				return { ok = false, reason = "invite_unknown" }
			end
			local characterId, reason = partyCharacter(actorUserId)
			if reason ~= nil then
				return { ok = false, reason = reason }
			end
			local outcome = party.accept({
				partyId = partyId,
				accountId = tostring(actorUserId),
				characterId = characterId,
				at = deps.clock(),
			})
			if outcome.ok then
				clearPendingInvite(actorUserId)
			end
			return outcome
		end

		local function partyDecline(actorUserId: number): PartyResponse
			local partyId = pendingPartyByUser[actorUserId]
			if partyId == nil then
				return { ok = false, reason = "invite_unknown" }
			end
			local outcome = party.decline({ partyId = partyId, accountId = tostring(actorUserId), at = deps.clock() })
			if outcome.ok then
				clearPendingInvite(actorUserId)
			end
			return outcome
		end

		local function partyLeave(actorUserId: number): PartyResponse
			local partyId = membershipFor(actorUserId)
			if partyId == nil then
				return { ok = false, reason = "party_missing" }
			end
			local before = party.read(partyId)
			local outcome = party.leave({ partyId = partyId, accountId = tostring(actorUserId), at = deps.clock() })
			if not outcome.ok then
				return outcome
			end
			deps.projectPartyMembership(tostring(actorUserId), nil)
			local dissolved = type(outcome.party) == "table" and outcome.party.disbandedAt ~= nil
			local stranded: { number } = {}
			if dissolved and before.ok and before.found and before.party ~= nil then
				for _, member in before.party.members do
					local strandedUserId = tonumber(member.accountId)
					if strandedUserId ~= nil and strandedUserId ~= actorUserId then
						stranded[#stranded + 1] = strandedUserId
					end
				end
			end
			return leftParty(outcome, dissolved, stranded)
		end

		local function partyRemove(actorUserId: number, targetUserId: number): PartyResponse
			local partyId = membershipFor(actorUserId)
			if partyId == nil then
				return { ok = false, reason = "party_missing" }
			end
			local outcome = party.kick({
				partyId = partyId,
				accountId = tostring(targetUserId),
				by = tostring(actorUserId),
				at = deps.clock(),
			})
			if outcome.ok then
				deps.projectPartyMembership(tostring(targetUserId), nil)
			end
			return outcome
		end

		local function partyTransferLeader(actorUserId: number, targetUserId: number): PartyResponse
			local partyId = membershipFor(actorUserId)
			if partyId == nil then
				return { ok = false, reason = "party_missing" }
			end
			return party.transferLeader({
				partyId = partyId,
				accountId = tostring(targetUserId),
				by = tostring(actorUserId),
				at = deps.clock(),
			})
		end

		local function partyAcceptLeaderTransfer(actorUserId: number): PartyResponse
			local partyId = membershipFor(actorUserId)
			if partyId == nil then
				return { ok = false, reason = "party_missing" }
			end
			local characterId, reason = partyCharacter(actorUserId)
			if reason ~= nil then
				return { ok = false, reason = reason }
			end
			return party.acceptLeaderTransfer({
				partyId = partyId,
				accountId = tostring(actorUserId),
				characterId = characterId,
				at = deps.clock(),
			})
		end

		local function partyDisband(actorUserId: number): PartyResponse
			local partyId = membershipFor(actorUserId)
			if partyId == nil then
				return { ok = false, reason = "party_missing" }
			end
			local before = party.read(partyId)
			local outcome = party.disband({ partyId = partyId, by = tostring(actorUserId), at = deps.clock() })
			if outcome.ok and before.ok and before.found and before.party ~= nil then
				for _, member in before.party.members do
					deps.projectPartyMembership(member.accountId, nil)
				end
			end
			return outcome
		end

		local function partyDisconnect(actorUserId: number): PartyResponse
			joinedRallyByUser[actorUserId] = nil
			deps.projectRallyJoin(actorUserId, nil)
			local ownPendingPartyId = clearPendingInvite(actorUserId)
			if ownPendingPartyId ~= nil then
				party.decline({ partyId = ownPendingPartyId, accountId = tostring(actorUserId), at = deps.clock() })
			end
			local invitedTargets = pendingTargetsByInviter[actorUserId]
			if invitedTargets ~= nil then
				local targets = {}
				for targetUserId in invitedTargets do
					targets[#targets + 1] = targetUserId
				end
				for _, targetUserId in targets do
					local pendingPartyId = clearPendingInvite(targetUserId)
					if pendingPartyId ~= nil then
						party.decline({
							partyId = pendingPartyId,
							accountId = tostring(targetUserId),
							at = deps.clock(),
						})
					end
				end
			end
			local partyId = membershipFor(actorUserId)
			if partyId == nil then
				return { ok = true, party = nil }
			end
			return party.markAbsent({ partyId = partyId, accountId = tostring(actorUserId), at = deps.clock() })
		end

		local function partySweep(partyId: string)
			local before = party.read(partyId)
			local outcome = party.sweep({ partyId = partyId, at = deps.clock() })
			if outcome.ok and before.ok and before.found and before.party ~= nil and outcome.party ~= nil then
				local current: { [string]: boolean } = {}
				for _, member in outcome.party.members do
					current[member.accountId] = true
				end
				for _, member in before.party.members do
					if not current[member.accountId] then
						deps.projectPartyMembership(member.accountId, nil)
					end
				end
			end
			return outcome
		end

		local function partyReconnect(actorUserId: number): PartyResponse
			local partyId = membershipFor(actorUserId)
			if partyId == nil then
				return { ok = true, party = nil }
			end
			local swept = partySweep(partyId)
			if not swept.ok then
				return swept
			end
			local characterId, reason = partyCharacter(actorUserId)
			if reason ~= nil then
				return { ok = false, reason = reason }
			end
			return party.markPresent({
				partyId = partyId,
				accountId = tostring(actorUserId),
				characterId = characterId,
				at = deps.clock(),
			})
		end

		return table.freeze({
			party = party,
			partyInvite = partyInvite,
			partyAccept = partyAccept,
			partyDecline = partyDecline,
			partyLeave = partyLeave,
			partyRemove = partyRemove,
			partyTransferLeader = partyTransferLeader,
			partyAcceptLeaderTransfer = partyAcceptLeaderTransfer,
			partyDisband = partyDisband,
			partyDisconnect = partyDisconnect,
			partyReconnect = partyReconnect,
			partySweep = partySweep,
			partyProjection = partyProjection,
			candidateProjection = candidateProjection,
			candidateNamed = candidateNamed,
			partyAudience = function(actorUserId: number): { number }
				local projected = partyProjection(actorUserId)
				local audience: { number } = { actorUserId }
				if projected.party ~= false then
					for _, member in projected.party.members do
						if member.userId ~= actorUserId then
							audience[#audience + 1] = member.userId
						end
					end
				end
				return audience
			end,
			pendingInviteCount = function(): number
				return pendingInviteCount
			end,
			rallyBoard = function(zoneId: string, realmId: string): { Rally.Row }?
				return RallyBoardCore.project(deps.objectiveRows(), zoneId, realmId, deps.clock())
			end,
			joinRally = function(actorUserId: number, objectiveId: string, zoneId: string): RallyJoinResult
				local realmId = deps.realmFor(actorUserId)
				local rows = if realmId == nil
					then nil
					else RallyBoardCore.project(deps.objectiveRows(), zoneId, realmId, deps.clock())
				if rows == nil then
					return { ok = false, reason = "rally_unavailable" }
				end
				for _, row in rows do
					if row.objectiveId == objectiveId then
						if joinedRallyByUser[actorUserId] == objectiveId then
							return { ok = true, objectiveId = objectiveId, replayed = true }
						end
						joinedRallyByUser[actorUserId] = objectiveId
						deps.projectRallyJoin(actorUserId, objectiveId)
						return { ok = true, objectiveId = objectiveId, replayed = false }
					end
				end
				return { ok = false, reason = "rally_unavailable" }
			end,
			leaveRally = function(actorUserId: number)
				local previous = joinedRallyByUser[actorUserId]
				joinedRallyByUser[actorUserId] = nil
				deps.projectRallyJoin(actorUserId, nil)
				return { ok = true, replayed = previous == nil }
			end,
		})
	end

	return table.freeze({
		create = create,
		projectionRefusals = function()
			return table.clone(projectionRefusals)
		end,
	})
end

return table.freeze({ configure = configure })
