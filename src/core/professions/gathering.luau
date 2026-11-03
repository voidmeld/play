--!strict
local Value = require("../../kernel/value")

type Raw = { [unknown]: unknown }

export type RealmId = string

export type SpaceKind = "pve" | "contested"

export type Phase = "ready" | "gathering"

export type Node = {
	id: string,
	materialId: string,
	spaceKind: SpaceKind,
	gatherDurationSec: number,
	respawnPeriodSec: number,
	baseYield: number,
}

export type State = {
	lastClockSec: number,
	phase: Phase,
	startedAtSec: number?,
	completesAtSec: number?,
	harvestedSlot: number?,
	claims: { [string]: number },
}

export type CommandKind = "start" | "interrupt" | "complete"

export type Command = {
	kind: CommandKind,
	eventId: string?,
	gatheringRealmId: RealmId?,
	populationMultiplier: number?,
}

export type Result = {
	state: State,
	phase: Phase,
	available: boolean,
	completed: boolean,
	interrupted: boolean,
	replayed: boolean,
	yieldAmount: number,
	materialId: string?,
	eventId: string?,
}

local System = {}

function System.create(config: {
	realms: { [string]: boolean },
	minYieldMultiplier: number,
	maxYieldMultiplier: number,
	resolveYield: (Node, unknown, unknown) -> number?,
})
	local MIN_YIELD_MULTIPLIER = config.minYieldMultiplier
	local MAX_YIELD_MULTIPLIER = config.maxYieldMultiplier
	local REALMS = config.realms
	local resolveYield = config.resolveYield

	local NODE_FIELDS: { [string]: boolean } = {
		id = true,
		materialId = true,
		spaceKind = true,
		gatherDurationSec = true,
		respawnPeriodSec = true,
		baseYield = true,
	}

	local STATE_FIELDS: { [string]: boolean } = {
		lastClockSec = true,
		phase = true,
		startedAtSec = true,
		completesAtSec = true,
		harvestedSlot = true,
		claims = true,
	}

	local COMMAND_FIELDS: { [string]: boolean } = {
		kind = true,
		eventId = true,
		gatheringRealmId = true,
		populationMultiplier = true,
	}

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function integral(value: unknown): boolean
		return (type(value) == "number" and finite(value)) and value == math.floor(value)
	end

	local function nonempty(value: unknown): boolean
		return type(value) == "string" and #value > 0
	end

	local function knownRealm(value: unknown): boolean
		return type(value) == "string" and REALMS[value] == true
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

	local function slotOf(nowSec: number, respawnPeriodSec: number): number
		return math.floor(nowSec / respawnPeriodSec)
	end

	local function projectNode(value: unknown): Node?
		if not hasOnlyFields(value, NODE_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		if
			not (type(source.id) == "string" and nonempty(source.id))
			or not (type(source.materialId) == "string" and nonempty(source.materialId))
			or (source.spaceKind ~= "pve" and source.spaceKind ~= "contested")
			or not (type(source.gatherDurationSec) == "number" and finite(source.gatherDurationSec))
			or source.gatherDurationSec <= 0
			or not (type(source.respawnPeriodSec) == "number" and finite(source.respawnPeriodSec))
			or source.respawnPeriodSec <= 0
			or not (type(source.baseYield) == "number" and integral(source.baseYield))
			or source.baseYield < 1
		then
			return nil
		end
		return Value.freezeDeep({
			id = source.id,
			materialId = source.materialId,
			spaceKind = source.spaceKind,
			gatherDurationSec = source.gatherDurationSec,
			respawnPeriodSec = source.respawnPeriodSec,
			baseYield = source.baseYield,
		})
	end

	local function admissibleMultiplier(value: unknown): boolean
		return (type(value) == "number" and finite(value))
			and value >= MIN_YIELD_MULTIPLIER
			and value <= MAX_YIELD_MULTIPLIER
	end

	local function copyState(value: unknown): State?
		if not hasOnlyFields(value, STATE_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		if
			not (type(source.lastClockSec) == "number" and finite(source.lastClockSec))
			or source.lastClockSec < 0
			or (source.phase ~= "ready" and source.phase ~= "gathering")
			or type(source.claims) ~= "table"
		then
			return nil
		end
		if
			source.harvestedSlot ~= nil
			and (
				not (type(source.harvestedSlot) == "number" and integral(source.harvestedSlot))
				or source.harvestedSlot < 0
			)
		then
			return nil
		end
		if source.phase == "gathering" then
			if
				not (type(source.startedAtSec) == "number" and finite(source.startedAtSec))
				or source.startedAtSec < 0
				or source.startedAtSec > source.lastClockSec
				or not (type(source.completesAtSec) == "number" and finite(source.completesAtSec))
				or source.completesAtSec <= source.startedAtSec
			then
				return nil
			end
		elseif source.startedAtSec ~= nil or source.completesAtSec ~= nil then
			return nil
		end

		local claims: { [string]: number } = {}
		for eventId, amount in source.claims do
			if
				not (type(eventId) == "string" and nonempty(eventId))
				or not (type(amount) == "number" and integral(amount))
				or amount < 1
			then
				return nil
			end
			claims[eventId] = amount
		end

		if source.startedAtSec ~= nil and type(source.startedAtSec) ~= "number" then
			return nil
		end
		if source.completesAtSec ~= nil and type(source.completesAtSec) ~= "number" then
			return nil
		end
		return {
			lastClockSec = source.lastClockSec,
			phase = source.phase,
			startedAtSec = source.startedAtSec,
			completesAtSec = source.completesAtSec,
			harvestedSlot = source.harvestedSlot,
			claims = claims,
		}
	end

	local function validCommand(value: unknown): Command?
		if not hasOnlyFields(value, COMMAND_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		if source.kind ~= "start" and source.kind ~= "interrupt" and source.kind ~= "complete" then
			return nil
		end
		if source.kind == "complete" then
			if not (type(source.eventId) == "string" and nonempty(source.eventId)) then
				return nil
			end
			if
				source.gatheringRealmId ~= nil
				and not (type(source.gatheringRealmId) == "string" and knownRealm(source.gatheringRealmId))
			then
				return nil
			end
			if
				source.populationMultiplier ~= nil
				and not (
					type(source.populationMultiplier) == "number" and admissibleMultiplier(source.populationMultiplier)
				)
			then
				return nil
			end
		elseif source.eventId ~= nil or source.gatheringRealmId ~= nil or source.populationMultiplier ~= nil then
			return nil
		end
		if
			(source.eventId ~= nil and type(source.eventId) ~= "string")
			or (source.gatheringRealmId ~= nil and type(source.gatheringRealmId) ~= "string")
			or (source.populationMultiplier ~= nil and type(source.populationMultiplier) ~= "number")
		then
			return nil
		end
		return {
			kind = source.kind,
			eventId = source.eventId,
			gatheringRealmId = source.gatheringRealmId,
			populationMultiplier = source.populationMultiplier,
		}
	end

	local function baseResult(state: State): Result
		return {
			state = state,
			phase = state.phase,
			available = false,
			completed = false,
			interrupted = false,
			replayed = false,
			yieldAmount = 0,
			materialId = nil,
			eventId = nil,
		}
	end

	local GatheringCore = {}

	function GatheringCore.emptyState(): State
		return {
			lastClockSec = 0,
			phase = "ready",
			startedAtSec = nil,
			completesAtSec = nil,
			harvestedSlot = nil,
			claims = {},
		}
	end

	function GatheringCore.projectNode(value: unknown): Node?
		return projectNode(value)
	end

	function GatheringCore.computeYield(
		nodeValue: unknown,
		gatheringRealmIdValue: unknown,
		populationMultiplierValue: unknown
	): number?
		local node = projectNode(nodeValue)
		if node == nil then
			return nil
		end
		return resolveYield(node, gatheringRealmIdValue, populationMultiplierValue)
	end

	function GatheringCore.step(
		previousStateValue: unknown,
		nodeValue: unknown,
		commandValue: unknown,
		nowSecValue: unknown
	): Result?
		local state = copyState(previousStateValue)
		local node = projectNode(nodeValue)
		local command = validCommand(commandValue)
		if
			state == nil
			or node == nil
			or command == nil
			or not (type(nowSecValue) == "number" and finite(nowSecValue))
		then
			return nil
		end
		local nowSec = nowSecValue
		if nowSec < 0 or nowSec < state.lastClockSec then
			return nil
		end
		state.lastClockSec = nowSec

		if command.kind == "start" then
			if state.phase ~= "ready" then
				return nil
			end
			local startSlot = slotOf(nowSec, node.respawnPeriodSec)
			local available = state.harvestedSlot == nil or startSlot > state.harvestedSlot
			local result = baseResult(state)
			result.materialId = node.materialId
			if available then
				local completesAtSec = nowSec + node.gatherDurationSec
				if not (type(completesAtSec) == "number" and finite(completesAtSec)) then
					return nil
				end
				state.phase = "gathering"
				state.startedAtSec = nowSec
				state.completesAtSec = completesAtSec
				result.phase = state.phase
				result.available = true
			end
			return result
		end

		if command.kind == "interrupt" then
			local wasGathering = state.phase == "gathering"
			state.phase = "ready"
			state.startedAtSec = nil
			state.completesAtSec = nil
			local result = baseResult(state)
			result.interrupted = wasGathering
			return result
		end

		local eventId = assert(command.eventId)
		local prior = state.claims[eventId]
		if prior ~= nil then
			local result = baseResult(state)
			result.replayed = true
			result.available = true
			result.yieldAmount = prior
			result.materialId = node.materialId
			result.eventId = eventId
			return result
		end

		if state.phase ~= "gathering" then
			return nil
		end
		if nowSec < assert(state.completesAtSec) then
			local result = baseResult(state)
			result.available = true
			return result
		end

		local completeSlot = slotOf(nowSec, node.respawnPeriodSec)
		local nodeAvailable = state.harvestedSlot == nil or completeSlot > state.harvestedSlot
		if not nodeAvailable then
			state.phase = "ready"
			state.startedAtSec = nil
			state.completesAtSec = nil
			local result = baseResult(state)
			result.materialId = node.materialId
			return result
		end

		local yield = resolveYield(node, command.gatheringRealmId, command.populationMultiplier)
		if yield == nil then
			return nil
		end
		state.claims[eventId] = yield
		state.harvestedSlot = completeSlot
		state.phase = "ready"
		state.startedAtSec = nil
		state.completesAtSec = nil
		local result = baseResult(state)
		result.available = true
		result.completed = true
		result.yieldAmount = yield
		result.materialId = node.materialId
		result.eventId = eventId
		return result
	end

	GatheringCore.MIN_YIELD_MULTIPLIER = MIN_YIELD_MULTIPLIER
	GatheringCore.MAX_YIELD_MULTIPLIER = MAX_YIELD_MULTIPLIER
	GatheringCore.REALMS = Value.freezeDeep(REALMS)

	return Value.freezeDeep(GatheringCore)
end

return Value.freezeDeep(System)
