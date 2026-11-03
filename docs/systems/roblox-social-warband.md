# Warband social host

[System catalog](../systems.md) · [Warband rules](social.md)

Coordinate several intact parties through durable membership records, invitations, orders and rally requests.
Import [roblox/social-warband](../../src/roblox/social-warband.luau), configure the rule projections,
limits, request lifetime, rally location, identifiers and display fallback, then call `create(dependencies)`.

## State shape

Durable records own warband units, command, invitations, revisions and per-party membership claims.
The coordinator caches observed records and invitations plus short-lived requests for rally invitations.
Each party retains its own membership, leadership and loot state.

## Operations and host requirements

`act` handles founding, invitations, acceptance, departure, removal, command transfer, orders,
markers and rally requests. `project` reads a subject's current view; `refresh` reconciles cached bands.
Supply durable record operations, party membership/read ports, clock, names, contact permission and
objective validation. Reads and mutation replies must describe committed state; unavailable records
refuse admission. The game owns objective catalogs, location policy, storage namespaces and native notices.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-warband.verify.luau
```

The [fixture](../../src/roblox/social-warband.verify.luau) uses real party, warband and record rules with
three independent parties, a seven-second request lifetime and a neutral rally location.

## Invariants

- Only current party leaders mutate a warband.
- Claims precede durable enrollment; confirmation and release reconcile interrupted membership changes.
- Commands use the expected durable revision and current party snapshots.
- Parties retain their membership and loot authority.
- Repeated rally requests do not extend their original expiry or enroll a party.
- Contact and objective permissions govern discovery and invitation requests.
