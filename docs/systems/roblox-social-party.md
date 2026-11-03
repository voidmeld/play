# Social party host

[System catalog](../systems.md) · [Atomic party host](roblox-party.md)

Compose durable membership with invitation tracking, projections, reconnect/succession and rally admission.
Import [roblox/social-party](../../src/roblox/social-party.luau), call `configure(config)`, then
`create(dependencies, partyPort)`.

## State shape

The supplied party port owns durable member, invite, loot and leadership state.
This coordinator tracks projected memberships, pending invitation routes, rally selections and a
bounded refusal log. Exported view types describe candidates, members, invitations and leadership
transfer. Account ids are opaque strings; subject ids use the Roblox host's numeric identity seam.

## Operations and host requirements

Party commands cover invitations, acceptance/decline, leaving/removal, leadership transfer/disband,
disconnect/reconnect and expiry sweep. `partyProjection`, `candidateProjection` and `partyAudience`
derive server views. `rallyBoard`, `joinRally` and `leaveRally` bind authored objectives through the
supplied rally decoder. `pendingInviteCount` and `projectionRefusals` expose host observations.

Supply the atomic party port plus membership read/projection, optional full snapshot projection,
candidate rows, grouping-domain lookup, current character identity, display names, clock and rally
selection projection. Configure rally policy, loot mode, TTLs, bounded observations/candidates,
party-id construction, fallback labels and refusal reporting. Keep native subscriptions, actual
names/text, visibility policy, objective catalogs and record/index storage scope in the game.
Use clocks and TTLs consistent with the supplied party rules. Readbacks must reflect actual durable
outcomes; projection refusals are observed rather than treated as successful index writes.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-party.verify.luau
```

The [executable fixture](../../src/roblox/social-party.verify.luau) composes real membership,
atomic party and rally systems with neutral identities. It tests candidate admission, durable
membership projection, pending-route cleanup, leadership succession, bounded refusals and rally expiry.

## Invariants

- Invitations target visible candidates in the same configured grouping domain.
- Successful member transitions project current seats and clear displaced seats.
- Pending invitation routes are released on accept, decline, replacement and departure.
- Reconnection uses current character identity and durable membership rules.
- Leadership and invitation deadlines use the supplied clock and matching TTLs.
- Refusal observations stay bounded, and expired objectives cannot admit a new rally selection.
