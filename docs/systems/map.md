# map

[System catalog](../systems.md) · [Play](../../README.md)

Track discoveries and project normalized world markers into a viewport.

## State shape

`ExploredState` stores discoveries by identity; bounds and points define coordinate conversion. Update `State` records sample/revision cadence; `Viewport` contains projected markers.

Types and configuration are exported from [src/core/map.luau](../../src/core/map.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [coordinates](../../src/core/map/coordinates.luau) | `mapToWorld`, `worldToMap` | `Bounds`, `WorldPoint`, `NormalizedPoint` |
| [exploration](../../src/core/map/exploration.luau) | `new` | `Record`, `CatalogValue`, `ExploredState`, `Identity`, `WorldPoint`, `Poi`, `Observation`, `RevealResult`, `Presentation`, `Transition`, `System` |
| [geometry](../../src/core/map/geometry.luau) | `imagePan`, `projectMarker`, `projectTrackedWaypoint` | `PanOffset`, `MarkerProjection` |
| [polyline](../../src/core/map/polyline.luau) | `simplifyPolyline`, `smoothPolyline` | `PixelPoint` |
| [renderer](../../src/core/map/renderer.luau) | `compose`, `new` | `PreferredInput`, `Surface`, `Input`, `Result` |
| [updates](../../src/core/map/updates.luau) | `emptyState`, `new`, `transition` | `NormalizedPoint`, `Sample`, `State`, `PanUpdate`, `MarkerUpdate`, `Output`, `Result` |
| [viewport](../../src/core/map/viewport.luau) | `build` | `NormalizedPoint`, `MarkerRow`, `TrackedWaypoint`, `Input`, `PoiMarker`, `Viewport` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply catalog normalization, marker-kind decoding, reveal radius, surface policy, observed position/time and marker revisions. The game renders native UI.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/map/exploration.verify.luau --name "reveals the configured boundary once without mutating prior state or another zone"
```

The [executable specification](../../src/core/map/exploration.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: reveals the configured boundary once without mutating prior state or another zone.

## Invariants

A discovery presents once. Zones do not share mutable discoveries. Coordinates clamp to valid bounds; only tracked waypoints clamp to the viewport edge.
