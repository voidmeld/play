# Public API

### `roblox.npc-motion.projection`

Takes epsilon, facingEpsilon and minimumDt. Returns plan, groundedPivotY and anchoredSurfaceY.
Projection compares both cached and observed transforms, so an externally displaced body is repaired.
Exports Planar, Point, Observed, Projection and Changes.

### `roblox.npc-motion.movement`

Takes an epsilon and returns moveToward and insideLeash. Movement limits a planar step and preserves
the source elevation. A missing leash origin or radius admits the point. Games own pursuit, path
selection, control state, leash reset, terrain queries and authoritative commits.

### `roblox.npc-motion.distance`

Returns planar distance between two Point values.

### `roblox.equipment-queue.create`

Takes Deps<P, C> with spawn, active, current, perform and warn. Returns Queue<P, C> with request,
invalidate, forget, generation, running and dispose. Applications drain serially per player,
coalesce to the newest pending body and receive a generation fence across yielding host work.
The caller owns service lifetime, body identity, equipment policy and attachment operations.

### `roblox.contact-markers.create`

Takes stamp, listen, marker and admit operations. Returns watch, onContact, confirmed and retrigger.
Ref-counted watchers bind tracks once, reject a marker from an old action stamp, present one contact
per admitted stamp, cancel older waiters and release the final watcher. The caller owns native
track discovery, marker names, clip identity, health and world admission, and playback.

### `roblox.screen-labels.create`

Takes maximum, farDistance, farCount, focusPriority and defaultPriority. Returns placementForScreen,
which admits priority-ordered anchored labels against caller reserves, topbar and screen bounds.
Overlapping or overflow labels collapse without moving their anchors. Exports ScreenRect,
ScreenPlate and ScreenPlacement.

### `roblox.screen-labels.rect`

Builds left/top/right/bottom bounds from a position and nonnegative-clamped dimensions.

### `roblox.screen-labels.rectsOverlap`

Tests strict overlap. Touching edges are clear.

### `roblox.screen-labels.contains`

Tests inclusive containment of an inner rectangle in an outer rectangle.

### `roblox.screen-labels.horizontalAvoidance`

Returns the shorter horizontal escape for overlapping label and reserved band, with a caller gap.

### `roblox.target-selection.pickNext`

Cycles a caller-ordered list, wrapping and recovering from an absent current identifier.

### `roblox.target-selection.create`

Takes a coordinate reader and returns pickNearestToTap and tapSelection over `Candidate<P>`.
Radius admission is inclusive; equal-distance candidates use lexical identifiers. Exact hits win.

### `roblox.target-selection.release`

Returns a Release with observe and reset, taking positive range and grace duration. In-range
observations reset the clock seam; missing positions count as outside. Exports Release and Candidate.

## Roblox input

### `roblox.camera.create`

Takes Tuning and returns zoomLimits, isCameraStructure, smoothObstruction, obstructedDistance,
newSpring, springStep, shoulderOffset, sprintWiden, fovTarget and yields. Exports Tuning,
Spring and Obstruction. Games own camera mode admission, tuning, collision queries and transforms.

### `roblox.conversation-camera.create`

Takes spring operations and Tuning. Returns new, step, space, views, choose and cameraGesture.
Exports Tuning, Point, Rect, View and State. Framing chooses available space beside a caller's
card and generates configured view candidates; the caller tests their actual sightlines.
Temporary unavailability permits reacquisition. Player override or departure releases ownership
until the conversation key changes. Games supply speaker identity, two-person bounds, measurements,
angle preferences and native camera application.

### `roblox.input-profile.create`

Takes named `Profile` records and mounted/refused phase names. Returns profile, reach, parity,
coverage, deviceOfInputName and start, with DEVICES. Exports Device, TouchAffordance, Action,
Profile and Session. A session owns only its requested actions, dispatches through injected bind,
thumbstick, dispatch and intent operations, rolls back partial mounts, and rejects input after stop.
Screen actions use the caller's existing surface. Mouse input belongs to the keyboard device family.

### `roblox.input-bindings.create`

Takes `Action<C>` rows, display labels and a chord modifier name. Returns actions, GAMEPAD_GAPS,
CHORD_MODIFIER, get, keyboardNames, primaryKeyboard, gamepad, matches, keyboardLabel,
gamepadLabel, matchesCode, matchesInput and forContext. The caller supplies enum values and a held
button query. Action names, contexts, keys, labels and touch affordances belong to the game.

### `roblox.thumbstick.create`

Takes radiusPx, deadZone, zoneWidth and zoneHeight. Returns anchorAt, drag, release, vectorFor,
knobFor and the configured RADIUS_PX, DEAD_ZONE, ZONE_WIDTH_SCALE and ZONE_HEIGHT_SCALE.
Exports Vec2 and Stick. The caller owns touch tracking, rendering and movement submission.

## [`src/core/social/membership.luau`](../src/core/social/membership.luau)

### `core.social.membership.membership`

Creates immutable party membership with named leader invitations, reserved seats, explicit
accept/decline/leave/kick, acknowledged leader transfer, absence recovery and disband tombstones.
The caller supplies realm admission, capacity, time and identifier bounds, invitation and recovery
durations and default loot mode. Authority and platform group admission remain caller-owned.
Returns projectState, open, invite, accept, decline, leave, kick, transferLeader,
acceptLeaderTransfer, disband, setLootMode, markAbsent, markPresent and sweep.

## [`src/roblox/party.luau`](../src/roblox/party.luau)

### `roblox.party.party`

Creates an atomic-store host for a membership core, exact record schema and caller boundary text.
Returns mount, SCHEMA_VERSION and REASONS. Mount takes an atomic update store, party-key builder
and membership reader. The host resets captured results whenever a store retries its transform,
refuses failed or mismatched readbacks and performs reads with a cancelling transform.
Only the configured schema is admitted. Store namespaces, engine wiring, admission and notices
remain in the consumer. The host provides no membership index or matchmaking.

## Account and character identity

The `core/identity` factories take `policy.Policy`. The caller owns canonical name validation,
registry-key construction and validation, profile partition keys, destination syntax, allowed
realms and peoples, account and per-realm capacity, and level bounds. Keep these callbacks pure
and stable for the lifetime of the returned slice. Creation choices and routing admission belong
to the caller. The modules preserve schema version 1 and never perform host writes.

### `core.identity.roster.create`

Returns detached roster validation, stored validation, add/remove, monotonic played/level updates,
destination updates and recent-play realm projections. Stored validation permits retired realm
and people identifiers; ordinary admission uses the supplied policy. IDs remain independent of names.
Exports `CharacterIdentity` and `Roster` types.

### `core.identity.name-claims.create`

Returns validated atomic claim, exact-owner release and advisory availability transforms. A claim
from a different registry key refuses. Case and canonicalization come entirely from the policy.
Exports `Claim`, `ClaimStatus`, `ReleaseStatus` and `Availability` types.

### `core.identity.name-record.create`

Returns immutable revisioned claim records, validation, copy/equality, empty records, claim/release
and availability. Releases retain a tombstone. Revision exhaustion refuses mutation; foreign
owners survive stale release. The caller supplies the entire key namespace.
Exports `Record` and `Claim` types.

### `core.identity.creation.create`

Returns a typed creation transaction: `prepare`, `plan`, `observeName`, `observeProfile`,
`observeRoster`, `requestRollback`, `observeRollback`, `observeLeaseRelease` and `takeover`.
Also supplies ordinary/stored validation, fingerprinting and copies. Plans do not perform writes.
Each observation checks the operation fingerprint, revision, fence and exact readback. Absent,
foreign, stale and future records remain distinct refusals. Takeover advances the lease generation
without changing the original creation identity. Rollback requires proof that owned names were released.
Exports `State`, `Prepared`, `Phase`, `Plan`, `Result`, `Accepted` and `Rejected` types.

### `core.identity.deletion.create`

Returns a typed deletion transaction with prepare/plan, roster-removal observation, name-release
observation, lease-release observation, rollback, takeover, validation, fingerprinting and copies.
An exact roster readback precedes name release; a received post-release read precedes completion.
Exports `State`, `Prepared`, `Phase`, `Plan`, `Result`, `Accepted` and `Rejected` types.

### `core.identity.creation-record.create`

Returns immutable prepared profile seeds and committed receipts, their validators, copies and
cross-record identity matching. Seeds can be issued only after profile preparation; receipts only
after the roster commit. Both retain the original generation across takeover. Exports `Seed` and
`Receipt` types.

### `core.identity.account-lease.SCHEMA_VERSION`
### `core.identity.account-lease.MAX_REVISION`
### `core.identity.account-lease.MAX_FENCE`
### `core.identity.account-lease.MAX_SAFE_INTEGER`
### `core.identity.account-lease.MAX_ID_BYTES`

Persisted lease schema and finite numeric/string bounds. Exports the `Lease` type.

### `core.identity.account-lease.validate`
### `core.identity.account-lease.copy`

Return a detached immutable lease or nil for an invalid shape, identity or generation.

### `core.identity.account-lease.empty`

Creates an unowned lease for a positive integer account ID.

### `core.identity.account-lease.equal`

Compares validated lease values, including the acquisition ID and generation.

### `core.identity.account-lease.acquire`

Acquires or exactly replays a session/acquisition pair using injected time and duration.
An unexpired foreign owner holds the lease; takeover at expiry increments its fence and revision.

### `core.identity.account-lease.renew`

Renews only the exact live session, fence and revision. Stale or expired authority refuses.

### `core.identity.account-lease.release`

Releases only the exact session and generation; already-released readback is idempotent.

### `core.identity.value.check`
### `core.identity.value.fields`

Internal plain-record inspection used by identity codecs. Consumers use the system factories.

### `test-scene.identity.accountLimit`
### `test-scene.identity.realmLimit`
### `test-scene.identity.minLevel`
### `test-scene.identity.maxLevel`
### `test-scene.identity.realms`
### `test-scene.identity.peoples`
### `test-scene.identity.profilePartitionKey`
### `test-scene.identity.registryKey`
### `test-scene.identity.validDestination`
### `test-scene.identity.validRegistryKey`
### `test-scene.identity.validateName`

Neutral identity policy fixture for Lute specifications. Its claim and profile namespaces differ
from consumer namespaces. Exclude this test fixture from shipped module trees.

## Profession systems

### `core.professions.skills.create`

Takes a profession catalogue, skill cap, primary slot count, start skill, advancement chances,
recipe lookups and a saved quest-input projector. Returns normalization, detached copy, learn,
unlearn, recipe admission, trainer projection and skill advancement operations. The caller owns
catalogue order, trainer eligibility, costs and quest rewards. Refusal does not mutate the input.

### `core.professions.crafting.create`

Takes skill operations, recipe and quality policies and a stack limit. Returns plan and craft.
Craft checks profession, recipe knowledge, required skill, stations, reagents, output stack and
entry capacity before returning detached inventory and skill state. Stack changes use inventory/stacks.
Quality selection and recipe content come from the caller.

### `core.professions.harvest.create`

Takes skill operations and the skinning profession ID. Returns admission, node harvesting and
skinning operations. The caller supplies each node or skin row, including yields, extras, thresholds
and random samples. Failed admission returns the unchanged skill state.

### `core.professions.fishing.create`

Takes skill operations, profession ID, waiting range, bite window and zone catch/junk tables.
Returns idle, cast, observe, hook, weighted selection and reel operations. Injected time controls
the bite window; junk catches never grant advancement. The caller owns catch content and weights.

### `core.professions.session.create`

Takes movement tolerance and a host admission policy. Returns begin and check for timed work.
The caller supplies clock, position, health, life and combat samples. Damage, movement, combat,
death or a host refusal interrupts before completion.

### `core.professions.gathering.create`

Takes allowed affiliations, multiplier bounds and a yield resolver. Returns emptyState, projectNode,
computeYield and step for timed gathering, respawn slots and replay-safe claims. A repeated event
returns its original amount. Invalid shapes, backwards clocks and refused yield policy return nil.
Population calculations, resource definitions and yield policy remain with the caller.

### `roblox.professions.decodeIntent`

Reads a string action and optional string arguments. Unknown actions are ignored by the host.

### `roblox.professions.new`

Takes typed profile reads/updates, session context, clock, randomness, world queries, message delivery,
receipt identity and durable commit operations, plus the profession policies. Returns handle,
interrupt, step, forget and harvestedSlots. The host owns active work, fishing lines, harvest slots,
skin claims, stock windows, repair quotes and pending craft saves. A failed save blocks subsequent
actions until that context settles. The game retains trainer admission, recipes, nodes, yields,
quest inputs, progress rewards, repair law, profile composition and all mounted input/presentation.
Hosts must serialize updates and commits through their authoritative store, provide trusted content
and random samples, call step with the game clock, and call forget on departure. These operations
do not establish persisted durability by themselves.

## [`src/core/quest/run.luau`](../src/core/quest/run.luau)

### `core.quest.run.run`

Creates immutable, revisioned run progress with exact event receipts, checkpoints,
disconnect recovery, leader succession, wipes and replacement seats. The caller supplies
package validation, checkpoint validity, wipe progress, replacement admission and member limits.
The typed package stays private to the injected policies; describe projects only generic run fields.
Returns transition, projectRunState and refusal reasons. Clocks must be finite and monotonic.
Reusing an event ID with another fingerprint refuses without advancing state.

## [`src/core/quest/claims.luau`](../src/core/quest/claims.luau)

### `core.quest.claims.claims`

Creates reservation records and pure atomic-store transforms for claim, renewal, close,
write-through and replacement rosters. The caller supplies lease and record durations,
member count, carrier contract, text limit and retry delays. Writes require a current job
lease and a newer run revision. Rejoin targets validate membership and record expiry.
The host remains responsible for atomic storage, ordered writes and destination authority.

## [`src/core/progression/settlement.luau`](../src/core/progression/settlement.luau)

### `core.progression.settlement.settlement`

Creates per-character run reward history and replay-safe settlement. Package, run and personal
state readers, reward qualities, role eligibility, reward choice and personal grants are injected.
A grant must be pure and return a detached state. Failed grants do not advance reward history.
Replay requires matching receipts in both ledgers; another transaction cannot reward the same run.
Returns emptyRewardHistory and applyPersonalReward. Reward content and grant limits belong to the caller.

## [`src/core/progression/talents.luau`](../src/core/progression/talents.luau)

### `core.progression.talents.default`

Creates empty ranks with revision and respec count zero.

### `core.progression.talents.toLoadout`

Copies state ranks into a role loadout.

### `core.progression.talents.fromLoadout`

Copies role ranks into state with the supplied revision.

### `core.progression.talents.decodeIntent`

Reads exact plain view, select and respec requests. Talent IDs contain 1 to 128 bytes.
Wire revisions are nonnegative integers. The existing wire contract also permits positive infinity.
Persisted counts must be finite.

### `core.progression.talents.change`

Checks the revision and respec admission before calling the supplied rank operation.
An accepted change returns detached ranks and increases the revision once.
A refused change returns nil and its reason. A view returns the input state.
The caller must supply validated state, a decoded intent and a pure rank operation.

### `core.progression.talents.rules`

Takes a runtime identity reader and a loadout compiler.
Returns normalize and load operations. Normalize rejects invalid saved fields, identity, ranks or compilation.
Load refunds an invalid save to empty state only when that state compiles for the supplied runtime.
The game supplies talent rules, point limits and ability compilation.

The headings list the module exports.
Each source link gives the declaration and signature.
The game supplies host operations to Roblox adapters.
Test scenes run only in Lute.

[Return to Play](../README.md).

## [`src/core/bank/vault.luau`](../src/core/bank/vault.luau)

### `core.bank.vault.adjust`

### `core.bank.vault.vault`

## [`src/core/cast/queue.luau`](../src/core/cast/queue.luau)

### `core.cast.queue.cancel`

### `core.cast.queue.empty`

### `core.cast.queue.ready`

### `core.cast.queue.remaining`

### `core.cast.queue.rules`

### `core.cast.queue.take`

### `core.cast.queue.windows`

## [`src/core/chat/channels.luau`](../src/core/chat/channels.luau)

### `core.chat.channels.allows`

### `core.chat.channels.consume`

### `core.chat.channels.pairName`

### `core.chat.channels.parse`

### `core.chat.channels.trim`

### `core.chat.channels.window`

## [`src/core/control/diminishing.luau`](../src/core/control/diminishing.luau)

### `core.control.diminishing.empty`

[Source](../src/core/control/diminishing.luau). Signature: `empty(): State`.
Creates an empty category and family ledger.

### `core.control.diminishing.clone`

[Source](../src/core/control/diminishing.luau). Signature: `clone(state: State): State`.
Copies the ledger and each bucket.
The copy includes expired entries.

### `core.control.diminishing.rules`

[Source](../src/core/control/diminishing.luau). Signature: `rules(config: Config)`.

The configuration supplies positive `resetSec`, duration `multipliers`, and `categories`.
The multiplier list must contain at least one value.
Each multiplier must be between zero and one, inclusive.
Each category supplies a family key, duration cap, and immunity price and bounds.
Family keys must differ from all category keys.
Categories can share a family.
The price and bounds must be zero or more.
The maximum must be at least the minimum.

The returned `apply(state, category, baseDurationSec, nowSec)` returns a detached `dr` ledger.
Each result also has `grantedSec`, `multiplier`, `step`, and `immune`.
The configuration is a copy.

Use nonnegative integer counts, finite deadlines, and a monotonic clock.
A live family window prevents application before the category count changes.
Otherwise, the category count selects a multiplier.
Counts beyond the list use the last multiplier.
The first counted application starts the fixed reset window.
Later applications keep its deadline.
Equality at an expiry permits application or reset.
The system applies the duration cap before multiplication.

Positive granted duration starts family immunity at the application clock.
The granted duration times the price gives the immunity duration, within the configured bounds.
A zero maximum disables immunity.
Expired family counts continue when the family starts again.
The returned ledger keeps expired buckets.

Unknown categories and nonfinite clocks return an immune result.
Ledger values stay the same.
Nonpositive or nonfinite requested durations grant zero but consume a category step.
The `step` and `immune` fields describe the multiplier.
Zero granted seconds do not necessarily indicate immunity.

Supply category names and caps from game tuning.
Install the returned state atomically.
Keep effect lifetimes in the host.
Reset the ledger at lifecycle boundaries.
Do not clear its ledger when you cleanse an effect.

## [`src/core/craft/recipes.luau`](../src/core/craft/recipes.luau)

### `core.craft.recipes.catalog`

## [`src/core/effects/timed.luau`](../src/core/effects/timed.luau)

### `core.effects.timed.advance`

### `core.effects.timed.advanceTimes`

### `core.effects.timed.application`

### `core.effects.timed.count`

### `core.effects.timed.dispelFirst`

### `core.effects.timed.expired`

### `core.effects.timed.refresh`

### `core.effects.timed.remainingFraction`

### `core.effects.timed.remainingSec`

## [`src/core/events/catalog.luau`](../src/core/events/catalog.luau)

### `core.events.catalog.catalog`

### `core.events.catalog.finite`

## [`src/core/events/schedule.luau`](../src/core/events/schedule.luau)

### `core.events.schedule.schedule`

## [`src/core/events/watch.luau`](../src/core/events/watch.luau)

### `core.events.watch.watch`

## [`src/core/internal/value.luau`](../src/core/internal/value.luau)

### `core.internal.value.dense`

### `core.internal.value.freezeDeep`

### `core.internal.value.identifier`

### `core.internal.value.opaque`

### `core.internal.value.raw`

### `core.internal.value.record`

### `core.internal.value.whole`

## [`src/core/inventory/stacks.luau`](../src/core/inventory/stacks.luau)

### `core.inventory.stacks.stacks`

## [`src/core/ledger/ledger.luau`](../src/core/ledger/ledger.luau)

### `core.ledger.ledger.ledger`

## [`src/core/loot/roll.luau`](../src/core/loot/roll.luau)

### `core.loot.roll.roll`

## [`src/core/loot/decision.luau`](../src/core/loot/decision.luau)

### `core.loot.decision.decision`

## [`src/core/mail/mailbox.luau`](../src/core/mail/mailbox.luau)

### `core.mail.mailbox.mailbox`

## [`src/core/market/book.luau`](../src/core/market/book.luau)

### `core.market.book.book`

## [`src/core/market/conservation.luau`](../src/core/market/conservation.luau)

### `core.market.conservation.conservation`

## [`src/core/market/goods.luau`](../src/core/market/goods.luau)

### `core.market.goods.catalog`

## [`src/core/market/wallet.luau`](../src/core/market/wallet.luau)

### `core.market.wallet.wallet`

## [`src/core/net/rate-limit.luau`](../src/core/net/rate-limit.luau)

### `core.net.rate-limit.consume`

### `core.net.rate-limit.newBucket`

### `core.net.rate-limit.tryConsume`

## [`src/core/orders/patron.luau`](../src/core/orders/patron.luau)

### `core.orders.patron.patron`

## [`src/core/orders/work.luau`](../src/core/orders/work.luau)

### `core.orders.work.emptyState`

### `core.orders.work.projectOrder`

### `core.orders.work.projectState`

### `core.orders.work.step`

## [`src/core/persistence/session-lock.luau`](../src/core/persistence/session-lock.luau)

### `core.persistence.session-lock.isLocked`

### `core.persistence.session-lock.release`

### `core.persistence.session-lock.tryAcquire`

## [`src/core/progression/actionbar.luau`](../src/core/progression/actionbar.luau)

### `core.progression.actionbar.actionbar`

## [`src/core/progression/grants.luau`](../src/core/progression/grants.luau)

### `core.progression.grants.grants`

## [`src/core/progression/hearth.luau`](../src/core/progression/hearth.luau)

### `core.progression.hearth.hearth`

## [`src/core/progression/levels.luau`](../src/core/progression/levels.luau)

### `core.progression.levels.levels`

## [`src/core/progression/recovery.luau`](../src/core/progression/recovery.luau)

### `core.progression.recovery.recovery`

## [`src/core/progression/season.luau`](../src/core/progression/season.luau)

### `core.progression.season.season`

## [`src/core/progression/tracking.luau`](../src/core/progression/tracking.luau)

### `core.progression.tracking.tracking`

## [`src/core/progression/transactions.luau`](../src/core/progression/transactions.luau)

### `core.progression.transactions.transactions`

## [`src/core/quest/counter.luau`](../src/core/quest/counter.luau)

### `core.quest.counter.counter`

## [`src/core/quest/index.luau`](../src/core/quest/index.luau)

### `core.quest.index.index`

## [`src/core/quest/lifecycle.luau`](../src/core/quest/lifecycle.luau)

### `core.quest.lifecycle.lifecycle`

## [`src/core/quest/markers.luau`](../src/core/quest/markers.luau)

### `core.quest.markers.markers`

## [`src/core/quest/objectives.luau`](../src/core/quest/objectives.luau)

### `core.quest.objectives.catalog`

## [`src/core/social/allies.luau`](../src/core/social/allies.luau)

### `core.social.allies.allies`

## [`src/core/social/chronicle.luau`](../src/core/social/chronicle.luau)

### `core.social.chronicle.chronicle`

## [`src/core/social/fellowship.luau`](../src/core/social/fellowship.luau)

### `core.social.fellowship.fellowship`

## [`src/core/social/formation.luau`](../src/core/social/formation.luau)

### `core.social.formation.formation`

## [`src/core/social/group.luau`](../src/core/social/group.luau)

### `core.social.group.group`

## [`src/core/social/guildbank.luau`](../src/core/social/guildbank.luau)

### `core.social.guildbank.guildbank`

## [`src/core/social/guildhome.luau`](../src/core/social/guildhome.luau)

### `core.social.guildhome.guildhome`

## [`src/core/social/guildledger.luau`](../src/core/social/guildledger.luau)

### `core.social.guildledger.guildledger`

## [`src/core/social/notes.luau`](../src/core/social/notes.luau)

### `core.social.notes.notes`

## [`src/core/social/profile.luau`](../src/core/social/profile.luau)

### `core.social.profile.profile`

## [`src/core/social/rally.luau`](../src/core/social/rally.luau)

### `core.social.rally.rally`

## [`src/core/social/roster.luau`](../src/core/social/roster.luau)

### `core.social.roster.roster`

## [`src/core/social/shape.luau`](../src/core/social/shape.luau)

### `core.social.shape.array`

### `core.social.shape.boolean`

### `core.social.shape.dense`

### `core.social.shape.denseLength`

### `core.social.shape.exact`

### `core.social.shape.freezeDeep`

### `core.social.shape.freezeDeepWithKeys`

### `core.social.shape.map`

### `core.social.shape.number`

### `core.social.shape.onlyFields`

### `core.social.shape.opaque`

### `core.social.shape.raw`

### `core.social.shape.string`

### `core.social.shape.whole`

## [`src/core/social/warband.luau`](../src/core/social/warband.luau)

### `core.social.warband.warband`

## [`src/core/threat/table.luau`](../src/core/threat/table.luau)

### `core.threat.table.empty`

### `core.threat.table.prune`

### `core.threat.table.remove`

### `core.threat.table.rules`

### `core.threat.table.targetFor`

## [`src/core/trade/exchange.luau`](../src/core/trade/exchange.luau)

### `core.trade.exchange.exchange`

## [`src/core/trade/receipt.luau`](../src/core/trade/receipt.luau)

### `core.trade.receipt.receipts`

## [`src/core/vendors/exchange.luau`](../src/core/vendors/exchange.luau)

### `core.vendors.exchange.empty`

### `core.vendors.exchange.vendor`

## [`src/roblox/chat.luau`](../src/roblox/chat.luau)

### `roblox.chat.directAllowed`

### `roblox.chat.permission`

### `roblox.chat.removeForeign`

### `roblox.chat.seat`

## [`src/roblox/data-store.luau`](../src/roblox/data-store.luau)

### `roblox.data-store.retryPolicy`

## [`src/roblox/messaging.luau`](../src/roblox/messaging.luau)

### `roblox.messaging.bind`

## [`src/roblox/profile-sessions.luau`](../src/roblox/profile-sessions.luau)

### `roblox.profile-sessions.new`

## [`src/roblox/remote-events.luau`](../src/roblox/remote-events.luau)

### `roblox.remote-events.transport`

## [`src/roblox/travel-placement.luau`](../src/roblox/travel-placement.luau)

### `roblox.travel-placement.entrance`

### `roblox.travel-placement.place`

## [`src/test-scene/cast.luau`](../src/test-scene/cast.luau)

### `test-scene.cast.new`

## [`src/test-scene/clock.luau`](../src/test-scene/clock.luau)

### `test-scene.clock.new`

## [`src/test-scene/diminishing.luau`](../src/test-scene/diminishing.luau)

### `test-scene.diminishing.new`

[Source](../src/test-scene/diminishing.luau). Signature: `new(config: Config)`.
Creates an isolated ledger host with a fake `clock`.
It supplies `apply(category, durationSec)` and detached `snapshot()` values.
It does not schedule work or install effects.

## [`src/test-scene/effects.luau`](../src/test-scene/effects.luau)

### `test-scene.effects.new`

## [`src/test-scene/owner.luau`](../src/test-scene/owner.luau)

### `test-scene.owner.new`

## [`src/test-scene/signal.luau`](../src/test-scene/signal.luau)

### `test-scene.signal.new`

## [`src/test-scene/threat.luau`](../src/test-scene/threat.luau)

### `test-scene.threat.new`

## [`src/test-scene/vendor.luau`](../src/test-scene/vendor.luau)

### `test-scene.vendor.new`

## [`src/core/internal/chronicle-read.luau`](../src/core/internal/chronicle-read.luau)

The system module uses these internal input readers.
Use the system module for game code.

### `core.internal.chronicle-read.readDefinition`

### `core.internal.chronicle-read.readActiveVow`

### `core.internal.chronicle-read.readDeed`

### `core.internal.chronicle-read.readState`

## [`src/core/internal/fellowship-read.luau`](../src/core/internal/fellowship-read.luau)

The system module uses these internal input readers.
Use the system module for game code.

### `core.internal.fellowship-read.readState`

### `core.internal.fellowship-read.readFoundRequest`

### `core.internal.fellowship-read.readFormationRequest`

## [`src/core/internal/season-read.luau`](../src/core/internal/season-read.luau)

The system module uses these internal input readers.
Use the system module for game code.

### `core.internal.season-read.readState`

### `core.internal.season-read.readAuthoredDefinition`

### `core.internal.season-read.readEvent`

[Source](../src/core/internal/season-read.luau).
