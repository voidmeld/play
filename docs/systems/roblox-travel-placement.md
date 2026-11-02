# travel-placement

[System catalog](../systems.md) · [Play](../../README.md)

Find clear, grounded arrival/entrance positions through injected geometry.

## State shape

`PlacementHost`/`EntranceHost` describe candidates and floor evidence; operations return a frame or nil.

Types and configuration are exported from [src/roblox/travel-placement.luau](../../src/roblox/travel-placement.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [travel-placement](../../src/roblox/travel-placement.luau) | `entrance`, `place` | `PlacementHost`, `EntranceHost` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject candidate/point generation, collision clearance, ground/near/far floor queries, safe checks and commit/frame construction.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/travel-placement.verify.luau --name "occupied arrival selects the first clear supported floor before committing"
```

The [executable specification](../../src/roblox/travel-placement.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: occupied arrival selects the first clear supported floor before committing.

## Invariants

Placement commits only a clear supported candidate. Search is bounded. An unsafe or absent floor cannot produce a destination.
