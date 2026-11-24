--!strict
local Value = require("../../kernel/value")

export type LootMode = "round_robin" | "need_greed"

export type Member = {
	accountId: string,
	characterId: string?,
	joinedAt: number,
	absentSince: number?,
}

export type Invite = {
	accountId: string,
	invitedBy: string,
	at: number,
}

export type LeaderTransfer = { accountId: string, by: string, at: number }

export type State = {
	partyId: string,
	realmId: string,
	leaderId: string,
	leaderTransfer: LeaderTransfer?,
	members: { Member },
	invites: { Invite },
	lootMode: LootMode,
	lootCursor: string?,
	createdAt: number,
	lastAt: number,
	disbandedAt: number?,
}

export type Result = {
	state: State,
	replayed: boolean,
}

export type Config = {
	maxMembers: number,
	minimumPartyMembers: number,
	disconnectGraceSec: number,
	leaderSuccessionSec: number,
	leaderTransferTtlSec: number,
	inviteTtlSec: number,
	maxText: number,
	maxAt: number,
	realms: { [string]: boolean },
	defaultLootMode: LootMode,
}
local System = {}
function System.membership(config: Config)
	local MAX_MEMBERS = config.maxMembers
	local MINIMUM_PARTY_MEMBERS = config.minimumPartyMembers
	local DISCONNECT_GRACE_SEC = config.disconnectGraceSec
	local LEADER_SUCCESSION_SEC = config.leaderSuccessionSec
	local LEADER_TRANSFER_TTL_SEC = config.leaderTransferTtlSec
	local INVITE_TTL_SEC = config.inviteTtlSec
	local MAX_TEXT = config.maxText
	local MAX_AT = config.maxAt
	local REALMS = config.realms
	local DEFAULT_LOOT_MODE = config.defaultLootMode
	local LEADER_TRANSFER_FIELDS: { [string]: boolean } = { accountId = true, by = true, at = true }

	local STATE_FIELDS: { [string]: boolean } = {
		partyId = true,
		realmId = true,
		leaderId = true,
		leaderTransfer = true,
		members = true,
		invites = true,
		lootMode = true,
		lootCursor = true,
		createdAt = true,
		lastAt = true,
		disbandedAt = true,
	}

	local MEMBER_FIELDS: { [string]: boolean } = {
		accountId = true,
		characterId = true,
		joinedAt = true,
		absentSince = true,
	}

	local INVITE_FIELDS: { [string]: boolean } = {
		accountId = true,
		invitedBy = true,
		at = true,
	}

	local OPEN_REQUEST_FIELDS: { [string]: boolean } = {
		partyId = true,
		realmId = true,
		founderId = true,
		founderCharacterId = true,
		lootMode = true,
		at = true,
	}

	local INVITE_REQUEST_FIELDS: { [string]: boolean } = {
		accountId = true,
		invitedBy = true,
		targetRealmId = true,
		targetGrouped = true,
		at = true,
	}

	local ACCEPT_REQUEST_FIELDS: { [string]: boolean } = {
		accountId = true,
		characterId = true,
		accepterGrouped = true,
		at = true,
	}

	local PRESENT_REQUEST_FIELDS: { [string]: boolean } = { accountId = true, characterId = true, at = true }

	local ACCOUNT_REQUEST_FIELDS: { [string]: boolean } = {
		accountId = true,
		at = true,
	}

	local KICK_REQUEST_FIELDS: { [string]: boolean } = {
		accountId = true,
		by = true,
		at = true,
	}

	local TRANSFER_LEADER_REQUEST_FIELDS: { [string]: boolean } = {
		accountId = true,
		by = true,
		at = true,
	}

	local DISBAND_REQUEST_FIELDS: { [string]: boolean } = {
		by = true,
		at = true,
	}

	local LOOT_MODE_REQUEST_FIELDS: { [string]: boolean } = {
		by = true,
		lootMode = true,
		at = true,
	}

	local SWEEP_REQUEST_FIELDS: { [string]: boolean } = {
		at = true,
	}

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_TEXT
	end

	local function timestamp(value: unknown): boolean
		return (type(value) == "number" and finite(value)) and value >= 0 and value <= MAX_AT
	end

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" then
			return false
		end
		for key in value do
			if type(key) ~= "string" or fields[key] ~= true then
				return false
			end
		end
		return true
	end

	local function denseLength(value: unknown): number?
		local rows = Value.dense(value, math.huge, false)
		return if rows == nil then nil else #rows
	end

	local function frozenMember(member: Member): Member
		return Value.freezeDeep(member)
	end
	local function projectMember(value: unknown): (Member?, string?)
		if not hasOnlyFields(value, MEMBER_FIELDS) then
			return nil, "member_shape_invalid"
		end
		local source = assert(Value.raw(value))
		if not (type(source.accountId) == "string" and text(source.accountId)) then
			return nil, "account_invalid"
		end
		if source.characterId ~= nil and not (type(source.characterId) == "string" and text(source.characterId)) then
			return nil, "account_invalid"
		end
		if not (type(source.joinedAt) == "number" and timestamp(source.joinedAt)) then
			return nil, "time_invalid"
		end
		if
			source.absentSince ~= nil and not (type(source.absentSince) == "number" and timestamp(source.absentSince))
		then
			return nil, "time_invalid"
		end
		return frozenMember({
			accountId = source.accountId,
			characterId = source.characterId,
			joinedAt = source.joinedAt,
			absentSince = source.absentSince,
		}),
			nil
	end

	local function projectInvite(value: unknown): (Invite?, string?)
		if not hasOnlyFields(value, INVITE_FIELDS) then
			return nil, "invite_shape_invalid"
		end
		local source = assert(Value.raw(value))
		if
			not (type(source.accountId) == "string" and text(source.accountId))
			or not (type(source.invitedBy) == "string" and text(source.invitedBy))
		then
			return nil, "account_invalid"
		end
		if not (type(source.at) == "number" and timestamp(source.at)) then
			return nil, "time_invalid"
		end
		return Value.freezeDeep({
			accountId = source.accountId,
			invitedBy = source.invitedBy,
			at = source.at,
		}),
			nil
	end

	local function projectState(value: unknown): (State?, string?)
		if not hasOnlyFields(value, STATE_FIELDS) then
			return nil, "state_shape_invalid"
		end
		local source = assert(Value.raw(value))
		if not (type(source.partyId) == "string" and text(source.partyId)) then
			return nil, "party_id_invalid"
		end
		if type(source.realmId) ~= "string" or REALMS[source.realmId] ~= true then
			return nil, "realm_unknown"
		end
		if not (type(source.leaderId) == "string" and text(source.leaderId)) then
			return nil, "account_invalid"
		end
		if source.lootMode ~= "round_robin" and source.lootMode ~= "need_greed" then
			return nil, "loot_mode_invalid"
		end
		if source.lootCursor ~= nil and not (type(source.lootCursor) == "string" and text(source.lootCursor)) then
			return nil, "account_invalid"
		end
		if
			not (type(source.createdAt) == "number" and timestamp(source.createdAt))
			or not (type(source.lastAt) == "number" and timestamp(source.lastAt))
		then
			return nil, "time_invalid"
		end
		if source.lastAt < source.createdAt then
			return nil, "time_regressed"
		end
		if
			source.disbandedAt ~= nil and not (type(source.disbandedAt) == "number" and timestamp(source.disbandedAt))
		then
			return nil, "time_invalid"
		end

		local memberCount = denseLength(source.members)
		if memberCount == nil then
			return nil, "state_shape_invalid"
		end
		local members: { Member } = {}
		local seen: { [string]: boolean } = {}
		for index = 1, memberCount do
			local row, reason = projectMember(assert(Value.dense(source.members, math.huge, false))[index])
			if row == nil then
				return nil, reason
			end
			local member = row
			if seen[member.accountId] then
				return nil, "member_duplicate"
			end
			seen[member.accountId] = true
			members[index] = member
		end

		local inviteCount = denseLength(source.invites)
		if inviteCount == nil then
			return nil, "state_shape_invalid"
		end
		local invites: { Invite } = {}
		local invited: { [string]: boolean } = {}
		for index = 1, inviteCount do
			local row, reason = projectInvite(assert(Value.dense(source.invites, math.huge, false))[index])
			if row == nil then
				return nil, reason
			end
			local invite = row
			if invited[invite.accountId] then
				return nil, "invite_duplicate"
			end
			if seen[invite.accountId] then
				return nil, "invite_targets_member"
			end
			invited[invite.accountId] = true
			invites[index] = invite
		end

		if source.disbandedAt ~= nil then
			if memberCount ~= 0 or inviteCount ~= 0 then
				return nil, "state_invalid"
			end
		else
			if memberCount < 1 then
				return nil, "members_empty"
			end
			if memberCount + inviteCount > MAX_MEMBERS then
				return nil, "members_overfull"
			end
			if not seen[source.leaderId] then
				return nil, "leader_not_member"
			end
		end

		local transfer: LeaderTransfer? = nil
		if source.leaderTransfer ~= nil then
			local row = Value.raw(source.leaderTransfer)
			if
				row == nil
				or not hasOnlyFields(row, LEADER_TRANSFER_FIELDS)
				or not (type(row.accountId) == "string" and text(row.accountId))
				or not (type(row.by) == "string" and text(row.by))
				or not (type(row.at) == "number" and timestamp(row.at))
				or row.at > source.lastAt
				or row.by ~= source.leaderId
				or row.accountId == row.by
				or not seen[row.accountId]
				or source.disbandedAt ~= nil
			then
				return nil, "leader_transfer_invalid"
			end
			transfer = Value.freezeDeep({ accountId = row.accountId, by = row.by, at = row.at })
		end

		return Value.freezeDeep({
			partyId = source.partyId,
			realmId = source.realmId,
			leaderId = source.leaderId,
			leaderTransfer = transfer,
			members = Value.freezeDeep(members),
			invites = Value.freezeDeep(invites),
			lootMode = source.lootMode,
			lootCursor = source.lootCursor,
			createdAt = source.createdAt,
			lastAt = source.lastAt,
			disbandedAt = source.disbandedAt,
		}),
			nil
	end

	local function memberIndex(state: State, accountId: string): number?
		for index, member in state.members do
			if member.accountId == accountId then
				return index
			end
		end
		return nil
	end

	local function inviteIndex(state: State, accountId: string): number?
		for index, invite in state.invites do
			if invite.accountId == accountId then
				return index
			end
		end
		return nil
	end

	local function copyMembers(members: { Member }): { Member }
		local rows: { Member } = {}
		for index, member in members do
			rows[index] = member
		end
		return rows
	end

	local function copyInvites(invites: { Invite }): { Invite }
		local rows: { Invite } = {}
		for index, invite in invites do
			rows[index] = invite
		end
		return rows
	end

	local function rebuild(
		state: State,
		members: { Member },
		invites: { Invite },
		leaderId: string,
		lootMode: LootMode,
		lootCursor: string?,
		at: number,
		disbandedAt: number?
	): State
		local transfer = state.leaderTransfer
		if transfer ~= nil then
			local sourcePresent, targetPresent = false, false
			for _, member in members do
				if member.absentSince == nil then
					sourcePresent = sourcePresent or member.accountId == transfer.by
					targetPresent = targetPresent or member.accountId == transfer.accountId
				end
			end
			if
				disbandedAt ~= nil
				or leaderId ~= transfer.by
				or at - transfer.at >= LEADER_TRANSFER_TTL_SEC
				or not sourcePresent
				or not targetPresent
			then
				transfer = nil
			end
		end

		return Value.freezeDeep({
			partyId = state.partyId,
			realmId = state.realmId,
			leaderId = leaderId,
			leaderTransfer = transfer,
			members = Value.freezeDeep(members),
			invites = Value.freezeDeep(invites),
			lootMode = lootMode,
			lootCursor = lootCursor,
			createdAt = state.createdAt,
			lastAt = at,
			disbandedAt = disbandedAt,
		})
	end

	local function unchanged(state: State): Result
		return Value.freezeDeep({ state = state, replayed = true })
	end

	local function advanced(state: State): Result
		return Value.freezeDeep({ state = state, replayed = false })
	end

	local function successor(members: { Member }, leaderId: string): string
		local connected: Member? = nil
		local remaining: Member? = nil
		local function earlier(member: Member, prior: Member?): boolean
			if prior == nil or member.joinedAt < prior.joinedAt then
				return true
			end
			if member.joinedAt ~= prior.joinedAt then
				return false
			end
			local id = member.characterId or member.accountId
			local priorId = prior.characterId or prior.accountId
			return id < priorId or (id == priorId and member.accountId < prior.accountId)
		end
		for _, member in members do
			if earlier(member, remaining) then
				remaining = member
			end
			if member.absentSince == nil and earlier(member, connected) then
				connected = member
			end
		end
		local chosen = connected or remaining
		return if chosen ~= nil then chosen.accountId else leaderId
	end

	local function settleLifecycle(state: State, at: number): (State, boolean)
		local members: { Member } = {}
		local leaderAbsent = false
		local leaderGone = true
		for _, member in state.members do
			if member.absentSince ~= nil and at - member.absentSince >= DISCONNECT_GRACE_SEC then
				continue
			end
			table.insert(members, member)
			if member.accountId == state.leaderId then
				leaderGone = false
				leaderAbsent = member.absentSince ~= nil and at - member.absentSince >= LEADER_SUCCESSION_SEC
			end
		end
		local invites: { Invite } = {}
		for _, invite in state.invites do
			if at - invite.at < INVITE_TTL_SEC then
				table.insert(invites, invite)
			end
		end
		local leaderId = if leaderGone or leaderAbsent then successor(members, state.leaderId) else state.leaderId
		local nextState = rebuild(
			state,
			members,
			invites,
			leaderId,
			state.lootMode,
			state.lootCursor,
			at,
			if #members == 0 then at else nil
		)
		local changed = #members ~= #state.members
			or #invites ~= #state.invites
			or leaderId ~= state.leaderId
			or nextState.leaderTransfer ~= state.leaderTransfer
		return if changed then nextState else state, changed
	end

	local function openState(stateValue: unknown, at: unknown, allowExpired: boolean?): (State?, string?, boolean?)
		local state, reason = projectState(stateValue)
		if state == nil then
			return nil, reason, false
		end
		local live = state
		if live.disbandedAt ~= nil then
			return nil, "party_disbanded", false
		end
		if not (type(at) == "number" and timestamp(at)) then
			return nil, "time_invalid", false
		end
		if at < live.lastAt then
			return nil, "time_regressed", false
		end
		local settled, changed = settleLifecycle(live, at)
		if settled.disbandedAt ~= nil and not allowExpired then
			return nil, "party_disbanded", changed
		end
		return settled, nil, changed
	end

	local function succeed(members: { Member }, departedLeader: boolean, leaderId: string): string
		return if departedLeader then successor(members, leaderId) else leaderId
	end

	local PartyCore = {}

	function PartyCore.projectState(value: unknown): (State?, string?)
		return projectState(value)
	end

	function PartyCore.open(requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, OPEN_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		if not (type(request.partyId) == "string" and text(request.partyId)) then
			return nil, "party_id_invalid"
		end
		if type(request.realmId) ~= "string" or REALMS[request.realmId] ~= true then
			return nil, "realm_unknown"
		end
		if
			request.founderCharacterId ~= nil
			and not (type(request.founderCharacterId) == "string" and text(request.founderCharacterId))
		then
			return nil, "account_invalid"
		end
		if not (type(request.founderId) == "string" and text(request.founderId)) then
			return nil, "account_invalid"
		end
		local lootMode = request.lootMode
		if lootMode == nil then
			lootMode = DEFAULT_LOOT_MODE
		end
		if lootMode ~= "round_robin" and lootMode ~= "need_greed" then
			return nil, "loot_mode_invalid"
		end
		if not (type(request.at) == "number" and timestamp(request.at)) then
			return nil, "time_invalid"
		end
		local state, reason = projectState({
			partyId = request.partyId,
			realmId = request.realmId,
			leaderId = request.founderId,
			members = {
				{ accountId = request.founderId, characterId = request.founderCharacterId, joinedAt = request.at },
			},
			invites = {},
			lootMode = lootMode,
			lootCursor = nil,
			createdAt = request.at,
			lastAt = request.at,
			disbandedAt = nil,
		})
		if state == nil then
			return nil, reason
		end
		return advanced(state), nil
	end

	function PartyCore.invite(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, INVITE_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if
			not (type(request.accountId) == "string" and text(request.accountId))
			or not (type(request.invitedBy) == "string" and text(request.invitedBy))
		then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		local invitedBy = request.invitedBy
		if invitedBy ~= live.leaderId then
			return nil, "not_leader"
		end
		if accountId == invitedBy then
			return nil, "self_target"
		end
		if type(request.targetGrouped) ~= "boolean" then
			return nil, "grouped_flag_invalid"
		end
		if type(request.targetRealmId) ~= "string" or REALMS[request.targetRealmId] ~= true then
			return nil, "realm_unknown"
		end
		if request.targetRealmId ~= live.realmId then
			return nil, "realm_mismatch"
		end
		if memberIndex(live, accountId) ~= nil then
			return nil, "already_member"
		end
		if request.targetGrouped then
			return nil, "already_grouped"
		end
		if inviteIndex(live, accountId) ~= nil then
			return unchanged(live), nil
		end
		if #live.members + #live.invites >= MAX_MEMBERS then
			return nil, "party_full"
		end
		local invites = copyInvites(live.invites)
		table.insert(invites, Value.freezeDeep({ accountId = accountId, invitedBy = invitedBy, at = at }))
		return advanced(
			rebuild(live, copyMembers(live.members), invites, live.leaderId, live.lootMode, live.lootCursor, at, nil)
		),
			nil
	end

	function PartyCore.accept(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, ACCEPT_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if request.characterId ~= nil and not (type(request.characterId) == "string" and text(request.characterId)) then
			return nil, "account_invalid"
		end
		if not (type(request.accountId) == "string" and text(request.accountId)) then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		if type(request.accepterGrouped) ~= "boolean" then
			return nil, "grouped_flag_invalid"
		end
		if memberIndex(live, accountId) ~= nil then
			return nil, "already_member"
		end
		local pending = inviteIndex(live, accountId)
		if pending == nil then
			return nil, "invite_unknown"
		end
		if request.accepterGrouped then
			return nil, "already_grouped"
		end
		if #live.members >= MAX_MEMBERS then
			return nil, "party_full"
		end
		local invites = copyInvites(live.invites)
		table.remove(invites, pending)
		local members = copyMembers(live.members)
		table.insert(
			members,
			frozenMember({
				accountId = accountId,
				characterId = request.characterId,
				joinedAt = at,
			})
		)
		return advanced(rebuild(live, members, invites, live.leaderId, live.lootMode, live.lootCursor, at, nil)), nil
	end

	function PartyCore.decline(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, ACCOUNT_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if not (type(request.accountId) == "string" and text(request.accountId)) then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		local pending = inviteIndex(live, accountId)
		if pending == nil then
			return unchanged(live), nil
		end
		local invites = copyInvites(live.invites)
		table.remove(invites, pending)
		return advanced(
			rebuild(live, copyMembers(live.members), invites, live.leaderId, live.lootMode, live.lootCursor, at, nil)
		),
			nil
	end

	function PartyCore.leave(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, ACCOUNT_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if not (type(request.accountId) == "string" and text(request.accountId)) then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		local index = memberIndex(live, accountId)
		if index == nil then
			return nil, "not_member"
		end
		local members = copyMembers(live.members)
		table.remove(members, index)
		if #members < MINIMUM_PARTY_MEMBERS then
			return advanced(rebuild(live, {}, {}, live.leaderId, live.lootMode, live.lootCursor, at, at)), nil
		end
		local leaderId = succeed(members, accountId == live.leaderId, live.leaderId)
		return advanced(
			rebuild(live, members, copyInvites(live.invites), leaderId, live.lootMode, live.lootCursor, at, nil)
		),
			nil
	end

	function PartyCore.kick(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, KICK_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if
			not (type(request.accountId) == "string" and text(request.accountId))
			or not (type(request.by) == "string" and text(request.by))
		then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		local by = request.by
		if by ~= live.leaderId then
			return nil, "not_leader"
		end
		if accountId == by then
			return nil, "self_target"
		end
		local index = memberIndex(live, accountId)
		if index == nil then
			return nil, "not_member"
		end
		local members = copyMembers(live.members)
		table.remove(members, index)
		return advanced(
			rebuild(live, members, copyInvites(live.invites), live.leaderId, live.lootMode, live.lootCursor, at, nil)
		),
			nil
	end

	function PartyCore.transferLeader(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, TRANSFER_LEADER_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if
			not (type(request.accountId) == "string" and text(request.accountId))
			or not (type(request.by) == "string" and text(request.by))
		then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		local by = request.by
		if by ~= live.leaderId then
			return nil, "not_leader"
		end
		if accountId == by then
			return nil, "self_target"
		end
		if memberIndex(live, accountId) == nil then
			return nil, "not_member"
		end
		local target = live.members[assert(memberIndex(live, accountId))]
		local leader = live.members[assert(memberIndex(live, by))]
		if target.absentSince ~= nil or leader.absentSince ~= nil then
			return nil, "member_absent"
		end
		if live.leaderTransfer ~= nil and live.leaderTransfer.accountId == accountId then
			return unchanged(live), nil
		end
		local nextState = table.clone(
			rebuild(
				live,
				copyMembers(live.members),
				copyInvites(live.invites),
				live.leaderId,
				live.lootMode,
				live.lootCursor,
				at,
				nil
			)
		)
		nextState.leaderTransfer = Value.freezeDeep({ accountId = accountId, by = by, at = at })
		return advanced(Value.freezeDeep(nextState)), nil
	end

	function PartyCore.acceptLeaderTransfer(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, PRESENT_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, reason = openState(stateValue, request.at)
		if state == nil then
			return nil, reason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		if not (type(request.accountId) == "string" and text(request.accountId)) then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		local live = state
		local transfer = live.leaderTransfer
		if transfer == nil then
			return nil, "leader_transfer_unknown"
		end
		if accountId ~= transfer.accountId then
			return nil, "transfer_recipient_mismatch"
		end
		local member = live.members[assert(memberIndex(live, accountId))]
		if request.characterId ~= nil and not (type(request.characterId) == "string" and text(request.characterId)) then
			return nil, "account_invalid"
		end
		if request.characterId ~= nil and member.characterId ~= nil and request.characterId ~= member.characterId then
			return nil, "character_mismatch"
		end
		return advanced(
			rebuild(
				live,
				copyMembers(live.members),
				copyInvites(live.invites),
				accountId,
				live.lootMode,
				live.lootCursor,
				at,
				nil
			)
		),
			nil
	end

	function PartyCore.disband(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, DISBAND_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if not (type(request.by) == "string" and text(request.by)) then
			return nil, "account_invalid"
		end
		if request.by ~= live.leaderId then
			return nil, "not_leader"
		end
		return advanced(rebuild(live, {}, {}, live.leaderId, live.lootMode, live.lootCursor, at, at)), nil
	end

	function PartyCore.setLootMode(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, LOOT_MODE_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if not (type(request.by) == "string" and text(request.by)) then
			return nil, "account_invalid"
		end
		if request.by ~= live.leaderId then
			return nil, "not_leader"
		end
		if request.lootMode ~= "round_robin" and request.lootMode ~= "need_greed" then
			return nil, "loot_mode_invalid"
		end
		if request.lootMode == live.lootMode then
			return unchanged(live), nil
		end
		return advanced(
			rebuild(
				live,
				copyMembers(live.members),
				copyInvites(live.invites),
				live.leaderId,
				request.lootMode,
				live.lootCursor,
				at,
				nil
			)
		),
			nil
	end

	function PartyCore.markAbsent(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, ACCOUNT_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if not (type(request.accountId) == "string" and text(request.accountId)) then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		local index = memberIndex(live, accountId)
		if index == nil then
			return nil, "not_member"
		end
		if live.members[index].absentSince ~= nil then
			return unchanged(live), nil
		end
		local members = copyMembers(live.members)
		members[index] = frozenMember({
			accountId = live.members[index].accountId,
			characterId = live.members[index].characterId,
			joinedAt = live.members[index].joinedAt,
			absentSince = at,
		})
		return advanced(
			rebuild(live, members, copyInvites(live.invites), live.leaderId, live.lootMode, live.lootCursor, at, nil)
		),
			nil
	end

	function PartyCore.markPresent(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, PRESENT_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local request = assert(Value.raw(requestValue))
		local state, stateReason = openState(stateValue, request.at)
		if state == nil then
			return nil, stateReason
		end
		local at = request.at
		if type(at) ~= "number" then
			return nil, "time_invalid"
		end
		local live = state
		if not (type(request.accountId) == "string" and text(request.accountId)) then
			return nil, "account_invalid"
		end
		local accountId = request.accountId
		local index = memberIndex(live, accountId)
		if index == nil then
			return nil, "not_member"
		end
		if request.characterId ~= nil and not (type(request.characterId) == "string" and text(request.characterId)) then
			return nil, "account_invalid"
		end
		if
			request.characterId ~= nil
			and live.members[index].characterId ~= nil
			and request.characterId ~= live.members[index].characterId
		then
			return nil, "character_mismatch"
		end
		if
			live.members[index].absentSince == nil
			and (request.characterId == nil or live.members[index].characterId ~= nil)
		then
			return unchanged(live), nil
		end
		local members = copyMembers(live.members)
		members[index] = frozenMember({
			accountId = live.members[index].accountId,
			characterId = request.characterId or live.members[index].characterId,
			joinedAt = live.members[index].joinedAt,
			absentSince = nil,
		})
		return advanced(
			rebuild(live, members, copyInvites(live.invites), live.leaderId, live.lootMode, live.lootCursor, at, nil)
		),
			nil
	end

	function PartyCore.sweep(stateValue: unknown, requestValue: unknown): (Result?, string?)
		if not hasOnlyFields(requestValue, SWEEP_REQUEST_FIELDS) then
			return nil, "request_shape_invalid"
		end
		local state, reason, changed = openState(stateValue, assert(Value.raw(requestValue)).at, true)
		if state == nil then
			return nil, reason
		end
		return if changed then advanced(state) else unchanged(state), nil
	end

	return Value.freezeDeep(PartyCore)
end
export type Core = {
	read projectState: (unknown) -> (State?, string?),
	read open: (unknown) -> (Result?, string?),
	read invite: (unknown, unknown) -> (Result?, string?),
	read accept: (unknown, unknown) -> (Result?, string?),
	read decline: (unknown, unknown) -> (Result?, string?),
	read leave: (unknown, unknown) -> (Result?, string?),
	read kick: (unknown, unknown) -> (Result?, string?),
	read transferLeader: (unknown, unknown) -> (Result?, string?),
	read acceptLeaderTransfer: (unknown, unknown) -> (Result?, string?),
	read disband: (unknown, unknown) -> (Result?, string?),
	read setLootMode: (unknown, unknown) -> (Result?, string?),
	read markAbsent: (unknown, unknown) -> (Result?, string?),
	read markPresent: (unknown, unknown) -> (Result?, string?),
	read sweep: (unknown, unknown) -> (Result?, string?),
}
return Value.freezeDeep(System)
