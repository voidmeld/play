--!strict

local Codec = require("../../kernel/codec")
local Result = require("../../kernel/result")
local Value = require("../../kernel/value")

export type Identity = { read id: string, read characterId: string?, read epoch: number?, read contentId: string? }
export type Plan<P> = {
	read source: Identity,
	read target: Identity,
	read equipmentToken: string?,
	read sequence: number,
	read startedTick: number,
	read anticipationSec: number,
	read contactSec: number,
	read recoverySec: number,
	read rangeStuds: number,
	read payload: P,
}
export type State<P> = {
	read plan: Plan<P>,
	read elapsedSec: number,
	read lastTick: number,
	read contacted: boolean,
	read reserved: boolean,
}
export type Status = "waiting" | "contact" | "complete" | "cancelled" | "missed"
export type Transition<P> = { read status: Status, read next: State<P>?, read reason: string? }
export type Config<P> = { read copyPayload: (unknown) -> (P?, string?), read epsilon: number, read idLimit: number }
export type API<P> = {
	read admit: (unknown) -> Result.Result<State<P>>,
	read advance: (unknown, unknown) -> Transition<P>,
	read resolve: (unknown, unknown) -> Transition<P>,
}

local IDENTITY = { id = true, characterId = true, epoch = true, contentId = true }
local PLAN = {
	source = true,
	target = true,
	equipmentToken = true,
	sequence = true,
	startedTick = true,
	anticipationSec = true,
	contactSec = true,
	recoverySec = true,
	rangeStuds = true,
	payload = true,
}
local STATE = { plan = true, elapsedSec = true, lastTick = true, contacted = true, reserved = true }
local MAX_INTEGER = 9007199254740991
local function nonnegative(raw: unknown): number?
	return if type(raw) == "number" and Value.finite(raw) and raw >= 0 then raw else nil
end
local function frozen(raw: unknown): boolean
	if type(raw) ~= "table" then
		return true
	end
	if not table.isfrozen(raw) then
		return false
	end
	for _, value in raw do
		if not frozen(value) then
			return false
		end
	end
	return true
end
local function configure<P>(config: Config<P>): API<P>
	assert(nonnegative(config.epsilon) ~= nil, "invalid contact epsilon")
	assert(Value.whole(config.idLimit, 1, MAX_INTEGER), "invalid contact identity limit")
	config = table.freeze(table.clone(config))
	local function identity(raw: unknown): Identity?
		local fields = Value.record(raw, IDENTITY)
		if fields == nil then
			return nil
		end
		local id = Value.opaque(fields.id, config.idLimit)
		local characterId = if fields.characterId == nil then nil else Value.opaque(fields.characterId, config.idLimit)
		local contentId = if fields.contentId == nil then nil else Value.opaque(fields.contentId, config.idLimit)
		local epoch = if fields.epoch == nil then nil else Value.whole(fields.epoch, 0, MAX_INTEGER)
		if
			id == nil
			or (fields.characterId ~= nil and characterId == nil)
			or (fields.contentId ~= nil and contentId == nil)
			or (fields.epoch ~= nil and epoch == nil)
		then
			return nil
		end
		return table.freeze({ id = id, characterId = characterId, contentId = contentId, epoch = epoch })
	end
	local function same(expected: Identity, raw: unknown): boolean
		local current = identity(raw)
		return current ~= nil
			and current.id == expected.id
			and current.characterId == expected.characterId
			and current.epoch == expected.epoch
			and current.contentId == expected.contentId
	end
	local function admit(raw: unknown): Result.Result<State<P>>
		local fields = Value.record(raw, PLAN)
		if fields == nil then
			return Result.fail("plan_invalid")
		end
		local source, target = identity(fields.source), identity(fields.target)
		local sequence, startedTick =
			Value.whole(fields.sequence, 1, MAX_INTEGER), Value.whole(fields.startedTick, 0, MAX_INTEGER)
		local anticipation, contact, recovery, range =
			nonnegative(fields.anticipationSec),
			nonnegative(fields.contactSec),
			nonnegative(fields.recoverySec),
			nonnegative(fields.rangeStuds)
		local token = if fields.equipmentToken == nil then nil else Value.opaque(fields.equipmentToken, config.idLimit)
		if
			source == nil
			or target == nil
			or sequence == nil
			or startedTick == nil
			or anticipation == nil
			or contact == nil
			or recovery == nil
			or range == nil
			or (fields.equipmentToken ~= nil and token == nil)
		then
			return Result.fail("plan_invalid")
		end
		if not Value.finite(anticipation + contact + recovery) then
			return Result.fail("plan_invalid")
		end
		local copied = Codec.copyData(fields.payload)
		if not copied.ok then
			return Result.fail("payload_invalid")
		end
		local decoded, payload, reason = pcall(config.copyPayload, copied.value)
		if not decoded or payload == nil then
			return Result.fail(if decoded then reason or "payload_invalid" else "payload_invalid")
		end
		local checked = Codec.copyData(payload)
		if not checked.ok then
			return Result.fail("payload_invalid")
		end
		local plan: Plan<P> = Value.freezeDeep({
			source = source,
			target = target,
			equipmentToken = token,
			sequence = sequence,
			startedTick = startedTick,
			anticipationSec = anticipation,
			contactSec = contact,
			recoverySec = recovery,
			rangeStuds = range,
			payload = payload,
		})
		return Result.ok(
			table.freeze({ plan = plan, elapsedSec = 0, lastTick = startedTick, contacted = false, reserved = false })
		)
	end
	local function state(raw: unknown): State<P>?
		local fields = Value.record(raw, STATE, true)
		if fields == nil or type(fields.plan) ~= "table" or not table.isfrozen(fields.plan) then
			return nil
		end
		local admitted = admit(fields.plan)
		if not admitted.ok or not frozen(fields.plan) then
			return nil
		end
		local elapsed, lastTick = nonnegative(fields.elapsedSec), Value.whole(fields.lastTick, 0, MAX_INTEGER)
		if
			not admitted.ok
			or elapsed == nil
			or lastTick == nil
			or lastTick < admitted.value.plan.startedTick
			or type(fields.contacted) ~= "boolean"
			or type(fields.reserved) ~= "boolean"
			or (fields.contacted and fields.reserved)
		then
			return nil
		end
		if (fields.contacted or fields.reserved) and elapsed + config.epsilon < admitted.value.plan.anticipationSec then
			return nil
		end
		return {
			plan = admitted.value.plan,
			elapsedSec = elapsed,
			lastTick = lastTick,
			contacted = fields.contacted,
			reserved = fields.reserved,
		}
	end
	local function transition(status: Status, nextState: State<P>?, reason: string?): Transition<P>
		local result: Transition<P> = { status = status, next = nextState, reason = reason }
		return table.freeze(result)
	end
	local function cancelled(reason: string): Transition<P>
		return transition("cancelled", nil, reason)
	end
	local function owns(plan: Plan<P>, raw: unknown): boolean
		local fields = Value.record(raw, { identity = true, alive = true, equipmentToken = true, blocked = true })
		return fields ~= nil
			and fields.alive == true
			and fields.blocked == false
			and same(plan.source, fields.identity)
			and fields.equipmentToken == plan.equipmentToken
	end
	local function advance(raw: unknown, observation: unknown): Transition<P>
		local current = state(raw)
		local fields = Value.record(observation, { tick = true, dt = true, source = true })
		if current == nil or fields == nil then
			return cancelled("state_invalid")
		end
		local tick, dt = Value.whole(fields.tick, 0, MAX_INTEGER), nonnegative(fields.dt)
		if tick == nil or dt == nil or tick < current.lastTick then
			return cancelled("clock_invalid")
		end
		if not owns(current.plan, fields.source) then
			return cancelled("source_invalidated")
		end
		if tick == current.lastTick then
			return transition("waiting", Value.freezeDeep(current), nil)
		end
		local elapsed = current.elapsedSec + dt
		if not Value.finite(elapsed) then
			return cancelled("clock_invalid")
		end
		local reserved = current.reserved
			or (not current.contacted and elapsed + config.epsilon >= current.plan.anticipationSec)
		local nextState: State<P> = table.freeze({
			plan = current.plan,
			elapsedSec = elapsed,
			lastTick = tick,
			contacted = current.contacted,
			reserved = reserved,
		})
		if reserved and not current.reserved then
			return transition("contact", nextState, nil)
		end
		if
			current.contacted
			and elapsed + config.epsilon
				>= current.plan.anticipationSec + current.plan.contactSec + current.plan.recoverySec
		then
			return transition("complete", nil, nil)
		end
		return transition("waiting", nextState, nil)
	end
	local function resolve(raw: unknown, observation: unknown): Transition<P>
		local current = state(raw)
		local fields = Value.record(
			observation,
			{ source = true, target = true, distanceStuds = true, spatial = true, spatialExempt = true, allowed = true }
		)
		if current == nil or fields == nil then
			return cancelled("state_invalid")
		end
		if not current.reserved or current.contacted then
			return cancelled("contact_not_reserved")
		end
		if not owns(current.plan, fields.source) then
			return cancelled("source_invalidated")
		end
		local target = Value.record(fields.target, { identity = true, alive = true })
		if target == nil or target.alive ~= true or not same(current.plan.target, target.identity) then
			return cancelled("target_invalidated")
		end
		local distance = nonnegative(fields.distanceStuds)
		local spatial = Value.record(fields.spatial, { clear = true, distanceStuds = true })
		local measured = if spatial ~= nil then nonnegative(spatial.distanceStuds) else nil
		local exempt = fields.spatialExempt == true and current.plan.source.id == current.plan.target.id
		local hit = fields.allowed == true
			and distance ~= nil
			and distance <= current.plan.rangeStuds + config.epsilon
			and (
				exempt
				or (
					spatial ~= nil
					and spatial.clear == true
					and measured ~= nil
					and measured <= current.plan.rangeStuds + config.epsilon
				)
			)
		local done = current.elapsedSec + config.epsilon
			>= current.plan.anticipationSec + current.plan.contactSec + current.plan.recoverySec
		local nextState: State<P>? = if done
			then nil
			else table.freeze({
				plan = current.plan,
				elapsedSec = current.elapsedSec,
				lastTick = current.lastTick,
				contacted = true,
				reserved = false,
			})
		return transition(
			if hit then "contact" else "missed",
			nextState,
			if hit then nil else "spatial_or_policy_refused"
		)
	end
	return table.freeze({ admit = admit, advance = advance, resolve = resolve })
end

return table.freeze({ configure = configure })
