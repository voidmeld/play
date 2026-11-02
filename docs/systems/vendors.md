# vendors

[System catalog](../systems.md) · [Play](../../README.md)

Buy and sell against configured vendors, finite stock and owner-scoped buyback.

## State shape

`State` contains stock and buyback receipts; `Account` contains inventory/coin; operations return next vendor state, account and decision.

Types and configuration are exported from [src/core/vendors.luau](../../src/core/vendors.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [exchange](../../src/core/vendors/exchange.luau) | `buy`, `buyBack`, `buyStock`, `empty`, `sell`, `sellBack`, `validateVendor`, `vendor` | `Inventory`, `Account`, `Ware`, `Vendor`, `Decision`, `Receipt`, `State`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply item admission, prices, inventory arithmetic, capacity, bounds, vendor catalog and time. Persist state and account together; choose owner/vendor buyback keys.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/vendors/exchange.verify.luau --name "purchases and sales exchange coin and holdings without mutating inputs"
```

The [executable specification](../../src/core/vendors/exchange.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: purchases and sales exchange coin and holdings without mutating inputs.

## Invariants

A refusal returns both original inputs. Receipt IDs increase within state. Consumed buyback receipts cannot apply twice.
