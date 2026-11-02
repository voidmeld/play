# inventory

[System catalog](../systems.md) · [Play](../../README.md)

Manage stack capacity and replay-safe cargo custody, drops, recovery and delivery.

## State shape

`Inventory` maps item IDs to counts; `Holdings` adds equipment/bank views. Cargo `State` contains claims, drops, extraction and delivery history.

Types and configuration are exported from [src/core/inventory.luau](../../src/core/inventory.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [cargo](../../src/core/inventory/cargo.luau) | `carriedOf`, `census`, `create`, `emptyState`, `openDrops`, `projectState`, `retireTransient`, `step` | `Status`, `Cause`, `Claim`, `Drop`, `Total`, `Extraction`, `State`, `Intent`, `CommandKind`, `Command`, `Result`, `CensusRow`, `Config` |
| [stacks](../../src/core/inventory/stacks.luau) | `addToBag`, `capacity`, `copyBag`, `entries`, `fits`, `hasItem`, `isValidCount`, `normalizeBindings`, `permanent`, `removeFromBag`, `stacks`, `unboundCount` | `Inventory`, `Holdings`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply stack/capacity/permanent-item policy and cargo identity, quantity, timestamp and ledger bounds. The game persists inventory and settles emitted credit.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/inventory/cargo.verify.luau --name "hands off a dropped claim once and deposits it with replay-safe credit"
```

The [executable specification](../../src/core/inventory/cargo.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: hands off a dropped claim once and deposits it with replay-safe credit.

## Invariants

Capacity and stack limits hold. Bound/worn/permanent rules are explicit. A claim has one custodian and cannot be deposited twice.
