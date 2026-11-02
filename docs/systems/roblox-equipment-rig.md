# equipment-rig

[System catalog](../systems.md) · [Play](../../README.md)

Scope construction attempts, join meshes and settle equipment slots.

## State shape

`Ownership<O,C>` supplies lifetime/checkpoints; `MeshCache` and `BatchState` track bounded work and per-slot settlement.

Types and configuration are exported from [src/roblox/equipment-rig.luau](../../src/roblox/equipment-rig.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [equipment-rig](../../src/roblox/equipment-rig.luau) | `afterExternal`, `applyBatch`, `assertCurrent`, `attempt`, `disposeLoose`, `isInFlight`, `isRefused`, `lifetime`, `meshCache`, `refuse`, `refusedCount`, `reset`, `resolve`, `withOwner` | `Ownership`, `MeshCache`, `Failure`, `BatchState`, `BatchHost` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject ownership run/create/dispose/checkpoint/rollback, native mesh/adopt operations, recipes, fitting and reporting.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/equipment-rig.verify.luau --name "rolls back refused and throwing attempts without disposing the surrounding owner"
```

The [executable specification](../../src/roblox/equipment-rig.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: rolls back refused and throwing attempts without disposing the surrounding owner.

## Invariants

Refused or throwing attempts roll back. Stale external results are disposed. Slot settlement does not dispose the surrounding owner.
