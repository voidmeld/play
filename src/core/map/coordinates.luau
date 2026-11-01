--!strict
local Value = require("../internal/value")

export type Bounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}

export type WorldPoint = {
	x: number,
	z: number,
}

export type NormalizedPoint = {
	u: number,
	v: number,
}

local BOUNDS_FIELDS: { [string]: boolean } = {
	minX = true,
	maxX = true,
	minZ = true,
	maxZ = true,
}

local WORLD_POINT_FIELDS: { [string]: boolean } = {
	x = true,
	z = true,
}

local NORMALIZED_POINT_FIELDS: { [string]: boolean } = {
	u = true,
	v = true,
}

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function spans(value: unknown): (Bounds?, number?, number?)
	local raw = Value.record(value, BOUNDS_FIELDS, false, false)
	if raw == nil then
		return nil, nil, nil
	end
	local minX, maxX, minZ, maxZ = raw.minX, raw.maxX, raw.minZ, raw.maxZ
	if
		type(minX) ~= "number"
		or type(maxX) ~= "number"
		or type(minZ) ~= "number"
		or type(maxZ) ~= "number"
		or not finite(minX)
		or not finite(maxX)
		or not finite(minZ)
		or not finite(maxZ)
	then
		return nil, nil, nil
	end
	local spanX, spanZ = maxX - minX, maxZ - minZ
	if not finite(spanX) or not finite(spanZ) or spanX <= 0 or spanZ <= 0 then
		return nil, nil, nil
	end
	return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }, spanX, spanZ
end

local function worldPoint(value: unknown): WorldPoint?
	local raw = Value.record(value, WORLD_POINT_FIELDS, false, false)
	if raw == nil then
		return nil
	end
	local x, z = raw.x, raw.z
	if type(x) ~= "number" or type(z) ~= "number" or not finite(x) or not finite(z) then
		return nil
	end
	return { x = x, z = z }
end

local function normalizedPoint(value: unknown): NormalizedPoint?
	local raw = Value.record(value, NORMALIZED_POINT_FIELDS, false, false)
	if raw == nil then
		return nil
	end
	local u, v = raw.u, raw.v
	if type(u) ~= "number" or type(v) ~= "number" or not finite(u) or not finite(v) then
		return nil
	end
	return { u = u, v = v }
end

local ZoneMapProjectionCore = {}

function ZoneMapProjectionCore.worldToMap(boundsValue: unknown, worldValue: unknown): NormalizedPoint?
	local bounds, spanX, spanZ = spans(boundsValue)
	local world = worldPoint(worldValue)
	if bounds == nil or spanX == nil or spanZ == nil or world == nil then
		return nil
	end
	local boundedX = math.clamp(world.x, bounds.minX, bounds.maxX)
	local boundedZ = math.clamp(world.z, bounds.minZ, bounds.maxZ)
	local result: NormalizedPoint = {
		u = (boundedX - bounds.minX) / spanX,
		v = (boundedZ - bounds.minZ) / spanZ,
	}
	return Value.freezeDeep(result)
end

function ZoneMapProjectionCore.mapToWorld(boundsValue: unknown, normalizedValue: unknown): WorldPoint?
	local bounds, spanX, spanZ = spans(boundsValue)
	local normalized = normalizedPoint(normalizedValue)
	if bounds == nil or spanX == nil or spanZ == nil or normalized == nil then
		return nil
	end
	local boundedU = math.clamp(normalized.u, 0, 1)
	local boundedV = math.clamp(normalized.v, 0, 1)
	local result: WorldPoint = {
		x = bounds.minX + boundedU * spanX,
		z = bounds.minZ + boundedV * spanZ,
	}
	return Value.freezeDeep(result)
end

return table.freeze(ZoneMapProjectionCore)
