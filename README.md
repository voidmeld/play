# Play

Typed, game-agnostic MMORPG systems for Luau experiences: quests, mail, inventory, parties and
vendors. Each system is pure data and transition law; the game supplies its content, kinds and
host bindings.

The [public API inventory](docs/api.md) links every exported member to its declaration and signature.

`src/core` holds deterministic, engine-free law. `src/roblox` holds adapter lifecycles with
injected Roblox operations. `src/test-scene` holds Lute-only fake hosts and must be excluded
from Roblox module trees.

| Adapter | API |
| --- | --- |
| `src/roblox/profile-sessions.luau` | `new(owner, dependencies)` admits acquired leases, saves, coalesces requests, retries renewal and close, drains and disposes; the consumer validates persisted identity and lock readback |
| `src/roblox/data-store.luau` | `retryPolicy(policy)` supplies bounded operation retries and backoff with injected waits and jitter |
| `src/roblox/remote-events.luau` | `transport(host)` shares channel dispatchers and releases handlers; `limiter(budget)` tracks independent sender buckets |
| `src/roblox/chat.luau` | `seat`, `removeForeign`, `permission` and `directAllowed` bind native channel membership and platform privacy without transporting message text |
| `src/roblox/travel-placement.luau` | `place` and `entrance` select collision-free, grounded destinations through injected geometry operations |
| `src/roblox/messaging.luau` | `bind(host, topic, decode)` publishes notices asynchronously, filters incoming notices and owns disconnect error handling |

## Systems

| Path | Covers |
| --- | --- |
| `src/core/cast/queue.luau` | Configured bounded cast queues, cancellation tokens, due-time consumption and independent global cooldown, cast and channel windows |
| `src/core/control/diminishing.luau` | Per-category duration steps, fixed reset windows and shared family immunity with configured caps and pricing |
| `src/core/threat/table.luau` | Per-attacker accumulation, melee/ranged takeover, deterministic selection, taunt and host-qualified leash pruning |
| `src/core/effects/timed.luau` | Stack caps, duration replacement and refresh policy, periodic timer advancement, expiration, ordered dispels and presentation timing |
| `src/core/vendors/exchange.luau` | Atomic buy/sell quotations and inventory transitions, shared limited stock and owner-keyed expiring buyback receipts |
| `src/core/chat/channels.luau` | Configured say, realm, party, guild, warband and whisper audiences, bounded history, commands and sender budgets |
| `src/core/net/rate-limit.luau` | Pure token buckets and immutable sender-keyed budget transitions |
| `src/core/persistence/session-lock.luau` | Exclusive session acquisition, renewal, expiry takeover and owner-bound release |
| `src/core/quest/objectives.luau` | Objective kind catalogs, objective-to-event bindings and event matching |
| `src/core/quest/lifecycle.luau` | Objective projection, stillness and group constraints, and data-only validation using the shared objective catalog |
| `src/core/quest/counter.luau` | Level-eligible quest completion counts with supplied status, marker prefix and label copy |
| `src/core/quest/markers.luau` | Quest-giver priority, replay aliases, actionability, visibility and generic palette lookup |
| `src/core/quest/index.luau` | Supplied quest binding indexes, event matching and grouping by configured target fields |
| `src/core/mail/mailbox.luau` | Mail envelopes, recovery pointers, claim and return transitions, and attachment transfers with configured bounds and inventory bindings |
| `src/core/bank/vault.luau` | Bank transfers, bounded inventory adjustments, receipt replay and legacy state projection with configured inventory and profile bindings |
| `src/core/ledger/ledger.luau` | Append-only value events, atomic craft and trade groups, reservations, replay and derived balances with configured bounds |
| `src/core/market/book.luau` | Realm-local listings, ordered bundle fills, burning fees, receipts, operation fences and replay with configured bounds |
| `src/core/market/wallet.luau` | Market holds, consignment, claims, refunds, recovery and merchant trades with configured bounds |
| `src/core/market/conservation.luau` | Coin and goods conservation across configured wallet and book projections |
| `src/core/market/goods.luau` | Configured goods classification, tradeable holdings and equipment filters |
| `src/core/trade/exchange.luau` | Revisioned offers, locks, confirmations and settlement with configured bounds |
| `src/core/trade/receipt.luau` | Durable trade receipts, wire maps and recovery pointers with configured bounds and offer projection |
| `src/core/craft/recipes.luau` | Recipe projection and material-source requirements supplied by a configured rung catalog |
| `src/core/social/group.luau` | Group admission, relation snapshots, recovery tickets and roster privacy with configured bounds |
| `src/core/social/warband.luau` | Party coordination, command succession, invites, assistants and objective orders with configured policy |
| `src/core/social/fellowship.luau` | Durable membership, invitations, ranks, stewardship and configured creeds and identities |
| `src/core/social/formation.luau` | Founder consent, fee holds, formation expiry and completion with configured requirements |
| `src/core/social/guildbank.luau` | Shared stock, withdrawal limits, receipts, operation fences and expiry with configured policy |
| `src/core/social/guildledger.luau` | Profile-side pending deposits, refunds, claims and acknowledgements using vault inventory adjustments |
| `src/core/social/guildhome.luau` | Configured realm home-slot catalogs and projection |
| `src/core/social/rally.luau` | Authored live objective boards with configured kinds, titles, landmarks, realms and bounds |
| `src/core/social/allies.luau` | Qualified recent allies, privacy filtering and retention with configured qualification kinds and bounds |
| `src/core/social/profile.luau` | Social profile composition with supplied fellowship identities, allies and chronicle projectors |
| `src/core/social/notes.luau` | Preset phrase catalogs, bounded note delivery, expiry, read state and replay with configured limits |
| `src/core/social/chronicle.luau` | Vow offers, witnesses, fulfillment and terminal history with supplied definitions and authorities |
| `src/core/social/shape.luau` | Shared strict record, dense-list, projection and freezing helpers |
| `src/core/orders/work.luau` | Authored work-order steps, progress, completion and idempotent reward claims |
| `src/core/orders/patron.luau` | Authored realm order turn-ins, payout caps, calendar carry and replay with configured bounds |
| `src/core/progression/levels.luau` | Supplied XP curve validation, levels, brackets, awards and reward projections |
| `src/core/progression/grants.luau` | Supplied ability kits, unlock gates, curve validation and deterministic production registries |
| `src/core/progression/actionbar.luau` | Configured layered action bars, ownership, item references, edits, normalization and wire encoding |
| `src/core/progression/hearth.luau` | Supplied bind destinations and home mappings, return intent, reach and cooldown transitions |
| `src/core/progression/recovery.luau` | Death generations, release and recovery, safe position anchoring and bounded echo encoding |
| `src/core/progression/season.luau` | Permanent tracks, sequential milestones, rolling allowances, receipts, tier claims and configured retention |
| `src/core/progression/tracking.luau` | Quest tracking eligibility from supplied progress statuses |
| `src/core/progression/transactions.luau` | Atomic profile effects, receipt replay, order repair and pinned bounded history with supplied copy and collection bindings |
| `src/core/events/catalog.luau` | Validation and projection of supplied event schedules, rollout, reward and content hooks |
| `src/core/events/schedule.luau` | Active event ordering, deterministic rollout and configured reward, flag and content composition |
| `src/core/events/watch.luau` | Configured public event cycles, participant admission, work and protection credit, recovery and reward tickets |
| `src/core/loot/roll.luau` | Deterministic weighted loot draws without replacement, authored counts and namespaced receipts |
| `src/core/social/roster.luau` | Immutable party snapshot reconciliation, membership projection and local loot-cursor preservation with supplied identity and record bindings |
| `src/core/inventory/stacks.luau` | Bounded stacks, bag capacity, permanent-item rules and bound or worn holdings using vault arithmetic |

## Validate

`vendors.exchange.vendor(config)` supplies `validateVendor`, `buy`, `sell`, `buyStock`,
`sellBack` and `buyBack`. The consumer supplies item existence, sell values, inventory arithmetic,
capacity and quantity/stack/history bounds. `empty()` creates stock and buyback state.
`buy` and `sell` serve stateless unlimited vendors. Stateful operations return the next vendor
state, account and decision; the caller must commit both returned states together under its own
authority. A refusal retains both input identities. Buyback keys define the consumer's owner or
owner-and-merchant scope. Receipt ids are monotonic within the supplied state; consumed receipts
cannot be replayed against the resulting state. `now` is supplied by the host.

```sh
lute run tools/gate.luau
```

Use `lute run tools/gate.luau --tier fast` while editing. Its command producers include
`type-policy`, `types`, `test-manifest`, `spec-style`, `boundary`, `provenance`, `leakage`,
`public-surface`, `comments`, `format`, `lint` and `verify-check`; `specs` runs the test manifest.
The full gate also runs `clean-clone` on a clean committed HEAD.

Run `lute run tools/check-spec-style.luau` or `lute run tools/gate.luau --only spec-style`
to check spec syntax. Specs use `Bdd.create` and declare `local describe, it, expect` once.
The check rejects colon case registration, context expectations and dotted `Test.it`,
`Test.expect` and `Test.describe` calls in `*.verify.luau`, including untracked specs.
Any spec whose subject is Verify's raw harness API belongs in the path-based
`specStyle.exclude` selection in `tools/checks-config.luau`.

`cast.queue.rules(config)` captures `windowSec`, `maxRequeues` and `minRetrySec`.
`enqueue(state, payload, requeues, reason, remainingSec, now)` accepts only `on_gcd`
inside the positive inclusive queue window and below the retry bound. It replaces the
pending entry and increments its token; refusals retain state identity. `take(state,
token, now)` consumes a matching due entry once. `cancel(state, token)` cancels a
matching entry; omit the token to clear the queue. Keep the returned state for each
owner's lifetime so stale callbacks cannot reuse tokens. The host supplies a monotonic
clock, schedules wakeups, revalidates actor/context identity before retrying, and
cancels on departure or disposal. Payloads are retained by reference and must be
immutable. A refused new press leaves a pending entry intact; hosts that cancel on
every admitted press call `cancel` before admission. `windows(now, gcdSec, castSec,
channelSec)` creates independent deadlines; `remaining` and `ready` project them
against the supplied clock without scheduling or applying combat effects.

`threat.table.rules(config)` captures `meleeTakeover`, `rangedTakeover` and positive
`tauntLead`. `add(state, actorId, amount, inMelee)` returns an immutable next state
and a flag asking the host to refresh pursuit when the previous holder has no entry.
The challenger must strictly exceed the holder's total times the configured ratio;
holder additions retain selection. Signed finite amounts are supported. `targetFor`
chooses the highest nonnegative total, breaking ties by ascending actor id; an empty
or all-negative table selects the empty string. `taunt` sets the actor above the
whole table's maximum (with a zero floor), then reselects. There is no timed taunt
lock or threat decay. Actors use nonempty ids; hosts own validated finite state.

`empty()` supplies reset state. `remove` drops an actor and always reselects.
`prune(state, candidates)` removes absent, dead, ineligible or outside-leash actors,
reselecting only when entries were removed. It returns sorted removed ids, sorted
living outside-leash ids and prior engagement for host events and evade decisions.
The host supplies eligibility, melee and leash geometry, and owns pursuit overrides,
pending casts, evade readiness, lifecycle resets and atomic state installation.
`src/test-scene/threat.luau` supplies an isolated fake host and clock.
