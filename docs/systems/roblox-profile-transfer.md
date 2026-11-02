# profile-transfer

[System catalog](../systems.md) · [Play](../../README.md)

Read and settle profiles under exact session identity and per-key exclusion.

## State shape

`Identity` includes all lease fields; `Outcome`/`Result` and `Reader` preserve observed authority.

Types and configuration are exported from [src/roblox/profile-transfer.luau](../../src/roblox/profile-transfer.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [profile-transfer](../../src/roblox/profile-transfer.luau) | `exclusive`, `profileFor`, `sameSession`, `settle` | `Identity`, `Outcome`, `Result`, `Reader` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject current identity/profile observations, settled writes and keyed exclusion.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/profile-transfer.verify.luau --name "matches a session only when every lease field agrees"
```

The [executable specification](../../src/roblox/profile-transfer.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: matches a session only when every lease field agrees.

## Invariants

Every identity field must agree. A stale session cannot settle a newer profile. Conflicting per-key work remains excluded.
