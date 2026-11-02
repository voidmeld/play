# bank

[System catalog](../systems.md) · [Play](../../README.md)

Move items between carried inventory and a vault with bounded receipt replay.

## State shape

`State = { items, receipts, receiptOrder }`; requests identify direction, item, count, banker and receipt.

Types and configuration are exported from [src/core/bank.luau](../../src/core/bank.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [vault](../../src/core/bank/vault.luau) | `adjust`, `apply`, `default`, `project`, `request`, `sameRequest`, `vault` | `Inventory`, `Request`, `State`, `Config`, `Vault` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply profile read/write, permanent-item admission, capacity/fit and transfer callbacks. Persist inventory and vault together.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/bank/vault.verify.luau --name "refuses permanent carried items without moving or duplicating them"
```

The [executable specification](../../src/core/bank/vault.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: refuses permanent carried items without moving or duplicating them.

## Invariants

A refused transfer moves nothing. Receipt replay cannot move an item twice. Permanent items remain carried.
