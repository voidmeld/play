# npc-motion

[System catalog](../systems.md) · [Play](../../README.md)

Project bounded planar movement and repair externally displaced bodies.

## State shape

`Point`/`Planar` describe geometry; `Projection` and `Changes` compare cached and observed transforms.

Types and configuration are exported from [src/roblox/npc-motion.luau](../../src/roblox/npc-motion.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [npc-motion](../../src/roblox/npc-motion.luau) | `anchoredSurfaceY`, `distance`, `groundedPivotY`, `insideLeash`, `moveToward`, `movement`, `plan`, `projection` | `Planar`, `Point`, `Observed`, `Projection`, `Changes` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply epsilon/timing tuning, observed position/facing, grounding and native pivot application.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/npc-motion.verify.luau --name "limits planar movement, preserves elevation and admits the leash edge"
```

The [executable specification](../../src/roblox/npc-motion.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: limits planar movement, preserves elevation and admits the leash edge.

## Invariants

Steps cannot overshoot. Elevation is preserved. Leash edges are inclusive and displaced bodies receive corrective projection.
