--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Coordinates = require("./coordinates")
local Exploration = require("./exploration")
local Geometry = require("./geometry")
local Polyline = require("./polyline")
local Renderer = require("./renderer")
local Updates = require("./updates")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local Viewport = require("./viewport")

local function readKind(value: unknown): ("a" | "b")?
	return if value == "a" or value == "b" then value else nil
end
local System: Exploration.System<"a" | "b"> = Exploration.new({ readKind = readKind, revealRadius = 5 })
local function markers()
	return {
		{ zoneId = "one", poiId = "near", displayName = "Near", kind = "a", position = { u = 0.5, v = 0.5 } },
		{ zoneId = "one", poiId = "edge", displayName = "Edge", kind = "b", position = { u = 0.75, v = 0.5 } },
		{ zoneId = "two", poiId = "away", displayName = "Away", kind = "a", position = { u = 0.5, v = 0.5 } },
	}
end
local function pois()
	return {
		{ zoneId = "one", poiId = "near", position = { x = 0, z = 0 } },
		{ zoneId = "one", poiId = "edge", position = { x = 3, z = 4 } },
		{ zoneId = "two", poiId = "away", position = { x = 0, z = 0 } },
	}
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("map mechanisms", function()
		it("reveals the configured boundary once without mutating prior state or another zone", function()
			local before: Exploration.ExploredState = {}
			local observed = { zoneId = "one", position = { x = 0, z = 0 } }
			local result = assert(System.pipeline.transition(before, observed, pois(), markers()))
			expect(before):toEqual({})
			expect(result.state):toEqual({ one = { near = true, edge = true } })
			expect(#result.presentations):toBe(2)
			expect(result.presentations[2].kind):toBe("b")
			expect(table.isfrozen(result.state.one)):toBe(true)
			local again = assert(System.pipeline.transition(result.state, observed, pois(), markers()))
			expect(#again.presentations):toBe(0)
			expect(again.state):toEqual(result.state)
		end)
		it("refuses bad catalog kinds, duplicate identities and mismatched reveal rows", function()
			local rows = markers()
			rows[1].kind = "unknown"
			expect(System.catalog.normalize(rows)):toBeNil()
			rows = markers()
			rows[2].poiId = "near"
			expect(System.catalog.normalize(rows)):toBeNil()
			local revealRows = pois()
			revealRows[2].poiId = "near"
			expect(
				System.pipeline.transition({}, { zoneId = "one", position = { x = 0, z = 0 } }, revealRows, markers())
			):toBeNil()
		end)
		it("rejects unknown saved discoveries and merges only validated catalog identities", function()
			expect(System.state.normalize({ one = { unknown = true } }, markers())):toBeNil()
			local merged = assert(System.state.merge({ one = { near = true } }, { two = { away = true } }, markers()))
			expect(System.state.ordered(merged, markers())):toEqual({
				{ zoneId = "one", poiId = "near" },
				{ zoneId = "two", poiId = "away" },
			})
			expect(
				System.discovery.project(
					{ { zoneId = "one", poiId = "near" }, { zoneId = "one", poiId = "near" } },
					markers()
				)
			):toBeNil()
		end)
		it("refuses kind policies that rewrite authored identity or return a non-string kind", function()
			local renamed: Exploration.System<string> = Exploration.new({
				readKind = function(_value: unknown): string?
					return "renamed"
				end,
				revealRadius = 5,
			})
			expect(renamed.catalog.normalize(markers())):toBeNil()
			local invalid: Exploration.System<boolean> = Exploration.new({
				readKind = function(_value: unknown): boolean?
					return false
				end,
				revealRadius = 5,
			})
			expect(invalid.catalog.normalize(markers())):toBeNil()
		end)
		it("preserves the prior state and reason when observation distance overflows", function()
			local before: Exploration.ExploredState = {}
			local result =
				System.reveal.transition(before, { zoneId = "one", position = { x = 1e308, z = 1e308 } }, pois())
			expect(result.ok):toBe(false)
			expect(result.state):toBe(before)
			expect(result.reason):toBe("nonfinite_distance")
		end)
		it("round trips bounded coordinates and rejects degenerate or nonfinite inputs", function()
			local bounds = { minX = -20, maxX = 80, minZ = 10, maxZ = 210 }
			local map = assert(Coordinates.worldToMap(bounds, { x = 30, z = 60 }))
			expect(map):toEqual({ u = 0.5, v = 0.25 })
			expect(Coordinates.mapToWorld(bounds, map)):toEqual({ x = 30, z = 60 })
			expect(Coordinates.worldToMap(bounds, { x = 1000, z = -1000 })):toEqual({ u = 1, v = 0 })
			expect(Coordinates.mapToWorld({ minX = 0, maxX = 0, minZ = 0, maxZ = 10 }, { u = 0, v = 0 })):toBeNil()
			expect(Coordinates.worldToMap(bounds, { x = math.nan, z = 0 })):toBeNil()
		end)
		it("filters hidden viewport markers and clamps only the tracked waypoint to the edge", function()
			local rows = {}
			for _, row in markers() do
				table.insert(rows, { zoneId = row.zoneId, poiId = row.poiId, position = row.position })
			end
			local view = assert(Viewport.build({
				zoneId = "one",
				exploredMap = { one = { near = true } },
				markerRows = rows,
				player = { u = 0.5, v = 0.5 },
				imageScale = 2,
				trackedWaypoint = { zoneId = "one", position = { u = 1, v = 0.5 } },
			}))
			expect(#view.poiMarkers):toBe(1)
			expect(assert(view.trackedWaypoint).edgeClamped):toBe(true)
			expect(assert(view.trackedWaypoint).x):toBe(1)
			expect(Geometry.projectMarker(0.5, 0.5, 1, 0.5, 2)):toEqual({
				x = 1.5,
				y = 0.5,
				withinWindow = false,
				edgeClamped = false,
			})
		end)
		it("throttles pan by caller frequency while updating changed markers and rejecting clock reversal", function()
			local update = Updates.new(4)
			local first =
				assert(update.transition({}, { atSeconds = 1, player = { u = 0.5, v = 0.5 }, markerRevision = 0 }))
			local early = assert(
				update.transition(first.state, { atSeconds = 1.1, player = { u = 0.6, v = 0.5 }, markerRevision = 1 })
			)
			expect(early.output.pan):toBeNil()
			expect(assert(early.output.markers).revision):toBe(1)
			local due = assert(
				update.transition(early.state, { atSeconds = 1.25, player = { u = 0.6, v = 0.5 }, markerRevision = 1 })
			)
			expect(assert(due.output.pan).atSeconds):toBe(1.25)
			expect(update.transition(due.state, { atSeconds = 1.2, player = { u = 0.5, v = 0.5 }, markerRevision = 1 })):toBeNil()
		end)
		it("keeps disabled surface state and composes enabled output from caller policy", function()
			local update = Updates.new(4)
			local function resolve(_preferred: unknown, enabled: unknown): Renderer.Surface?
				return {
					preferredInput = "pointer",
					enabled = enabled ~= false,
					diameterPx = 96,
					northLocked = true,
					rotates = false,
				}
			end
			local render =
				Renderer.new({ normalize = System.catalog.normalize, resolve = resolve, update = update.transition })
			local input: Renderer.Input<"a" | "b"> = {
				preferredInput = "pointer",
				explicitEnabled = false,
				previousUpdateState = {},
				sample = { atSeconds = 1, player = { u = 0.5, v = 0.5 }, markerRevision = 0 },
				zoneId = "one",
				markerRows = assert(System.catalog.normalize(markers())).records,
				exploredMap = { one = { near = true } },
				imageScale = 2,
			}
			local off = assert(render.compose(input))
			expect(off.updateState):toEqual({})
			expect(off.viewportUpdate):toBeNil()
			input.explicitEnabled = true
			local on = assert(render.compose(input))
			expect(on.surface.diameterPx):toBe(96)
			expect(#assert(on.viewportUpdate).poiMarkers):toBe(1)
			expect(input.previousUpdateState):toEqual({})
		end)
		it("simplifies within tolerance while preserving route endpoints and input geometry", function()
			local points = { { x = 0, y = 0 }, { x = 0.5, y = 0.01 }, { x = 1, y = 0 } }
			expect(Polyline.simplifyPolyline(points, 0.02)):toEqual({ points[1], points[3] })
			local smoothed = Polyline.smoothPolyline(points)
			expect(smoothed[1]):toEqual(points[1])
			expect(smoothed[#smoothed]):toEqual(points[3])
			expect(points[2]):toEqual({ x = 0.5, y = 0.01 })
		end)
	end)
end
