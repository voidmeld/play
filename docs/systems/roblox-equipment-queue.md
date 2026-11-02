# equipment-queue

[System catalog](../systems.md) · [Play](../../README.md)

Serialize equipment application per owner across yielding work.

## State shape

`Queue<P,C>` retains latest pending body and per-owner generation.

Types and configuration are exported from [src/roblox/equipment-queue.luau](../../src/roblox/equipment-queue.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [equipment-queue](../../src/roblox/equipment-queue.luau) | `create`, `dispose`, `forget`, `generation`, `invalidate`, `request`, `running` | `Deps`, `Queue` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject spawn, active/current body reads, perform and warn operations.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/equipment-queue.verify.luau --name "returns before stalled gear resolves and fences a stale request"
```

The [executable specification](../../src/roblox/equipment-queue.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: returns before stalled gear resolves and fences a stale request.

## Invariants

Pending requests coalesce. Generations fence stale completion. Invalidate/forget/dispose revoke owned work.
