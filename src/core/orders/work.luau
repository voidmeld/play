--!strict

local SocialShape = require("../social/shape")

type RawTable = SocialShape.Raw

export type Phase = "unaccepted" | "accepted" | "completed"

export type WorkOrderStep = {
	id: string,
	tag: string,
	targetCount: number,
}

export type WorkOrder = {
	id: string,
	rewardId: string,
	repeatable: boolean,
	steps: { WorkOrderStep },
}

export type State = {
	lastClockSec: number,
	phase: Phase,
	stepProgress: { [string]: number },
	claimed: boolean,
	claims: { [string]: string },
}

export type CommandKind = "accept" | "progress" | "complete" | "claim"

export type Command = {
	kind: CommandKind,
	stepTag: string?,
	amount: number?,
	eventId: string?,
}

export type Result = {
	state: State,
	phase: Phase,
	accepted: boolean,
	progressed: boolean,
	completed: boolean,
	claimed: boolean,
	replayed: boolean,
	rewardId: string?,
	eventId: string?,
}

local function readPhase(value: unknown): Phase?
	return if value == "unaccepted" or value == "accepted" or value == "completed" then value else nil
end

local function readWorkOrderStep(value: unknown): WorkOrderStep?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if not SocialShape.onlyFields(value, { id = true, tag = true, targetCount = true }) then
		return nil
	end
	local id = SocialShape.string(raw.id)
	if id == nil then
		return nil
	end
	local tag = SocialShape.string(raw.tag)
	if tag == nil then
		return nil
	end
	local targetCount = SocialShape.number(raw.targetCount)
	if targetCount == nil then
		return nil
	end
	return { id = id, tag = tag, targetCount = targetCount }
end

local function readWorkOrder(value: unknown): WorkOrder?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if not SocialShape.onlyFields(value, { id = true, rewardId = true, repeatable = true, steps = true }) then
		return nil
	end
	local id = SocialShape.string(raw.id)
	if id == nil then
		return nil
	end
	local rewardId = SocialShape.string(raw.rewardId)
	if rewardId == nil then
		return nil
	end
	local repeatable = SocialShape.boolean(raw.repeatable)
	if repeatable == nil then
		return nil
	end
	local steps = SocialShape.array(raw.steps, readWorkOrderStep)
	if steps == nil then
		return nil
	end
	return { id = id, rewardId = rewardId, repeatable = repeatable, steps = steps }
end

local function readState(value: unknown): State?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if
		not SocialShape.onlyFields(
			value,
			{ lastClockSec = true, phase = true, stepProgress = true, claimed = true, claims = true }
		)
	then
		return nil
	end
	local lastClockSec = SocialShape.number(raw.lastClockSec)
	if lastClockSec == nil then
		return nil
	end
	local phase = readPhase(raw.phase)
	if phase == nil then
		return nil
	end
	local stepProgress = SocialShape.map(raw.stepProgress, SocialShape.string, SocialShape.number)
	if stepProgress == nil then
		return nil
	end
	local claimed = SocialShape.boolean(raw.claimed)
	if claimed == nil then
		return nil
	end
	local claims = SocialShape.map(raw.claims, SocialShape.string, SocialShape.string)
	if claims == nil then
		return nil
	end
	return {
		lastClockSec = lastClockSec,
		phase = phase,
		stepProgress = stepProgress,
		claimed = claimed,
		claims = claims,
	}
end

local ORDER_FIELDS: { [string]: boolean } = {
	id = true,
	rewardId = true,
	repeatable = true,
	steps = true,
}

local STEP_FIELDS: { [string]: boolean } = {
	id = true,
	tag = true,
	targetCount = true,
}

local STATE_FIELDS: { [string]: boolean } = {
	lastClockSec = true,
	phase = true,
	stepProgress = true,
	claimed = true,
	claims = true,
}

local COMMAND_FIELDS: { [string]: boolean } = {
	kind = true,
	stepTag = true,
	amount = true,
	eventId = true,
}

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function integral(value: unknown): boolean
	return finite(value) and value == math.floor(assert(SocialShape.number(value)))
end

local function nonempty(value: unknown): boolean
	return type(value) == "string" and #value > 0
end

local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
	if type(value) ~= "table" then
		return false
	end
	for key in assert(SocialShape.raw(value)) do
		if type(key) ~= "string" or fields[key] ~= true then
			return false
		end
	end
	return true
end

local function denseLength(value: unknown): number?
	if type(value) ~= "table" then
		return nil
	end
	local count = 0
	for key in assert(SocialShape.raw(value)) do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return nil
		end
		count += 1
	end
	for index = 1, count do
		if (assert(SocialShape.raw(value)))[index] == nil then
			return nil
		end
	end
	return count
end

local function projectStep(value: unknown): WorkOrderStep?
	if not hasOnlyFields(value, STEP_FIELDS) then
		return nil
	end
	local source = readWorkOrderStep(value)
	if source == nil then
		return nil
	end
	if
		not nonempty(source.id)
		or not nonempty(source.tag)
		or not integral(source.targetCount)
		or (assert(SocialShape.number(source.targetCount))) < 1
	then
		return nil
	end
	return SocialShape.freezeDeep({
		id = assert(SocialShape.string(source.id)),
		tag = assert(SocialShape.string(source.tag)),
		targetCount = assert(SocialShape.number(source.targetCount)),
	})
end

local function projectOrder(value: unknown): WorkOrder?
	if not hasOnlyFields(value, ORDER_FIELDS) then
		return nil
	end
	local source = readWorkOrder(value)
	if source == nil then
		return nil
	end
	if not nonempty(source.id) or not nonempty(source.rewardId) or type(source.repeatable) ~= "boolean" then
		return nil
	end
	local count = denseLength(source.steps)
	if count == nil or count < 1 then
		return nil
	end
	local steps: { WorkOrderStep } = {}
	local ids: { [string]: boolean } = {}
	local tags: { [string]: boolean } = {}
	for index = 1, assert(SocialShape.number(count)) do
		local step = projectStep(source.steps[index])
		if step == nil or ids[step.id] == true or tags[step.tag] == true then
			return nil
		end
		ids[step.id] = true
		tags[step.tag] = true
		steps[#steps + 1] = step
	end
	return SocialShape.freezeDeep({
		id = assert(SocialShape.string(source.id)),
		rewardId = assert(SocialShape.string(source.rewardId)),
		repeatable = source.repeatable,
		steps = SocialShape.freezeDeep(steps),
	})
end

local function stepById(order: WorkOrder, stepId: string): WorkOrderStep?
	for _, step in order.steps do
		if step.id == stepId then
			return step
		end
	end
	return nil
end

local function stepByTag(order: WorkOrder, tag: string): WorkOrderStep?
	for _, step in order.steps do
		if step.tag == tag then
			return step
		end
	end
	return nil
end

local function copyState(value: unknown): State?
	if not hasOnlyFields(value, STATE_FIELDS) then
		return nil
	end
	local source = readState(value)
	if source == nil then
		return nil
	end
	if
		not finite(source.lastClockSec)
		or (assert(SocialShape.number(source.lastClockSec))) < 0
		or type(source.claimed) ~= "boolean"
		or type(source.stepProgress) ~= "table"
		or type(source.claims) ~= "table"
	then
		return nil
	end
	if source.phase ~= "completed" and source.claimed then
		return nil
	end

	local stepProgress: { [string]: number } = {}
	for stepId, count in source.stepProgress do
		if not nonempty(stepId) or not integral(count) or (assert(SocialShape.number(count))) < 0 then
			return nil
		end
		stepProgress[assert(SocialShape.string(stepId))] = assert(SocialShape.number(count))
	end
	if source.phase == "unaccepted" and next(stepProgress) ~= nil then
		return nil
	end

	local claims: { [string]: string } = {}
	for eventId, rewardId in source.claims do
		if not nonempty(eventId) or not nonempty(rewardId) then
			return nil
		end
		claims[assert(SocialShape.string(eventId))] = assert(SocialShape.string(rewardId))
	end

	return {
		lastClockSec = assert(SocialShape.number(source.lastClockSec)),
		phase = source.phase,
		stepProgress = stepProgress,
		claimed = source.claimed,
		claims = claims,
	}
end

local function reconcileProgress(state: State, order: WorkOrder): boolean
	if state.phase == "unaccepted" then
		return next(state.stepProgress) == nil
	end
	local trackedCount = 0
	for stepId, value in state.stepProgress do
		local step = stepById(order, stepId)
		if step == nil or value < 0 or value > step.targetCount then
			return false
		end
		trackedCount += 1
	end
	return trackedCount == #order.steps
end

local function allStepsMet(state: State, order: WorkOrder): boolean
	for _, step in order.steps do
		local value = state.stepProgress[step.id]
		if value == nil or value < step.targetCount then
			return false
		end
	end
	return true
end

local function validCommand(value: unknown): Command?
	if not hasOnlyFields(value, COMMAND_FIELDS) then
		return nil
	end
	local source = SocialShape.raw(value)
	if source == nil then
		return nil
	end
	local kind = source.kind
	if kind == "progress" then
		local stepTag = SocialShape.string(source.stepTag)
		local amount = SocialShape.number(source.amount)
		if
			stepTag == nil
			or not nonempty(stepTag)
			or amount == nil
			or not integral(amount)
			or amount < 1
			or source.eventId ~= nil
		then
			return nil
		end
		return { kind = kind, stepTag = stepTag, amount = amount }
	elseif kind == "claim" then
		local eventId = SocialShape.string(source.eventId)
		if eventId == nil or not nonempty(eventId) or source.stepTag ~= nil or source.amount ~= nil then
			return nil
		end
		return { kind = kind, eventId = eventId }
	elseif kind == "accept" or kind == "complete" then
		if source.stepTag ~= nil or source.amount ~= nil or source.eventId ~= nil then
			return nil
		end
		return { kind = kind }
	end
	return nil
end

local function baseResult(state: State): Result
	return {
		state = state,
		phase = state.phase,
		accepted = false,
		progressed = false,
		completed = false,
		claimed = false,
		replayed = false,
		rewardId = nil,
		eventId = nil,
	}
end

local WorkOrderCore = {}

function WorkOrderCore.emptyState(): State
	return {
		lastClockSec = 0,
		phase = "unaccepted",
		stepProgress = {},
		claimed = false,
		claims = {},
	}
end

function WorkOrderCore.projectOrder(value: unknown): WorkOrder?
	return projectOrder(value)
end

function WorkOrderCore.projectState(value: unknown, orderValue: unknown): State?
	local state = copyState(value)
	local order = projectOrder(orderValue)
	if state == nil or order == nil or not reconcileProgress(state, order) then
		return nil
	end
	return state
end

function WorkOrderCore.step(
	previousStateValue: unknown,
	orderValue: unknown,
	commandValue: unknown,
	nowSecValue: unknown
): Result?
	local state = copyState(previousStateValue)
	local order = projectOrder(orderValue)
	local command = validCommand(commandValue)
	if state == nil or order == nil or command == nil or not finite(nowSecValue) then
		return nil
	end
	local nowSec = assert(SocialShape.number(nowSecValue))
	if nowSec < 0 or nowSec < state.lastClockSec then
		return nil
	end
	state.lastClockSec = nowSec

	if not reconcileProgress(state, order) then
		return nil
	end

	if command.kind == "accept" then
		if state.phase ~= "unaccepted" then
			return nil
		end
		local stepProgress: { [string]: number } = {}
		for _, step in order.steps do
			stepProgress[step.id] = 0
		end
		state.phase = "accepted"
		state.stepProgress = stepProgress
		state.claimed = false
		local result = baseResult(state)
		result.accepted = true
		return result
	end

	if command.kind == "progress" then
		if state.phase ~= "accepted" then
			return nil
		end
		local step = stepByTag(order, assert(SocialShape.string(command.stepTag)))
		if step == nil then
			return nil
		end
		local current = state.stepProgress[step.id] or 0
		state.stepProgress[step.id] = math.min(step.targetCount, current + (assert(SocialShape.number(command.amount))))
		local result = baseResult(state)
		result.progressed = true
		return result
	end

	if command.kind == "complete" then
		if state.phase == "completed" then
			local result = baseResult(state)
			result.completed = true
			return result
		end
		if state.phase ~= "accepted" or not allStepsMet(state, order) then
			return nil
		end
		state.phase = "completed"
		state.claimed = false
		local result = baseResult(state)
		result.completed = true
		return result
	end

	local eventId = assert(SocialShape.string(command.eventId))
	local priorReward = state.claims[eventId]
	if priorReward ~= nil then
		local result = baseResult(state)
		result.claimed = true
		result.replayed = true
		result.rewardId = priorReward
		result.eventId = eventId
		return result
	end

	if state.phase ~= "completed" or state.claimed then
		return nil
	end

	local claims: { [string]: string } = {}
	for existingEventId, rewardId in state.claims do
		claims[existingEventId] = rewardId
	end
	claims[eventId] = order.rewardId
	state.claims = claims
	state.claimed = true
	if order.repeatable then
		state.phase = "unaccepted"
		state.stepProgress = {}
		state.claimed = false
	end
	local result = baseResult(state)
	result.claimed = true
	result.rewardId = order.rewardId
	result.eventId = eventId
	return result
end

return WorkOrderCore
