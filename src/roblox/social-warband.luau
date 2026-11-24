--!strict

local Core = require("../core/social/warband")
local PartyTypes = require("../core/social/membership")
local RecordTypes = require("./social-records")
type State = Core.State
type Party = PartyTypes.State
type Membership = RecordTypes.WarbandMembership
type Records = RecordTypes.Service
export type PartyResult = { read ok: boolean, read found: boolean?, read party: Party?, read reason: string? }
export type Dependencies = {
	records: Records?,
	membership: (string) -> unknown,
	readParty: (string) -> PartyResult,
	clock: () -> number,
	nameFor: (number) -> string?,
	objectiveAllowed: (number, string, string) -> boolean,
	inviteAllowed: (number, number) -> boolean,
}
export type Summary = {
	partyId: string,
	leaderUserId: number,
	leaderName: string,
	connected: boolean,
	members: number,
	commander: boolean,
	assistant: boolean,
}
export type Projection = {
	rallyHosts: { { leaderUserId: number, leaderName: string, objectiveId: string } },
	requests: { { leaderUserId: number, leaderName: string, objectiveId: string } },
	available: boolean,
	revision: number,
	warbandId: string?,
	units: { Summary },
	isLeader: boolean,
	isCommander: boolean,
	canCommand: boolean,
	canAccept: boolean,
	canAcceptTransfer: boolean,
	order: Core.Order?,
	rallyObjectiveId: string?,
	targetObjectiveId: string?,
	rallyByActorId: string?,
	targetByActorId: string?,
	refusal: string?,
}
export type Result = { ok: boolean, reason: string?, audience: { number } }
export type Handle = {
	read act: (number, string, number, number, string, string) -> Result,
	read project: (number, boolean?) -> Projection,
	read refresh: () -> { number },
}

export type Config = {
	read unitOf: (State, string) -> Core.Unit?,
	read command: (State, string) -> boolean,
	read maxParties: number,
	read requestTtlSec: number,
	read rallyZone: string,
	read warbandId: (string, number, number) -> string,
	read memberFallback: (number) -> string,
}
export type API = { read create: (Dependencies) -> Handle }
local function configure(config: Config): API
	config = table.freeze(table.clone(config))
	assert(config.maxParties >= 1 and config.maxParties % 1 == 0, "invalid warband party limit")
	assert(config.requestTtlSec > 0 and config.requestTtlSec < math.huge, "invalid warband request lifetime")
	local WarbandSocial = {}

	function WarbandSocial.create(deps: Dependencies): Handle
		local cached: { [string]: State } = {}
		local invitations: { [string]: string } = {}
		local requests: { [string]: { [string]: { leaderUserId: number, objectiveId: string, expiresAtSec: number } } } =
			{}
		local sequence = 0
		local function actorParty(userId: number): Party?
			local id = deps.membership(tostring(userId))
			if type(id) ~= "string" then
				return nil
			end
			local result = deps.readParty(id)
			local state = if result.ok then result.party else nil
			if state == nil or state.disbandedAt ~= nil then
				return nil
			end
			for _, member in state.members do
				if member.accountId == tostring(userId) then
					return state
				end
			end
			return nil
		end
		local function snapshots(state: State?, extra: Party?): (Core.Parties?, string?)
			local rows: Core.Parties = {}
			local ids: { string } = {}
			if state ~= nil then
				for _, unit in state.units do
					table.insert(ids, unit.partyId)
				end
			end
			if extra ~= nil and table.find(ids, extra.partyId) == nil then
				table.insert(ids, extra.partyId)
			end
			for _, id in ids do
				local read = deps.readParty(id)
				if not read.ok then
					return nil, read.reason or "party_unavailable"
				end
				local party = read.party
				if party ~= nil and party.disbandedAt == nil then
					for _, member in party.members do
						if member.accountId == party.leaderId and member.characterId ~= nil then
							rows[id] = {
								realmId = party.realmId,
								leaderId = party.leaderId,
								characterId = member.characterId,
								connected = member.absentSince == nil,
								absentSinceSec = member.absentSince,
							}
						end
					end
				else
					rows[id] = { realmId = "", leaderId = "", characterId = "", connected = false, closed = true }
				end
			end
			return rows, nil
		end
		local function remember(state: State)
			for id, prior in cached do
				if prior.warbandId == state.warbandId then
					cached[id] = nil
				end
			end
			for _, unit in state.units do
				cached[unit.partyId] = state
			end
		end
		local function current(party: Party): (State?, Membership?, string?)
			local records = deps.records
			if records == nil then
				return nil, nil, "warband_unavailable"
			end
			local held = records.readWarbandMembership(party.partyId)
			if not held.ok then
				return nil, nil, held.reason
			end
			local member = held.membership
			if member == nil then
				cached[party.partyId] = nil
				return nil, nil, nil
			end
			local read = records.readWarband(member.warbandId)
			if not read.ok or read.state == nil then
				if read.reason == "warband_unknown" and member.pending then
					local released = records.releaseWarbandMembership(party.partyId, member)
					if released.ok then
						return nil, nil, nil
					end
					return nil, member, released.reason
				end
				return nil, member, read.reason or "warband_unavailable"
			end
			local unit = config.unitOf(read.state, party.partyId)
			if unit == nil or unit.membershipRevision ~= member.revision then
				local released = records.releaseWarbandMembership(party.partyId, member)
				if not released.ok then
					return nil, member, released.reason
				end
				cached[party.partyId] = nil
				return nil, nil, nil
			end
			if member.pending then
				local confirmed = records.confirmWarbandMembership(party.partyId, member)
				if not confirmed.ok then
					return nil, member, confirmed.reason
				end
				member = confirmed.membership
			end
			local rows, reason = snapshots(read.state, nil)
			if rows == nil then
				return nil, member, reason
			end
			local observed = records.applyWarband(read.state.warbandId, {
				kind = "observe",
				actorPartyId = party.partyId,
				actorId = party.leaderId,
				expectedRevision = read.state.revision,
			}, rows)
			if not observed.ok or observed.state == nil then
				return nil, member, observed.reason
			end
			remember(observed.state)
			return observed.state, member, nil
		end
		local function audience(state: State?, extra: Party?): { number }
			local seen: { [number]: boolean } = {}
			local ids: { string } = {}
			if state ~= nil then
				for _, unit in state.units do
					table.insert(ids, unit.partyId)
				end
			end
			if extra ~= nil then
				table.insert(ids, extra.partyId)
			end
			for _, id in ids do
				local read = deps.readParty(id)
				if read.ok and read.party ~= nil then
					for _, member in read.party.members do
						local numberId = tonumber(member.accountId)
						if numberId ~= nil then
							seen[numberId] = true
						end
					end
				end
			end
			local result: { number } = {}
			for userId in seen do
				table.insert(result, userId)
			end
			table.sort(result)
			return result
		end
		local function act(
			userId: number,
			kind: string,
			targetId: number,
			expectedRevision: number,
			objectiveId: string,
			zoneId: string
		): Result
			local party = actorParty(userId)
			local records = deps.records
			if party == nil or records == nil then
				return { ok = false, reason = "warband_party_required", audience = { userId } }
			end
			if party.leaderId ~= tostring(userId) then
				return { ok = false, reason = "warband_not_leader", audience = { userId } }
			end
			local state, member, reason = current(party)
			if reason ~= nil then
				return { ok = false, reason = reason, audience = { userId } }
			end
			local target = if targetId > 0 then actorParty(targetId) else nil
			local beforeAudience = audience(state, target)
			if kind == "request_invite" then
				if state ~= nil or member ~= nil or target == nil or target.leaderId ~= tostring(targetId) then
					return { ok = false, reason = "warband_request_invalid", audience = { userId } }
				end
				local host, _, unavailable = current(target)
				if unavailable ~= nil then
					return { ok = false, reason = unavailable, audience = { userId } }
				end
				if
					host == nil
					or host.realmId ~= party.realmId
					or host.commanderPartyId ~= target.partyId
					or #host.units >= config.maxParties
					or host.rallyObjectiveId ~= objectiveId
					or not deps.objectiveAllowed(userId, objectiveId, zoneId)
					or not deps.inviteAllowed(userId, targetId)
				then
					return { ok = false, reason = "warband_request_invalid", audience = { userId } }
				end
				local rows = requests[host.warbandId]
				if rows == nil then
					rows = {}
					requests[host.warbandId] = rows
				end
				local prior = rows[party.partyId]
				if prior == nil or prior.expiresAtSec <= deps.clock() then
					local count = 0
					for _, request in rows do
						if request.expiresAtSec > deps.clock() then
							count += 1
						end
					end
					if count >= config.maxParties then
						return { ok = false, reason = "warband_request_invalid", audience = { userId } }
					end
					rows[party.partyId] = {
						leaderUserId = userId,
						objectiveId = objectiveId,
						expiresAtSec = deps.clock() + config.requestTtlSec,
					}
				else
					prior.objectiveId = objectiveId
				end
				return { ok = true, audience = audience(host, party) }
			end
			local id = if state ~= nil then state.warbandId else invitations[party.partyId]
			local result: Core.Result
			if kind == "found" then
				if state ~= nil or member ~= nil then
					return { ok = false, reason = "warband_membership_held", audience = beforeAudience }
				end
				local rows, failure = snapshots(nil, party)
				if rows == nil or rows[party.partyId] == nil then
					return { ok = false, reason = failure or "character_unavailable", audience = { userId } }
				end
				sequence += 1
				id = config.warbandId(party.partyId, deps.clock(), sequence)
				local claimed = records.claimWarbandMembership(party.partyId, id)
				if not claimed.ok or claimed.membership == nil then
					return { ok = false, reason = claimed.reason, audience = { userId } }
				end
				member = claimed.membership
				result = records.foundWarband(id, party.partyId, rows[party.partyId], member.revision)
			else
				if id == nil then
					return { ok = false, reason = "warband_unknown", audience = beforeAudience }
				end
				if kind == "accept" then
					if state ~= nil or member ~= nil then
						return { ok = false, reason = "warband_membership_held", audience = beforeAudience }
					end
					local read = records.readWarband(id)
					if not read.ok or read.state == nil then
						return { ok = false, reason = read.reason, audience = beforeAudience }
					end
					state = read.state
					local claimed = records.claimWarbandMembership(party.partyId, id)
					if not claimed.ok or claimed.membership == nil then
						return { ok = false, reason = claimed.reason, audience = beforeAudience }
					end
					member = claimed.membership
				end
				if state == nil then
					return { ok = false, reason = "warband_unknown", audience = beforeAudience }
				end
				local rows, failure = snapshots(state, if kind == "accept" then party else target)
				if rows == nil then
					return { ok = false, reason = failure, audience = beforeAudience }
				end
				if kind == "invite" then
					if
						target == nil
						or target.leaderId ~= tostring(targetId)
						or not deps.inviteAllowed(userId, targetId)
					then
						return { ok = false, reason = "warband_invite_invalid", audience = beforeAudience }
					end
					local held = records.readWarbandMembership(target.partyId)
					if not held.ok or held.membership ~= nil then
						return {
							ok = false,
							reason = held.reason or "warband_membership_held",
							audience = beforeAudience,
						}
					end
				end
				if
					(kind == "order" or kind == "rally" or kind == "marker")
					and not deps.objectiveAllowed(userId, objectiveId, zoneId)
				then
					return { ok = false, reason = "warband_objective_invalid", audience = beforeAudience }
				end
				local orderKind = string.match(kind, "^order:(%a+)$")
				if orderKind ~= nil and not deps.objectiveAllowed(userId, objectiveId, zoneId) then
					return { ok = false, reason = "warband_objective_invalid", audience = beforeAudience }
				end
				result = records.applyWarband(id, {
					kind = if orderKind ~= nil then "order" else kind,
					actorPartyId = party.partyId,
					actorId = tostring(userId),
					expectedRevision = expectedRevision,
					targetPartyId = if target ~= nil then target.partyId else nil,
					membershipRevision = if member ~= nil then member.revision else nil,
					orderKind = orderKind,
					objectiveId = objectiveId,
				}, rows)
			end
			if not result.ok or result.state == nil then
				return { ok = false, reason = result.reason or "not_durable", audience = beforeAudience }
			end
			remember(result.state)
			if kind == "invite" and target ~= nil then
				invitations[target.partyId] = result.state.warbandId
				local rows = requests[result.state.warbandId]
				if rows ~= nil then
					rows[target.partyId] = nil
				end
			end
			if (kind == "found" or kind == "accept") and member ~= nil then
				local confirmed = records.confirmWarbandMembership(party.partyId, member)
				if not confirmed.ok then
					return { ok = false, reason = confirmed.reason, audience = beforeAudience }
				end
				invitations[party.partyId] = nil
			end
			local removed = if kind == "leave" then party else if kind == "remove" then target else nil
			if removed ~= nil then
				local held = records.readWarbandMembership(removed.partyId)
				if not held.ok then
					return { ok = false, reason = held.reason, audience = beforeAudience }
				end
				if held.membership ~= nil and held.membership.warbandId == result.state.warbandId then
					local released = records.releaseWarbandMembership(removed.partyId, held.membership)
					if not released.ok then
						return { ok = false, reason = released.reason, audience = beforeAudience }
					end
				end
			end
			local seen: { [number]: boolean } = {}
			for _, idBefore in beforeAudience do
				seen[idBefore] = true
			end
			for _, idAfter in audience(result.state, party) do
				seen[idAfter] = true
			end
			local ids: { number } = {}
			for idMember in seen do
				table.insert(ids, idMember)
			end
			return { ok = true, audience = ids }
		end
		local function project(userId: number, refresh: boolean?): Projection
			local party = actorParty(userId)
			local result: Projection = {
				rallyHosts = {},
				requests = {},
				available = deps.records ~= nil,
				revision = 0,
				units = {},
				isLeader = party ~= nil and party.leaderId == tostring(userId),
				isCommander = false,
				canCommand = false,
				canAccept = false,
				canAcceptTransfer = false,
			}
			if party == nil then
				return result
			end
			for bandId, rows in requests do
				for partyId, request in rows do
					local field = actorParty(request.leaderUserId)
					if
						request.expiresAtSec <= deps.clock()
						or field == nil
						or field.partyId ~= partyId
						or field.leaderId ~= tostring(request.leaderUserId)
					then
						rows[partyId] = nil
					end
				end
				if next(rows) == nil then
					requests[bandId] = nil
				end
			end
			if result.isLeader then
				local seen: { [string]: boolean } = {}
				for _, host in cached do
					if
						not seen[host.warbandId]
						and host.realmId == party.realmId
						and host.rallyObjectiveId ~= nil
						and #host.units < config.maxParties
					then
						seen[host.warbandId] = true
						local commander = if host.commanderPartyId ~= nil
							then deps.readParty(host.commanderPartyId)
							else nil
						local leader = if commander ~= nil
								and commander.ok
								and commander.party ~= nil
							then tonumber(commander.party.leaderId)
							else nil
						if
							leader ~= nil
							and deps.inviteAllowed(userId, leader)
							and deps.objectiveAllowed(userId, host.rallyObjectiveId, config.rallyZone)
						then
							local name = deps.nameFor(leader)
							if name ~= nil then
								table.insert(
									result.rallyHosts,
									{ leaderUserId = leader, leaderName = name, objectiveId = host.rallyObjectiveId }
								)
							end
						end
					end
				end
				table.sort(result.rallyHosts, function(a: { leaderUserId: number }, b: { leaderUserId: number })
					return a.leaderUserId < b.leaderUserId
				end)
			end
			local state: State? = cached[party.partyId]
			if refresh or state == nil then
				local nextState, _, failure = current(party)
				state = nextState
				result.refusal = failure
			end
			if state == nil and invitations[party.partyId] ~= nil and deps.records ~= nil then
				local read = deps.records.readWarband(invitations[party.partyId])
				if read.ok and read.state ~= nil then
					local invite = read.state.invites[party.partyId]
					if
						invite ~= nil
						and invite.expiresAtSec > deps.clock()
						and config.command(read.state, invite.byPartyId)
					then
						result.canAccept = result.isLeader
						result.revision = read.state.revision
					end
				end
				return result
			end
			if state == nil then
				return result
			end
			result.warbandId = state.warbandId
			result.revision = state.revision
			result.isCommander = result.isLeader and state.commanderPartyId == party.partyId
			result.canCommand = result.isLeader and config.command(state, party.partyId)
			if result.canCommand then
				local rows = requests[state.warbandId]
				if rows ~= nil then
					for _, request in rows do
						if deps.inviteAllowed(userId, request.leaderUserId) then
							local name = deps.nameFor(request.leaderUserId)
							if name ~= nil then
								table.insert(result.requests, {
									leaderUserId = request.leaderUserId,
									leaderName = name,
									objectiveId = request.objectiveId,
								})
							end
						end
					end
				end
				table.sort(result.requests, function(a: { leaderUserId: number }, b: { leaderUserId: number })
					return a.leaderUserId < b.leaderUserId
				end)
			end
			result.canAcceptTransfer = result.isLeader
				and state.transfer ~= nil
				and state.transfer.partyId == party.partyId
				and state.transfer.expiresAtSec > deps.clock()
			result.order = state.order
			result.rallyObjectiveId = state.rallyObjectiveId
			result.targetObjectiveId = state.targetObjectiveId
			result.rallyByActorId = state.rallyByActorId
			result.targetByActorId = state.targetByActorId
			for _, unit in state.units do
				local read = deps.readParty(unit.partyId)
				local field = if read.ok then read.party else nil
				if field ~= nil then
					local leaderId = tonumber(field.leaderId)
					if leaderId ~= nil then
						local connected = false
						for _, memberRow in field.members do
							if memberRow.accountId == field.leaderId then
								connected = memberRow.absentSince == nil
							end
						end
						table.insert(result.units, {
							partyId = unit.partyId,
							leaderUserId = leaderId,
							leaderName = deps.nameFor(leaderId) or config.memberFallback(leaderId),
							connected = connected,
							members = #field.members,
							commander = state.commanderPartyId == unit.partyId,
							assistant = table.find(state.assistants, unit.partyId) ~= nil,
						})
					end
				end
			end
			return result
		end
		local function refresh(): { number }
			local seenBands: { [string]: boolean } = {}
			local affected: { [number]: boolean } = {}
			local pendingStates = table.clone(cached)
			for partyId, prior in pendingStates do
				if seenBands[prior.warbandId] then
					continue
				end
				local read = deps.readParty(partyId)
				if read.ok and read.party ~= nil then
					seenBands[prior.warbandId] = true
					for _, id in audience(prior, read.party) do
						affected[id] = true
					end
					current(read.party)
				end
			end
			local ids: { number } = {}
			for id in affected do
				table.insert(ids, id)
			end
			return ids
		end
		return table.freeze({ act = act, project = project, refresh = refresh })
	end

	return table.freeze(WarbandSocial)
end

return table.freeze({ configure = configure })
