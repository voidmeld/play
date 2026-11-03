# Play

Play is a strict Luau library of reusable MMORPG systems: authoritative state transitions,
transaction recovery and host coordination. Share quests, inventory, combat participation,
progression and social rules across games without sharing their worlds.
Play is MIT licensed; access to this repository is private.

The game supplies content, configuration and host operations. Play does not supply world canon,
item or ability catalogs, assets, credentials, deployment destinations or a running server.
Compose builds interfaces, Generate produces authored outputs, Execute runs workflows and Verify
checks behavior; Play owns reusable gameplay systems.

## Layers

| Layer | Responsibility | Deployment |
| --- | --- | --- |
| [core](src/core) | Engine-independent rules, validators, state machines and injected host coordinators. Pure transitions perform no host work. | Runtime under the game's authority boundary. |
| [roblox](src/roblox) | Typed adapters over injected native, storage, scheduling and observation operations. | Runtime beside the game's engine bindings. |
| [test-scene](src/test-scene) | Fake clocks, signals, ownership and small hosts exercising real rules. | Lute verification only; exclude from shipped Roblox trees. |

Import systems directly. The game owns service discovery, remote wiring and lifetime.
Keep authoritative decisions on the server.

## Five minutes: threat without Roblox

Install the versions in [rokit.toml](rokit.toml) with `rokit install --no-trust-check`, then run
`lute setup`. Put Rokit's `bin` on `PATH`; on Windows use `$env:ROKIT_ROOT/bin`.
From this checkout, run:

```sh
lute run tools/quickstart.luau
```

The [complete example](tools/quickstart.luau) drives real threat rules through the
[fake host](src/test-scene/threat.luau):

```luau
--!strict
local ThreatScene = require("../src/test-scene/threat")
local scene = ThreatScene.new({ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 })
scene.add("guard", 100, true)
scene.add("ranger", 120, false)
assert(scene.snapshot().targetActorId == "guard")
scene.add("ranger", 11, false)
assert(scene.snapshot().targetActorId == "ranger")
scene.taunt("guard")
assert(scene.snapshot().targetActorId == "guard")
```

Save this snippet under `tools/` to preserve its relative import. The game chose the ratios;
Play chose the target. The full example also checks absent/dead actor pruning and the fake clock.
It prints `Threat: takeover, taunt and host pruning passed at t=1`.
Production hosts import `src/core/threat` and use its `table` component, supply observations and install returned state.
Each core family has one entry module with an exported `API` type and component-prefixed type aliases.
For example, `Threat.TableState` names the state accepted by `Threat.table.rules`. Existing component
paths remain compatible while adopters move to these entries.

## Pin and consume

Pin immutable Git commits and their exact trees in the game's `dependencies.lock.luau`.
A consumer using the shared delivery format adds this entry to its `dependencies` array:

```luau
{
    name = "play",
    repository = "https://github.com/voidmeld/play.git",
    commit = "<full merged commit>",
    tree = "<exact commit tree>",
    rights = "MIT",
    surfaces = {
        { root = "src/core", role = "runtime" },
        { root = "src/roblox", role = "runtime" },
        { root = "src/test-scene", role = "verification" },
    },
}
```

After fetching, resolve the merged commit with `git rev-parse origin/main` and its tree with
`git rev-parse 'origin/main^{tree}'`. The placeholders above are not runnable pins.
The game's dependency tooling verifies both identities and makes the selected surfaces available.
Preserve relative paths within surfaces and between `core` and `roblox`. Map only runtime surfaces
into Roblox, then require the mapped module from the game's binding. Lute tests may require the
pinned checkout through relative filesystem paths.

Play's own [lock](dependencies.lock.luau) pins Verify for development; it is not a game lock or a
Play installer. Private-repository access uses the operator's existing Git setup.
After repinning, run affected adopter specifications and whole-tree analysis for changed contracts.
Publish, repin and test the adopter together; the game owner controls its pin update.

## System catalog

Each row links to a system guide with its entry, state, host requirements and executable example. [Systems](docs/systems.md) explains usage and
[API](docs/api.md) lists module exports. State and policy are explicit inputs.

| Core system | Provides |
| --- | --- |
| [Bank](docs/systems/bank.md) | Vault transfers, capacity checks and replay-safe receipts. |
| [Cast](docs/systems/cast.md) | Bounded queues, cancellation tokens and cooldown windows. |
| [Character](docs/systems/character.md) | Cancellable respawn watches and guarded body replacement. |
| [Chat](docs/systems/chat.md) | Audiences, history, commands and sender budgets. |
| [Control](docs/systems/control.md) | Diminishing durations, reset windows and immunity. |
| [Craft](docs/systems/craft.md) | Recipe projection and material requirements. |
| [Effects](docs/systems/effects.md) | Timed stacks, periodic ticks and dispels. |
| [Events](docs/systems/events.md) | Catalogs, schedules, participation and reward tickets. |
| [Identity](docs/systems/identity.md) | Rosters, claims, account/character leases, arrival receipts and retirement recovery. |
| [Inventory](docs/systems/inventory.md) | Stacks, bag capacity, cargo custody and delivery. |
| [Ledger](docs/systems/ledger.md) | Value events, balances, reservations and grouped operations. |
| [Loot](docs/systems/loot.md) | Weighted draws and party need/greed/pass decisions. |
| [Mail](docs/systems/mail.md) | Attachments, claims, returns, expiry and recovery. |
| [Map](docs/systems/map.md) | Discovery, coordinates, viewport geometry and update cadence. |
| [Market](docs/systems/market.md) | Listings, fills, fees, wallet holds and conservation. |
| [Network](docs/systems/net.md) | Token buckets and per-sender rate limits. |
| [Orders](docs/systems/orders.md) | Work progress, realm orders and reward claims. |
| [Persistence](docs/systems/persistence.md) | Session locks, profile lifetime, ordered stores and close draining. |
| [Professions](docs/systems/professions.md) | Skills, crafting, harvest, fishing and node sessions. |
| [Progression](docs/systems/progression.md) | Levels, talents, consumables, action bars, recovery, reputation, seasons and settlement. |
| [Quest](docs/systems/quest.md) | Objectives, indexes, progress, markers, run history and claims. |
| [Social](docs/systems/social.md) | Parties, fellowships, warbands, shared banks, allies, notes and chronicles. |
| [Threat](docs/systems/threat.md) | Target selection, taunts, contribution and encounter eligibility. |
| [Trade](docs/systems/trade.md) | Revisioned offers, mutual confirmation, receipts and recovery. |
| [Vendors](docs/systems/vendors.md) | Buying, selling, finite stock and owner-scoped buyback. |

| Roblox adapter | Provides |
| --- | --- |
| [camera](docs/systems/roblox-camera.md) | Follow dynamics, springs and obstruction clearance. |
| [chat](docs/systems/roblox-chat.md) | Native channels and platform privacy admission. |
| [consumables](docs/systems/roblox-consumables.md) | Durable consumption and revalidated recovery dispatch. |
| [contact-markers](docs/systems/roblox-contact-markers.md) | Ref-counted animation contacts with action stamps. |
| [conversation-camera](docs/systems/roblox-conversation-camera.md) | Conversation ownership and framing beside UI. |
| [cue-mixer](docs/systems/roblox-cue-mixer.md) | Retrigger admission, voice caps and ducking. |
| [cue-playback](docs/systems/roblox-cue-playback.md) | Voice lifetime and effect progression. |
| [data-store](docs/systems/roblox-data-store.md) | Storage retries, delays and jitter. |
| [equipment-queue](docs/systems/roblox-equipment-queue.md) | Serial per-owner application and fencing. |
| [equipment-rig](docs/systems/roblox-equipment-rig.md) | Construction ownership, mesh joins and slot settlement. |
| [input-bindings](docs/systems/roblox-input-bindings.md) | Keyboard/gamepad bindings, labels and chords. |
| [input-contexts](docs/systems/roblox-input-contexts.md) | Deadline-bound readiness and template adoption. |
| [input-profile](docs/systems/roblox-input-profile.md) | Device coverage and rollback-safe binding sessions. |
| [inventory](docs/systems/roblox-inventory.md) | Context-fenced item mutation and atomic reward bundles over supplied profiles. |
| [mail](docs/systems/roblox-mail.md) | Durable attachment holds, delivery decisions, returns and admission recovery. |
| [market](docs/systems/roblox-market.md) | Catalog-bound trading, merchant operations, item search and server projections. |
| [market-settlement](docs/systems/roblox-market-settlement.md) | Durable wallet holds, order-book fences, receipt claims and crash recovery. |
| [messaging](docs/systems/roblox-messaging.md) | Notices, filtering and subscription cleanup. |
| [movement-intake](docs/systems/roblox-movement-intake.md) | Epochs, acknowledgments and speed enforcement. |
| [movement-sender](docs/systems/roblox-movement-sender.md) | Handshake, resend ledger and revocation. |
| [npc-motion](docs/systems/roblox-npc-motion.md) | Planar steps, leash geometry and puppet projection. |
| [party](docs/systems/roblox-party.md) | Atomic membership persistence and exact readback. |
| [professions](docs/systems/roblox-professions.md) | Profile/world coordination and durable commits. |
| [profile-sessions](docs/systems/roblox-profile-sessions.md) | Lease admission, save, renewal, close and drain. |
| [profile-transfer](docs/systems/roblox-profile-transfer.md) | Session identity, settled writes and per-key exclusion. |
| [remote-events](docs/systems/roblox-remote-events.md) | Shared channel dispatch and handler release. |
| [screen-labels](docs/systems/roblox-screen-labels.md) | Priority labels and reserved-screen avoidance. |
| [social-host](docs/systems/roblox-social-host.md) | Actor exclusion, caches and membership settlement. |
| [social-records](docs/systems/roblox-social-records.md) | Durable records, ledgers, inboxes and indexes. |
| [target-selection](docs/systems/roblox-target-selection.md) | Cycling, pointer selection and range release. |
| [thumbstick](docs/systems/roblox-thumbstick.md) | Dead-zone movement and knob displacement. |
| [trade](docs/systems/roblox-trade.md) | Revisioned two-profile exchange with durable holds, decisions and recovery. |
| [travel-placement](docs/systems/roblox-travel-placement.md) | Grounded destinations without collisions. |

## Host-operation contract

Read the exported `Config`, `Deps`, `Host` or operation-specific types before binding a system.
There is no universal engine host interface. Supply exactly its requested capabilities:
clocks, randomness, observations, scheduling, persistence, native resources or dispatch.

- Keep policy callbacks deterministic and stable for an instance. Supply catalogs and bounds explicitly.
- Use the documented clock domain: monotonic time for elapsed deadlines and supplied timestamps for durable records.
- Treat borrowed inputs as read-only. Install related returned state and account/profile effects atomically.
- Decode untrusted requests and stored records at the boundary. Static types do not validate remote data.
- Return actual committed persistence readbacks. Missing replies or uncertain writes do not prove success; retain receipts for reconciliation.
- Atomic-store transforms can retry. Keep them free of external effects. Fence yielding work against session, character and operation generations.
- Own cleanup: disconnect listeners, cancel scheduled work and dispose native resources at lifetime end.

Pure transitions do not discover services or schedule work. Host coordinators use injected
operations. The game owns authentication, authority, storage namespaces, content and deployment.

## Compatibility and contributing

The supported unit is an exact commit and tree; Play currently has no semantic-version release
promise. Exported declarations, result/refusal meanings and saved schemas are contracts.
Keep existing consumers working when adding capabilities. Change a contract only with its consumer;
include migration and adopter checks for saved-shape or behavior changes. Helpers under `internal/`
and verification fixtures are not supported game APIs.

Use strict Luau, explicit types, zero type assertions and no code comments except compiler directives.
Land small squash-merged PRs to `main` with the required **Gate** check green.
Run `lute run tools/gate.luau --tier fast` while editing; commit the candidate and run
`lute run tools/gate.luau` on clean HEAD before integration. See [validation](docs/validation.md)
and [repository rules](AGENTS.md). Never push `main` directly or bypass a failed check.
