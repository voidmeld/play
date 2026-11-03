# Bank host

[System catalog](../systems.md) · [Vault rules](bank.md)

Admit authenticated personal-bank transfers and commit them with a durable profile receipt.
Import [roblox/bank](../../src/roblox/bank.luau), call `configure(config)`, then `create(dependencies)`.

## State shape

`Result` reports acceptance, durability uncertainty, refusal and the read-back vault state.
`Location` and `Banker` describe place identity, finite position and banker availability.
The host stores only per-subject exclusion and rate windows. Vault items/receipts stay in the profile.

## Operations and host requirements

`intent` decodes a configured vault request, verifies the active subject, context, banker proximity
and item policy, then commits the transfer. `forget` releases rate state. `reachable` exposes the same
place/distance admission used by the coordinator.

Configure vault operations, profile read/commit, vault projection, transaction namespace and numeric
limits. The commit must atomically record its transaction with the effect, replay without applying
twice and return actual durability. Dependencies provide the authoritative subject/context/profile,
positions, banker lookup, item authorization, optional identity decoding and elapsed-time clock.
Keep catalogs, banker placement, profile shape, item-binding policy and remote lifetime in the game.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/bank.verify.luau
```

The [executable fixture](../../src/roblox/bank.verify.luau) binds real vault rules and idempotent
profile commits. It checks receipt replay, forged subjects, distance, item admission, uncertain
saves and rate-state release.

## Invariants

- A subject must be the current authenticated instance for its identity.
- Bankers must be enabled and reachable in the same place.
- Item authorization is checked before admission and again inside the profile effect.
- A transfer is successful only after durable commit and receipt readback.
- Lost durability remains pending; replay cannot duplicate the transfer.
