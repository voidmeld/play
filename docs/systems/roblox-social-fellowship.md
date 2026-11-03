# Fellowship host

[System catalog](../systems.md) · [Durable social records](roblox-social-records.md)

Compose durable guild records with membership custody, privacy admission, invitations and projections.
Import [roblox/social-fellowship](../../src/roblox/social-fellowship.luau) and configure the supplied
home/group policies, TTLs, refresh interval, identifiers and fallback labels. `create` takes dependencies,
a shared social host, member-name lookup, event-id source and notification callback.

## State shape

Durable fellowship and membership shapes come from `core/social/fellowship` and `roblox/social-records`.
The coordinator retains pending invitation routes and reconciled-user observations. Public view types
describe guild members, steward audit, pending invitations and home/creed projections. `BankMembership`
projects the member identities and role needed by a bank binding.

## Operations and host requirements

Operations cover direct founding, inviting/answering, member intents, bank membership, projections,
audiences, notices, steward observations, membership settlement and per-user cleanup.
Supply records, grouping-domain lookup, current clock, optional home catalog and fresh privacy relations.
Use the same group admission/visibility policy as the game and TTLs consistent with its configured
fellowship rules. The supplied social host owns actor exclusion, cache/custody and durable record commits.
Keep names, home/catalog data, identifier namespaces, platform observations and native notices in the game.
Use the separate formation coordinator when founding requires multiple consents or a profile fee.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-fellowship.verify.luau --name "fellowship host"
```

The [executable fixture](../../src/roblox/social-fellowship.verify.luau) composes real records,
membership custody, home and privacy rules with neutral identities. It covers domain admission,
durable seats, bank-role projection, privacy refusals, invitation expiry and configurable refresh cadence.

## Invariants

- Membership custody precedes durable founding or acceptance.
- Invitations require fresh privacy admission against the current members.
- Projections use the supplied visibility policy and authoritative member identities.
- Expired invitation routes cannot authorize acceptance.
- Steward observations respect the configured refresh interval.
- Forgetting a user releases coordinator caches and invitation routes.
