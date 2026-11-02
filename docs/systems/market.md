# market

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate listings, fills, fees, wallet holds and economic conservation.

## State shape

Book `State` contains listings, operations and receipts. Wallet `State` retains pending holds/claims. Conservation `Totals` and `Audit` compare both sides.

Types and configuration are exported from [src/core/market.luau](../../src/core/market.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [book](../../src/core/market/book.luau) | `apply`, `book`, `emptyState`, `knowsOperation`, `projectState`, `receiptsFor`, `search` | `Listing`, `ReceiptKind`, `Receipt`, `Operation`, `State`, `Result`, `Command`, `Search`, `Config` |
| [conservation](../../src/core/market/conservation.luau) | `audit`, `conservation`, `measure` | `Totals`, `Audit`, `Config` |
| [goods](../../src/core/market/goods.luau) | `bookFor`, `bookIds`, `catalog`, `isCategoryBook`, `matches`, `tradeableCount` | `ItemFacts`, `Class`, `Config`, `Filters` |
| [wallet](../../src/core/market/wallet.luau) | `beginBuy`, `beginConsign`, `claim`, `compose`, `emptyLedger`, `emptyState`, `heal`, `ledgerOf`, `npcTrade`, `projectLedger`, `projectState`, `refund`, `settleConsign`, `wallet` | `Pending`, `State`, `Ledger`, `Result`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply book/fee/expiry rules, goods classification, account conversion, identifiers, clocks and durable coordination. The game provides realm admission and storage.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/market/book.verify.luau --name "lists into a 48-hour realm-local book at the default 5% burning cut"
```

The [executable specification](../../src/core/market/book.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: lists into a 48-hour realm-local book at the default 5% burning cut.

## Invariants

Goods and coin are conserved across holds and settlement except configured burns. Receipt replay is idempotent. Refused or uncertain work cannot silently grant value.
