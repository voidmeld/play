# party

[System catalog](../systems.md) · [Play](../../README.md)

Apply immutable party membership through an atomic store.

## State shape

`PartyOutcome` and `MountResult` distinguish accepted/readback/refused results over configured membership state.

Types and configuration are exported from [src/roblox/party.luau](../../src/roblox/party.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [party](../../src/roblox/party.luau) | `mount`, `party` | `StoreOutcome`, `Store`, `Dependencies`, `PartyOutcome`, `Service`, `MountResult`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject update store, key builder, membership reader, exact schema and boundary text.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/party.verify.luau --name "retries pure transforms and refuses old schemas without rewriting them"
```

The [executable specification](../../src/roblox/party.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: retries pure transforms and refuses old schemas without rewriting them.

## Invariants

Retried transforms do not leak captured results. Foreign schema and mismatched readback refuse. Reads use cancelling transforms.
