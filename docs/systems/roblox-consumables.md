# consumables

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate durable item consumption before recovery dispatch.

## State shape

Pending uses retain receipt, character identity and interruption generation; `Status` reports progress/refusal.

Types and configuration are exported from [src/roblox/consumables.luau](../../src/roblox/consumables.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [consumables](../../src/roblox/consumables.luau) | `create`, `decodeUseRequest`, `enforce`, `forget`, `status`, `use` | `Actor`, `Snapshot`, `Status`, `CommitResult`, `Rules`, `Dependencies`, `Handle`, `UseRequest` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject snapshots, profile readiness, receipt reads, durable commits, begin/cancel commands and time.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/consumables.verify.luau --name "starts recovery only after durable consumption and rejects replayed input"
```

The [executable specification](../../src/roblox/consumables.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: starts recovery only after durable consumption and rejects replayed input.

## Invariants

No recovery starts before consumption commits. Uncertain writes retain identity. Character/movement/control admission is checked again after yielding.
