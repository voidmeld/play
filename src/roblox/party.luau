--!strict
local Codec = require("../kernel/codec")
local Membership = require("../core/social/membership")
local Result = require("../kernel/result")
local Store = require("../kernel/store")
local Value = require("../kernel/value")
type CoreState = Membership.State
type CoreResult = Membership.Result

export type StoreOutcome = Result.Result<unknown>
export type Store = Store.Port

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
		return Value.record(value, fields, false) ~= nil
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

	local function buildRecord(state: CoreState): StoreOutcome
		local projected, reason = Core.projectState(state)
		if projected == nil then
			return Result.fail(reason or "record_invalid")
		end
		return Codec.copyData({ schemaVersion = SCHEMA_VERSION, partyId = state.partyId, party = projected })
	end

	local function readRecord(value: unknown, partyId: string): (CoreState?, string?)
		if not hasOnlyFields(value, RECORD_FIELDS) then
			return nil, "record_invalid"
		end
		local raw = assert(Value.raw(value))
		if Value.whole(raw.schemaVersion, 1, math.huge) == nil then
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
			or type(((dependencies).store).read) ~= "function"
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
			local replayed = false
			local transformFail: string? = nil
			local expected: StoreOutcome = Result.fail("store_failure")
			local result = deps.store.update(deps.keyForParty(partyId), function(current)
				replayed = false
				transformFail = nil
				expected = Result.fail("store_failure")
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
				replayed = wasReplayed and nextState.lastAt == state.lastAt
				if replayed then
					expected = Codec.copyData(current)
					return nil
				end
				local desired = buildRecord(nextState)
				expected = if desired.ok then Codec.copyData(desired.value) else desired
				return if desired.ok then desired.value else nil
			end)
			local observed = result
			if not result.ok then
				if result.reason ~= "callback_cancelled" then
					return refused(result.reason)
				end
				if not replayed then
					return refused(transformFail or "store_failure")
				end
				observed = Store.confirm(deps.store, deps.keyForParty(partyId), expected)
			end
			if not observed.ok then
				return refused(observed.reason)
			end
			local readback, reason = readRecord(observed.value, partyId)
			if readback == nil then
				return refused(reason or "readback_mismatch")
			end
			if not expected.ok or not Codec.equalData(observed.value, expected.value) then
				return refused("readback_mismatch")
			end
			return frozenOutcome({
				ok = true,
				reason = nil,
				replayed = replayed,
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
			local expected = buildRecord(fresh)
			if not expected.ok then
				return refused(expected.reason)
			end
			local transformFail: string? = nil
			local produced = false
			local outcome = deps.store.update(deps.keyForParty(partyId), function(current)
				transformFail = nil
				produced = false
				if current ~= nil then
					transformFail = "party_exists"
					return nil
				end
				local desired = buildRecord(fresh)
				produced = desired.ok
				return if desired.ok then desired.value else nil
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
			if not produced or not Codec.equalData(outcome.value, expected.value) then
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
			local result = deps.store.read(deps.keyForParty(partyIdValue))
			if not result.ok then
				return refused(result.reason)
			end
			if result.value == nil then
				return frozenOutcome({
					ok = true,
					reason = nil,
					replayed = false,
					found = false,
					party = nil,
					boundary = BOUNDARY,
				})
			end
			local state, reason = readRecord(result.value, partyIdValue)
			if state == nil then
				return refused(reason or "record_invalid")
			end
			return frozenOutcome({
				ok = true,
				reason = nil,
				replayed = false,
				found = true,
				party = state,
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
