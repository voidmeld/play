# screen-labels

[System catalog](../systems.md) · [Play](../../README.md)

Admit anchored labels around reserved screen rectangles.

## State shape

`ScreenRect`, `ScreenPlate` and `ScreenPlacement` hold bounds, priority and admission/collapse results.

Types and configuration are exported from [src/roblox/screen-labels.luau](../../src/roblox/screen-labels.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [screen-labels](../../src/roblox/screen-labels.luau) | `contains`, `create`, `horizontalAvoidance`, `placementForScreen`, `rect`, `rectsOverlap` | `ScreenRect`, `ScreenPlate`, `ScreenPlacement` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply crowd/range/priority limits, projections, screen/topbar bounds and reserves; render labels in the game.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/screen-labels.verify.luau --name "hides conflicting labels without displacing their anchors"
```

The [executable specification](../../src/roblox/screen-labels.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: hides conflicting labels without displacing their anchors.

## Invariants

Conflicting labels collapse without moving anchors. Touching edges are clear. Placement stays within screen bounds.
