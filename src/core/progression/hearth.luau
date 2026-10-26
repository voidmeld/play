--!strict

local SocialShape = require("../social/shape")

type Raw = { [unknown]: unknown }
export type Destination = { npcId: string, name: string }
export type Bind = { zoneId: string, npcId: string }
export type State = { bind: Bind?, hearthReadyAt: number, returningTo: Bind? }
export type BoundState = { bind: Bind, hearthReadyAt: number, returningTo: Bind? }

export type Config = {
	destinations: { [string]: { Destination } },
	homeZones: { [string]: string },
	cooldownSec: number,
	bindRange: number,
}
local System = {}
function System.hearth(config: Config)
	local Core = {}
	local DESTINATIONS = config.destinations
	local HOME_ZONES = config.homeZones
	Core.HEARTH_COOLDOWN_SEC = config.cooldownSec
	Core.BIND_RANGE_STUDS = config.bindRange
	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	function Core.destination(zoneId: unknown, npcId: unknown): Destination?
		local destinations = if type(zoneId) == "string" then DESTINATIONS[zoneId] else nil
		if destinations == nil then
			return nil
		end
		if npcId == nil then
			return destinations[1]
		end
		for _, destination in destinations do
			if destination.npcId == npcId then
				return destination
			end
		end
		return nil
	end

	function Core.homeZone(faction: unknown): string?
		return if type(faction) == "string" then HOME_ZONES[faction] else nil
	end

	function Core.normalize(raw: unknown): State
		local bind = if type(raw) == "table" then assert(SocialShape.raw(raw)).bind else nil
		local zoneId = if type(bind) == "table" then assert(SocialShape.raw(bind)).zoneId else nil
		local npcId = if type(bind) == "table" then assert(SocialShape.raw(bind)).npcId else nil
		local destination = Core.destination(zoneId, npcId)
		local readyAt = if type(raw) == "table" then assert(SocialShape.raw(raw)).hearthReadyAt else nil
		local savedBind = if destination ~= nil
				and (bind == nil or assert(SocialShape.raw(bind)).npcId == destination.npcId)
			then { zoneId = assert(SocialShape.string(zoneId)), npcId = destination.npcId }
			else nil
		local returning = if type(raw) == "table" then assert(SocialShape.raw(raw)).returningTo else nil
		if returning ~= nil then
			assert(
				type(returning) == "table"
					and savedBind ~= nil
					and assert(SocialShape.raw(returning)).zoneId == savedBind.zoneId
					and assert(SocialShape.raw(returning)).npcId == savedBind.npcId
					and finite(readyAt)
					and (assert(SocialShape.number(readyAt))) >= 0,
				"invalid bindstone return intent"
			)
		end
		return {
			bind = savedBind,
			hearthReadyAt = if finite(readyAt) and (assert(SocialShape.number(readyAt))) >= 0
				then assert(SocialShape.number(readyAt))
				else 0,
			returningTo = if returning ~= nil then savedBind else nil,
		}
	end

	function Core.bind(
		state: unknown,
		zoneId: unknown,
		npcId: unknown,
		distance: unknown,
		alive: boolean
	): (BoundState?, string?)
		local destination = Core.destination(zoneId, npcId)
		if destination == nil or type(npcId) ~= "string" then
			return nil, "destination_invalid"
		end
		if not alive then
			return nil, "not_alive"
		end
		if
			not finite(distance)
			or (assert(SocialShape.number(distance))) > Core.BIND_RANGE_STUDS
			or (assert(SocialShape.number(distance))) < 0
		then
			return nil, "out_of_reach"
		end
		local current = Core.normalize(state)
		if current.returningTo ~= nil then
			return nil, "return_pending"
		end
		return {
			bind = { zoneId = assert(SocialShape.string(zoneId)), npcId = assert(SocialShape.string(npcId)) },
			hearthReadyAt = current.hearthReadyAt,
		},
			nil
	end

	function Core.hearth(state: unknown, now: unknown, alive: boolean, inCombat: boolean): (BoundState?, string?)
		local current = Core.normalize(state)
		if current.bind == nil then
			return nil, "bind_missing"
		end
		if current.returningTo ~= nil then
			return nil, "return_pending"
		end
		if not alive then
			return nil, "not_alive"
		end
		if inCombat then
			return nil, "in_combat"
		end
		if not finite(now) or (assert(SocialShape.number(now))) < 0 then
			return nil, "clock_invalid"
		end
		if (assert(SocialShape.number(now))) < current.hearthReadyAt then
			return nil, "cooldown"
		end
		return {
			bind = current.bind,
			hearthReadyAt = (assert(SocialShape.number(now))) + Core.HEARTH_COOLDOWN_SEC,
			returningTo = current.bind,
		},
			nil
	end

	function Core.arrived(state: unknown): State
		local current = Core.normalize(state)
		assert(current.returningTo ~= nil, "bindstone return intent is absent")
		return { bind = current.bind, hearthReadyAt = current.hearthReadyAt }
	end

	return table.freeze(Core)
end
return System
