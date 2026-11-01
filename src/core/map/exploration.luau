--!strict
local Value = require("../internal/value")
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
	type MarkerRecord = Record<K>
	type Catalog = CatalogValue<K>
	type ZoneIndex = { [string]: { MarkerRecord } }
	type ExploredIdentity = Identity
	type Discovery = Identity
	type ExploredMap = ExploredState
	type PoiRow = Poi
	type Point = WorldPoint
	type PresentationRecord = Presentation<K>
	type Raw = { [unknown]: unknown }
	local MapMarkerCatalogCore = (function()
		type Raw = { [unknown]: unknown }

		local ROW_FIELDS: { [string]: boolean } = {
			zoneId = true,
			poiId = true,
			displayName = true,
			kind = true,
			position = true,
			hub = true,
		}

		local POSITION_FIELDS: { [string]: boolean } = {
			u = true,
			v = true,
		}

		local function finite(value: unknown): boolean
			return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
		end

		local function normalized(value: unknown): boolean
			return finite(value) and value >= 0 and value <= 1
		end

		local function nonempty(value: unknown): boolean
			return type(value) == "string" and #value > 0
		end

		local function hasOnlyFields(value: unknown, allowed: { [string]: boolean }): boolean
			if type(value) ~= "table" then
				return false
			end
			for key in value do
				if type(key) ~= "string" or not allowed[key] then
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
			for key in value do
				if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
					return nil
				end
				count += 1
			end
			for index = 1, count do
				if (value)[index] == nil then
					return nil
				end
			end
			return count
		end

		local function validPosition(value: unknown): boolean
			return hasOnlyFields(value, POSITION_FIELDS) and normalized((value).u) and normalized((value).v)
		end

		local function validRow(value: unknown): boolean
			local row = value
			return hasOnlyFields(value, ROW_FIELDS)
				and nonempty(row.zoneId)
				and nonempty(row.poiId)
				and nonempty(row.displayName)
				and type(row.kind) == "string"
				and config.readKind(row.kind) == row.kind
				and validPosition(row.position)
				and (row.hub == nil or type(row.hub) == "boolean")
		end

		local function copyRow(row: MarkerRecord): MarkerRecord
			return {
				zoneId = row.zoneId,
				poiId = row.poiId,
				displayName = row.displayName,
				kind = assert(config.readKind(row.kind)),
				position = {
					u = row.position.u,
					v = row.position.v,
				},
				hub = row.hub,
			}
		end

		local MapMarkerCatalogCore = {}

		function MapMarkerCatalogCore.normalize(rows: unknown): Catalog?
			local count = denseLength(rows)
			if count == nil then
				return nil
			end

			local source = rows
			local records: { MarkerRecord } = {}
			local byZone: ZoneIndex = {}
			local seen: { [string]: { [string]: boolean } } = {}

			for index = 1, count do
				local rowValue = source[index]
				if not validRow(rowValue) then
					return nil
				end
				local row = rowValue

				local zoneSeen = seen[row.zoneId]
				if zoneSeen == nil then
					zoneSeen = {}
					seen[row.zoneId] = zoneSeen
				end
				if zoneSeen[row.poiId] then
					return nil
				end
				zoneSeen[row.poiId] = true

				local record = copyRow(row)
				records[#records + 1] = record
				local zoneRecords = byZone[record.zoneId]
				if zoneRecords == nil then
					zoneRecords = {}
					byZone[record.zoneId] = zoneRecords
				end
				zoneRecords[#zoneRecords + 1] = copyRow(record)
			end

			return {
				records = records,
				byZone = byZone,
			}
		end

		return Value.freezeDeep(MapMarkerCatalogCore)
	end)()
	local MapRevealCore = (function()
		type Result = RevealResult
		local REVEAL_RADIUS_STUDS = config.revealRadius
		local REVEAL_RADIUS_SQUARED = REVEAL_RADIUS_STUDS * REVEAL_RADIUS_STUDS

		local ROW_FIELDS: { [string]: boolean } = {
			zoneId = true,
			poiId = true,
			position = true,
		}

		local OBSERVATION_FIELDS: { [string]: boolean } = {
			zoneId = true,
			position = true,
		}

		local POINT_FIELDS: { [string]: boolean } = {
			x = true,
			z = true,
		}

		type CatalogIndex = { [string]: { [string]: boolean } }
		type Raw = { [unknown]: unknown }

		local function finite(value: unknown): boolean
			return type(value) == "number" and value == value and math.abs(value) ~= math.huge
		end

		local function validId(value: unknown): boolean
			return type(value) == "string" and value ~= ""
		end

		local function validatePoint(value: unknown): boolean
			if type(value) ~= "table" then
				return false
			end
			for key in value do
				if type(key) ~= "string" or not POINT_FIELDS[key] then
					return false
				end
			end
			return finite((value).x) and finite((value).z)
		end

		local function catalogIndex(rows: unknown): (CatalogIndex?, string?)
			if type(rows) ~= "table" then
				return nil, "poi_rows_not_table"
			end
			local count = 0
			for key in rows do
				if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
					return nil, "poi_rows_not_array"
				end
				count += 1
			end
			if count == 0 then
				return nil, "poi_rows_empty"
			end
			for rowIndex = 1, count do
				if (rows)[rowIndex] == nil then
					return nil, "poi_rows_not_contiguous"
				end
			end
			local index: CatalogIndex = {}
			for rowIndex = 1, count do
				local rowValue = (rows)[rowIndex]
				if type(rowValue) ~= "table" then
					return nil, "poi_row_not_table"
				end
				local row = rowValue
				for key in row do
					if type(key) ~= "string" or not ROW_FIELDS[key] then
						return nil, "poi_row_unknown_field"
					end
				end
				if not validId(row.zoneId) then
					return nil, "invalid_poi_zone_id"
				end
				if not validId(row.poiId) then
					return nil, "invalid_poi_id"
				end
				if not validatePoint(row.position) then
					return nil, "invalid_poi_position"
				end
				local zone = index[row.zoneId]
				if zone == nil then
					zone = {}
					index[row.zoneId] = zone
				end
				if zone[row.poiId] then
					return nil, "duplicate_poi"
				end
				zone[row.poiId] = true
			end
			return index, nil
		end

		local function stateReason(state: unknown, index: CatalogIndex): string?
			if type(state) ~= "table" then
				return "explored_map_not_table"
			end
			for zoneId, exploredPois in state do
				if not validId(zoneId) or index[zoneId] == nil then
					return "unknown_explored_zone"
				end
				if type(exploredPois) ~= "table" then
					return "explored_zone_not_table"
				end
				for poiId, revealed in exploredPois do
					if not validId(poiId) or index[zoneId][poiId] == nil then
						return "unknown_explored_poi"
					end
					if revealed ~= true then
						return "explored_value_not_true"
					end
				end
			end
			return nil
		end

		local function observationReason(value: unknown, index: CatalogIndex): string?
			if type(value) ~= "table" then
				return "observation_not_table"
			end
			local observation = value
			for key in observation do
				if type(key) ~= "string" or not OBSERVATION_FIELDS[key] then
					return "observation_unknown_field"
				end
			end
			if not validId(observation.zoneId) then
				return "invalid_observation_zone_id"
			end
			if index[observation.zoneId] == nil then
				return "unknown_observation_zone"
			end
			if not validatePoint(observation.position) then
				return "invalid_observation_position"
			end
			return nil
		end

		local function copyState(state: ExploredMap): ExploredMap
			local copy: ExploredMap = {}
			for zoneId, exploredPois in state do
				copy[zoneId] = table.clone(exploredPois)
			end
			return copy
		end

		local function rejected(state: ExploredMap, reason: string): Result
			return {
				ok = false,
				reason = reason,
				state = state,
				discoveries = {},
			}
		end

		local MapRevealCore = {}

		function MapRevealCore.emptyState(): ExploredMap
			return {}
		end

		function MapRevealCore.transition(previous: ExploredMap, observation: Observation, poiRows: { PoiRow }): Result
			local index, catalogReason = catalogIndex(poiRows)
			if index == nil then
				return rejected(previous, catalogReason or "invalid_poi_rows")
			end
			local invalidState = stateReason(previous, index)
			if invalidState ~= nil then
				return rejected(previous, invalidState)
			end
			local invalidObservation = observationReason(observation, index)
			if invalidObservation ~= nil then
				return rejected(previous, invalidObservation)
			end

			local zoneId = observation.zoneId
			local exploredZone = previous[zoneId]
			local discoveredIds: { string } = {}
			for _, row in poiRows do
				if row.zoneId == zoneId and (exploredZone == nil or exploredZone[row.poiId] ~= true) then
					local dx = observation.position.x - row.position.x
					local dz = observation.position.z - row.position.z
					local distanceSquared = dx * dx + dz * dz
					if not finite(distanceSquared) then
						return rejected(previous, "nonfinite_distance")
					end
					if distanceSquared <= REVEAL_RADIUS_SQUARED then
						discoveredIds[#discoveredIds + 1] = row.poiId
					end
				end
			end

			if #discoveredIds == 0 then
				return {
					ok = true,
					state = previous,
					discoveries = {},
				}
			end

			local nextState = copyState(previous)
			local nextZone = nextState[zoneId] or {}
			nextState[zoneId] = nextZone
			local discoveries: { Discovery } = {}
			for _, poiId in discoveredIds do
				nextZone[poiId] = true
				discoveries[#discoveries + 1] = { zoneId = zoneId, poiId = poiId }
			end
			return {
				ok = true,
				state = nextState,
				discoveries = discoveries,
			}
		end

		MapRevealCore.REVEAL_RADIUS_STUDS = REVEAL_RADIUS_STUDS

		return MapRevealCore
	end)()
	local MapExploredStateCore = (function()
		type CatalogIndex = { [string]: { [string]: boolean } }

		local function catalogIndex(markerRowsValue: unknown): (CatalogIndex?, Catalog?)
			local catalog = MapMarkerCatalogCore.normalize(markerRowsValue)
			if catalog == nil then
				return nil, nil
			end

			local index: CatalogIndex = {}
			for _, record in catalog.records do
				local zone = index[record.zoneId]
				if zone == nil then
					zone = {}
					index[record.zoneId] = zone
				end
				zone[record.poiId] = true
			end
			return index, catalog
		end

		local function copyValidated(value: unknown, index: CatalogIndex): ExploredState?
			if type(value) ~= "table" then
				return nil
			end

			local result: ExploredState = {}
			for zoneId, zoneValue in value do
				if type(zoneId) ~= "string" or index[zoneId] == nil or type(zoneValue) ~= "table" then
					return nil
				end

				local zone: { [string]: true } = {}
				for poiId, explored in zoneValue do
					if type(poiId) ~= "string" or index[zoneId][poiId] ~= true or explored ~= true then
						return nil
					end
					zone[poiId] = true
				end
				result[zoneId] = zone
			end
			return result
		end

		local MapExploredStateCore = {}

		function MapExploredStateCore.defaultState(): ExploredState
			return {}
		end

		function MapExploredStateCore.resetState(): ExploredState
			return {}
		end

		function MapExploredStateCore.normalize(value: unknown, markerRowsValue: unknown): ExploredState?
			local index = catalogIndex(markerRowsValue)
			if index == nil then
				return nil
			end
			return copyValidated(value, index)
		end

		function MapExploredStateCore.merge(
			previousValue: unknown,
			additionsValue: unknown,
			markerRowsValue: unknown
		): ExploredState?
			local index = catalogIndex(markerRowsValue)
			if index == nil then
				return nil
			end

			local previous = copyValidated(previousValue, index)
			local additions = copyValidated(additionsValue, index)
			if previous == nil or additions == nil then
				return nil
			end

			for zoneId, additionZone in additions do
				local mergedZone = previous[zoneId]
				if mergedZone == nil then
					mergedZone = {}
					previous[zoneId] = mergedZone
				end
				for poiId in additionZone do
					mergedZone[poiId] = true
				end
			end
			return previous
		end

		function MapExploredStateCore.ordered(value: unknown, markerRowsValue: unknown): { ExploredIdentity }?
			local index, catalog = catalogIndex(markerRowsValue)
			if index == nil or catalog == nil then
				return nil
			end

			local state = copyValidated(value, index)
			if state == nil then
				return nil
			end

			local result: { ExploredIdentity } = {}
			for _, record in catalog.records do
				local zone = state[record.zoneId]
				if zone ~= nil and zone[record.poiId] == true then
					result[#result + 1] = {
						zoneId = record.zoneId,
						poiId = record.poiId,
					}
				end
			end
			return result
		end

		return Value.freezeDeep(MapExploredStateCore)
	end)()
	local MapDiscoveryProjectionCore = (function()
		local DISCOVERY_FIELDS: { [string]: boolean } = {
			zoneId = true,
			poiId = true,
		}

		local function nonempty(value: unknown): boolean
			return type(value) == "string" and #value > 0
		end

		local function denseLength(value: unknown): number?
			if type(value) ~= "table" then
				return nil
			end
			local count = 0
			for key in value do
				if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
					return nil
				end
				count += 1
			end
			for index = 1, count do
				if (value)[index] == nil then
					return nil
				end
			end
			return count
		end

		local function validDiscovery(value: unknown): boolean
			if type(value) ~= "table" then
				return false
			end
			for key in value do
				if type(key) ~= "string" or not DISCOVERY_FIELDS[key] then
					return false
				end
			end
			local discovery = value
			return nonempty(discovery.zoneId) and nonempty(discovery.poiId)
		end

		local MapDiscoveryProjectionCore = {}

		function MapDiscoveryProjectionCore.project(
			discoveriesValue: unknown,
			markerRowsValue: unknown
		): { PresentationRecord }?
			local catalog = MapMarkerCatalogCore.normalize(markerRowsValue)
			if catalog == nil then
				return nil
			end

			local count = denseLength(discoveriesValue)
			if count == nil then
				return nil
			end

			local discoveries = discoveriesValue
			local seen: { [string]: { [string]: boolean } } = {}
			local presentations: { PresentationRecord } = {}
			for index = 1, count do
				local discoveryValue = discoveries[index]
				if not validDiscovery(discoveryValue) then
					return nil
				end
				local discovery = discoveryValue

				local zoneSeen = seen[discovery.zoneId]
				if zoneSeen == nil then
					zoneSeen = {}
					seen[discovery.zoneId] = zoneSeen
				end
				if zoneSeen[discovery.poiId] then
					return nil
				end
				zoneSeen[discovery.poiId] = true

				local matched: MarkerRecord? = nil
				local zoneRecords = catalog.byZone[discovery.zoneId]
				if zoneRecords ~= nil then
					for _, record in zoneRecords do
						if record.poiId == discovery.poiId then
							if matched ~= nil then
								return nil
							end
							matched = record
						end
					end
				end
				if matched == nil then
					return nil
				end

				presentations[#presentations + 1] = {
					zoneId = discovery.zoneId,
					poiId = discovery.poiId,
					name = matched.displayName,
					kind = matched.kind,
					hub = matched.hub,
				}
			end

			return presentations
		end

		return Value.freezeDeep(MapDiscoveryProjectionCore)
	end)()
	local MapExplorationPipelineCore = (function()
		type Raw = { [unknown]: unknown }
		type Result = Transition<K>
		local ROW_FIELDS: { [string]: boolean } = {
			zoneId = true,
			poiId = true,
			position = true,
		}

		local POINT_FIELDS: { [string]: boolean } = {
			x = true,
			z = true,
		}

		local function finite(value: unknown): boolean
			return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
		end

		local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
			if type(value) ~= "table" then
				return false
			end
			for key in value do
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
			for key in value do
				if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
					return nil
				end
				count += 1
			end
			for index = 1, count do
				if (value)[index] == nil then
					return nil
				end
			end
			return count
		end

		local function validRevealRow(value: unknown): boolean
			if not hasOnlyFields(value, ROW_FIELDS) then
				return false
			end
			local row = value
			if type(row.zoneId) ~= "string" or #row.zoneId == 0 or type(row.poiId) ~= "string" or #row.poiId == 0 then
				return false
			end
			if not hasOnlyFields(row.position, POINT_FIELDS) then
				return false
			end
			return finite((row.position).x) and finite((row.position).z)
		end

		local function matchingRevealRows(revealRowsValue: unknown, catalog: Catalog): boolean
			local count = denseLength(revealRowsValue)
			if count == nil or count ~= #catalog.records then
				return false
			end

			local expected: { [string]: { [string]: boolean } } = {}
			for _, record in catalog.records do
				local zone = expected[record.zoneId]
				if zone == nil then
					zone = {}
					expected[record.zoneId] = zone
				end
				zone[record.poiId] = true
			end

			for index = 1, count do
				local row = (revealRowsValue)[index]
				if not validRevealRow(row) then
					return false
				end
				local expectedZone = expected[row.zoneId]
				if expectedZone == nil or expectedZone[row.poiId] ~= true then
					return false
				end
				expectedZone[row.poiId] = false
			end
			return true
		end

		local function freezeState(state: ExploredState): ExploredState
			for _, zone in state do
				table.freeze(zone)
			end
			return table.freeze(state)
		end

		local function freezePresentations(presentations: { PresentationRecord }): { PresentationRecord }
			for _, presentation in presentations do
				table.freeze(presentation)
			end
			return table.freeze(presentations)
		end

		local MapExplorationPipelineCore = {}

		function MapExplorationPipelineCore.transition(
			previousStateValue: unknown,
			observationValue: unknown,
			revealRowsValue: unknown,
			markerRowsValue: unknown
		): Result?
			local catalog = MapMarkerCatalogCore.normalize(markerRowsValue)
			if catalog == nil or not matchingRevealRows(revealRowsValue, catalog) then
				return nil
			end

			local previousState = MapExploredStateCore.normalize(previousStateValue, markerRowsValue)
			if previousState == nil then
				return nil
			end

			local revealResult = MapRevealCore.transition(previousState, observationValue, revealRowsValue)
			if not revealResult.ok then
				return nil
			end

			local presentations = MapDiscoveryProjectionCore.project(revealResult.discoveries, markerRowsValue)
			if presentations == nil then
				return nil
			end

			local result: Result = {
				state = freezeState(revealResult.state),
				presentations = freezePresentations(presentations),
			}
			return Value.freezeDeep(result)
		end

		return Value.freezeDeep(MapExplorationPipelineCore)
	end)()
	local result: System<K> = {
		catalog = MapMarkerCatalogCore,
		reveal = MapRevealCore,
		state = MapExploredStateCore,
		discovery = MapDiscoveryProjectionCore,
		pipeline = MapExplorationPipelineCore,
	}
	return Value.freezeDeep(result)
end
return table.freeze(Exploration)
