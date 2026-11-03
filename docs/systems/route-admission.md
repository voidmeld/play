# Route admission

[Identity](identity.md) · [System catalog](../systems.md) · [API reference](../api.md)

Validate route policy, decide outgoing handoffs and admit destination arrivals using pure rules.
Import [identity/routing](../../src/core/identity/routing.luau) or `Identity.routing`, then call `create`.
The game supplies realm labels, identifier validators, text limits and fallback refusal policy.

## State shape

`Policy` is a frozen projection of a channel/universe/source binding, destination/place index,
attempt/time budgets, handoff freshness and refusal rows. `Request` contains character identity,
request and currently held session/acquisition/revision, selection/issue/current times, attempt
and an authoritative destination resolution. Decisions carry a route or a structured refusal.
`Arrival` carries the expected channel, universe/place and source/character/destination identities.

## Operations

`projectPolicy` validates and detaches game content into a frozen policy, rejecting duplicate
destinations/places, malformed refusal tables and explicitly unrouted channel bindings. `decide`
validates a request, enforces its binding, attempt budget, clock ordering, deadline and held-session
identity, then verifies its resolver result and bound destination. An absent resolution is classified
using known destination facts such as realm, level and unlock policy. `refuse` creates an approved
refusal, using the configured fallback when its reason or policy is invalid. `accept` checks the
arrival's channel/universe/source/place binding. `boundPlaceIds` projects the destination places.

## Required host operations

None are called by the rules. The host owns current time, held lease/session authority, selection,
destination resolution and actual teleport/recovery. A resolver result must come from the game's
authoritative admission path, including unlock and destination eligibility; client-supplied matching
fields are not proof of admission. Arrival checks establish a binding match, not authentication of a
native carrier or ownership of a character. The game must authenticate that carrier and acquire/fence
the destination lease before admitting a player. Never pass client data as the held-session authority.

Configuration includes pure structural/namespaced identifier validators, the realm-key-to-label map,
identity/refusal/unrouted text limits, unknown request label and invalid-binding refusal. The factory
copies its configuration and realm map. Keep actual destinations, place IDs, player-facing lines,
channel policy, budgets, clock and native lifetime in the game.

## Runnable example

```sh
lute run tools/gate.luau --file src/core/identity/routing.verify.luau
```

The [fixture](../../src/core/identity/routing.verify.luau) uses neutral realms, named synthetic place
identities, colon-separated destination IDs, smaller text limits and short budgets. It exercises frozen
projection, routing, exact deadlines, session fencing, refused resolutions, arrival binding and fallback text.

## Invariants

- Unrecognized or malformed policy fails closed with the configured invalid-binding refusal.
- Mutable content cannot alter the projected policy or the factory's realm map.
- A request's channel/universe/source and current held session must match its authority.
- Clock regression, exhausted attempts and late requests cannot produce routes.
- Resolver subject/destination facts must match the captured request and projected catalog.
- Arrival place and source bindings must match the projected policy.
- The pure rules perform no storage, scheduling, discovery or native teleport operations.
