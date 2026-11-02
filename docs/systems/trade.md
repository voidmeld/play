# trade

[System catalog](../systems.md) · [Play](../../README.md)

Settle mutually confirmed, revisioned offers and retain recovery receipts.

## State shape

`State` holds offers, revision, locks, confirmations and settlement phase. Receipt records/wire maps/pointers retain exact grant identity.

Types and configuration are exported from [src/core/trade.luau](../../src/core/trade.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [exchange](../../src/core/trade/exchange.luau) | `empty`, `exchange`, `offer`, `settled`, `step` | `Stack`, `Offer`, `Phase`, `State`, `Config` |
| [receipt](../../src/core/trade/receipt.luau) | `pointers`, `project`, `receipts`, `wire` | `Record`, `Projected`, `Wire`, `Pointer`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply item/count/coin/user/revision bounds, receipt policy and authoritative identities. The game handles proximity/admission and atomically persists both accounts.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/trade/exchange.verify.luau --name "resets both locks and confirmations whenever an offer changes"
```

The [executable specification](../../src/core/trade/exchange.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: resets both locks and confirmations whenever an offer changes.

## Invariants

Offer edits clear both parties' locks and confirmations. Stale revisions refuse. Settlement and grant receipts prevent duplicate application.
