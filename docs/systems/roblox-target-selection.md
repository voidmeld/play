# target-selection

[System catalog](../systems.md) · [Play](../../README.md)

Cycle ordered candidates, select pointer hits and release distant targets.

## State shape

`Candidate<P>` carries stable identity/point; `Release` retains out-of-range timing.

Types and configuration are exported from [src/roblox/target-selection.luau](../../src/roblox/target-selection.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [target-selection](../../src/roblox/target-selection.luau) | `create`, `observe`, `pickNearestToTap`, `pickNext`, `release`, `reset`, `tapSelection` | `Candidate`, `Release` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply ordered candidates, coordinate reader, hit/radius observations, range and grace duration.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/target-selection.verify.luau --name "cycles, wraps and recovers from an absent selection"
```

The [executable specification](../../src/roblox/target-selection.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: cycles, wraps and recovers from an absent selection.

## Invariants

Exact hits win. Equal distances use lexical identities. In-range observations reset release timing; missing points count as outside.
