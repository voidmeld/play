# identity

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate rosters, names, account snapshots, creation, deletion and fenced leases.

[Character leases and retirement](character-leases.md) covers the character store, arrival receipts,
retirement planner and a standalone fake-host example. The [adoption guide](../adoption.md) identifies
the displaced game implementations and their remaining policy/host bindings.
Account and character leases share the [kernel lease rules](../kernel/lease.md); their stored schemas
and domain fences remain in their record codecs.

## State shape

`Roster` holds stable character identities. Account snapshots hold profiles and receipts. Creation/deletion `State` records phase, revision and fence; leases record owner and expiry.

Types and configuration are exported from [src/core/identity.luau](../../src/core/identity.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [account-lease](../../src/core/identity/account-lease.luau) | `MAX_FENCE`, `MAX_ID_BYTES`, `MAX_REVISION`, `MAX_SAFE_INTEGER`, `SCHEMA_VERSION`, `acquire`, `copy`, `empty`, `equal`, `release`, `renew`, `validate` | `Lease` |
| [account](../../src/core/identity/account.luau) | `characterCard`, `clearDeletionTerminal`, `clearTerminal`, `copy`, `create`, `empty`, `equal`, `equalStored`, `markCharacterDeparted`, `markCharacterLevel`, `markCharacterPlayed`, `receiptFor`, `removeCharacter`, `transition`, `transitionDeletion`, `validate`, `validateStored` | `DeletionState`, `Base`, `CreationReceipt`, `Account`, `Extension` |
| [character-lease](../../src/core/identity/character-lease.luau) | `create`, `copy`, `equal`, `witness`, `claim`, `retire`, `restore`, `arrive`, receipt readers | `Config`, `API`, `Record`, `Retirement`, `Arrival`, `Witness`, `Claim` |
| [character-lease-store](../../src/core/identity/character-lease-store.luau) | `create`, `acquire`, `renew`, `release`, `retire`, `restore`, `arrive` | `Config`, `API`, `Store`, `StoreOutcome`, `Outcome`, `Accepted`, `Refused` |
| [creation-record](../../src/core/identity/creation-record.luau) | `copy`, `copyReceipt`, `create`, `fromTransaction`, `matchesTransaction`, `receiptFromTransaction`, `receiptMatchesSeed`, `seedMatchesReceipt`, `validate`, `validateReceipt`, `validateStored` | `Seed`, `Receipt` |
| [creation](../../src/core/identity/creation.luau) | `copy`, `create`, `fingerprint`, `observeLeaseRelease`, `observeName`, `observeProfile`, `observeRollback`, `observeRoster`, `plan`, `prepare`, `requestRollback`, `takeover`, `validate`, `validateStored` | `Completion`, `Receipt`, `Phase`, `State`, `Prepared`, `Rejected`, `Accepted`, `Result`, `Plan` |
| [deletion](../../src/core/identity/deletion.luau) | `copy`, `create`, `fingerprint`, `observeLeaseRelease`, `observeNameRelease`, `observeRollback`, `observeRoster`, `plan`, `prepare`, `requestRollback`, `takeover`, `validate` | `Phase`, `State`, `Prepared`, `Rejected`, `Accepted`, `Result`, `Plan` |
| [name-claims](../../src/core/identity/name-claims.luau) | `availability`, `claim`, `create`, `release`, `validate` | `Claim`, `ClaimStatus`, `ReleaseStatus`, `Availability` |
| [name-record](../../src/core/identity/name-record.luau) | `availability`, `claim`, `copy`, `create`, `empty`, `equal`, `release`, `validate` | `Record`, `Claim` |
| [policy](../../src/core/identity/policy.luau) |  | `Policy` |
| [retirement](../../src/core/identity/retirement.luau) | `create`, `view`, `decide` | `Config`, `API`, `View`, `Decision`, `Deletion`, `Retirement` |
| [roster](../../src/core/identity/roster.luau) | `add`, `create`, `markDeparted`, `markLevel`, `markPlayed`, `realmCards`, `remove`, `removeStored`, `validate`, `validateStored` | `CharacterIdentity`, `Roster` |
| [routing](../../src/core/identity/routing.luau) | `create`, `projectPolicy`, `decide`, `refuse`, `accept`, `boundPlaceIds` | `Config`, `API`, `Policy`, `Binding`, `PlaceBinding`, `Budget`, `Handoff`, `DestinationProjection`, `RefusalRow`, `Session`, `Character`, `Request`, `Route`, `Refusal`, `Decision`, `Arrival` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply `policy.Policy`, pure extension projectors and identity/key/destination validation. Apply transaction plans through ordered durable operations and return actual readbacks.

[Route admission](route-admission.md) covers configured destination bindings, request/held-session
fencing, attempt/deadline budgets and arrival source checks. It has no native service dependency.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/identity/account-lease.verify.luau --name "acquires one fenced account lease and permits exact-expiry takeover"
```

The [executable specification](../../src/core/identity/account-lease.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: acquires one fenced account lease and permits exact-expiry takeover.

## Invariants

Foreign names survive stale release. Fences reject old owners. Missing or conflicting readbacks do not advance a transaction. Extensions survive detached transitions.
