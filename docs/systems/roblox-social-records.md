# social-records

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate ordered durable records, ledgers, inboxes and indexes.

## State shape

Typed store outcomes feed fellowship/formation/warband ports, settled ledgers, keyed records and bounded indexes.

Types and configuration are exported from [src/roblox/social-records.luau](../../src/roblox/social-records.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [social-records](../../src/roblox/social-records.luau) | `add`, `apply`, `create`, `deliver`, `getOutcome`, `inbox`, `index`, `keyed`, `ledger`, `list`, `markRead`, `read`, `remove`, `updateOutcome` | `Outcome`, `Store`, `FellowshipPort`, `FormationPort`, `WarbandPort`, `Dependencies`, `Refusal`, `RecordResult`, `Result`, `FormationResult`, `Status`, `ProposerResult`, `Membership`, `MembershipResult`, `WarbandMembership`, `WarbandMembershipResult`, `LedgerOutcome`, `Settled`, `LedgerCore`, `LedgerDependencies`, `Ledger`, `InboxCore`, `InboxDependencies`, `InboxResult`, `Inbox`, `UncachedStore`, `KeyedOutcome`, `KeyedDependencies`, `Keyed`, `IndexDependencies`, `IndexListing`, `Index`, `Service` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject compare-and-swap/update/read operations, record projectors, clocks, keys and bounds.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/social-records.verify.luau --name "refuses foreign guild and formation identities before applying events"
```

The [executable specification](../../src/roblox/social-records.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: refuses foreign guild and formation identities before applying events.

## Invariants

Foreign record identity refuses before applying events. Ordered updates preserve readback identity. Duplicate receipts do not settle twice.
