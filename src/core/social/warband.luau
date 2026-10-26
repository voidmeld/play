--!strict

local SocialShape = require("./shape")

export type Party = {
	realmId: string,
	leaderId: string,
	characterId: string,
	connected: boolean,
	absentSinceSec: number?,
	closed: boolean?,
}
export type Unit = { partyId: string, joinedAtSec: number, membershipRevision: number }
export type Invite = { byPartyId: string, expiresAtSec: number }
export type Transfer = { partyId: string, expiresAtSec: number }
export type Order = { kind: string, objectiveId: string, byPartyId: string, byActorId: string?, atSec: number }
export type State = {
	schemaVersion: number,
	warbandId: string,
	realmId: string,
	revision: number,
	lastClockSec: number,
	units: { Unit },
	commanderPartyId: string?,
	commanderAbsentSinceSec: number?,
	assistants: { string },
	invites: { [string]: Invite },
	transfer: Transfer?,
	order: Order?,
	rallyObjectiveId: string?,
	targetObjectiveId: string?,
	rallyByActorId: string?,
	targetByActorId: string?,
}
export type Event = {
	kind: string,
	actorPartyId: string,
	actorId: string,
	expectedRevision: number,
	targetPartyId: string?,
	membershipRevision: number?,
	orderKind: string?,
	objectiveId: string?,
}
export type Parties = { [string]: Party }
export type Result = { ok: boolean, state: State?, reason: string? }

export type Config = {
	maxParties: number,
	inviteSeconds: number,
	transferSeconds: number,
	successionSeconds: number,
	orders: { [string]: boolean },
	realms: { [string]: boolean },
	maxId: number,
	maxInteger: number,
	maxAssistants: number,
}

local System = {}

function System.warband(config: Config)
	local function readUnit(value: unknown): Unit?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { partyId = true, joinedAtSec = true, membershipRevision = true }) then
			return nil
		end
		local partyId = SocialShape.string(raw.partyId)
		if partyId == nil then
			return nil
		end
		local joinedAtSec = SocialShape.number(raw.joinedAtSec)
		if joinedAtSec == nil then
			return nil
		end
		local membershipRevision = SocialShape.number(raw.membershipRevision)
		if membershipRevision == nil then
			return nil
		end
		return { partyId = partyId, joinedAtSec = joinedAtSec, membershipRevision = membershipRevision }
	end

	local function readInvite(value: unknown): Invite?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { byPartyId = true, expiresAtSec = true }) then
			return nil
		end
		local byPartyId = SocialShape.string(raw.byPartyId)
		if byPartyId == nil then
			return nil
		end
		local expiresAtSec = SocialShape.number(raw.expiresAtSec)
		if expiresAtSec == nil then
			return nil
		end
		return { byPartyId = byPartyId, expiresAtSec = expiresAtSec }
	end

	local function readTransfer(value: unknown): Transfer?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { partyId = true, expiresAtSec = true }) then
			return nil
		end
		local partyId = SocialShape.string(raw.partyId)
		if partyId == nil then
			return nil
		end
		local expiresAtSec = SocialShape.number(raw.expiresAtSec)
		if expiresAtSec == nil then
			return nil
		end
		return { partyId = partyId, expiresAtSec = expiresAtSec }
	end

	local function readOrder(value: unknown): Order?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(
				value,
				{ kind = true, objectiveId = true, byPartyId = true, byActorId = true, atSec = true }
			)
		then
			return nil
		end
		local kind = SocialShape.string(raw.kind)
		if kind == nil then
			return nil
		end
		local objectiveId = SocialShape.string(raw.objectiveId)
		if objectiveId == nil then
			return nil
		end
		local byPartyId = SocialShape.string(raw.byPartyId)
		if byPartyId == nil then
			return nil
		end
		local byActorId = SocialShape.string(raw.byActorId)
		if raw.byActorId ~= nil and byActorId == nil then
			return nil
		end
		local atSec = SocialShape.number(raw.atSec)
		if atSec == nil then
			return nil
		end
		return { kind = kind, objectiveId = objectiveId, byPartyId = byPartyId, byActorId = byActorId, atSec = atSec }
	end

	local function readState(value: unknown): State?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				schemaVersion = true,
				warbandId = true,
				realmId = true,
				revision = true,
				lastClockSec = true,
				units = true,
				commanderPartyId = true,
				commanderAbsentSinceSec = true,
				assistants = true,
				invites = true,
				transfer = true,
				order = true,
				rallyObjectiveId = true,
				targetObjectiveId = true,
				rallyByActorId = true,
				targetByActorId = true,
			})
		then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local warbandId = SocialShape.string(raw.warbandId)
		if warbandId == nil then
			return nil
		end
		local realmId = SocialShape.string(raw.realmId)
		if realmId == nil then
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
		local units = SocialShape.array(raw.units, readUnit)
		if units == nil then
			return nil
		end
		local commanderPartyId = SocialShape.string(raw.commanderPartyId)
		if raw.commanderPartyId ~= nil and commanderPartyId == nil then
			return nil
		end
		local commanderAbsentSinceSec = SocialShape.number(raw.commanderAbsentSinceSec)
		if raw.commanderAbsentSinceSec ~= nil and commanderAbsentSinceSec == nil then
			return nil
		end
		local assistants = SocialShape.array(raw.assistants, SocialShape.string)
		if assistants == nil then
			return nil
		end
		local invites = SocialShape.map(raw.invites, SocialShape.string, readInvite)
		if invites == nil then
			return nil
		end
		local transfer = readTransfer(raw.transfer)
		if raw.transfer ~= nil and transfer == nil then
			return nil
		end
		local order = readOrder(raw.order)
		if raw.order ~= nil and order == nil then
			return nil
		end
		local rallyObjectiveId = SocialShape.string(raw.rallyObjectiveId)
		if raw.rallyObjectiveId ~= nil and rallyObjectiveId == nil then
			return nil
		end
		local targetObjectiveId = SocialShape.string(raw.targetObjectiveId)
		if raw.targetObjectiveId ~= nil and targetObjectiveId == nil then
			return nil
		end
		local rallyByActorId = SocialShape.string(raw.rallyByActorId)
		if raw.rallyByActorId ~= nil and rallyByActorId == nil then
			return nil
		end
		local targetByActorId = SocialShape.string(raw.targetByActorId)
		if raw.targetByActorId ~= nil and targetByActorId == nil then
			return nil
		end
		return {
			schemaVersion = schemaVersion,
			warbandId = warbandId,
			realmId = realmId,
			revision = revision,
			lastClockSec = lastClockSec,
			units = units,
			commanderPartyId = commanderPartyId,
			commanderAbsentSinceSec = commanderAbsentSinceSec,
			assistants = assistants,
			invites = invites,
			transfer = transfer,
			order = order,
			rallyObjectiveId = rallyObjectiveId,
			targetObjectiveId = targetObjectiveId,
			rallyByActorId = rallyByActorId,
			targetByActorId = targetByActorId,
		}
	end

	local Core = {}
	Core.MAX_PARTIES = config.maxParties
	Core.INVITE_SECONDS = config.inviteSeconds
	Core.TRANSFER_SECONDS = config.transferSeconds
	Core.SUCCESSION_SECONDS = config.successionSeconds
	Core.ORDERS = config.orders

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= config.maxId
	end

	local function integer(value: unknown): boolean
		return type(value) == "number" and value >= 0 and value < config.maxInteger and value % 1 == 0
	end

	local function unitOf(state: State, partyId: string): Unit?
		for _, unit in state.units do
			if unit.partyId == partyId then
				return unit
			end
		end
		return nil
	end

	function Core.project<T>(value: T): T?
		local probe: unknown = value
		if type(probe) ~= "table" then
			return nil
		end
		local state = readState(probe)
		if state == nil then
			return nil
		end
		if
			state.schemaVersion ~= 1
			or not text(state.warbandId)
			or not integer(state.revision)
			or not integer(state.lastClockSec)
			or config.realms[state.realmId] ~= true
			or type(state.units) ~= "table"
			or #state.units > Core.MAX_PARTIES
			or type(state.assistants) ~= "table"
			or #state.assistants > config.maxAssistants
			or type(state.invites) ~= "table"
		then
			return nil
		end
		local seen: { [string]: boolean } = {}
		for _, unit in state.units do
			if
				type(unit) ~= "table"
				or not text(unit.partyId)
				or not integer(unit.joinedAtSec)
				or not integer(unit.membershipRevision)
				or seen[unit.partyId]
			then
				return nil
			end
			seen[unit.partyId] = true
		end
		if state.commanderPartyId ~= nil and not seen[state.commanderPartyId] then
			return nil
		end
		if state.commanderAbsentSinceSec ~= nil and not integer(state.commanderAbsentSinceSec) then
			return nil
		end
		local assistants: { [string]: boolean } = {}
		for _, id in state.assistants do
			if not seen[id] or assistants[id] or id == state.commanderPartyId then
				return nil
			end
			assistants[id] = true
		end
		for id, invite in state.invites do
			if
				not text(id)
				or type(invite) ~= "table"
				or not text(invite.byPartyId)
				or not integer(invite.expiresAtSec)
			then
				return nil
			end
		end
		if
			state.transfer ~= nil
			and (
				type(state.transfer) ~= "table"
				or not text(state.transfer.partyId)
				or not integer(state.transfer.expiresAtSec)
			)
		then
			return nil
		end
		if
			state.order ~= nil
			and (
				type(state.order) ~= "table"
				or not Core.ORDERS[state.order.kind]
				or not text(state.order.objectiveId)
				or not text(state.order.byPartyId)
				or (state.order.byActorId ~= nil and not text(state.order.byActorId))
				or not integer(state.order.atSec)
			)
		then
			return nil
		end
		if state.rallyObjectiveId ~= nil and not text(state.rallyObjectiveId) then
			return nil
		end
		if state.targetObjectiveId ~= nil and not text(state.targetObjectiveId) then
			return nil
		end
		if
			(state.rallyByActorId ~= nil and not text(state.rallyByActorId))
			or (state.targetByActorId ~= nil and not text(state.targetByActorId))
		then
			return nil
		end
		return value
	end

	local function copy(state: State): State
		local next = table.clone(state)
		next.units = {}
		for _, unit in state.units do
			table.insert(next.units, table.clone(unit))
		end
		next.assistants = table.clone(state.assistants)
		next.invites = table.clone(state.invites)
		return next
	end

	local function successor(state: State, parties: Parties): string?
		local best: Unit? = nil
		for _, unit in state.units do
			local party = parties[unit.partyId]
			if party ~= nil and party.connected then
				local prior = if best ~= nil then parties[best.partyId] else nil
				if
					best == nil
					or unit.joinedAtSec < best.joinedAtSec
					or (unit.joinedAtSec == best.joinedAtSec and prior ~= nil and party.characterId < prior.characterId)
				then
					best = unit
				end
			end
		end
		return if best ~= nil then best.partyId else nil
	end

	local function command(state: State, partyId: string): boolean
		return state.commanderPartyId == partyId or table.find(state.assistants, partyId) ~= nil
	end

	function Core.found(
		warbandId: string,
		partyId: string,
		party: Party,
		membershipRevision: number,
		now: number
	): Result
		if
			not text(warbandId)
			or not text(partyId)
			or not text(party.leaderId)
			or not text(party.characterId)
			or not party.connected
			or not integer(membershipRevision)
			or not integer(now)
		then
			return { ok = false, reason = "warband_invalid" }
		end
		local state: State = {
			schemaVersion = 1,
			warbandId = warbandId,
			realmId = party.realmId,
			revision = 1,
			lastClockSec = now,
			units = { { partyId = partyId, joinedAtSec = now, membershipRevision = membershipRevision } },
			commanderPartyId = partyId,
			assistants = {},
			invites = {},
		}
		if Core.project(state) == nil then
			return { ok = false, reason = "warband_invalid" }
		end
		return { ok = true, state = state }
	end

	function Core.transition(previous: State, event: Event, parties: Parties, now: number): Result
		if Core.project(previous) == nil or not integer(now) or now < previous.lastClockSec then
			return { ok = false, reason = "warband_invalid" }
		end
		if event.kind ~= "observe" and event.expectedRevision ~= previous.revision then
			return { ok = false, reason = "warband_stale" }
		end
		local state = copy(previous)
		local pruned = false
		local removedCommander = false
		for index = #state.units, 1, -1 do
			local id = state.units[index].partyId
			local party = parties[id]
			if party ~= nil and party.closed then
				table.remove(state.units, index)
				local assistant = table.find(state.assistants, id)
				if assistant ~= nil then
					table.remove(state.assistants, assistant)
				end
				if state.commanderPartyId == id then
					state.commanderPartyId = nil
					state.commanderAbsentSinceSec = now
					removedCommander = true
				end
				if state.transfer ~= nil and state.transfer.partyId == id then
					state.transfer = nil
				end
				pruned = true
			end
		end
		local commander = if state.commanderPartyId ~= nil then parties[state.commanderPartyId] else nil
		if commander ~= nil and commander.connected then
			state.commanderAbsentSinceSec = nil
		else
			state.commanderAbsentSinceSec = state.commanderAbsentSinceSec
				or (if commander ~= nil then commander.absentSinceSec else nil)
				or now
			if removedCommander or now - assert(state.commanderAbsentSinceSec) >= Core.SUCCESSION_SECONDS then
				local id = successor(state, parties)
				if id ~= nil then
					state.commanderPartyId = id
					state.commanderAbsentSinceSec = nil
					state.transfer = nil
					local index = table.find(state.assistants, id)
					if index ~= nil then
						table.remove(state.assistants, index)
					end
				end
			end
		end
		if event.kind ~= "observe" then
			local actor = parties[event.actorPartyId]
			if actor == nil or not actor.connected or actor.leaderId ~= event.actorId then
				return { ok = false, reason = "warband_not_leader" }
			end
			if actor.realmId ~= state.realmId then
				return { ok = false, reason = "warband_wrong_realm" }
			end
			local target = event.targetPartyId
			if event.kind == "accept" then
				local invite = state.invites[event.actorPartyId]
				if
					invite == nil
					or invite.expiresAtSec <= now
					or not command(state, invite.byPartyId)
					or unitOf(state, event.actorPartyId) ~= nil
					or #state.units >= Core.MAX_PARTIES
					or not integer(event.membershipRevision)
				then
					return { ok = false, reason = "warband_invite_invalid" }
				end
				table.insert(state.units, {
					partyId = event.actorPartyId,
					joinedAtSec = now,
					membershipRevision = assert(SocialShape.number(event.membershipRevision)),
				})
				state.invites[event.actorPartyId] = nil
			elseif unitOf(state, event.actorPartyId) == nil then
				return { ok = false, reason = "warband_not_member" }
			elseif event.kind == "invite" then
				local recipient = if target ~= nil then parties[target] else nil
				if not command(state, event.actorPartyId) then
					return { ok = false, reason = "warband_not_command" }
				end
				if
					target == nil
					or recipient == nil
					or not recipient.connected
					or recipient.realmId ~= state.realmId
					or unitOf(state, target) ~= nil
				then
					return { ok = false, reason = "warband_invite_invalid" }
				end
				state.invites[target] = { byPartyId = event.actorPartyId, expiresAtSec = now + Core.INVITE_SECONDS }
			elseif event.kind == "leave" or event.kind == "remove" then
				if event.kind == "remove" and state.commanderPartyId ~= event.actorPartyId then
					return { ok = false, reason = "warband_not_commander" }
				end
				local removed = if event.kind == "leave" then event.actorPartyId else target
				if removed == nil or unitOf(state, removed) == nil then
					return { ok = false, reason = "warband_not_member" }
				end
				for index = #state.units, 1, -1 do
					if state.units[index].partyId == removed then
						table.remove(state.units, index)
					end
				end
				local assistant = table.find(state.assistants, removed)
				if assistant ~= nil then
					table.remove(state.assistants, assistant)
				end
				if state.commanderPartyId == removed then
					state.commanderPartyId = successor(state, parties)
					state.commanderAbsentSinceSec = if state.commanderPartyId == nil then now else nil
					state.transfer = nil
					local index = if state.commanderPartyId ~= nil
						then table.find(state.assistants, state.commanderPartyId)
						else nil
					if index ~= nil then
						table.remove(state.assistants, index)
					end
				end
			elseif event.kind == "assistant" or event.kind == "transfer" then
				if state.commanderPartyId ~= event.actorPartyId then
					return { ok = false, reason = "warband_not_commander" }
				end
				if target == nil or target == state.commanderPartyId or unitOf(state, target) == nil then
					return { ok = false, reason = "warband_not_member" }
				end
				if event.kind == "transfer" then
					state.transfer = { partyId = target, expiresAtSec = now + Core.TRANSFER_SECONDS }
				else
					local index = table.find(state.assistants, target)
					if index ~= nil then
						table.remove(state.assistants, index)
					elseif #state.assistants < config.maxAssistants then
						table.insert(state.assistants, target)
					else
						return { ok = false, reason = "warband_assistants_full" }
					end
				end
			elseif event.kind == "accept_transfer" then
				if
					state.transfer == nil
					or state.transfer.partyId ~= event.actorPartyId
					or state.transfer.expiresAtSec <= now
				then
					return { ok = false, reason = "warband_transfer_invalid" }
				end
				state.commanderPartyId = event.actorPartyId
				state.commanderAbsentSinceSec = nil
				state.transfer = nil
				local index = table.find(state.assistants, event.actorPartyId)
				if index ~= nil then
					table.remove(state.assistants, index)
				end
			elseif event.kind == "order" or event.kind == "rally" or event.kind == "marker" then
				if not command(state, event.actorPartyId) then
					return { ok = false, reason = "warband_not_command" }
				end
				if not text(event.objectiveId) then
					return { ok = false, reason = "warband_objective_invalid" }
				end
				if event.kind == "order" then
					if event.orderKind == nil or not Core.ORDERS[event.orderKind] then
						return { ok = false, reason = "warband_order_invalid" }
					end
					state.order = {
						kind = event.orderKind,
						objectiveId = assert(SocialShape.string(event.objectiveId)),
						byPartyId = event.actorPartyId,
						byActorId = event.actorId,
						atSec = now,
					}
				elseif event.kind == "rally" then
					state.rallyObjectiveId = event.objectiveId
					state.rallyByActorId = event.actorId
				else
					state.targetObjectiveId = event.objectiveId
					state.targetByActorId = event.actorId
				end
			else
				return { ok = false, reason = "warband_command_invalid" }
			end
		end
		if
			event.kind == "observe"
			and not pruned
			and state.commanderPartyId == previous.commanderPartyId
			and state.commanderAbsentSinceSec == previous.commanderAbsentSinceSec
		then
			return { ok = true, state = previous }
		end
		state.lastClockSec = now
		state.revision += 1
		return { ok = true, state = state }
	end

	Core.unitOf = unitOf
	Core.command = command

	return SocialShape.freezeDeep(Core)
end

return System
