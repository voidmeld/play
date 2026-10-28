--!strict
local Exploration = require("./exploration")
local MapViewportModel = require("./viewport")
local UpdateTypes = require("./updates")
export type PreferredInput = "pointer" | "touch"
export type Surface = {
	preferredInput: PreferredInput,
	enabled: boolean,
	diameterPx: number,
	northLocked: boolean,
	rotates: boolean,
}
export type Input<K> = {
	preferredInput: PreferredInput,
	explicitEnabled: boolean?,
	previousUpdateState: UpdateTypes.State,
	sample: UpdateTypes.Sample,
	zoneId: string,
	markerRows: { Exploration.Record<K> },
	exploredMap: Exploration.ExploredState,
	imageScale: number,
	trackedWaypoint: MapViewportModel.TrackedWaypoint?,
}

export type Result = {
	surface: Surface,
	updateState: UpdateTypes.State,
	viewportUpdate: MapViewportModel.Viewport?,
}

local Renderer = {}
function Renderer.new<K>(deps: {
	read normalize: (unknown) -> Exploration.CatalogValue<K>?,
	read resolve: (unknown, unknown) -> Surface?,
	read update: (unknown, unknown) -> UpdateTypes.Result?,
})
	local MapMarkerCatalogCore = { normalize = deps.normalize }
	local MinimapSurfacePolicy = { resolve = deps.resolve }
	local MinimapUpdateCore = { transition = deps.update }
	local INPUT_FIELDS: { [string]: boolean } = {
		preferredInput = true,
		explicitEnabled = true,
		previousUpdateState = true,
		sample = true,
		zoneId = true,
		markerRows = true,
		exploredMap = true,
		imageScale = true,
		trackedWaypoint = true,
	}

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" then
			return false
		end
		for key in value :: { [unknown]: unknown } do
			if type(key) ~= "string" or not fields[key] then
				return false
			end
		end
		return true
	end

	local function copyState(state: UpdateTypes.State): UpdateTypes.State
		return {
			lastSampleAtSeconds = state.lastSampleAtSeconds,
			lastPanAtSeconds = state.lastPanAtSeconds,
			markerRevision = state.markerRevision,
		}
	end

	local function viewportRows(records: { Exploration.Record<K> }): { MapViewportModel.MarkerRow }
		local rows: { MapViewportModel.MarkerRow } = {}
		for _, record in records do
			rows[#rows + 1] = {
				zoneId = record.zoneId,
				poiId = record.poiId,
				position = {
					u = record.position.u,
					v = record.position.v,
				},
			}
		end
		return rows
	end

	local MinimapRenderCore = {}

	function MinimapRenderCore.compose(input: unknown): Result?
		if not hasOnlyFields(input, INPUT_FIELDS) then
			return nil
		end
		local source = input :: Input<K>
		local surface = MinimapSurfacePolicy.resolve(source.preferredInput, source.explicitEnabled)
		if surface == nil then
			return nil
		end

		local update = MinimapUpdateCore.transition(source.previousUpdateState, source.sample)
		if update == nil then
			return nil
		end
		if not surface.enabled then
			return {
				surface = surface,
				updateState = copyState(source.previousUpdateState :: UpdateTypes.State),
				viewportUpdate = nil,
			}
		end
		if update.output.pan == nil and update.output.markers == nil then
			return {
				surface = surface,
				updateState = update.state,
				viewportUpdate = nil,
			}
		end

		local catalog = MapMarkerCatalogCore.normalize(source.markerRows)
		if catalog == nil then
			return nil
		end
		local viewport = MapViewportModel.build({
			zoneId = source.zoneId,
			exploredMap = source.exploredMap,
			markerRows = viewportRows(catalog.records),
			player = source.sample.player,
			imageScale = source.imageScale,
			trackedWaypoint = source.trackedWaypoint,
		})
		if viewport == nil then
			return nil
		end

		return {
			surface = surface,
			updateState = update.state,
			viewportUpdate = viewport,
		}
	end

	return table.freeze(MinimapRenderCore)
end
return table.freeze(Renderer)
