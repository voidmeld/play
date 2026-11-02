# ledger

[System catalog](../systems.md) · [Play](../../README.md)

Record value events, reservations and grouped economic operations.

## State shape

`State` stores events and derived balances/reservations; `Journal` projects grouped history and torn groups.

Types and configuration are exported from [src/core/ledger.luau](../../src/core/ledger.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [ledger](../../src/core/ledger/ledger.luau) | `apply`, `available`, `balances`, `emptyState`, `ledger`, `projectEvent`, `projectState`, `tornGroups` | `EventKind`, `Event`, `State`, `ApplyResult`, `TornGroup`, `Config`, `Journal` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply earning/spending kinds, identity and quantity bounds, group policy and event timestamps. Durable event append belongs to the game.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/ledger/ledger.verify.luau --name "settles grants immediately and derives balances"
```

The [executable specification](../../src/core/ledger/ledger.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: settles grants immediately and derives balances.

## Invariants

Identical event replay does not regrant value. Conflicting identities refuse. Group accounting exposes incomplete settlement.
