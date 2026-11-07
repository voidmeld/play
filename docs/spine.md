# Build a persistent world with Play

Run one server and three clients, each with a Compose and Facet screen:

```console
lute run examples/world/run.luau
```

After [tool setup](quickstart.md#prepare-the-tools), this command fetches the exact development
pins, mounts the clients in Verify's simulator and drives their controls with simulated pointer
input. Two players accept a quest, equip weapons, defeat an enemy, collect loot and claim rewards.
One crafts a shield and lists it; the other buys it. The third observes the shared combat and
market while retaining its own untouched journal and inventory. Chat reaches nearby clients.

The command checks the resulting state, closes the server and clients, and writes UI trees plus
the committed world to `.lute/tmp/world-demo`. It uses no Studio, account or live service.
These observations cover simulated Instances, scheduling, transport, layout, input and disposal.
They do not establish native rendering, physics, replication or live storage behavior.

Run the scenarios through Gate:

```console
lute run tools/gate.luau --file examples/world/demo.verify.luau --file examples/world/world.verify.luau
```

Both specifications are in the committed manifest. Gate also runs the standalone command.
The original scenario retains its assertions for trade, admission, stack capacity, competing
sessions, renewal, restart and uncertain writes.

## Follow the spine

| File | Responsibility |
| --- | --- |
| [content.luau](../examples/world/content.luau) | Replaceable roster, XP, items, objectives, loot, recipe, trade and market policy. |
| [state.luau](../examples/world/state.luau) | Saved-world decoder, character creation and committed-readback configuration. |
| [protocol.luau](../examples/world/protocol.luau) | Exact intentions and public projections, decoded in both directions. |
| [server.luau](../examples/world/server.luau) | Authority: leases, transactions, progression, inventory, quests, contact, crafting, market, trade and chat. |
| [roblox-server.luau](../examples/world/roblox-server.luau) | Storage, staged character admission and plain typed remote events. |
| [roblox-client.luau](../examples/world/roblox-client.luau) | Intent sending, response admission, bounded chat and presentation subscriptions. |
| [ui.luau](../examples/world/ui.luau) | Example-only Compose state and Facet controls. |
| [scene.luau](../examples/world/scene.luau) | Verify Instances and scheduler, native ports and explicit storage faults. |
| [simulator.luau](../examples/world/simulator.luau) | Isolated clients, detached queued messages, reflected UI hosts and pointer input. |
| [tour.luau](../examples/world/tour.luau) | The same executable tour used by the command and specification. |

The [API task table](api.md#task-table) links each system's contract and executable specification.
Imports use public components and adapters. Consumers supply content, identity and native operations.

## Authority and storage

The server creates a roster, resolves its configured destination and acquires a durable session
before admitting the actor, body and movement. Failed admission unwinds completed stages in reverse.
The scene uses reflected Players, Models, Parts and Humanoids, with characters under the world
hierarchy. Portable adapters receive typed identity projections of those Instances.

Every player mutation checks the current session token and lease. A transaction reads a fresh
world, edits a detached candidate and compares the expected revision and complete contents.
Only the actual committed readback becomes installed state. Missing or divergent replies hold
authority and refuse further writes; a later session recovers from saved bytes after lease expiry.
Renewal, departure and shutdown use the same persistence and profile-session contracts.
Failed reads refuse account creation and value changes without saving a default or overwriting
earned state. A closing session retains its leased profile for save retries while refusing gameplay;
after storage recovers, its committed close can release the lease.
The scene removes a departing player and body even when saving fails; server-side save custody
remains retryable. Profile unload and lease release bind the acquisition identity, so delayed
cleanup from an earlier departure cannot close a newly arrived session for the same account.
If departure meets an in-flight transaction, its scoped close queues one owned retry at the save
retry interval. The transaction settles first; close then saves its committed result and releases custody.
An unavailable or malformed startup read reports the failure and leaves the world uninstalled.
Admission retries read storage again; only a successful read can establish absence and create accounts.

This bounded example keeps at most eight accounts and its market book in one world record.
Trade and market settlement can therefore commit all touched inventories, balances and receipts
atomically. Listing removes one carried shield; buying spends five coin, grants one shield,
credits the seller and burns the configured fee. Receipt acknowledgement is in the same commit.
The assembly specification pauses a fill while another buyer contends and the seller departs.
It checks the single debit/grant, refused retry, conserved fee and goods, and saved proceeds on rejoin.
The optional market field preserves admission of earlier example records. A malformed book refuses.
For separate profile records, use the documented [trade](api.md#roblox-trade) and
[market settlement](api.md#roblox-market-settlement) recovery adapters.

The server owns recipe inputs, output, attack damage and reward amounts. Clients send only an
intention. Crafting projects a Play recipe, checks and removes its materials and validates the
output bag before committing. Combat admits a Play contact plan, waits through anticipation,
then rechecks the source session, native body epoch and health, equipment, current Part positions
and the host's obstruction observation. Observation can yield: admission rechecks its session
and recovery gate before reserving an attack,
and resolution uses the current target generation rather than the captured target identity.
Failed native observations refuse admission or cancel contact and finish recovery; they report
`contact_unavailable` through the host's reporting port.
One resolved contact applies damage. Recovery blocks repeated attacks; the scene
respawns the enemy after three seconds. Disconnection fences an outstanding contact.
Completed combat timers detach from their owner; shutdown cancels timers that have not fired.
Integer wall time serves saved records and leases; an injected elapsed clock serves combat.

## Subscribe from any UI

Play's runtime has no Compose or Facet imports. Its events and network ports remain typed
callbacks. `client.subscribe(listener)` returns an unsubscribe function and replays the latest
admitted response. Dispose the subscription with the presentation that owns it.

For a Compose consumer, the bridge is ordinary application code:

```luau
local initial: Protocol.View? = nil
local view = Compose.cell(initial)
local disconnect = client.subscribe(function(response)
    if response.view ~= nil then
        view:set(response.view)
    end
end)
```

A component reads `view` through `use(view)`. Its teardown calls `disconnect()` before disposing
the screen and cell. [ui.luau](../examples/world/ui.luau) implements that lifecycle, retains the
last admitted projection through transient notices and displays refusals without granting state.
Another UI can subscribe to exactly the same callback without reactive state.

Compose and `josha/Facet` are exact, example-only pins in
[dependencies.lock.luau](../dependencies.lock.luau); Verify has a verification role.
Facet binds the separately pinned Compose copy so controls and state share one graph.
Dependency checkouts retain upstream licenses and history. None belongs in a Play runtime export.

## Replace the host

Start with content and the saved-record boundary, then bind the typed server and client ports to
your native storage, authentication, character operations, observations, text filtering and remotes.
The simulator's storage failure controls and deterministic filter are verification inputs.
Keep source/destination configuration and globally unique session/acquisition IDs in the consumer.
Choose storage partitioning and recovery before increasing the example's bounds.
