# Character admission lifecycle

[System catalog](../systems.md) · [Route admission](route-admission.md) · [Character leases](identity.md)

Stage a leased character's arrival into a host's profile, session, actor, body and movement owners,
then unwind those owners safely on failure or departure. Import
[roblox/character-admission](../../src/roblox/character-admission.luau) and call `start(config, dependencies)`.
The result is a started runtime or a structured setup refusal. Profiles remain opaque generic values.

## State shape

The runtime tracks per-subject context and user/character/session/acquisition/revision identities,
destination, installed-owner flags, renewal state and pending cleanup. Context is a frozen six-field
identity/key/lease-revision record. Return snapshots capture the subject, character, destination,
route identity and fence. Optional per-coroutine timelines record bounded stage/storage observations.

## Operations

`start` validates policy/place/reclaim inputs, installs owned subscriptions and admits current subjects.
Admission validates the subject and native route through injected authority, reserves any group claim,
marks roster departure, acquires character authority and fences it before loading/binding downstream
owners. It compares profile identity facts before projecting the game profile and admitting actor,
body and movement. Optional receipt failure is reported as a stage observation.

`cleanup` removes movement, body and actor owners before releasing session/profile/lease authority.
Failed removal retains its ownership flags for retry. Cleanup during renewal either waits within the
configured budget or reports failure with custody retained. `dispose` stops admission, releases
subscriptions and attempts cleanup for every retained entry. `isAdmitted` observes current movement
and optional group authority. `previewDeparture`, `prepareReturn` and `recover` expose fenced return
snapshots and recovery; preparation reports a separate recoverable snapshot if cleanup fails.

## Required host operations

Supply authenticated carrier/routing, roster/character lease, profile, session, actor, body, movement,
player-presence/subscription and receipt ports. Supply the clock and owned renewal scheduler, optional
wait/reclaim and group-authority/reconnect operations, and optional timeline publication/store observation.
Native operations may yield; return actual outcomes and maintain the supplied acquisition identity.
The game retains authentication, namespaces, native object lifetime and all gameplay authority.

Configuration supplies typed profile-fact and native profile projections, an identity comparison,
lease-failure reporting, identity/timeline limits, lease/retry/renewal/cleanup cadence and retry reasons.
Reclaim attempts, delays and wait operation belong to the runtime dependencies. Profile ports must
validate the full game model; the coordinator only checks the projected user/character/version facts.
Keep profile schemas, identity fields, attribute names, content, labels and telemetry destinations local.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/character-admission.verify.luau
```

The [fixture](../../src/roblox/character-admission.verify.luau) supplies fake native owners, synthetic
place identities, an alternate profile layout/version and short lease timings. It checks stage order,
reverse cleanup, retained authority on failed removal, stale renewal callbacks across recovery, expiry
fencing and subscription setup failure. Consumer tests exercise real routing/profile/session ports.

## Invariants

- Actor/body/movement authority is installed only after identity and lease fencing.
- Downstream owner failure unwinds completed owners in reverse order.
- A failed actor removal cannot release session, profile or lease authority underneath it.
- Lease/session/acquisition/revision facts bind renewal and recovery.
- Expired renewal failure fences admission and reports through the game's telemetry port.
- Old scheduled callbacks cannot advance a replacement admission or a disposed runtime.
- Native projection, persistence, routing and gameplay operations remain injected and host-owned.
