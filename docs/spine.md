# Build a persistent world with Play

Start after the [quickstart](quickstart.md). This example puts identity, persistence,
progression, quests, inventory, loot, threat, trade, chat and networking in one running server.
Two players arrive in Harbor, earn a level, complete a supply quest, exchange items, chat,
leave and return with their saved state. All names and numbers are replaceable fixtures.

Run the [scenario](../examples/world/world.verify.luau) from the repository root:

```console
lute run tools/gate.luau --only specs --file examples/world/world.verify.luau
```

This runs the real rules and Roblox adapters with a deterministic host. It needs no account,
engine, network service or destination. The specification is in the test manifest and runs
in the normal gate. The example also stays under the neutral-content check.

## Read the assembly in this order

| File | What it owns |
| --- | --- |
| [content.luau](../examples/world/content.luau) | Roster policy, item limits, XP thresholds, two objectives, loot weights and trade limits. |
| [state.luau](../examples/world/state.luau) | The saved record, its decoder, new characters and compare-and-swap configuration. |
| [protocol.luau](../examples/world/protocol.luau) | Exact request fields, public response views and decoding in both directions. |
| [server.luau](../examples/world/server.luau) | The authoritative assembly: sessions, observations, rewards, inventory, trade and chat. |
| [roblox-server.luau](../examples/world/roblox-server.luau) | One server entry binding storage, admission and remote events through typed native ports. |
| [roblox-client.luau](../examples/world/roblox-client.luau) | One client entry sending intentions, decoding responses and retaining a short chat window. |
| [scene.luau](../examples/world/scene.luau) | A test host supplying clocks, storage, players, events and native operations to those same entries. |
| [world.verify.luau](../examples/world/world.verify.luau) | The complete two-client scenario and refusal/recovery checks. |

Imports use documented public components and adapters. There are no imports from internal helpers.
The [API task table](api.md#task-table) is the index when you replace a fixture.

## 1. Choose content before starting services

`content.luau` creates a roster policy with one character per account, three XP levels,
an eight-entry bag and a single equipment slot. Item IDs are `training_sword`, `shield`
and `copper_ore`. Keep machine IDs stable; give them your own display labels in the client.

The quest has two objectives: defeat the Warden and collect Copper Ore. Its objective catalog
matches server events to objectives. The loot table supplies the item and count after a defeat.
Trade validates offers and advances only the current revision through locking and confirmation.

Replace these tables and bounds before replacing the server. The selected public contracts are
[identity](api.md#identity), [progression](api.md#progression), [inventory](api.md#inventory),
[quest](api.md#quest), [loot](api.md#loot) and [trade](api.md#trade).

## 2. Define the record that can be committed together

`state.luau` stores a world revision and a map of players. Each player has a roster, XP,
coin, inventory, equipment, quest journal, defeat receipts, unclaimed loot and a session lock.
The character ID derives from the account ID in this one-character fixture. The roster rules
validate creation and later level, departure and played-time updates.

The decoder checks stored values before they enter authority. It copies nested state, checks
the XP-derived roster level and rejects invalid items, counts or identities. Unknown saved
versions fail instead of silently resetting a player. The record-store rules compare the
expected revision and contents, increment the revision and confirm the committed readback.
The server installs only that readback.

One record is a deliberate size limit: at most eight saved accounts and 32 defeat receipts
per account. This makes a two-player exchange one atomic write. It is an understandable
starting point for a small persistent world, with contention and record-size limits. Choose
the storage partition before increasing those bounds. For independent profile records,
use [the durable trade adapter](api.md#roblox-trade) and its receipts and recovery protocol;
two sequential profile writes cannot replace this transaction.

Replace the key `world:Harbor`, partition labels, decoder and initial character together.
The public contracts are [record storage and session lifetime](api.md#persistence),
[atomic stores](api.md#kernel-store), [identity](api.md#identity) and [quest journals](api.md#quest).

## 3. Start one server authority and acquire each session

`server.new` first reads and validates the world record. It then owns the admitted-session map,
remote budgets, current trade and one enemy's health and threat table. No client can write
this state. The exported profile and view operations return copies.

`transact` serializes local writes, reads a fresh record, edits a private candidate and commits
it through the record store. Another server's write causes the comparison to fail. Every
player mutation also checks the saved session token and its expiry. Server IDs and generated
acquisition IDs must be unique across restarts; an old session cannot act for a new acquisition.

`create` uses the roster rules to make a character. `join` acquires the saved session lock and
opens a profile session only after a successful readback. A second server is refused while
that lock is fresh. `change` marks the profile session dirty, starts its write, commits the
effect and finishes the profile-session operation. Normal requests save immediately.

The profile-sessions adapter schedules renewal every 20 seconds for a 60-second lease.
Leaving saves played time and releases the lock. Shutdown reverses admission and drains
all remaining sessions before disposing resources. Failed cleanup returns false.

Supply an integer wall clock in seconds to the world and a scheduler for elapsed delays.
The storage port separately accepts its own measurement clock and budget operations.
Replace IDs, clocks, storage and scheduling through the typed ports, preserving the lock
checks and readback requirement. See [persistence](api.md#persistence) and
[profile sessions](api.md#roblox-profile-sessions).

## 4. Admit the character through the native adapter

`roblox-server.start` builds the data-store backend and the world, then starts character
admission. It supplies the configured routing rules and connects native player events.
Admission runs this sequence:

1. Clear old native state and ensure the saved roster exists.
2. Resolve this fixture's fixed destination and check roster ownership.
3. Acquire the world session and create an immutable context for this acquisition.
4. Check the context, load a profile copy and bind the session.
5. Admit the actor, body and movement through the supplied native operations.

A failure removes completed stages in reverse order and releases the durable session.
The native adapter controls removal; a request is served only while its character is admitted.
Periodic profile renewal keeps the saved session lock authoritative during admission.

This fixture selects its only character and destination on the server. Its source and destination
IDs are separate routing configuration inputs; the test host uses invented numbers. For a selection
screen or travel flow, replace that fixed selection with your authenticated selection and handoff,
then supply your own routing content. Keep the staged cleanup. See
[identity routing](api.md#identity) and [character admission](api.md#roblox-character-admission).

## 5. Let observations earn progress and loot

Clients may accept the quest, equip an owned item, claim available loot and claim a finished
quest. They cannot submit damage, XP, objective counts, reward amounts or another player ID
to those operations.

The native combat owner calls `world.hit` after validating contact. In the test scene those
observations are explicit calls: the second player contributes five damage, the first
contributes ten and then fifteen. Threat makes the first player the enemy's target and this
fixture awards the defeat to that target. Replace that reward policy with contribution or
party eligibility when you need shared rewards.

Defeat commits 100 XP, a defeat receipt, one pending loot roll and the first objective.
The progression rules resolve level two and the roster is updated in the same write.
The loot request transfers the pending drop into the bag and advances the second objective.
The claim request atomically marks the quest completed, records its reward and grants 25 coin
and 50 XP. Repeating either claim has no reward. Equipment uses the inventory planner's
returned bag and slots together.

Replace damage observations, reward ownership, XP amounts, objective bindings and loot tables
as one content change. Preserve server ownership and receipt checks. See
[threat](api.md#threat), [progression](api.md#progression), [quest](api.md#quest),
[loot](api.md#loot) and [inventory](api.md#inventory).

## 6. Exchange items after both players confirm

The first player requests a trade with the second. Each offer increases the revision and
clears old locks and confirmations. Both players lock the same revision, then confirm it.
Stale revisions are refused.

At final confirmation, the server rechecks both live sessions, holdings, coin and capacity.
It removes both offers and adds the incoming goods in one private candidate. One confirmed
world-record write installs both inventories. A refusal discards the entire candidate.
The example exchanges Copper Ore for a Shield and verifies conservation after reconnect.

Open offers are temporary and disappear on disconnect or restart. No goods leave inventory
until the atomic settlement; there are no abandoned holds to recover. A committed exchange
survives through the saved inventories. Replace the single active-trade fixture with a map
when needed. A larger storage layout needs the durable adapter described in step 2.
See [trade rules](api.md#trade) and [durable trade coordination](api.md#roblox-trade).

## 7. Put a budget and decoder before every remote request

`protocol.luau` declares requests and responses. `world.request` consumes a per-sender network
budget before decoding the exact permitted fields. Authentication comes from the native
event's player argument. A payload cannot select its own sender. Server-only observations
have no remote request shape.

Public views contain the player's progress and possessions. They exclude session tokens and
other players' profiles. Trade views convert account-keyed maps into string-keyed dictionaries
for native remote transport. The client decodes received views, trades and chat lines before
installing them. Its disposable remote subscription uses the same dispatch adapter as the server.
The client entry retains data for a consumer UI; the example has no UI or native presentation.

Chat has a separate budget and one local channel. Channel rules select listeners; the supplied
filter returns text for each recipient before delivery. The scene returns a fixed safe line to
prove that raw input is not broadcast. A Roblox binding must supply platform filtering and privacy
admission. Replace the fixture's always-reachable audience with your own proximity observations.
See [network budgets](api.md#net), [remote events](api.md#roblox-remote-events),
[chat rules](api.md#chat) and [native chat](api.md#roblox-chat).

## 8. Mount the same assembly in Roblox

Keep `content`, `state`, `protocol`, `server` and the two `roblox-*` entries beside the selected
runtime Play surfaces, preserving their relative imports or rewriting them to your instance
mapping. Exclude `scene.luau`, the specification, test hosts and tools from the runtime tree.
Call the server entry once from a server script and the client entry once from a local script.
There is no second gameplay implementation to copy into Roblox.

| Entry port | Native binding | Play adapter or rule it supplies |
| --- | --- | --- |
| `storage.raw` | Data-store `GetAsync`, `UpdateAsync` and `SetAsync` wrappers. | [Store host](api.md#persistence) and [atomic-store adapter](api.md#kernel-store). |
| `storage` and `circuit` | Fresh-read options, request budgets, retry sleep, jitter, queue and circuit policy. | [Data-store retry](api.md#roblox-data-store); the entry constructs the real store backend. |
| `owner`, `schedule`, `clock` | Consumer lifetime, cancellation and timers; integer wall time for saved leases. | [Profile sessions](api.md#roblox-profile-sessions). |
| `players`, `clear`, `actor`, `body`, `movement`, `refuse` | Player lifecycle, body loading, actor registration, movement admission and refusal handling. | [Character admission](api.md#roblox-character-admission). |
| Server `remote.connectRequest` | One request RemoteEvent's `OnServerEvent`; forward its authenticated player argument. | [Remote-event dispatch](api.md#roblox-remote-events) and [network limits](api.md#net). |
| Server `remote.sendResponse` | Response RemoteEvent `FireClient` to the selected player. | The typed [response contract](../examples/world/protocol.luau). |
| Client `fireRequest`, `connectResponse` | Request `FireServer` and response `OnClientEvent`, returning a disconnect function. | [Remote-event dispatch](api.md#roblox-remote-events) and response decoding. |
| `filter` | Recipient-specific platform filtering plus privacy admission; return nil when delivery is refused. | [Channel rules](api.md#chat); use [native chat](api.md#roblox-chat) when adopting platform-owned channels. |
| `onClose` | Register the supplied shutdown callback with the server's close lifecycle. | Admission cleanup and profile drain. |

The typed `NativePorts` declaration is the complete host contract. `scene.luau` fills every
required slot, including the real-store adapter over an in-memory native-store fake. Use it
as the executable wiring reference. Native engine operations, text filtering and body behavior
need verification in your consumer; this repository's headless scenario proves the assembly,
not an engine deployment. See [host duties](api.md#host-operations).

## 9. Recover without guessing whether a write happened

An uncertain write holds the server authority. It reports refusal, stops further gameplay
writes and cannot report a successful close. It does not replay a reward or trade against an
unknown result. Keep the committed record; reconcile it through a fresh server and session
admission after the old lease expires. Never erase it to make admission succeed.

The specification drops a write reply after commit, verifies that the old authority stops
writing, expires the old lease and opens a fresh server. The recovered quest is active,
showing that the committed change was preserved. Other cases cover competing sessions,
forged fields, stale offers, sender floods, failed body admission and normal shutdown.
It also checks requests arriving during a yielding settlement, recovery of both traded inventories
after a lost reply, and full-stack refusals that preserve goods and pending loot.

For the main scenario, both clients run through the native entries. It checks level, objective
counts, claimed loot, reward, equipment, both trade inventories and filtered chat. It then
disconnects and reconnects the first player, advances through scheduled renewal, drains the
server and reconstructs a new server from storage alone. The recovered public view must equal
the saved view. See [persistence refusals](api.md#persistence) and
[the executable assertions](../examples/world/world.verify.luau).
