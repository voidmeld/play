--!strict
local Membership = require("../core/social/membership")
local Value = require("../kernel/value")
type CoreMember = Membership.Member
type CoreInvite = Membership.Invite
type CoreState = Membership.State
type CoreResult = Membership.Result

export type StoreOutcome = { ok: boolean, value: unknown, reason: string? }
export type Store = { update: (string, (unknown) -> unknown) -> StoreOutcome }

export type Dependencies = {
	store: Store,
	keyForParty: (string) -> string,
	readMembership: (string) -> unknown,
}

export type PartyOutcome = {
	ok: boolean,
	reason: string?,
	replayed: boolean,
	found: boolean,
	party: CoreState?,
	boundary: string,
}

export type Service = {
	open: (request: unknown) -> PartyOutcome,
	invite: (request: unknown) -> PartyOutcome,
	accept: (request: unknown) -> PartyOutcome,
	decline: (request: unknown) -> PartyOutcome,
	leave: (request: unknown) -> PartyOutcome,
	kick: (request: unknown) -> PartyOutcome,
	transferLeader: (request: unknown) -> PartyOutcome,
	acceptLeaderTransfer: (request: unknown) -> PartyOutcome,
	disband: (request: unknown) -> PartyOutcome,
	setLootMode: (request: unknown) -> PartyOutcome,
	markAbsent: (request: unknown) -> PartyOutcome,
	markPresent: (request: unknown) -> PartyOutcome,
	sweep: (request: unknown) -> PartyOutcome,
	read: (partyId: unknown) -> PartyOutcome,
}

export type MountResult = {
	ok: boolean,
	service: Service?,
	reason: string?,
}

export type Config = { core: Membership.Core, schemaVersion: number, boundary: string, maxText: number }
local System = {}
function System.party(config: Config)
	local Core = config.core
	local SCHEMA_VERSION = config.schemaVersion
	local BOUNDARY = config.boundary
	local REASONS: { string } = {
		"dependencies_malformed",
		"request_shape_invalid",
		"party_id_invalid",
		"account_invalid",
		"record_invalid",
		"schema_unknown",
		"party_mismatch",
		"party_missing",
		"party_exists",
		"membership_load_failed",
		"core_refused",
		"store_failure",
		"readback_mismatch",
		"read_wrote",
	}

	local RECORD_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		partyId = true,
		party = true,
	}

	local OPEN_FIELDS: { [string]: boolean } = {
		partyId = true,
		realmId = true,
		founderId = true,
		founderCharacterId = true,
		lootMode = true,
		at = true,
	}

	local INVITE_FIELDS: { [string]: boolean } = {
		partyId = true,
		accountId = true,
		invitedBy = true,
		targetRealmId = true,
		at = true,
	}

	local ACCEPT_FIELDS: { [string]: boolean } = {
		partyId = true,
		characterId = true,
		accountId = true,
		at = true,
	}

	local PRESENT_FIELDS: { [string]: boolean } = { partyId = true, accountId = true, characterId = true, at = true }

	local ACCOUNT_FIELDS: { [string]: boolean } = {
		partyId = true,
		accountId = true,
		at = true,
	}

	local KICK_FIELDS: { [string]: boolean } = {
		partyId = true,
		accountId = true,
		by = true,
		at = true,
	}

	local TRANSFER_LEADER_FIELDS: { [string]: boolean } = {
		partyId = true,
		accountId = true,
		by = true,
		at = true,
	}

	local DISBAND_FIELDS: { [string]: boolean } = {
		partyId = true,
		by = true,
		at = true,
	}

	local LOOT_MODE_FIELDS: { [string]: boolean } = {
		partyId = true,
		by = true,
		lootMode = true,
		at = true,
	}

	local SWEEP_FIELDS: { [string]: boolean } = {
		partyId = true,
		at = true,
	}

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= config.maxText
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

	local function frozenOutcome(value: PartyOutcome): PartyOutcome
		return Value.freezeDeep(value)
	end
	local function mounted(value: MountResult): MountResult
		return Value.freezeDeep(value)
	end
	local function refusedMount(reason: string): MountResult
		return mounted({ ok = false, service = nil, reason = reason })
	end

	local function refused(reason: string): PartyOutcome
		return frozenOutcome({
			ok = false,
			reason = reason,
			replayed = false,
			found = false,
			party = nil,
			boundary = BOUNDARY,
		})
	end

	local function plainMembers(state: CoreState): { CoreMember }
		local rows: { CoreMember } = {}
		for index, member in state.members do
			rows[index] = {
				accountId = member.accountId,
				characterId = member.characterId,
				joinedAt = member.joinedAt,
				absentSince = member.absentSince,
			}
		end
		return rows
	end

	local function plainInvites(state: CoreState): { CoreInvite }
		local rows: { CoreInvite } = {}
		for index, invite in state.invites do
			rows[index] = {
				accountId = invite.accountId,
				invitedBy = invite.invitedBy,
				at = invite.at,
			}
		end
		return rows
	end

	type PartyRecord = { schemaVersion: number, partyId: string, party: CoreState }

	local function buildRecord(state: CoreState): PartyRecord
		return {
			schemaVersion = SCHEMA_VERSION,
			partyId = state.partyId,
			party = {
				partyId = state.partyId,
				realmId = state.realmId,
				leaderId = state.leaderId,
				leaderTransfer = if state.leaderTransfer == nil
					then nil
					else {
						accountId = state.leaderTransfer.accountId,
						by = state.leaderTransfer.by,
						at = state.leaderTransfer.at,
					},
				members = plainMembers(state),
				invites = plainInvites(state),
				lootMode = state.lootMode,
				lootCursor = state.lootCursor,
				createdAt = state.createdAt,
				lastAt = state.lastAt,
				disbandedAt = state.disbandedAt,
			},
		}
	end

	local function readRecord(value: unknown, partyId: string): (CoreState?, string?)
		if not hasOnlyFields(value, RECORD_FIELDS) then
			return nil, "record_invalid"
		end
		local raw = assert(Value.raw(value))
		if
			type(raw.schemaVersion) ~= "number"
			or raw.schemaVersion ~= raw.schemaVersion
			or raw.schemaVersion == math.huge
			or raw.schemaVersion < 1
			or raw.schemaVersion ~= math.floor(raw.schemaVersion)
		then
			return nil, "record_invalid"
		end
		if raw.schemaVersion ~= SCHEMA_VERSION then
			return nil, "schema_unknown"
		end
		if raw.partyId ~= partyId then
			return nil, "party_mismatch"
		end
		local state, stateReason = Core.projectState(raw.party)
		if state == nil then
			return nil, stateReason or "record_invalid"
		end
		if (state).partyId ~= partyId then
			return nil, "party_mismatch"
		end
		return state, nil
	end

	local PartyService = {}

	function PartyService.mount(dependencies: Dependencies?): MountResult
		if
			type(dependencies) ~= "table"
			or type((dependencies).store) ~= "table"
			or type(((dependencies).store).update) ~= "function"
			or type((dependencies).keyForParty) ~= "function"
			or type((dependencies).readMembership) ~= "function"
		then
			return refusedMount("dependencies_malformed")
		end
		local deps = dependencies

		local function membershipOf(accountId: string): (string?, string?)
			local loaded = table.pack(pcall(deps.readMembership, accountId))
			if loaded.n ~= 2 or loaded[1] ~= true then
				return nil, "membership_load_failed"
			end
			local value = loaded[2]
			if value == nil then
				return nil, nil
			end
			if not (type(value) == "string" and text(value)) then
				return nil, "membership_load_failed"
			end
			return value, nil
		end

		local function commit(partyId: string, transform: (CoreState) -> (CoreState?, boolean, string?)): PartyOutcome
			local captured: CoreState? = nil
			local replayed = false
			local transformFail: string? = nil
			local result = deps.store.update(deps.keyForParty(partyId), function(current)
				captured = nil
				replayed = false
				transformFail = nil
				if current == nil then
					transformFail = "party_missing"
					return nil
				end
				local state, migrateReason = readRecord(current, partyId)
				if state == nil then
					transformFail = migrateReason
					return nil
				end
				local nextState, wasReplayed, reason = transform(state)
				if nextState == nil then
					transformFail = reason
					return nil
				end
				captured = nextState
				replayed = wasReplayed and nextState.lastAt == (state).lastAt
				if replayed then
					return nil
				end
				return buildRecord(nextState)
			end)

			if not result.ok then
				if result.reason ~= "callback_cancelled" then
					return refused(result.reason or "store_failure")
				end
				if replayed and captured ~= nil then
					return frozenOutcome({
						ok = true,
						reason = nil,
						replayed = true,
						found = true,
						party = captured,
						boundary = BOUNDARY,
					})
				end
				return refused(transformFail or "store_failure")
			end

			local readback, readbackReason = readRecord(result.value, partyId)
			if readback == nil then
				return refused(readbackReason or "readback_mismatch")
			end
			if captured == nil or (readback).lastAt ~= (captured).lastAt then
				return refused("readback_mismatch")
			end
			return frozenOutcome({
				ok = true,
				reason = nil,
				replayed = false,
				found = true,
				party = readback,
				boundary = BOUNDARY,
			})
		end

		local function open(requestValue: unknown): PartyOutcome
			if not hasOnlyFields(requestValue, OPEN_FIELDS) then
				return refused("request_shape_invalid")
			end
			local request = assert(Value.raw(requestValue))
			if not (type(request.partyId) == "string" and text(request.partyId)) then
				return refused("party_id_invalid")
			end
			local partyId = request.partyId
			local result, reason = Core.open({
				partyId = partyId,
				realmId = request.realmId,
				founderId = request.founderId,
				founderCharacterId = request.founderCharacterId,
				lootMode = request.lootMode,
				at = request.at,
			})
			if result == nil then
				return refused("core_refused: " .. tostring(reason))
			end
			local fresh = (result).state
			local transformFail: string? = nil
			local outcome = deps.store.update(deps.keyForParty(partyId), function(current)
				transformFail = nil
				if current ~= nil then
					transformFail = "party_exists"
					return nil
				end
				return buildRecord(fresh)
			end)
			if not outcome.ok then
				if outcome.reason ~= "callback_cancelled" then
					return refused(outcome.reason or "store_failure")
				end
				return refused(transformFail or "store_failure")
			end
			local readback, readbackReason = readRecord(outcome.value, partyId)
			if readback == nil then
				return refused(readbackReason or "readback_mismatch")
			end
			return frozenOutcome({
				ok = true,
				reason = nil,
				replayed = false,
				found = true,
				party = readback,
				boundary = BOUNDARY,
			})
		end

		local function invite(requestValue: unknown): PartyOutcome
			if not hasOnlyFields(requestValue, INVITE_FIELDS) then
				return refused("request_shape_invalid")
			end
			local request = assert(Value.raw(requestValue))
			if not (type(request.partyId) == "string" and text(request.partyId)) then
				return refused("party_id_invalid")
			end
			if not (type(request.accountId) == "string" and text(request.accountId)) then
				return refused("account_invalid")
			end
			local held, membershipReason = membershipOf(request.accountId)
			if membershipReason ~= nil then
				return refused(membershipReason)
			end
			local grouped = held ~= nil and held ~= request.partyId
			return commit(request.partyId, function(state)
				local result, reason = Core.invite(state, {
					accountId = request.accountId,
					invitedBy = request.invitedBy,
					targetRealmId = request.targetRealmId,
					targetGrouped = grouped,
					at = request.at,
				})
				if result == nil then
					return nil, false, "core_refused: " .. tostring(reason)
				end
				return (result).state, (result).replayed, nil
			end)
		end

		local function accept(requestValue: unknown): PartyOutcome
			if not hasOnlyFields(requestValue, ACCEPT_FIELDS) then
				return refused("request_shape_invalid")
			end
			local request = assert(Value.raw(requestValue))
			if not (type(request.partyId) == "string" and text(request.partyId)) then
				return refused("party_id_invalid")
			end
			if not (type(request.accountId) == "string" and text(request.accountId)) then
				return refused("account_invalid")
			end
			local held, membershipReason = membershipOf(request.accountId)
			if membershipReason ~= nil then
				return refused(membershipReason)
			end
			local grouped = held ~= nil and held ~= request.partyId
			return commit(request.partyId, function(state)
				local result, reason = Core.accept(state, {
					accountId = request.accountId,
					accepterGrouped = grouped,
					characterId = request.characterId,
					at = request.at,
				})
				if result == nil then
					return nil, false, "core_refused: " .. tostring(reason)
				end
				return (result).state, (result).replayed, nil
			end)
		end

		local function accountCommand(
			fields: { [string]: boolean },
			apply: (CoreState, { [unknown]: unknown }) -> (CoreResult?, string?)
		): (requestValue: unknown) -> PartyOutcome
			return function(requestValue: unknown): PartyOutcome
				if not hasOnlyFields(requestValue, fields) then
					return refused("request_shape_invalid")
				end
				local request = assert(Value.raw(requestValue))
				if not (type(request.partyId) == "string" and text(request.partyId)) then
					return refused("party_id_invalid")
				end
				return commit(request.partyId, function(state)
					local result, reason = apply(state, request)
					if result == nil then
						return nil, false, "core_refused: " .. tostring(reason)
					end
					return (result).state, (result).replayed, nil
				end)
			end
		end

		local decline = accountCommand(ACCOUNT_FIELDS, function(state, request)
			return Core.decline(state, { accountId = request.accountId, at = request.at })
		end)

		local leave = accountCommand(ACCOUNT_FIELDS, function(state, request)
			return Core.leave(state, { accountId = request.accountId, at = request.at })
		end)

		local kick = accountCommand(KICK_FIELDS, function(state, request)
			return Core.kick(state, { accountId = request.accountId, by = request.by, at = request.at })
		end)

		local transferLeader = accountCommand(TRANSFER_LEADER_FIELDS, function(state, request)
			return Core.transferLeader(state, { accountId = request.accountId, by = request.by, at = request.at })
		end)

		local acceptLeaderTransfer = accountCommand(PRESENT_FIELDS, function(state, request)
			return Core.acceptLeaderTransfer(
				state,
				{ accountId = request.accountId, characterId = request.characterId, at = request.at }
			)
		end)

		local disband = accountCommand(DISBAND_FIELDS, function(state, request)
			return Core.disband(state, { by = request.by, at = request.at })
		end)

		local setLootMode = accountCommand(LOOT_MODE_FIELDS, function(state, request)
			return Core.setLootMode(state, { by = request.by, lootMode = request.lootMode, at = request.at })
		end)

		local markAbsent = accountCommand(ACCOUNT_FIELDS, function(state, request)
			return Core.markAbsent(state, { accountId = request.accountId, at = request.at })
		end)

		local markPresent = accountCommand(PRESENT_FIELDS, function(state, request)
			return Core.markPresent(
				state,
				{ accountId = request.accountId, characterId = request.characterId, at = request.at }
			)
		end)

		local sweep = accountCommand(SWEEP_FIELDS, function(state, request)
			return Core.sweep(state, { at = request.at })
		end)

		local function read(partyIdValue: unknown): PartyOutcome
			if not (type(partyIdValue) == "string" and text(partyIdValue)) then
				return refused("party_id_invalid")
			end
			local partyId = partyIdValue
			local captured: CoreState? = nil
			local missing = false
			local transformFail: string? = nil
			local result = deps.store.update(deps.keyForParty(partyId), function(current)
				captured = nil
				missing = false
				transformFail = nil
				if current == nil then
					missing = true
					return nil
				end
				local state, migrateReason = readRecord(current, partyId)
				if state == nil then
					transformFail = migrateReason
					return nil
				end
				captured = state
				return nil
			end)
			if result.ok then
				return refused("read_wrote")
			end
			if result.reason ~= "callback_cancelled" then
				return refused(result.reason or "store_failure")
			end
			if missing then
				return frozenOutcome({
					ok = true,
					reason = nil,
					replayed = false,
					found = false,
					party = nil,
					boundary = BOUNDARY,
				})
			end
			if captured == nil then
				return refused(transformFail or "store_failure")
			end
			return frozenOutcome({
				ok = true,
				reason = nil,
				replayed = false,
				found = true,
				party = captured,
				boundary = BOUNDARY,
			})
		end

		local service: Service = Value.freezeDeep({
			open = open,
			invite = invite,
			accept = accept,
			decline = decline,
			leave = leave,
			kick = kick,
			transferLeader = transferLeader,
			acceptLeaderTransfer = acceptLeaderTransfer,
			disband = disband,
			setLootMode = setLootMode,
			markAbsent = markAbsent,
			markPresent = markPresent,
			sweep = sweep,
			read = read,
		})
		return mounted({ ok = true, service = service, reason = nil })
	end

	PartyService.SCHEMA_VERSION = SCHEMA_VERSION
	PartyService.REASONS = Value.freezeDeep(REASONS)
	return Value.freezeDeep(PartyService)
end
return Value.freezeDeep(System)
