# character

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate death observations, recovery timers and cancellable body replacement.

## State shape

A `Host<P,C,O>` owns character generations and watches; `Observation<C>` carries current body/death observations.

Types and configuration are exported from [src/core/character.luau](../../src/core/character.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [respawn-host](../../src/core/character/respawn-host.luau) | `completeSpawn`, `create` | `Refresh`, `Observation`, `Dependencies`, `Host` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject ownership, observe/connect, schedule/cancel, current-session checks, spawn, body validation and destination restoration from `Dependencies`.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/character/respawn-host.verify.luau --name "uses authoritative death state after a previously live body disappears"
```

The [executable specification](../../src/core/character/respawn-host.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: uses authoritative death state after a previously live body disappears.

## Invariants

A body change revokes old waits. Spawn retries are bounded. Restoration requires a current session and valid new body.
