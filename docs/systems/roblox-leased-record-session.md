# Leased record sessions

[System catalog](../systems.md) · [Persistence](persistence.md) · [Character leases](identity.md)

Coordinate durable lease acquisition, record hydration, takeover fencing and payload saves over opaque
record schemas. Import [roblox/leased-record-session](../../src/roblox/leased-record-session.luau) and
call `configure(config)`. It composes the configured lease store, profile-session rules and record store.

## State shape

`Accepted<R>` contains the acquired lease, mutable profile-session state and authoritative
`record-store.Accepted<R>` snapshot. Saved outcomes carry the renewed lease even when a later stage
fails. The opaque record `R` remains owned by the adopter; projections expose only the subject identity
and payload replacement needed by the save coordinator.

## Operations and required host operations

`acquireAndHydrate` takes dependency ports and zone/subject/session/acquisition identities. It acquires
the lease, fences the previous owner's record partition, reads the requested record and opens a session
from the persisted expiry. On failure it attempts release and reports release uncertainty separately.
An old lease without a known partition requires the host's complete partition family before takeover.

`savePayload` marks the configured dirty reason, begins a save, renews the lease, checks the captured
snapshot and game-provided payload replacement, then runs record compare-and-swap and completes the
session. Supply a monotonic clock and store read/atomic-update operations. These may yield; the stored
expiry and session completion rules fence late replies. Backend transforms must be side-effect free.

Keep storage scope, schemas/migrations, payload policy, subject projection, duration and dirty-reason
selection in the adopter. The record codec and replacement must return detached valid data, preserve
unmodified fields and perform no I/O. Native scheduling and gameplay authority are host responsibilities.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/leased-record-session.verify.luau
```

The [fixture](../../src/roblox/leased-record-session.verify.luau) uses an alternate record shape,
numeric payload, four-revision ceiling, schema-seven lease, twenty-unit expiry and fake store/clock.
It includes final callback retry conflicts, uncertain readbacks, hydration failure, takeover fencing,
lease-length reply delays at renewal and storage, and game payload refusal.

## Invariants

- A failed read is never interpreted as an absent record.
- Compare-and-swap checks the full captured record on every callback invocation.
- A successful store result must contain the exact desired committed record.
- Takeover fences the prior partition before accepting a new session.
- Hydration failure releases the acquired lease or reports why release is uncertain.
- Save failure retains dirty state and reports the renewed lease when one was persisted.
- Lease expiry fences completions even after a successful backend write.
- Payload replacement preserves opaque record fields and leaves the captured snapshot unchanged.
