# Character leases and retirement

[Identity system](identity.md) · [System catalog](../systems.md)

Keep one character session authoritative across renewal, takeover, departure/arrival and deletion recovery.
Import [core/identity](../../src/core/identity.luau); it exports the component APIs and their types.

## State shape

`CharacterLeaseRecord` contains `schemaVersion`, `revision`, `characterId`, optional `zoneId`,
optional `sessionId`/`acquisitionId`, `expiresAt`, and explicit `retirement`/`arrival` slots.
Each slot is either `false` or its typed receipt. A retirement receipt identifies operation,
fingerprint, fence and time; an arrival receipt identifies session, acquisition, fence and time.
An unowned row has both owner fields absent and zero expiry. Returned rows are detached mutable
values, allowing the game's atomic transform to compose them without changing its input.

## Operations

| Component | Operations |
| --- | --- |
| [character_lease](../../src/core/identity/character-lease.luau) | `create(config)` returns record `create`, `copy`, `equal`, witness/claim decoders, `retire`, `restore`, `arrive`, `retired`, and receipt readers. |
| [character_lease_store](../../src/core/identity/character-lease-store.luau) | `create(config)` returns atomic `acquire`, `renew`, `release`, `retire`, `restore`, and `arrive`. |
| [retirement](../../src/core/identity/retirement.luau) | `create(config)` returns `view` and `decide`: retire, restore, settled, orphan or invalid. |

The [generated reference](../api.md) contains every configuration field and result type.

## Required host operations

Supply the saved schema, numeric/string bounds and a pure `migrate(unknown) -> unknown` projector.
The projector must leave its input unchanged; its result still passes the full record validator.
An identity projector deliberately refuses older schemas. Migration rules and their rollout belong to the game.
Factories snapshot scalar configuration; retirement also copies its phase maps. Phase sets must be disjoint.

Supply an atomic `store.updateOutcome(key, transform)` returning `{ ok, value, reason }` and a
character-key builder. A nil transform result must cancel with `callback_cancelled`; successful
updates must return the final committed readback. Transforms may retry. Transport failures must
retain their actual reason, including when a callback found a replay or proposed a committed value.
The [store host](persistence.md) implements this port, including a fake memory backend.

Pass authoritative timestamps, TTL and session-liveness observations. Optional live-session callbacks
control early takeover and retention of a lapsed lease. Without an early-liveness callback, an
unexpired foreign session holds its lease. Use the same identity/zone limits in the store and record policy.
The game owns the namespace, leases' durable ordering, caller authentication, session scheduling,
deletion phase maps and notices. These modules never discover services or write storage themselves.

## Runnable example

```sh
lute run tools/examples/character-leases.luau
```

The [complete example](../../tools/examples/character-leases.luau) uses a distinct schema and small
bounds, then drives the real store coordinator through the [test-scene fake host](../../src/test-scene/character-leases.luau).
It acquires, retires, drains the old owner, restores and consumes an arrival receipt once.

```sh
lute run tools/gate.luau --file src/core/identity/character-lease.verify.luau --file src/core/identity/retirement.verify.luau
```

## Invariants

- Renewal and release require exact character, session, acquisition and revision. Expiry is an exact boundary.
- Arrival requires the acquired revision to exceed its departure fence; another holder cannot reuse a consumed departure.
- Only the retirement operation with the matching fingerprint and an adequate fence can restore its tombstone.
- Retired characters cannot acquire or arrive, while their existing owner can drain and release.
- Replay preserves receipts. Callback retries clear provisional results. Missing, forged or failed readback does not become success.
- Saved rows require both receipt slots. Schema, limits and planner phase admission come from caller policy.

See the [adoption comparison and cutover](../adoption.md) for the current game's removable implementations.
