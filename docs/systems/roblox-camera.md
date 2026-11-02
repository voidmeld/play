# camera

[System catalog](../systems.md) · [Play](../../README.md)

Project configured follow-camera dynamics and obstruction response.

## State shape

`Spring` holds position/velocity; `Obstruction` holds smoothing state.

Types and configuration are exported from [src/roblox/camera.luau](../../src/roblox/camera.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [camera](../../src/roblox/camera.luau) | `create`, `fovTarget`, `isCameraStructure`, `newSpring`, `obstructedDistance`, `shoulderOffset`, `smoothObstruction`, `springStep`, `sprintWiden`, `yields`, `zoomLimits` | `Spring`, `Obstruction`, `Tuning` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply tuning, collision observations and elapsed time; apply transforms in the game.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/camera.verify.luau --name "settles without overshoot and is stable across frame rates"
```

The [executable specification](../../src/roblox/camera.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: settles without overshoot and is stable across frame rates.

## Invariants

Spring motion stays stable across frame rates. Obstruction pulls inward immediately and eases outward.
