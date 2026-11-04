# Leased quest durability host

[System catalog](../systems.md) · [Quest journals](quest.md) · [Character leases](identity.md)

Coordinate journal hydration, dirty admission, coalesced saves, lease renewal and close draining.
Import [roblox/quest-durability](../../src/roblox/quest-durability.luau), call `configure(config)`,
then `new(dependencies)`. Session snapshots remain generic; a typed projection exposes only existence,
revision and encoded quest progress to the coordinator.

## State shape

Each attached character holds its session/acquisition identity, current lease/session state, opaque
snapshot, committed/pending journal, dirty storage map, retry count, scheduling flags and phase.
Phases are active, stopping, release or fenced. Durable records remain owned by the supplied store ports.

## Operations and required host operations

`attach` acquires and hydrates before accepting writes. `markDirty` validates a journal or current draft;
`markDirtyBatch` prepares every subject before installing any dirty record. `flush` serializes a save,
retains work accepted during the operation and handles renewal/readback uncertainty. `overwriteRecord`
requires a validated full journal. `stopWrites`, `detach` and `drain` stop admission, flush and release.
`isAttached`, `canWrite` and `phase` expose bounded lifecycle observations.

Supply journal and lease rules, lease renewal/release operations, session acquire/save ports, snapshot
projection, clock, store/key functions and owned scheduling. Configure failure limits, lease duration,
renewal/retry cadence, default coalescing delay and fence-loss reasons. Session/store ports must report
settled outcomes and uncertainty; snapshot metadata must describe authoritative readback. Keep storage
codecs, current schema/migrations, namespaces, catalog, numeric/status policy and native lifetime in the game.

The actor accepting an attachment must own its gameplay authority. Ordered reconciliation and dirty
admission consume the authoritative reducer's records. Scheduling callbacks may outlive a detach;
the coordinator guards them against a replacement attachment. The host owns scheduled resource cleanup.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/quest-durability.verify.luau
```

The [fixture](../../src/roblox/quest-durability.verify.luau) uses actual Play lease and session rules,
a fake storage host, an alternate snapshot layout, short renewal intervals and a different failure limit.
It exercises draining, atomic batch admission, failure retention, stale callbacks, in-flight updates,
renewal and divergent reacquisition.
The same suite owns coalesced newest-journal saves, asymmetric batch retries, scheduler refusal,
admission retry, exact-holder adoption, long-lived renewal, transient and persistent renewal refusal,
and retryable save/release draining. Adopters retain their configured cadence and failure policy,
status/event encoding, storage namespace and actual yielding session/store integration checks.
The fake session ports do not certify native storage durability or an adopter's record compare-and-swap.

## Invariants

- Identity and current lease ownership fence every save.
- An attachment accepts dirty work only while active and writable.
- Reacquisition refuses a changed snapshot rather than overwriting a newer record.
- A failed save retains dirty work; repeated failures stop further admission while allowing drain.
- Batch preparation cannot partially install dirty records.
- Updates accepted during a save remain pending for a later flush.
- Closing releases only after pending work drains; failed release remains retryable.
- Old callbacks cannot advance a replacement attachment, and metatable payloads are refused.
