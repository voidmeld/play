# Architecture

[Play](../README.md) · [System catalog](api.md#task-table) · [API reference](api.md)

## Principles

1. Server authority. Rules are pure functions of state, event and policy; effects are returned, not performed.
2. One definition per concept. A primitive lives in the kernel once; parallel implementations are defects.
3. Complete or absent. A system meets the completeness bar or it does not ship.
4. Extracted, not speculated. Systems come from a working consumer; at least two consumers share one public API.
5. Games own content, policy and identity; Play owns rules and recovery.
6. Value moves only through custody: holds, receipts, idempotent replay and crash recovery.
7. Decode at every boundary. Static types do not validate remote or stored data.
8. Small, explicit, namespaced APIs: data in, data out, injected ports for every host operation.
9. Deletion over addition. Every change reports lines before and after, and merges remove duplication.
10. One fact per doc.

Play is a library of complete, reusable MMORPG systems that any Roblox game can adopt by
supplying content, policy and host operations. A system is complete when a game can adopt it
without writing its own persistence, recovery, validation or replication glue.

This is the target architecture. The [API reference](api.md) owns current declarations and import
paths while the migration proceeds; the [validation procedure](validation.md) owns gate commands.

## Layers

| Layer | Path | Rule |
| --- | --- | --- |
| kernel | `src/kernel` | Shared primitives. Pure, no host services, no domain knowledge. |
| core | `src/core/<domain>/<system>` | Pure rules plus host-agnostic coordinators over kernel ports. |
| roblox | `src/roblox/<domain>/<system>` | Binds kernel ports to Roblox services. No game rules. |
| client | `src/client/<concern>` | Optional presentation and input helpers (camera, cues, labels, input bindings). Never authoritative. |
| test-scene | `src/test-scene/<domain>` | Fake hosts for every system, used by specs and examples. |

Dependencies point downward only: client, then roblox, then core, then kernel. Core never
imports roblox or client.

## Kernel (one definition each; delete every per-module copy)

- `result`: `Result<T> = { ok: true, value: T } | { ok: false, reason: string, detail: string? }`
  and helpers. Replaces the 55 per-module Outcome/Result types.
- `store`: the atomic store port, `update(key, transform) -> Result<Readback>`, with
  compare-and-swap and committed readback semantics. Replaces the per-module Store types.
- `lease`: acquire, renew, fence and release a keyed lease with generations. Replaces
  account-lease, character-lease, session-lock, profile-session, leased-record-session,
  profile-sessions and the mail and quest-durability leases.
- `session`: a leased record session (hydrate, dirty tracking, batched save, renewal, drain on
  close) built on lease plus store. quest-durability and profile sessions become configurations of it.
- `custody`: the durable hold-commit-claim-reconcile saga with receipts and crash recovery. Trade,
  mail, bank, guild bank, market settlement, formation fees and vendor buyback become
  configurations of it.
- `codec`: decode and validate untrusted or stored data at the boundary, with versioned migration hooks.
- `clock`, `id`, `rate` (token buckets), `events` (effect lists returned by rules).
- `value`: one module replacing core/value, core/internal/value, identity/value and internal/identity-value.

## System shape (every system, no exceptions)

```
src/core/<domain>/<system>/
  init.luau        exports API type and the public functions
  types.luau       state, events, policy, results
  rules.luau       pure: apply(state, event, policy) -> Result<{ state, effects }>
  policy.luau      policy schema, defaults and validation
  coordinator.luau optional: orchestration over kernel ports (lease, store, custody, clock)
src/roblox/<domain>/<system>.luau  new(ports, policy) -> Service, binding ports to Roblox
src/test-scene/<domain>/<system>.luau
docs/systems/<system>.md           one guide: adoption, policy, host ports, runnable example
```

Public API is namespaced: `Play.economy.trade`, `Play.social.party`. Each entry exports one
`API` type. No barrels re-exporting prefixed type aliases.

## Domains and systems

| Domain | Systems |
| --- | --- |
| character | roster and identity (claims, creation, deletion, retirement), stats and attributes (new), respawn |
| combat | abilities and cast queues, resolution and contact timing (new, extracted from a consumer), effects, control (diminishing returns), threat, targeting |
| progression | levels, talents, reputation, seasons, action bars, consumables, recovery |
| items | item model (stacks, equipment slots, wear), inventory, loot |
| economy | ledger and wallet, bank, vendors, trade, mail, market, crafting and professions (craft merged into professions) |
| social | group (party and warband as one system with sizes), guild (fellowship, guild bank, ledger, home, formation), chat, whispers and notes, allies, chronicle |
| quest | journals, objectives, prerequisites, markers, run history, claims |
| world | map and discovery, travel and zone routing, instances and dungeons lifecycle (new), spawning and encounters (new), events, orders, NPC motion |
| net | remote channels, rate limits, movement replication (intake and sender) |
| client | camera, conversation camera, cue mixer and playback, screen labels, input bindings, contexts and profiles, thumbstick, target selection UI |

## What any MMORPG needs, and where Play stands

Have: present and reusable. Partial: exists but incomplete or split. Missing: absent.

| Area | Systems any MMORPG needs | Play today |
| --- | --- | --- |
| Foundation | account admission and sessions, reconnect, capacity and queueing | partial (identity, profile sessions) |
| Foundation | profile persistence, schema migration, autosave, idempotent receipts, audit trail | partial (split across 7 lease and session variants) |
| Foundation | actor model shared by players, NPCs and objects; spawn and despawn lifecycle | missing |
| Foundation | interest management and replication, server clock, request validation and rate limits | partial (rate limits, movement replication) |
| World | zone routing and travel with state handoff, instances and phases, lockouts | partial (route admission, travel placement) |
| World | map and discovery, world state (time, weather), scheduled world events | partial (map, events) |
| Character | creation, roster and names, appearance, classes and races | have (identity) |
| Character | stats and attributes with a modifier pipeline (base, gear, effects, derived) | missing |
| Character | experience and levels, talents, death, respawn and resurrection, rested recovery | partial (levels, talents, respawn, recovery; no death or resurrection) |
| Combat | ability definitions, costs, cooldowns, global cooldown, cast, channel and interrupt | partial (cast queues and cooldowns) |
| Combat | targeting and area shapes, hit and damage/heal resolution, mitigation and crits | partial (immutable contact admission/lifetime and custody/spatial fencing; target selection UI; consequence policy remains in adopters) |
| Combat | auras and status effects, crowd control with diminishing returns | have (effects, control) |
| Combat | threat and aggro, combat state, contribution and kill credit, PvP flagging | partial (threat and contribution) |
| NPC and AI | behaviors, leash and reset, spawners and respawn timers, encounters and boss phases | missing (NPC motion only) |
| NPC and AI | interaction and dialogue (vendors, trainers, quest givers) | missing |
| Items | item definitions, rarity, affixes, binding, unique instances | missing (stacks only) |
| Items | inventory and bags, equipment slots applying stats, durability and repair | partial (inventory, equipment wear) |
| Items | loot tables and group distribution | have (loot) |
| Economy | currencies, wallet and ledger, vendors and buyback, trade, mail, market, bank | have, but each reimplements custody |
| Economy | crafting, gathering and professions | have, split (craft and professions) |
| Economy | faucet and sink monitoring, anti-duplication guarantees | partial (custody per system, no monitoring) |
| Progression | quests (chains, repeatables, journal, tracking, markers) | have |
| Progression | achievements, titles and collections | missing |
| Progression | reputation and factions, seasons, leaderboards | partial (reputation, seasons; no leaderboards) |
| Social | chat channels, whispers, friends, ignore and block, presence | partial (chat, whispers, allies, notes; no presence or ignore) |
| Social | parties and raids, ready checks, loot rules, group finder | partial (party, warband; no finder or ready check) |
| Social | guilds with ranks, permissions, bank, message of the day | have (fellowship, guild bank, ledger) |
| PvP | duels, battlegrounds and arenas with matchmaking and ratings, territory control | missing |
| LiveOps | remote config and flags, moderation (mute, ban, report), telemetry, kill switches | missing |
| Client | input bindings, camera, cues, labels, settings persistence | partial (no settings persistence) |

Gap priority follows current consumer needs: stats and attributes; combat resolution and death;
actor, spawner and encounter lifecycle; instance lifecycle and lockouts; territory control (realm
war); then achievements, presence and ignore, settings persistence and LiveOps moderation.
Build gaps only when a consumer needs them, by moving and generalising code from an adopting game, never speculatively.

## Completeness bar (per system)

A system ships only with: validated policy with defaults; pure rules; persistence codec and
migration hook when it stores state; recovery path when it holds value; a roblox adapter; a
test-scene host; a guide with a runnable example; specs covering adversarial input, concurrency
and crash recovery. Two consumers (a game plus the test-scene) must use the same public API.

## Migration order

1. Kernel: result, store, lease, codec, value. Port two systems as proof and delete their copies.
2. Custody: build the saga, then move trade, mail, bank, guild bank, market settlement and formation onto it.
3. Session: collapse the persistence and lease variants onto lease plus session.
4. Re-home: move roblox adapters into domain folders, merge party and social-party and craft and
   professions, introduce namespaced entries, and split out the client layer.
5. Gaps, in the priority above: stats and attributes, combat resolution and death (with the
   consuming game's combat owner), actor, spawner and encounter lifecycle, instance lifecycle and lockouts,
   territory control, then the rest as consumers need them.

Each step is a small gated, squash-merged PR. The adopting game repins and deletes its replaced code in the same
deliverable. Every step reports line counts for Play and the adopting game before and after.
