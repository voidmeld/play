# Play

Reusable MMORPG game systems for Roblox, written in strict Luau.

Play is the gameplay layer under a persistent-world game: quests, inventory and equipment,
loot, trade, mail, an auction market, a bank, guilds and parties, levels and talents,
professions and crafting, threat and targeting, combat effects, chat, the world map,
and the persistence that keeps all of it safe across servers. Every rule is a pure Luau
function with no engine dependency, so it runs and is tested without Roblox Studio.
A matching set of Roblox adapters binds those rules to DataStores, remotes, characters
and input.

Play has no content of its own: no quests, items, zones or classes. Your game supplies the
data and the server authority; Play applies the rules and returns new state or a refusal.

First, run one fixture with the [quickstart](docs/quickstart.md).
Second, [build a persistent world with Play](docs/spine.md): one server, two clients,
saved progression, quests, loot, equipment, trade and chat, through headless and native hosts.

## What is inside

| Family | Systems | Entry |
| --- | --- | --- |
| Characters | Account and character leases, creation, naming, deletion, retirement, rosters, routing between places | [`identity`](docs/api.md#identity), [`character`](docs/api.md#character) |
| Progression | Levels and XP, talents and ranks, action bar, consumables, reputation, seasons, recovery, settlement of pending grants, fingerprinted transaction receipts | [`progression`](docs/api.md#progression) |
| Quests | Journal, objectives, counters, claims, markers, lifecycle and runs | [`quest`](docs/api.md#quest) |
| Items | Stacks, equipment slots, carried cargo | [`inventory`](docs/api.md#inventory) |
| Loot | Roll tables and loot decisions | [`loot`](docs/api.md#loot) |
| Economy | Player trade with receipts, mail with attachments, order book market with wallets and conservation, vendors, work orders, bank vaults | [`trade`](docs/api.md#trade), [`mail`](docs/api.md#mail), [`market`](docs/api.md#market), [`vendors`](docs/api.md#vendors), [`orders`](docs/api.md#orders), [`bank`](docs/api.md#bank) |
| Professions | Skills, gathering, harvest, fishing, crafting sessions, recipes | [`professions`](docs/api.md#professions), [`craft`](docs/api.md#craft) |
| Combat | Threat tables and contribution, cast queues, contact resolution, timed effects, crowd control with diminishing returns | [`threat`](docs/api.md#threat), [`cast`](docs/api.md#cast), [`combat`](docs/api.md#combat), [`effects`](docs/api.md#effects), [`control`](docs/api.md#control) |
| Social | Groups, parties, fellowships, warbands, formations, membership, guild bank, guild home, guild ledger, allies, notes, chronicle | [`social`](docs/api.md#social) |
| Communication | Chat channels, scheduled world events with watches | [`chat`](docs/api.md#chat), [`events`](docs/api.md#events) |
| World | Map geometry, coordinates, exploration, viewports and map updates | [`map`](docs/api.md#map) |
| Networking | Rate limits for remote traffic | [`net`](docs/api.md#net) |
| Persistence | Profile sessions, session locks, record stores, store hosts | [`persistence`](docs/api.md#persistence) |

Every family lives at `src/core/<family>` and exports an `API` type with its components.

The Roblox layer at `src/roblox/<adapter>` binds those rules to the engine: DataStore
sessions and profile transfer, remote events, character admission and travel placement,
movement intake and sending, equipment rigs, input profiles and bindings, thumbstick,
target selection, screen labels, cue playback, chat, party and social hosts, trade, mail,
market settlement and the guild bank. See [host operations](docs/api.md#host-operations).

The kernel at `src/kernel` holds the primitives everything else shares: value admission,
codecs, result envelopes, leases and atomic stores.

## Example

A threat table that decides which actor an enemy attacks:

```luau
local Threat = require(path.to.play.core.threat)

local rules = Threat.table.rules({ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 })
local state = Threat.table.empty()

local nextState, firstTarget = rules.add(state, "actor-a", 10, true)
state = nextState
assert(firstTarget)

state = rules.taunt(state, "actor-b")
assert(state.targetActorId == "actor-b")
```

Rules take state and return new state. Nothing is mutated, nothing touches the engine, and
an impossible request comes back as a refusal rather than a crash. The
[API reference](docs/api.md) shows the same pattern for every family, with the returns and
refusals of each call.

## How it fits together

| Surface | Purpose |
| --- | --- |
| `src/kernel` | Shared values, results, codecs, leases and atomic store contracts. |
| `src/core/<family>` | Configured rules and engine-independent coordinators. Each entry exports an `API` type and component aliases. |
| `src/roblox/<adapter>` | Typed Roblox adapters over supplied operations. |
| `src/test-scene` | Deterministic fixtures for verification. Exclude this surface from shipped runtime trees. |

Import only the public entries. Keep authoritative state transitions on the server.
[Architecture](docs/architecture.md) explains the boundaries between the layers.

## Install

Play is pinned by commit, not by version. Choose a commit of
`https://github.com/voidmeld/play.git`, record its commit and tree in your dependency lock,
and vendor the surfaces you use. [Adoption](docs/adoption.md) walks through choosing a
boundary and pinning it. After a pin change, run the specifications of the consumers you
changed.

## Documentation

| Task | Document |
| --- | --- |
| Run the first fixture | [Quickstart](docs/quickstart.md) |
| Assemble a persistent world | [Reference world walkthrough](docs/spine.md) |
| Find public calls, returns and failures | [API reference](docs/api.md) |
| Bind storage, clocks and native resources | [Host operations](docs/api.md#host-operations) |
| Choose a reusable boundary and pin a consumer | [Adoption](docs/adoption.md) |
| Understand library boundaries | [Architecture](docs/architecture.md) |
| Set up tools or diagnose checks | [Validation](docs/validation.md) |
| Change this repository | [Maintainer guide](AGENTS.md) and [contributing](CONTRIBUTING.md) |

## Compatibility

The supported unit is an exact commit and tree; there is no semantic-version promise.
Exported declarations, refusal meanings and saved schemas are contracts. A contract changes
together with its consumers. Internal helpers and verification fixtures are not public APIs.

## License

Play is [MIT licensed](LICENSE). Its own development dependencies are pinned in
[dependencies.lock.luau](dependencies.lock.luau).
