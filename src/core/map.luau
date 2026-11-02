--!strict

local Coordinates = require("./map/coordinates")
local Exploration = require("./map/exploration")
local Geometry = require("./map/geometry")
local Polyline = require("./map/polyline")
local Renderer = require("./map/renderer")
local Updates = require("./map/updates")
local Viewport = require("./map/viewport")

export type CoordinatesBounds = Coordinates.Bounds
export type CoordinatesWorldPoint = Coordinates.WorldPoint
export type CoordinatesNormalizedPoint = Coordinates.NormalizedPoint
export type ExplorationRecord<K> = Exploration.Record<K>
export type ExplorationCatalogValue<K> = Exploration.CatalogValue<K>
export type ExplorationExploredState = Exploration.ExploredState
export type ExplorationIdentity = Exploration.Identity
export type ExplorationWorldPoint = Exploration.WorldPoint
export type ExplorationPoi = Exploration.Poi
export type ExplorationObservation = Exploration.Observation
export type ExplorationRevealResult = Exploration.RevealResult
export type ExplorationPresentation<K> = Exploration.Presentation<K>
export type ExplorationTransition<K> = Exploration.Transition<K>
export type ExplorationSystem<K> = Exploration.System<K>
export type GeometryPanOffset = Geometry.PanOffset
export type GeometryMarkerProjection = Geometry.MarkerProjection
export type PolylinePixelPoint = Polyline.PixelPoint
export type RendererPreferredInput = Renderer.PreferredInput
export type RendererSurface = Renderer.Surface
export type RendererInput<K> = Renderer.Input<K>
export type RendererResult = Renderer.Result
export type UpdatesNormalizedPoint = Updates.NormalizedPoint
export type UpdatesSample = Updates.Sample
export type UpdatesState = Updates.State
export type UpdatesPanUpdate = Updates.PanUpdate
export type UpdatesMarkerUpdate = Updates.MarkerUpdate
export type UpdatesOutput = Updates.Output
export type UpdatesResult = Updates.Result
export type ViewportNormalizedPoint = Viewport.NormalizedPoint
export type ViewportMarkerRow = Viewport.MarkerRow
export type ViewportTrackedWaypoint = Viewport.TrackedWaypoint
export type ViewportInput = Viewport.Input
export type ViewportPoiMarker = Viewport.PoiMarker
export type ViewportViewport = Viewport.Viewport

export type API = {
	read coordinates: typeof(Coordinates),
	read exploration: typeof(Exploration),
	read geometry: typeof(Geometry),
	read polyline: typeof(Polyline),
	read renderer: typeof(Renderer),
	read updates: typeof(Updates),
	read viewport: typeof(Viewport),
}

local api: API = {
	coordinates = Coordinates,
	exploration = Exploration,
	geometry = Geometry,
	polyline = Polyline,
	renderer = Renderer,
	updates = Updates,
	viewport = Viewport,
}

return table.freeze(api)
