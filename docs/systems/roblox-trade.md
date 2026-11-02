# Trade host

[System catalog](../systems.md) · [Trade transitions](trade.md)

Coordinate a durable, revisioned two-profile exchange over injected profile and receipt stores.
Import [roblox/trade](../../src/roblox/trade.luau), call `configure(config)`, then `create(dependencies)`.

## State shape

`Account` projects coin, inventory and pending receipt pointers from the game's profile.
`State` extends the pure exchange state with captured character and session identities.
Durable receipts contain both offers, characters, the reviewed revision, decision and grant markers.
The game retains its profile schema, storage namespaces, migration and item policy.

## Operations and host requirements

`intent` admits an authenticated subject's open, offer, lock, confirm or cancel request.
`recover` reconciles a durable decision; `admit` recovers pointers for an arriving character.
`playerRemoving` cancels an active exchange; `sweepExpired` cancels expired offers.
`state` and `stateFor` expose the current exchange view.

Supply pure exchange and receipt codecs, account projection, capacity and unbound-item rules,
profile lookup, related-profile policy and transaction receipt admission. Supply a profile commit
operation which atomically records a transaction with its effect and returns the actual durability
outcome. Repeated transaction identifiers must replay without applying their effect again.

The receipt store's update callback may retry. It must return its committed value, or an uncertain
failure which the coordinator can reconcile by reading. `profileFor` must resolve an active exact
session. Context identities, authenticated subject identity, positions, authorization, identifiers,
clock and optional expiry scheduling come from the host. Positions require finite x, y and z.
Use a clock whose timestamps remain comparable after restart; receipt codecs must admit its range.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/trade.verify.luau
```

The [executable fixture](../../src/roblox/trade.verify.luau) uses two neutral profile accounts,
an idempotent commit port and a receipt map. It tests conservation, repeated recovery, failed grants,
uncertain receipt writes, unreadable decisions, replacement sessions and expiry.

## Invariants

- Consent applies only to the reviewed offer revision and captured sessions.
- Both holds precede a committed decision; a cancelled decision refunds recorded holds once.
- A committed decision remains recoverable until both grants and pointer cleanup settle.
- Unreadable or malformed decisions never authorize moving either account.
- Profile transaction replay cannot duplicate holds, grants or refunds.
- Game policy, profile projection and native remote lifetime remain outside the coordinator.
