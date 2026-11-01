# Systems

## Roblox sound and effects

`roblox/cue-mixer` owns retrigger admission, voice expiry and configured family ducking.
`roblox/cue-playback` owns cue-id voice lifetime and frame-driven effect progression.
Games own native voice operations, assets, catalogs, mix values, effect recipes and timing policy.

## Roblox NPC motion

`roblox/npc-motion` supplies bounded planar steps, leash geometry and cached/observed puppet projection.
Games own movement law, actor targeting, pathfinding, grounding queries, native body application and tuning.

## Roblox rig lifetime

`roblox/equipment-queue` serializes and fences asynchronous equipment application per character owner.
`roblox/contact-markers` coordinates ref-counted native animation contacts with stamped actions.
Games retain rigs, equipment fitting and attachment, clip selection, marker admission and playback policy.

## Roblox world labels

`roblox/screen-labels` supplies anchored nameplate admission and floating-text reserve avoidance.
Games own text, appearance, health policy, ranges, crowd limits, projection and rendering.

## Roblox targeting

`roblox/target-selection` supplies caller-ordered cycling, projected pointer selection and timed
range release. Games own hostility, eligibility, markers, frame data, native hit queries and tuning.

## Roblox camera

`roblox/camera` supplies configured follow-camera dynamics, springs and collision clearance.
`roblox/conversation-camera` supplies conversation ownership and safe-region framing candidates.
Games own world queries, native camera writes, speakers, UI measurement and all tuning.

## Roblox input

`roblox/input-contexts` supplies deadline-bound client readiness and fail-closed server template adoption.

`roblox/input-profile` owns device reach, exclusive action coverage and rollback-safe binding sessions.
`roblox/input-bindings` projects configured keyboard/gamepad bindings and chords.
`roblox/thumbstick` projects dead-zone movement and clamped knob displacement.
Games supply their complete action tables, tuning, device events, button surfaces and intent dispatch.
These modules neither render controls nor write authoritative game state.

## Account and character transactions

`core/identity/roster`, `name-claims`, `name-record`, `creation`, `deletion` and `creation-record`
are pure typed factories over `core/identity/policy`. `account-lease` owns fenced account leases.
The host applies plans through its own ordered persistence operations and returns actual readbacks
to the transaction. A lost response, future schema, foreign owner, stale revision or absent readback
does not advance success. The game owns account composition, saved keys, naming rules, creation
admission and routes. No factory supplies game data or performs persistence itself.

## Personal reward settlement

`core/progression/settlement` reconciles the run history and personal grant receipts. A retry must
agree with both ledgers before it reports success. The caller supplies package, run, role, reward
and grant policies. `copyPersonalState` validates and returns detached personal state;
`readQuality` validates and returns an immutable or detached quality value. Settlement freezes
its returned data. Neither reader may return mutable caller-owned data that freezing would affect.

## Consumable recovery

`core/progression/consumables` owns validated item registration, concurrent health and mana recovery,
interruption, replay order and timed food/elixir buffs. Games supply item definitions, resource
eligibility, movement tolerance, buff bounds and player text. Recovery returns state and gains;
the game's authoritative reducer installs them.

`roblox/consumables` coordinates use requests with injected character observations and durable
consumption. An uncertain write retains its receipt for retry. Recovery starts only after a
successful commit and a second character, health, movement and interruption check. Reopened
profiles reconcile consumed receipts. Games supply persistence, inventory changes, Roblox
observations, intent dispatch, remote wiring and presentation.

## Encounter contribution

`core/threat/contribution` records combat participation and effective credit, then freezes the
observed character, distance, life state and dungeon admission at encounter end. Games supply
relation law, categories, ranges, inactivity and recent-defeat windows, and activity thresholds.
The system decides eligibility from the recorded encounter; the game selects and persists rewards.

Input mounting uses typed callback dependencies. `input-profile.start` accepts missing optional
callbacks so it can report an incomplete host; accepted callbacks retain their declared argument
and result types. Game-facing requests and persisted records remain runtime-validated inputs.

[Return to Play](../README.md).

The game supplies content, limits, identities, and host operations.
The core returns data.
The game installs the returned state.

## Core

| Module | Function |
| --- | --- |
| [professions/skills](../src/core/professions/skills.luau), [crafting](../src/core/professions/crafting.luau), [harvest](../src/core/professions/harvest.luau), [fishing](../src/core/professions/fishing.luau), [session](../src/core/professions/session.luau), [gathering](../src/core/professions/gathering.luau) | Configured skills, recipe transactions, yields, fishing windows, interruption and replay-safe node claims. The [profession host](../src/roblox/professions.luau) coordinates injected profile, world and durable commit operations. |
| [progression/talents](../src/core/progression/talents.luau) | Saved talent state, request decoding, revisions, respec admission and atomic rank changes. |
| [progression/talent-ranks](../src/core/progression/talent-ranks.luau) | Point budgets, same-line tier gates, ranked spending and isolated role respecs over read-only game definitions. |
| [cast/queue](../src/core/cast/queue.luau) | Cast queues, cancellation tokens, and cooldown times. |
| [control/diminishing](../src/core/control/diminishing.luau) | Duration steps, reset times, and family immunity. |
| [threat/table](../src/core/threat/table.luau) | Threat totals, target selection, taunts, and actor removal. |
| [effects/timed](../src/core/effects/timed.luau) | Effect stacks, duration, periodic timers, and dispels. |
| [vendors/exchange](../src/core/vendors/exchange.luau) | Buy and sell operations, stock, and buyback receipts. |
| [chat/channels](../src/core/chat/channels.luau) | Chat audiences, history, commands, and sender budgets. |
| [net/rate-limit](../src/core/net/rate-limit.luau) | Token buckets and sender budgets. |
| [persistence/session-lock](../src/core/persistence/session-lock.luau) | Session acquisition, renewal, expiry, and release. |
| [quest/objectives](../src/core/quest/objectives.luau) | Objective kinds and event matching. |
| [quest/lifecycle](../src/core/quest/lifecycle.luau) | Objective progress, stillness, group limits, and validation. |
| [quest/counter](../src/core/quest/counter.luau) | Quest completion counts and level limits. |
| [quest/markers](../src/core/quest/markers.luau) | Quest markers, priority, visibility, and colors. |
| [quest/index](../src/core/quest/index.luau) | Quest indexes and event matching. |
| [mail/mailbox](../src/core/mail/mailbox.luau) | Mail, attachments, claims, returns, and recovery. |
| [bank/vault](../src/core/bank/vault.luau) | Bank transfers, inventory changes, receipts, and state projection. |
| [ledger/ledger](../src/core/ledger/ledger.luau) | Value events, craft groups, trade groups, balances, and reservations. |
| [market/book](../src/core/market/book.luau) | Market listings, fills, fees, receipts, and replay. |
| [market/wallet](../src/core/market/wallet.luau) | Market holds, claims, refunds, recovery, and merchant trades. |
| [market/conservation](../src/core/market/conservation.luau) | Coin and goods conservation between wallets and books. |
| [market/goods](../src/core/market/goods.luau) | Goods classes, trade limits, and equipment filters. |
| [trade/exchange](../src/core/trade/exchange.luau) | Trade offers, revisions, locks, confirmations, and settlement. |
| [trade/receipt](../src/core/trade/receipt.luau) | Trade receipts, wire maps, and recovery pointers. |
| [craft/recipes](../src/core/craft/recipes.luau) | Recipe projection and material requirements. |
| [social/group](../src/core/social/group.luau) | Group admission, relations, recovery tickets, and roster privacy. |
| [social/warband](../src/core/social/warband.luau) | Party coordination, command succession, invites, and orders. |
| [social/fellowship](../src/core/social/fellowship.luau) | Membership, invites, ranks, stewardship, creeds, and identities. |
| [social/formation](../src/core/social/formation.luau) | Founder consent, fee holds, expiry, and formation. |
| [social/guildbank](../src/core/social/guildbank.luau) | Shared stock, withdrawal limits, receipts, and expiry. |
| [social/guildledger](../src/core/social/guildledger.luau) | Pending deposits, refunds, claims, and acknowledgements. |
| [social/guildhome](../src/core/social/guildhome.luau) | Home slots and realm projection. |
| [social/rally](../src/core/social/rally.luau) | Live objective boards, titles, landmarks, and realms. |
| [social/allies](../src/core/social/allies.luau) | Recent allies, privacy filters, and retention. |
| [social/profile](../src/core/social/profile.luau) | Social profiles, fellowship identities, allies, and chronicles. |
| [social/notes](../src/core/social/notes.luau) | Preset phrases, notes, expiry, read state, and replay. |
| [social/chronicle](../src/core/social/chronicle.luau) | Vow offers, witnesses, completion, and history. |
| [social/shape](../src/core/social/shape.luau) | Record checks, list checks, projection, and freezing. |
| [orders/work](../src/core/orders/work.luau) | Work orders, progress, completion, and reward claims. |
| [orders/patron](../src/core/orders/patron.luau) | Realm orders, payouts, calendar carry, and replay. |
| [progression/levels](../src/core/progression/levels.luau) | XP curves, levels, brackets, awards, and rewards. |
| [progression/grants](../src/core/progression/grants.luau) | Ability kits, unlock gates, curves, and production registries. |
| [progression/actionbar](../src/core/progression/actionbar.luau) | Action bars, ownership, item references, edits, and wire encoding. |
| [progression/hearth](../src/core/progression/hearth.luau) | Bind destinations, home maps, return intent, reach, and cooldowns. |
| [progression/recovery](../src/core/progression/recovery.luau) | Death generations, release, recovery, positions, and echo encoding. |
| [progression/season](../src/core/progression/season.luau) | Permanent tracks, milestones, allowances, receipts, and tier claims. |
| [progression/tracking](../src/core/progression/tracking.luau) | Quest tracking from progress status. |
| [progression/transactions](../src/core/progression/transactions.luau) | Atomic profile effects, receipts, order repair, and history. |
| [events/catalog](../src/core/events/catalog.luau) | Event schedules, rollout rules, rewards, and content hooks. |
| [events/schedule](../src/core/events/schedule.luau) | Active events, rollout rules, rewards, flags, and content. |
| [events/watch](../src/core/events/watch.luau) | Public event cycles, participants, credit, recovery, and reward tickets. |
| [loot/roll](../src/core/loot/roll.luau) | Weighted loot draws, counts, and receipts. |
| [loot/decision](../src/core/loot/decision.luau) | Party need, greed and pass: a fixed window, one saved result and round robin when all pass. |
| [social/roster](../src/core/social/roster.luau) | Party snapshots, membership, and local loot cursors. |
| [inventory/stacks](../src/core/inventory/stacks.luau) | Item stacks, bag capacity, permanent items, and bound or worn items. |

## Roblox adapters

| Module | Function |
| --- | --- |
| [profile-sessions](../src/roblox/profile-sessions.luau) | Lease admission, saves, renewal, close, drain, and disposal. |
| [data-store](../src/roblox/data-store.luau) | Operation retries, delays, and jitter. |
| [remote-events](../src/roblox/remote-events.luau) | Shared channel dispatchers and handler release. |
| [chat](../src/roblox/chat.luau) | Native channel membership and platform privacy. |
| [travel-placement](../src/roblox/travel-placement.luau) | Grounded destinations without collisions. |
| [messaging](../src/roblox/messaging.luau) | Notice publication, input filters, and disconnect errors. |

The game validates persisted identity and session lock readback.
The chat adapter does not transport message text.

## Vendor state

`vendors.exchange.vendor(config)` creates the vendor operations.
The game supplies item checks, sell values, inventory arithmetic, capacity, and bounds.
`empty()` creates stock and buyback state.
`buy` and `sell` support unlimited vendors without vendor state.
Stateful operations return the next vendor state, account, and decision.

Install the returned vendor state and account together.
A refusal returns both input objects without changes.
Use buyback keys for an owner or an owner and merchant pair.
Receipt IDs increase within the supplied state.
A consumed receipt cannot apply again to the resulting state.
Supply the host clock as `now`.

## Cast queues

`cast.queue.rules(config)` uses `windowSec`, `maxRequeues`, and `minRetrySec`.
`enqueue` accepts only `on_gcd` within the positive queue window and below the retry bound.
The window includes its upper limit.
An accepted entry replaces the pending entry and increases its token.
A refusal returns the input state object.
`take` consumes a matching entry once, when it is due.
`cancel` cancels the entry with the supplied token.
Without a token, `cancel` clears the queue.

Keep each owner's returned state for the owner's lifetime.
This prevents old callbacks from reusing tokens.
Supply a monotonic clock.
Schedule queue wakeups in the host.
Check actor and context identity before each retry.
Cancel the queue on departure or disposal.
Keep payload objects immutable.
The queue keeps each payload by reference.

A refused press keeps the pending entry.
If each admitted press must clear the queue, call `cancel` before admission.
`windows` creates independent cooldown, cast, and channel deadlines.
`remaining` and `ready` read these deadlines against the supplied clock.
These operations do not schedule work or apply combat effects.

## Threat

`threat.table.rules(config)` uses `meleeTakeover`, `rangedTakeover`, and positive `tauntLead`.
`add` returns the next state and a pursuit refresh flag.
The flag is true when the previous holder has no entry.
A challenger must exceed the holder's total times the applicable takeover ratio.
An addition from the holder keeps the selection.
Amounts can be positive or negative finite numbers.

`targetFor` selects the highest total that is zero or more.
Equal totals use ascending actor IDs.
An empty table, or a table with only negative totals, selects the empty string.
`taunt` raises the actor above the table maximum, with a zero floor.
It then selects the target again.
The system has no timed taunt lock or threat decay.

Use nonempty actor IDs.
Validate finite state values in the host.
`empty` creates reset state.
`remove` removes an actor and selects the target again.
`prune` removes absent, dead, ineligible, or outside-leash actors.
It selects the target again only after removals.
It returns sorted removed IDs, sorted living outside-leash IDs, and prior engagement.

Supply eligibility, melee geometry, and leash geometry from the host.
Keep pursuit overrides, pending casts, evade readiness, and lifecycle resets in the host.
Install the returned state atomically.
The test scene supplies an isolated fake host and clock.
