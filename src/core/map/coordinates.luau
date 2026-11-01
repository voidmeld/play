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

local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
	if type(value) ~= "table" then
		return false
	end
	for key in value do
		if type(key) ~= "string" or not fields[key] then
			return false
		end
	end
	return true
end

local function spans(bounds: unknown): (Bounds?, number?, number?)
	if not hasOnlyFields(bounds, BOUNDS_FIELDS) then
		return nil, nil, nil
	end
	local candidate = bounds
	if
		not finite(candidate.minX)
		or not finite(candidate.maxX)
		or not finite(candidate.minZ)
		or not finite(candidate.maxZ)
	then
		return nil, nil, nil
	end
	local spanX = candidate.maxX - candidate.minX
	local spanZ = candidate.maxZ - candidate.minZ
	if not finite(spanX) or not finite(spanZ) or spanX <= 0 or spanZ <= 0 then
		return nil, nil, nil
	end
	return candidate, spanX, spanZ
end

local function validWorldPoint(value: unknown): boolean
	if not hasOnlyFields(value, WORLD_POINT_FIELDS) then
		return false
	end
	local point = value
	return finite(point.x) and finite(point.z)
end

local function validNormalizedPoint(value: unknown): boolean
	if not hasOnlyFields(value, NORMALIZED_POINT_FIELDS) then
		return false
	end
	local point = value
	return finite(point.u) and finite(point.v)
end

local ZoneMapProjectionCore = {}

function ZoneMapProjectionCore.worldToMap(boundsValue: unknown, worldValue: unknown): NormalizedPoint?
	local bounds, spanX, spanZ = spans(boundsValue)
	if bounds == nil or spanX == nil or spanZ == nil or not validWorldPoint(worldValue) then
		return nil
	end
	local world = worldValue
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
	if bounds == nil or spanX == nil or spanZ == nil or not validNormalizedPoint(normalizedValue) then
		return nil
	end
	local normalized = normalizedValue
	local boundedU = math.clamp(normalized.u, 0, 1)
	local boundedV = math.clamp(normalized.v, 0, 1)
	local result: WorldPoint = {
		x = bounds.minX + boundedU * spanX,
		z = bounds.minZ + boundedV * spanZ,
	}
	return Value.freezeDeep(result)
end

return table.freeze(ZoneMapProjectionCore)
