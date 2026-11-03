# Systems

[Return to Play](../README.md).

Import one core family entry or an individual Roblox adapter. Each page describes state,
operations, host obligations and executable examples. The [generated API](api.md) carries exact declarations.

## Core

| System | Purpose |
| --- | --- |
| [bank](systems/bank.md) | Move items between carried inventory and a vault with bounded receipt replay. |
| [cast](systems/cast.md) | Queue a cast near its cooldown deadline and reject stale wakeups. |
| [character](systems/character.md) | Coordinate death observations, recovery timers and cancellable body replacement. |
| [chat](systems/chat.md) | Project channel audiences, parse commands and budget senders. |
| [control](systems/control.md) | Apply diminishing control durations with fixed reset deadlines. |
| [craft](systems/craft.md) | Validate and project recipe definitions into immutable material requirements. |
| [effects](systems/effects.md) | Advance timed effects, stacks, periodic deadlines and dispels. |
| [events](systems/events.md) | Resolve configured event schedules and track participation through reward-ticket recovery. |
| [identity](systems/identity.md) | Coordinate rosters, names, account snapshots and [character lease/retirement recovery](systems/character-leases.md). |
| [inventory](systems/inventory.md) | Manage stack capacity and replay-safe cargo custody, drops, recovery and delivery. |
| [ledger](systems/ledger.md) | Record value events, reservations and grouped economic operations. |
| [loot](systems/loot.md) | Draw configured loot and settle party need/greed/pass choices. |
| [mail](systems/mail.md) | Manage attachment custody, claims, returns and uncertain-write recovery. |
| [map](systems/map.md) | Track discoveries and project normalized world markers into a viewport. |
| [market](systems/market.md) | Coordinate listings, fills, fees, wallet holds and economic conservation. |
| [net](systems/net.md) | Apply token buckets independently to network senders. |
| [orders](systems/orders.md) | Advance work orders and realm patron payouts with durable claims. |
| [persistence](systems/persistence.md) | Provide session exclusion, profile save lifetime, ordered stores and bounded shutdown. |
| [professions](systems/professions.md) | Run skills, recipe transactions, harvesting, fishing and gathering sessions. |
| [progression](systems/progression.md) | Compose levels, talents, recovery, consumables, action bars, reputation, seasons and reward settlement. |
| [quest](systems/quest.md) | Index declarative objectives and coordinate quest progress projections, runs and claims. |
| [social](systems/social.md) | Coordinate parties, fellowships, warbands, formation, shared banks, allies, notes and chronicles. |
| [threat](systems/threat.md) | Select threat targets and freeze combat contribution eligibility at encounter end. |
| [trade](systems/trade.md) | Settle mutually confirmed, revisioned offers and retain recovery receipts. |
| [vendors](systems/vendors.md) | Buy and sell against configured vendors, finite stock and owner-scoped buyback. |

## Roblox adapters

| Adapter | Purpose |
| --- | --- |
| [camera](systems/roblox-camera.md) | Project configured follow-camera dynamics and obstruction response. |
| [bank](systems/roblox-bank.md) | Admit nearby vault transfers through durable profile receipts. |
| [chat](systems/roblox-chat.md) | Bind admitted users to native channels and check platform privacy. |
| [consumables](systems/roblox-consumables.md) | Coordinate durable item consumption before recovery dispatch. |
| [contact-markers](systems/roblox-contact-markers.md) | Share animation-track watchers and confirm stamped contacts once. |
| [conversation-camera](systems/roblox-conversation-camera.md) | Own conversation framing while allowing temporary obstruction and player override. |
| [cue-mixer](systems/roblox-cue-mixer.md) | Admit cue voices with retrigger, family caps and ducking. |
| [cue-playback](systems/roblox-cue-playback.md) | Play admitted cue identities and drive bounded frame effects. |
| [data-store](systems/roblox-data-store.md) | Retry injected operations with bounded exponential delay and jitter. |
| [equipment-queue](systems/roblox-equipment-queue.md) | Serialize equipment application per owner across yielding work. |
| [equipment-rig](systems/roblox-equipment-rig.md) | Scope construction attempts, join meshes and settle equipment slots. |
| [input-bindings](systems/roblox-input-bindings.md) | Project configured keyboard/gamepad bindings, labels and chords. |
| [input-contexts](systems/roblox-input-contexts.md) | Resolve native readiness against one deadline and adopt server templates. |
| [input-profile](systems/roblox-input-profile.md) | Coordinate device reach, action coverage and rollback-safe sessions. |
| [inventory](systems/roblox-inventory.md) | Coordinate authoritative profile inventory and receipt-backed rewards. |
| [mail](systems/roblox-mail.md) | Coordinate durable attachment holds, delivery, returns and recovery. |
| [market](systems/roblox-market.md) | Admit catalog-bound trades, merchant operations, item search and cached projections. |
| [market-settlement](systems/roblox-market-settlement.md) | Settle wallets against order books with durable holds, fences and receipts. |
| [market-profile-wallet](systems/roblox-market-profile-wallet.md) | Apply paired market wallet deltas without overwriting concurrent profile rewards. |
| [messaging](systems/roblox-messaging.md) | Publish and receive typed notices over injected messaging. |
| [movement-intake](systems/roblox-movement-intake.md) | Validate authoritative movement against body epochs, ordering and speed bounds. |
| [movement-sender](systems/roblox-movement-sender.md) | Send client movement through an epoch handshake and acknowledgment ledger. |
| [npc-motion](systems/roblox-npc-motion.md) | Project bounded planar movement and repair externally displaced bodies. |
| [party](systems/roblox-party.md) | Apply immutable party membership through an atomic store. |
| [professions](systems/roblox-professions.md) | Coordinate profession requests with authoritative world/profile commits. |
| [profile-sessions](systems/roblox-profile-sessions.md) | Own lease admission, coalesced saves, renewal and bounded close. |
| [profile-transfer](systems/roblox-profile-transfer.md) | Read and settle profiles under exact session identity and per-key exclusion. |
| [remote-events](systems/roblox-remote-events.md) | Share one dispatcher per channel and release native handlers safely. |
| [screen-labels](systems/roblox-screen-labels.md) | Admit anchored labels around reserved screen rectangles. |
| [social-host](systems/roblox-social-host.md) | Coordinate actor exclusion, social caches and membership settlement. |
| [social-fellowship](systems/roblox-social-fellowship.md) | Compose guild custody, privacy admission, invitations and member/steward projections. |
| [social-formation](systems/roblox-social-formation.md) | Coordinate multi-founder charters, fee custody and interrupted creation recovery. |
| [social-party](systems/roblox-social-party.md) | Compose invitations, projections, succession, reconnect and rally admission over durable parties. |
| [social-records](systems/roblox-social-records.md) | Coordinate ordered durable records, ledgers, inboxes and indexes. |
| [target-selection](systems/roblox-target-selection.md) | Cycle ordered candidates, select pointer hits and release distant targets. |
| [thumbstick](systems/roblox-thumbstick.md) | Convert touch displacement into dead-zone movement and a bounded knob. |
| [trade](systems/roblox-trade.md) | Coordinate revisioned exchange through durable holds, decisions and grants. |
| [travel-placement](systems/roblox-travel-placement.md) | Find clear, grounded arrival/entrance positions through injected geometry. |
