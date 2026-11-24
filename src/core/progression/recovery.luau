--!strict
local SocialShape = require("../social/shape")

export type Point = { x: number, y: number, z: number }
export type Cost = { items: number, currency: number, experience: number, durability: number, delaySec: number }
export type Death = {
	generation: number,
	phase: "dead" | "released" | "resolved",
	cause: string,
	zoneId: string,
	corpse: Point,
	anchor: Point,
	cost: Cost,
}

export type Position<Travel> = {
	x: number,
	y: number,
	z: number,
	yaw: number,
	saved: boolean,
	recoveryZoneId: string?,
	travel: Travel?,
}

type Raw = { [unknown]: unknown }
export type AnchoredPosition = Raw & {
	x: number,
	y: number,
	z: number,
	yaw: number,
	saved: boolean,
	recoveryZoneId: string,
	travel: unknown,
}

export type Config = { coordinateLimit: number, lowHealthRatio: number, defaultCause: string }
local System = {}
function System.recovery(config: Config)
	local function finitePoint(point: unknown): boolean
		local candidate = SocialShape.raw(point)
		if candidate == nil then
			return false
		end
		return type(point) == "table"
			and type(candidate.x) == "number"
			and type(candidate.y) == "number"
			and type(candidate.z) == "number"
			and candidate.x == candidate.x
			and candidate.y == candidate.y
			and candidate.z == candidate.z
			and math.abs(candidate.x) < config.coordinateLimit
			and math.abs(candidate.y) < config.coordinateLimit
			and math.abs(candidate.z) < config.coordinateLimit
	end

	local function die(
		previous: Death?,
		cause: string,
		zoneId: string,
		corpse: Point,
		anchor: Point,
		delaySec: number
	): Death?
		if not finitePoint(corpse) or not finitePoint(anchor) or type(zoneId) ~= "string" or zoneId == "" then
			return nil
		end
		if previous ~= nil and previous.phase ~= "resolved" then
			return previous
		end
		return {
			generation = if previous == nil then 1 else previous.generation + 1,
			phase = "dead",
			cause = if cause ~= "" then cause else config.defaultCause,
			zoneId = zoneId,
			corpse = table.clone(corpse),
			anchor = table.clone(anchor),
			cost = { items = 0, currency = 0, experience = 0, durability = 0, delaySec = math.max(0, delaySec) },
		}
	end

	local function release(death: Death, generation: number): Death?
		if death.generation ~= generation or death.phase ~= "dead" then
			return nil
		end
		local next = table.clone(death)
		next.phase = "released"
		return next
	end

	local function recover(death: Death, generation: number): (Death?, Point?)
		if death.generation ~= generation or death.phase ~= "released" then
			return nil, nil
		end
		local next = table.clone(death)
		next.phase = "resolved"
		return next, table.clone(death.anchor)
	end

	local function anchorPosition<Travel>(current: Position<Travel>, death: Death): Position<Travel>
		local out = table.clone(current)
		out.x = death.anchor.x
		out.y = death.anchor.y
		out.z = death.anchor.z
		out.yaw = 0
		out.saved = true
		out.recoveryZoneId = death.zoneId
		return out
	end

	local function anchoredLastPosition(current: unknown, death: Death): Raw
		local out: Raw = if type(current) == "table" then assert(SocialShape.raw(current)) else {}
		out.x = death.anchor.x
		out.y = death.anchor.y
		out.z = death.anchor.z
		out.yaw = 0
		out.saved = true
		out.recoveryZoneId = death.zoneId
		return out
	end

	local function lowHealth(hp: number, maxHp: number): boolean
		return hp > 0 and maxHp > 0 and hp / maxHp <= config.lowHealthRatio
	end

	local function echoDistance(position: Point, echo: Point): number
		local x, y, z = position.x - echo.x, position.y - echo.y, position.z - echo.z
		return math.sqrt(x * x + y * y + z * z)
	end

	local function encodeEcho(point: Point): string
		assert(finitePoint(point), "echo point must be finite")
		return ("%.3f,%.3f,%.3f"):format(point.x, point.y, point.z)
	end

	local function decodeEcho(value: unknown): Point?
		if type(value) ~= "string" then
			return nil
		end
		local x, y, z = string.match(value, "^(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)$")
		local px, py, pz = tonumber(x), tonumber(y), tonumber(z)
		if px == nil or py == nil or pz == nil then
			return nil
		end
		local point = { x = px, y = py, z = pz }
		return if finitePoint(point) then point else nil
	end

	return table.freeze({
		encodeEcho = encodeEcho,
		decodeEcho = decodeEcho,
		lowHealth = lowHealth,
		echoDistance = echoDistance,
		die = die,
		release = release,
		recover = recover,
		anchoredLastPosition = anchoredLastPosition,
		anchorPosition = anchorPosition,
	})
end
return System
