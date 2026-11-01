--!strict
local Value = require("../value")
export type Record<K> = {
	zoneId: string,
	poiId: string,
	displayName: string,
	kind: K,
	position: { u: number, v: number },
	hub: boolean?,
}
export type CatalogValue<K> = { records: { Record<K> }, byZone: { [string]: { Record<K> } } }
export type ExploredState = { [string]: { [string]: true } }
export type Identity = { zoneId: string, poiId: string }
export type WorldPoint = { x: number, z: number }
export type Poi = { zoneId: string, poiId: string, position: WorldPoint }
export type Observation = { zoneId: string, position: WorldPoint }
export type RevealResult = { ok: boolean, reason: string?, state: ExploredState, discoveries: { Identity } }
export type Presentation<K> = { zoneId: string, poiId: string, name: string, kind: K, hub: boolean? }
export type Transition<K> = { state: ExploredState, presentations: { Presentation<K> } }
export type System<K> = {
	catalog: { normalize: (unknown) -> CatalogValue<K>? },
	reveal: {
		emptyState: () -> ExploredState,
		transition: (ExploredState, Observation, { Poi }) -> RevealResult,
		REVEAL_RADIUS_STUDS: number,
	},
	state: {
		defaultState: () -> ExploredState,
		resetState: () -> ExploredState,
		normalize: (unknown, unknown) -> ExploredState?,
		merge: (unknown, unknown, unknown) -> ExploredState?,
		ordered: (unknown, unknown) -> { Identity }?,
	},
	discovery: { project: (unknown, unknown) -> { Presentation<K> }? },
	pipeline: { transition: (unknown, unknown, unknown, unknown) -> Transition<K>? },
}
local Exploration = {}
function Exploration.new<K>(config: { read readKind: (unknown) -> K?, read revealRadius: number }): System<K>
	assert(
		config.revealRadius == config.revealRadius and config.revealRadius >= 0 and config.revealRadius < math.huge,
		"invalid reveal radius"
	)
	type Catalog = CatalogValue<K>
	type Marker = Record<K>
	type Index = { [string]: { [string]: boolean } }
	local markerFields = { zoneId = true, poiId = true, displayName = true, kind = true, position = true, hub = true }
	local poiFields = { zoneId = true, poiId = true, position = true }
	local observationFields = { zoneId = true, position = true }
	local identityFields = { zoneId = true, poiId = true }
	local normalizedFields = { u = true, v = true }
	local worldFields = { x = true, z = true }
	local function finite(value: unknown): number?
		return if type(value) == "number" and value == value and math.abs(value) ~= math.huge then value else nil
	end
	local function text(value: unknown): string?
		return if type(value) == "string" and value ~= "" then value else nil
	end
	local function worldPoint(value: unknown): WorldPoint?
		local raw = Value.record(value, worldFields, false, false)
		if raw == nil then
			return nil
		end
		local x, z = finite(raw.x), finite(raw.z)
		return if x ~= nil and z ~= nil then { x = x, z = z } else nil
	end
	local function normalizedPoint(value: unknown): { u: number, v: number }?
		local raw = Value.record(value, normalizedFields, false, false)
		if raw == nil then
			return nil
		end
		local u, v = finite(raw.u), finite(raw.v)
		if u == nil or v == nil or u < 0 or u > 1 or v < 0 or v > 1 then
			return nil
		end
		return { u = u, v = v }
	end
	local function readMarker(value: unknown): Marker?
		local raw = Value.record(value, markerFields, false, false)
		if raw == nil then
			return nil
		end
		local zone, poi, name = text(raw.zoneId), text(raw.poiId), text(raw.displayName)
		local position, kind, hub = normalizedPoint(raw.position), config.readKind(raw.kind), raw.hub
		if
			zone == nil
			or poi == nil
			or name == nil
			or position == nil
			or type(raw.kind) ~= "string"
			or kind == nil
			or kind ~= raw.kind
			or (hub ~= nil and type(hub) ~= "boolean")
		then
			return nil
		end
		local marker: Marker =
			{ zoneId = zone, poiId = poi, displayName = name, kind = kind, position = position, hub = hub }
		return marker
	end
	local function normalize(value: unknown): Catalog?
		local rows = Value.dense(value, math.huge, false)
		if rows == nil then
			return nil
		end
		local records: { Marker } = {}
		local byZone: { [string]: { Marker } } = {}
		local seen: Index = {}
		for _, value in rows do
			local record = readMarker(value)
			if record == nil then
				return nil
			end
			local zone = seen[record.zoneId]
			if zone == nil then
				zone = {}
				seen[record.zoneId] = zone
			end
			if zone[record.poiId] then
				return nil
			end
			zone[record.poiId] = true
			table.insert(records, record)
			local bucket = byZone[record.zoneId]
			if bucket == nil then
				bucket = {}
				byZone[record.zoneId] = bucket
			end
			local copy: Marker = {
				zoneId = record.zoneId,
				poiId = record.poiId,
				displayName = record.displayName,
				kind = record.kind,
				position = table.clone(record.position),
				hub = record.hub,
			}
			table.insert(bucket, copy)
		end
		return { records = records, byZone = byZone }
	end
	local function markerIndex(catalog: Catalog): Index
		local index: Index = {}
		for _, row in catalog.records do
			local zone = index[row.zoneId]
			if zone == nil then
				zone = {}
				index[row.zoneId] = zone
			end
			zone[row.poiId] = true
		end
		return index
	end
	local function readState(value: unknown, index: Index): (ExploredState?, string?)
		local raw = Value.raw(value)
		if raw == nil then
			return nil, "explored_map_not_table"
		end
		local state: ExploredState = {}
		for zoneId, rawPois in raw do
			if type(zoneId) ~= "string" or zoneId == "" or index[zoneId] == nil then
				return nil, "unknown_explored_zone"
			end
			local pois = Value.raw(rawPois)
			if pois == nil then
				return nil, "explored_zone_not_table"
			end
			local zone: { [string]: true } = {}
			for poiId, revealed in pois do
				if type(poiId) ~= "string" or poiId == "" or index[zoneId][poiId] == nil then
					return nil, "unknown_explored_poi"
				end
				if revealed ~= true then
					return nil, "explored_value_not_true"
				end
				zone[poiId] = true
			end
			state[zoneId] = zone
		end
		return state, nil
	end
	local function readPois(value: unknown): ({ Poi }?, Index?, string?)
		local raw = Value.raw(value)
		if raw == nil then
			return nil, nil, "poi_rows_not_table"
		end
		local count = 0
		for key in raw do
			if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
				return nil, nil, "poi_rows_not_array"
			end
			count += 1
		end
		if count == 0 then
			return nil, nil, "poi_rows_empty"
		end
		local rows: { Poi } = {}
		local index: Index = {}
		for at = 1, count do
			if raw[at] == nil then
				return nil, nil, "poi_rows_not_contiguous"
			end
			if type(raw[at]) ~= "table" then
				return nil, nil, "poi_row_not_table"
			end
			local row = Value.record(raw[at], poiFields, false, false)
			if row == nil then
				return nil, nil, "poi_row_unknown_field"
			end
			local zoneId, poiId, position = text(row.zoneId), text(row.poiId), worldPoint(row.position)
			if zoneId == nil then
				return nil, nil, "invalid_poi_zone_id"
			end
			if poiId == nil then
				return nil, nil, "invalid_poi_id"
			end
			if position == nil then
				return nil, nil, "invalid_poi_position"
			end
			local zone = index[zoneId]
			if zone == nil then
				zone = {}
				index[zoneId] = zone
			end
			if zone[poiId] then
				return nil, nil, "duplicate_poi"
			end
			zone[poiId] = true
			table.insert(rows, { zoneId = zoneId, poiId = poiId, position = position })
		end
		return rows, index, nil
	end
	local function readObservation(value: unknown, index: Index): (Observation?, string?)
		if type(value) ~= "table" then
			return nil, "observation_not_table"
		end
		local raw = Value.record(value, observationFields, false, false)
		if raw == nil then
			return nil, "observation_unknown_field"
		end
		local zone, position = text(raw.zoneId), worldPoint(raw.position)
		if zone == nil then
			return nil, "invalid_observation_zone_id"
		end
		if index[zone] == nil then
			return nil, "unknown_observation_zone"
		end
		if position == nil then
			return nil, "invalid_observation_position"
		end
		return { zoneId = zone, position = position }, nil
	end
	local function reveal(previous: ExploredState, observationValue: Observation, poiValues: { Poi }): RevealResult
		local function reject(reason: string): RevealResult
			return { ok = false, reason = reason, state = previous, discoveries = {} }
		end
		local rows, index, rowReason = readPois(poiValues)
		if rows == nil or index == nil then
			return reject(rowReason or "invalid_poi_rows")
		end
		local state, stateReason = readState(previous, index)
		if state == nil then
			return reject(stateReason or "explored_map_not_table")
		end
		local observation, observationReason = readObservation(observationValue, index)
		if observation == nil then
			return reject(observationReason or "observation_not_table")
		end
		local discoveries: { Identity } = {}
		local zone = state[observation.zoneId]
		for _, row in rows do
			if row.zoneId == observation.zoneId and (zone == nil or zone[row.poiId] ~= true) then
				local dx, dz = observation.position.x - row.position.x, observation.position.z - row.position.z
				local distance = finite(dx * dx + dz * dz)
				if distance == nil then
					return reject("nonfinite_distance")
				end
				if distance <= config.revealRadius * config.revealRadius then
					table.insert(discoveries, { zoneId = row.zoneId, poiId = row.poiId })
				end
			end
		end
		if #discoveries == 0 then
			return { ok = true, state = previous, discoveries = {} }
		end
		if zone == nil then
			zone = {}
			state[observation.zoneId] = zone
		end
		for _, row in discoveries do
			zone[row.poiId] = true
		end
		return { ok = true, state = state, discoveries = discoveries }
	end
	local function normalizeState(value: unknown, markerRows: unknown): ExploredState?
		local catalog = normalize(markerRows)
		if catalog == nil then
			return nil
		end
		local state = readState(value, markerIndex(catalog))
		return state
	end
	local function merge(previousValue: unknown, additionsValue: unknown, markerRows: unknown): ExploredState?
		local catalog = normalize(markerRows)
		if catalog == nil then
			return nil
		end
		local index = markerIndex(catalog)
		local previous, additions = readState(previousValue, index), readState(additionsValue, index)
		if previous == nil or additions == nil then
			return nil
		end
		for zoneId, entries in additions do
			local zone = previous[zoneId]
			if zone == nil then
				zone = {}
				previous[zoneId] = zone
			end
			for poiId in entries do
				zone[poiId] = true
			end
		end
		return previous
	end
	local function ordered(value: unknown, markerRows: unknown): { Identity }?
		local catalog = normalize(markerRows)
		if catalog == nil then
			return nil
		end
		local state = readState(value, markerIndex(catalog))
		if state == nil then
			return nil
		end
		local result: { Identity } = {}
		for _, row in catalog.records do
			local zone = state[row.zoneId]
			if zone ~= nil and zone[row.poiId] then
				table.insert(result, { zoneId = row.zoneId, poiId = row.poiId })
			end
		end
		return result
	end
	local function presentations(values: unknown, markerRows: unknown): { Presentation<K> }?
		local catalog, discoveries = normalize(markerRows), Value.dense(values, math.huge, false)
		if catalog == nil or discoveries == nil then
			return nil
		end
		local seen: Index = {}
		local result: { Presentation<K> } = {}
		for _, value in discoveries do
			local row = Value.record(value, identityFields, false, false)
			if row == nil then
				return nil
			end
			local zoneId, poiId = text(row.zoneId), text(row.poiId)
			if zoneId == nil or poiId == nil then
				return nil
			end
			local zone = seen[zoneId]
			if zone == nil then
				zone = {}
				seen[zoneId] = zone
			end
			if zone[poiId] then
				return nil
			end
			zone[poiId] = true
			local matched: Marker? = nil
			for _, marker in catalog.byZone[zoneId] or {} do
				if marker.poiId == poiId then
					matched = marker
					break
				end
			end
			if matched == nil then
				return nil
			end
			local presentation: Presentation<K> =
				{ zoneId = zoneId, poiId = poiId, name = matched.displayName, kind = matched.kind, hub = matched.hub }
			table.insert(result, presentation)
		end
		return result
	end
	local function transition(
		previousValue: unknown,
		observationValue: unknown,
		poiValues: unknown,
		markerRows: unknown
	): Transition<K>?
		local catalog = normalize(markerRows)
		local pois, index = readPois(poiValues)
		if catalog == nil or pois == nil or index == nil or #pois ~= #catalog.records then
			return nil
		end
		local expected = markerIndex(catalog)
		for _, poi in pois do
			local zone = expected[poi.zoneId]
			if zone == nil or not zone[poi.poiId] then
				return nil
			end
		end
		local previous = readState(previousValue, expected)
		local observation = readObservation(observationValue, index)
		if previous == nil or observation == nil then
			return nil
		end
		local revealed = reveal(previous, observation, pois)
		if not revealed.ok then
			return nil
		end
		local projected = presentations(revealed.discoveries, markerRows)
		if projected == nil then
			return nil
		end
		local result: Transition<K> = { state = revealed.state, presentations = projected }
		return Value.freezeDeep(result)
	end
	local function empty(): ExploredState
		return {}
	end
	local result: System<K> = {
		catalog = { normalize = normalize },
		reveal = { emptyState = empty, transition = reveal, REVEAL_RADIUS_STUDS = config.revealRadius },
		state = {
			defaultState = empty,
			resetState = empty,
			normalize = normalizeState,
			merge = merge,
			ordered = ordered,
		},
		discovery = { project = presentations },
		pipeline = { transition = transition },
	}
	return Value.freezeDeep(result)
end
return Value.freezeDeep(Exploration)
