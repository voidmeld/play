--!strict

local MinimapGeometry = {}

export type PanOffset = {
	x: number,
	y: number,
}

export type MarkerProjection = {
	x: number,
	y: number,
	withinWindow: boolean,
	edgeClamped: boolean,
}

local CIRCLE_RADIUS_NORMALIZED = 0.5

local function finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function normalized(value: unknown): boolean
	return finite(value) and (value :: number) >= 0 and (value :: number) <= 1
end

local function oversizedScale(value: unknown): boolean
	return finite(value) and (value :: number) > 1
end

local function project(
	playerU: unknown,
	playerV: unknown,
	markerU: unknown,
	markerV: unknown,
	imageScale: unknown
): MarkerProjection?
	if
		not normalized(playerU)
		or not normalized(playerV)
		or not normalized(markerU)
		or not normalized(markerV)
		or not oversizedScale(imageScale)
	then
		return nil
	end
	local x = 0.5 + ((markerU :: number) - (playerU :: number)) * (imageScale :: number)
	local y = 0.5 + ((markerV :: number) - (playerV :: number)) * (imageScale :: number)
	local deltaX = x - 0.5
	local deltaY = y - 0.5
	local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
	return {
		x = x,
		y = y,
		withinWindow = distance <= CIRCLE_RADIUS_NORMALIZED,
		edgeClamped = false,
	}
end

function MinimapGeometry.imagePan(playerU: unknown, playerV: unknown, imageScale: unknown): PanOffset?
	if not normalized(playerU) or not normalized(playerV) or not oversizedScale(imageScale) then
		return nil
	end
	return {
		x = 0.5 - (playerU :: number) * (imageScale :: number),
		y = 0.5 - (playerV :: number) * (imageScale :: number),
	}
end

function MinimapGeometry.projectMarker(
	playerU: unknown,
	playerV: unknown,
	markerU: unknown,
	markerV: unknown,
	imageScale: unknown
): MarkerProjection?
	return project(playerU, playerV, markerU, markerV, imageScale)
end

function MinimapGeometry.projectTrackedWaypoint(
	playerU: unknown,
	playerV: unknown,
	waypointU: unknown,
	waypointV: unknown,
	imageScale: unknown
): MarkerProjection?
	local projection = project(playerU, playerV, waypointU, waypointV, imageScale)
	if projection == nil or projection.withinWindow then
		return projection
	end
	local deltaX = projection.x - 0.5
	local deltaY = projection.y - 0.5
	local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
	local edgeScale = CIRCLE_RADIUS_NORMALIZED / distance
	return {
		x = 0.5 + deltaX * edgeScale,
		y = 0.5 + deltaY * edgeScale,
		withinWindow = false,
		edgeClamped = true,
	}
end

return table.freeze(MinimapGeometry)
