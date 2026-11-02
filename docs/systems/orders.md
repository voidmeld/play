# orders

[System catalog](../systems.md) · [Play](../../README.md)

Advance work orders and realm patron payouts with durable claims.

## State shape

Work `State` holds orders, steps, phases and claims. Patron `State` holds order progress, calendar carry and payout history.

Types and configuration are exported from [src/core/orders.luau](../../src/core/orders.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [patron](../../src/core/orders/patron.luau) | `allowance`, `catalog`, `emptyState`, `patron`, `projectState`, `turnIn`, `weekOf` | `Order`, `Catalog`, `State`, `Result`, `Config` |
| [work](../../src/core/orders/work.luau) | `emptyState`, `projectOrder`, `projectState`, `step` | `Phase`, `WorkOrderStep`, `WorkOrder`, `State`, `CommandKind`, `Command`, `Result` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply catalog, payout/cap/calendar policy, command identity, clocks and reward settlement. The host persists accepted state with rewards.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/orders/patron.verify.luau --name "accepts the authored catalog and refuses a payout above the weekly cap or a duplicate id"
```

The [executable specification](../../src/core/orders/patron.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: accepts the authored catalog and refuses a payout above the weekly cap or a duplicate id.

## Invariants

Malformed definitions refuse. Progress follows declared steps. Claims replay without a second payout and respect configured caps.
