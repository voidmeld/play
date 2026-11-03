--!strict
local Value = require("../../kernel/value")

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

local function point(value: unknown): NormalizedPoint?
	local raw = Value.record(value, POINT_FIELDS, false, false)
	if raw == nil then
		return nil
	end
	local u, v = raw.u, raw.v
	if type(u) ~= "number" or type(v) ~= "number" or MinimapGeometry.projectMarker(0.5, 0.5, u, v, 2) == nil then
		return nil
	end
	return { u = u, v = v }
end

local function marker(value: unknown): MarkerRow?
	local raw = Value.record(value, MARKER_FIELDS, false, false)
	if raw == nil then
		return nil
	end
	local zone, poi, position = raw.zoneId, raw.poiId, point(raw.position)
	if type(zone) ~= "string" or zone == "" or type(poi) ~= "string" or poi == "" or position == nil then
		return nil
	end
	return { zoneId = zone, poiId = poi, position = position }
end

local MapViewportModel = {}
function MapViewportModel.build(value: unknown): Viewport?
	local input = Value.record(value, INPUT_FIELDS, false, false)
	if input == nil then
		return nil
	end
	local zone = input.zoneId
	local playerPoint = point(input.player)
	if type(zone) ~= "string" or zone == "" or playerPoint == nil then
		return nil
	end
	local rawRows = Value.dense(input.markerRows, math.huge, false)
	if rawRows == nil or #rawRows == 0 then
		return nil
	end
	local rows: { MarkerRow } = {}
	local index: { [string]: { [string]: boolean } } = {}
	for _, value in rawRows do
		local row = marker(value)
		if row == nil then
			return nil
		end
		local bucket = index[row.zoneId]
		if bucket == nil then
			bucket = {}
			index[row.zoneId] = bucket
		end
		if bucket[row.poiId] then
			return nil
		end
		bucket[row.poiId] = true
		table.insert(rows, row)
	end
	if index[zone] == nil then
		return nil
	end
	local explored = Value.raw(input.exploredMap)
	if explored == nil then
		return nil
	end
	local revealed: { [string]: boolean } = {}
	for zoneId, rawPois in explored do
		if type(zoneId) ~= "string" or zoneId == "" or index[zoneId] == nil then
			return nil
		end
		local pois = Value.raw(rawPois)
		if pois == nil then
			return nil
		end
		for poiId, visible in pois do
			if type(poiId) ~= "string" or poiId == "" or index[zoneId][poiId] == nil or visible ~= true then
				return nil
			end
			if zoneId == zone then
				revealed[poiId] = true
			end
		end
	end
	local waypoint: NormalizedPoint? = nil
	if input.trackedWaypoint ~= nil then
		local raw = Value.record(input.trackedWaypoint, WAYPOINT_FIELDS, false, false)
		if raw == nil or raw.zoneId ~= zone then
			return nil
		end
		waypoint = point(raw.position)
		if waypoint == nil then
			return nil
		end
	end
	local scale = input.imageScale
	local imagePan = MinimapGeometry.imagePan(playerPoint.u, playerPoint.v, scale)
	local player = MinimapGeometry.projectMarker(playerPoint.u, playerPoint.v, playerPoint.u, playerPoint.v, scale)
	if imagePan == nil or player == nil then
		return nil
	end
	local markers: { PoiMarker } = {}
	for _, row in rows do
		if row.zoneId == zone and revealed[row.poiId] then
			local projection =
				MinimapGeometry.projectMarker(playerPoint.u, playerPoint.v, row.position.u, row.position.v, scale)
			if projection == nil then
				return nil
			end
			if projection.withinWindow then
				table.insert(markers, { zoneId = zone, poiId = row.poiId, projection = projection })
			end
		end
	end
	local tracked: MinimapGeometry.MarkerProjection? = nil
	if waypoint ~= nil then
		tracked = MinimapGeometry.projectTrackedWaypoint(playerPoint.u, playerPoint.v, waypoint.u, waypoint.v, scale)
		if tracked == nil then
			return nil
		end
	end
	return { imagePan = imagePan, player = player, poiMarkers = markers, trackedWaypoint = tracked }
end

return table.freeze(MapViewportModel)
