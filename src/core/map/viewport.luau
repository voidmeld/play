--!strict

local MapRevealCore = require("./exploration")
local MinimapGeometry = require("./geometry")

export type NormalizedPoint = {
	u: number,
	v: number,
}

export type MarkerRow = {
	zoneId: string,
	poiId: string,
	position: NormalizedPoint,
}

export type TrackedWaypoint = {
	zoneId: string,
	position: NormalizedPoint,
}

export type Input = {
	zoneId: string,
	exploredMap: MapRevealCore.ExploredState,
	markerRows: { MarkerRow },
	player: NormalizedPoint,
	imageScale: number,
	trackedWaypoint: TrackedWaypoint?,
}

export type PoiMarker = {
	zoneId: string,
	poiId: string,
	projection: MinimapGeometry.MarkerProjection,
}

export type Viewport = {
	imagePan: MinimapGeometry.PanOffset,
	player: MinimapGeometry.MarkerProjection,
	poiMarkers: { PoiMarker },
	trackedWaypoint: MinimapGeometry.MarkerProjection?,
}

local INPUT_FIELDS: { [string]: boolean } = {
	zoneId = true,
	exploredMap = true,
	markerRows = true,
	player = true,
	imageScale = true,
	trackedWaypoint = true,
}

local MARKER_FIELDS: { [string]: boolean } = {
	zoneId = true,
	poiId = true,
	position = true,
}

local WAYPOINT_FIELDS: { [string]: boolean } = {
	zoneId = true,
	position = true,
}

local POINT_FIELDS: { [string]: boolean } = {
	u = true,
	v = true,
}

type MarkerIndex = { [string]: { [string]: boolean } }
type Raw = { [unknown]: unknown }

local function validId(value: unknown): boolean
	return type(value) == "string" and value ~= ""
end

local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
	if type(value) ~= "table" then
		return false
	end
	for key in value :: Raw do
		if type(key) ~= "string" or not fields[key] then
			return false
		end
	end
	return true
end

local function validPoint(value: unknown): boolean
	return hasOnlyFields(value, POINT_FIELDS)
		and MinimapGeometry.projectMarker(0.5, 0.5, (value :: Raw).u, (value :: Raw).v, 2) ~= nil
end

local function arrayLength(value: unknown): number?
	if type(value) ~= "table" then
		return nil
	end
	local count = 0
	for key in value :: Raw do
		if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
			return nil
		end
		count += 1
	end
	for index = 1, count do
		if (value :: Raw)[index] == nil then
			return nil
		end
	end
	return count
end

local function markerIndex(rows: unknown): (MarkerIndex?, number?)
	local count = arrayLength(rows)
	if count == nil or count == 0 then
		return nil, nil
	end
	local index: MarkerIndex = {}
	for rowIndex = 1, count do
		local row = (rows :: Raw)[rowIndex]
		if
			not hasOnlyFields(row, MARKER_FIELDS)
			or not validId((row :: Raw).zoneId)
			or not validId((row :: Raw).poiId)
			or not validPoint((row :: Raw).position)
		then
			return nil, nil
		end
		local marker = row :: MarkerRow
		local zone = index[marker.zoneId]
		if zone == nil then
			zone = {}
			index[marker.zoneId] = zone
		end
		if zone[marker.poiId] then
			return nil, nil
		end
		zone[marker.poiId] = true
	end
	return index, count
end

local function validExploredMap(exploredMap: unknown, index: MarkerIndex): boolean
	if type(exploredMap) ~= "table" then
		return false
	end
	for zoneId, exploredPois in exploredMap :: Raw do
		if not validId(zoneId) or index[zoneId :: string] == nil or type(exploredPois) ~= "table" then
			return false
		end
		for poiId, revealed in exploredPois :: Raw do
			if not validId(poiId) or index[zoneId :: string][poiId :: string] == nil or revealed ~= true then
				return false
			end
		end
	end
	return true
end

local function validWaypoint(value: unknown, zoneId: string): boolean
	return hasOnlyFields(value, WAYPOINT_FIELDS)
		and (value :: Raw).zoneId == zoneId
		and validPoint((value :: Raw).position)
end

local MapViewportModel = {}

function MapViewportModel.build(value: unknown): Viewport?
	if
		not hasOnlyFields(value, INPUT_FIELDS)
		or not validId((value :: Raw).zoneId)
		or not validPoint((value :: Raw).player)
	then
		return nil
	end
	local input = value :: Input
	local index, markerCount = markerIndex(input.markerRows)
	if index == nil or markerCount == nil or index[input.zoneId] == nil then
		return nil
	end
	if not validExploredMap(input.exploredMap, index) then
		return nil
	end
	if input.trackedWaypoint ~= nil and not validWaypoint(input.trackedWaypoint, input.zoneId) then
		return nil
	end

	local imagePan = MinimapGeometry.imagePan(input.player.u, input.player.v, input.imageScale)
	local player =
		MinimapGeometry.projectMarker(input.player.u, input.player.v, input.player.u, input.player.v, input.imageScale)
	if imagePan == nil or player == nil then
		return nil
	end

	local exploredZone = input.exploredMap[input.zoneId]
	local poiMarkers: { PoiMarker } = {}
	for rowIndex = 1, markerCount do
		local row = input.markerRows[rowIndex]
		if row.zoneId == input.zoneId and exploredZone ~= nil and exploredZone[row.poiId] == true then
			local projection = MinimapGeometry.projectMarker(
				input.player.u,
				input.player.v,
				row.position.u,
				row.position.v,
				input.imageScale
			)
			if projection == nil then
				return nil
			end
			if projection.withinWindow then
				poiMarkers[#poiMarkers + 1] = {
					zoneId = row.zoneId,
					poiId = row.poiId,
					projection = projection,
				}
			end
		end
	end

	local trackedWaypoint = nil
	if input.trackedWaypoint ~= nil then
		trackedWaypoint = MinimapGeometry.projectTrackedWaypoint(
			input.player.u,
			input.player.v,
			input.trackedWaypoint.position.u,
			input.trackedWaypoint.position.v,
			input.imageScale
		)
		if trackedWaypoint == nil then
			return nil
		end
	end

	return {
		imagePan = imagePan,
		player = player,
		poiMarkers = poiMarkers,
		trackedWaypoint = trackedWaypoint,
	}
end

return table.freeze(MapViewportModel)
