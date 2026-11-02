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
Production hosts import `src/core/threat/table`, supply observations and install returned state.

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

Each row links to an implementation family. [Systems](docs/systems.md) explains usage and
[API](docs/api.md) lists module exports. State and policy are explicit inputs.

| Core system | Provides |
| --- | --- |
| [Bank](src/core/bank) | Vault transfers, capacity checks and replay-safe receipts. |
| [Cast](src/core/cast) | Bounded queues, cancellation tokens and cooldown windows. |
| [Character](src/core/character) | Cancellable respawn watches and guarded body replacement. |
| [Chat](src/core/chat) | Audiences, history, commands and sender budgets. |
| [Control](src/core/control) | Diminishing durations, reset windows and immunity. |
| [Craft](src/core/craft) | Recipe projection and material requirements. |
| [Effects](src/core/effects) | Timed stacks, periodic ticks and dispels. |
| [Events](src/core/events) | Catalogs, schedules, participation and reward tickets. |
| [Identity](src/core/identity) | Rosters, claims, fenced leases and account creation/deletion. |
| [Inventory](src/core/inventory) | Stacks, bag capacity, cargo custody and delivery. |
| [Ledger](src/core/ledger) | Value events, balances, reservations and grouped operations. |
| [Loot](src/core/loot) | Weighted draws and party need/greed/pass decisions. |
| [Mail](src/core/mail) | Attachments, claims, returns, expiry and recovery. |
| [Map](src/core/map) | Discovery, coordinates, viewport geometry and update cadence. |
| [Market](src/core/market) | Listings, fills, fees, wallet holds and conservation. |
| [Network](src/core/net) | Token buckets and per-sender rate limits. |
| [Orders](src/core/orders) | Work progress, realm orders and reward claims. |
| [Persistence](src/core/persistence) | Session locks, profile lifetime, ordered stores and close draining. |
| [Professions](src/core/professions) | Skills, crafting, harvest, fishing and node sessions. |
| [Progression](src/core/progression) | Levels, talents, consumables, action bars, recovery, reputation, seasons and settlement. |
| [Quest](src/core/quest) | Objectives, indexes, progress, markers, run history and claims. |
| [Social](src/core/social) | Parties, fellowships, warbands, shared banks, allies, notes and chronicles. |
| [Threat](src/core/threat) | Target selection, taunts, contribution and encounter eligibility. |
| [Trade](src/core/trade) | Revisioned offers, mutual confirmation, receipts and recovery. |
| [Vendors](src/core/vendors) | Buying, selling, finite stock and owner-scoped buyback. |

| Roblox adapter | Provides |
| --- | --- |
| [camera](src/roblox/camera.luau) | Follow dynamics, springs and obstruction clearance. |
| [chat](src/roblox/chat.luau) | Native channels and platform privacy admission. |
| [consumables](src/roblox/consumables.luau) | Durable consumption and revalidated recovery dispatch. |
| [contact-markers](src/roblox/contact-markers.luau) | Ref-counted animation contacts with action stamps. |
| [conversation-camera](src/roblox/conversation-camera.luau) | Conversation ownership and framing beside UI. |
| [cue-mixer](src/roblox/cue-mixer.luau) | Retrigger admission, voice caps and ducking. |
| [cue-playback](src/roblox/cue-playback.luau) | Voice lifetime and effect progression. |
| [data-store](src/roblox/data-store.luau) | Storage retries, delays and jitter. |
| [equipment-queue](src/roblox/equipment-queue.luau) | Serial per-owner application and fencing. |
| [equipment-rig](src/roblox/equipment-rig.luau) | Construction ownership, mesh joins and slot settlement. |
| [input-bindings](src/roblox/input-bindings.luau) | Keyboard/gamepad bindings, labels and chords. |
| [input-contexts](src/roblox/input-contexts.luau) | Deadline-bound readiness and template adoption. |
| [input-profile](src/roblox/input-profile.luau) | Device coverage and rollback-safe binding sessions. |
| [messaging](src/roblox/messaging.luau) | Notices, filtering and subscription cleanup. |
| [movement-intake](src/roblox/movement-intake.luau) | Epochs, acknowledgments and speed enforcement. |
| [movement-sender](src/roblox/movement-sender.luau) | Handshake, resend ledger and revocation. |
| [npc-motion](src/roblox/npc-motion.luau) | Planar steps, leash geometry and puppet projection. |
| [party](src/roblox/party.luau) | Atomic membership persistence and exact readback. |
| [professions](src/roblox/professions.luau) | Profile/world coordination and durable commits. |
| [profile-sessions](src/roblox/profile-sessions.luau) | Lease admission, save, renewal, close and drain. |
| [profile-transfer](src/roblox/profile-transfer.luau) | Session identity, settled writes and per-key exclusion. |
| [remote-events](src/roblox/remote-events.luau) | Shared channel dispatch and handler release. |
| [screen-labels](src/roblox/screen-labels.luau) | Priority labels and reserved-screen avoidance. |
| [social-host](src/roblox/social-host.luau) | Actor exclusion, caches and membership settlement. |
| [social-records](src/roblox/social-records.luau) | Durable records, ledgers, inboxes and indexes. |
| [target-selection](src/roblox/target-selection.luau) | Cycling, pointer selection and range release. |
| [thumbstick](src/roblox/thumbstick.luau) | Dead-zone movement and knob displacement. |
| [travel-placement](src/roblox/travel-placement.luau) | Grounded destinations without collisions. |

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
