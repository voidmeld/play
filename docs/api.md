# Public API

The module tables below are the public entry points. The [README](../README.md) describes each system and its host responsibilities. Core modules own pure transitions; Roblox adapters take host operations; test scenes are Lute-only fixtures.

## `src/core/bank/vault.luau`

### `core.bank.vault.adjust`

[Declaration and signature](../src/core/bank/vault.luau).

### `core.bank.vault.vault`

[Declaration and signature](../src/core/bank/vault.luau).

## `src/core/cast/queue.luau`

### `core.cast.queue.cancel`

[Declaration and signature](../src/core/cast/queue.luau).

### `core.cast.queue.empty`

[Declaration and signature](../src/core/cast/queue.luau).

### `core.cast.queue.ready`

[Declaration and signature](../src/core/cast/queue.luau).

### `core.cast.queue.remaining`

[Declaration and signature](../src/core/cast/queue.luau).

### `core.cast.queue.rules`

[Declaration and signature](../src/core/cast/queue.luau).

### `core.cast.queue.take`

[Declaration and signature](../src/core/cast/queue.luau).

### `core.cast.queue.windows`

[Declaration and signature](../src/core/cast/queue.luau).

## `src/core/chat/channels.luau`

### `core.chat.channels.allows`

[Declaration and signature](../src/core/chat/channels.luau).

### `core.chat.channels.consume`

[Declaration and signature](../src/core/chat/channels.luau).

### `core.chat.channels.pairName`

[Declaration and signature](../src/core/chat/channels.luau).

### `core.chat.channels.parse`

[Declaration and signature](../src/core/chat/channels.luau).

### `core.chat.channels.trim`

[Declaration and signature](../src/core/chat/channels.luau).

### `core.chat.channels.window`

[Declaration and signature](../src/core/chat/channels.luau).

## `src/core/craft/recipes.luau`

### `core.craft.recipes.catalog`

[Declaration and signature](../src/core/craft/recipes.luau).

## `src/core/effects/timed.luau`

### `core.effects.timed.advance`

[Declaration and signature](../src/core/effects/timed.luau).

### `core.effects.timed.advanceTimes`

[Declaration and signature](../src/core/effects/timed.luau).

### `core.effects.timed.application`

[Declaration and signature](../src/core/effects/timed.luau).

### `core.effects.timed.count`

[Declaration and signature](../src/core/effects/timed.luau).

### `core.effects.timed.dispelFirst`

[Declaration and signature](../src/core/effects/timed.luau).

### `core.effects.timed.expired`

[Declaration and signature](../src/core/effects/timed.luau).

### `core.effects.timed.refresh`

[Declaration and signature](../src/core/effects/timed.luau).

### `core.effects.timed.remainingFraction`

[Declaration and signature](../src/core/effects/timed.luau).

### `core.effects.timed.remainingSec`

[Declaration and signature](../src/core/effects/timed.luau).

## `src/core/events/catalog.luau`

### `core.events.catalog.catalog`

[Declaration and signature](../src/core/events/catalog.luau).

### `core.events.catalog.finite`

[Declaration and signature](../src/core/events/catalog.luau).

## `src/core/events/schedule.luau`

### `core.events.schedule.schedule`

[Declaration and signature](../src/core/events/schedule.luau).

## `src/core/events/watch.luau`

### `core.events.watch.watch`

[Declaration and signature](../src/core/events/watch.luau).

## `src/core/internal/value.luau`

### `core.internal.value.dense`

[Declaration and signature](../src/core/internal/value.luau).

### `core.internal.value.freezeDeep`

[Declaration and signature](../src/core/internal/value.luau).

### `core.internal.value.identifier`

[Declaration and signature](../src/core/internal/value.luau).

### `core.internal.value.opaque`

[Declaration and signature](../src/core/internal/value.luau).

### `core.internal.value.raw`

[Declaration and signature](../src/core/internal/value.luau).

### `core.internal.value.record`

[Declaration and signature](../src/core/internal/value.luau).

### `core.internal.value.whole`

[Declaration and signature](../src/core/internal/value.luau).

## `src/core/inventory/stacks.luau`

### `core.inventory.stacks.stacks`

[Declaration and signature](../src/core/inventory/stacks.luau).

## `src/core/ledger/ledger.luau`

### `core.ledger.ledger.ledger`

[Declaration and signature](../src/core/ledger/ledger.luau).

## `src/core/loot/roll.luau`

### `core.loot.roll.roll`

[Declaration and signature](../src/core/loot/roll.luau).

## `src/core/mail/mailbox.luau`

### `core.mail.mailbox.mailbox`

[Declaration and signature](../src/core/mail/mailbox.luau).

## `src/core/market/book.luau`

### `core.market.book.book`

[Declaration and signature](../src/core/market/book.luau).

## `src/core/market/conservation.luau`

### `core.market.conservation.conservation`

[Declaration and signature](../src/core/market/conservation.luau).

## `src/core/market/goods.luau`

### `core.market.goods.catalog`

[Declaration and signature](../src/core/market/goods.luau).

## `src/core/market/wallet.luau`

### `core.market.wallet.wallet`

[Declaration and signature](../src/core/market/wallet.luau).

## `src/core/net/rate-limit.luau`

### `core.net.rate-limit.consume`

[Declaration and signature](../src/core/net/rate-limit.luau).

### `core.net.rate-limit.newBucket`

[Declaration and signature](../src/core/net/rate-limit.luau).

### `core.net.rate-limit.tryConsume`

[Declaration and signature](../src/core/net/rate-limit.luau).

## `src/core/orders/patron.luau`

### `core.orders.patron.patron`

[Declaration and signature](../src/core/orders/patron.luau).

## `src/core/orders/work.luau`

### `core.orders.work.emptyState`

[Declaration and signature](../src/core/orders/work.luau).

### `core.orders.work.projectOrder`

[Declaration and signature](../src/core/orders/work.luau).

### `core.orders.work.projectState`

[Declaration and signature](../src/core/orders/work.luau).

### `core.orders.work.step`

[Declaration and signature](../src/core/orders/work.luau).

## `src/core/persistence/session-lock.luau`

### `core.persistence.session-lock.isLocked`

[Declaration and signature](../src/core/persistence/session-lock.luau).

### `core.persistence.session-lock.release`

[Declaration and signature](../src/core/persistence/session-lock.luau).

### `core.persistence.session-lock.tryAcquire`

[Declaration and signature](../src/core/persistence/session-lock.luau).

## `src/core/progression/actionbar.luau`

### `core.progression.actionbar.actionbar`

[Declaration and signature](../src/core/progression/actionbar.luau).

## `src/core/progression/grants.luau`

### `core.progression.grants.grants`

[Declaration and signature](../src/core/progression/grants.luau).

## `src/core/progression/hearth.luau`

### `core.progression.hearth.hearth`

[Declaration and signature](../src/core/progression/hearth.luau).

## `src/core/progression/levels.luau`

### `core.progression.levels.levels`

[Declaration and signature](../src/core/progression/levels.luau).

## `src/core/progression/recovery.luau`

### `core.progression.recovery.recovery`

[Declaration and signature](../src/core/progression/recovery.luau).

## `src/core/progression/season.luau`

### `core.progression.season.season`

[Declaration and signature](../src/core/progression/season.luau).

## `src/core/progression/tracking.luau`

### `core.progression.tracking.tracking`

[Declaration and signature](../src/core/progression/tracking.luau).

## `src/core/progression/transactions.luau`

### `core.progression.transactions.transactions`

[Declaration and signature](../src/core/progression/transactions.luau).

## `src/core/quest/counter.luau`

### `core.quest.counter.counter`

[Declaration and signature](../src/core/quest/counter.luau).

## `src/core/quest/index.luau`

### `core.quest.index.index`

[Declaration and signature](../src/core/quest/index.luau).

## `src/core/quest/lifecycle.luau`

### `core.quest.lifecycle.lifecycle`

[Declaration and signature](../src/core/quest/lifecycle.luau).

## `src/core/quest/markers.luau`

### `core.quest.markers.markers`

[Declaration and signature](../src/core/quest/markers.luau).

## `src/core/quest/objectives.luau`

### `core.quest.objectives.catalog`

[Declaration and signature](../src/core/quest/objectives.luau).

## `src/core/social/allies.luau`

### `core.social.allies.allies`

[Declaration and signature](../src/core/social/allies.luau).

## `src/core/social/chronicle.luau`

### `core.social.chronicle.chronicle`

[Declaration and signature](../src/core/social/chronicle.luau).

## `src/core/social/fellowship.luau`

### `core.social.fellowship.fellowship`

[Declaration and signature](../src/core/social/fellowship.luau).

## `src/core/social/formation.luau`

### `core.social.formation.formation`

[Declaration and signature](../src/core/social/formation.luau).

## `src/core/social/group.luau`

### `core.social.group.group`

[Declaration and signature](../src/core/social/group.luau).

## `src/core/social/guildbank.luau`

### `core.social.guildbank.guildbank`

[Declaration and signature](../src/core/social/guildbank.luau).

## `src/core/social/guildhome.luau`

### `core.social.guildhome.guildhome`

[Declaration and signature](../src/core/social/guildhome.luau).

## `src/core/social/guildledger.luau`

### `core.social.guildledger.guildledger`

[Declaration and signature](../src/core/social/guildledger.luau).

## `src/core/social/notes.luau`

### `core.social.notes.notes`

[Declaration and signature](../src/core/social/notes.luau).

## `src/core/social/profile.luau`

### `core.social.profile.profile`

[Declaration and signature](../src/core/social/profile.luau).

## `src/core/social/rally.luau`

### `core.social.rally.rally`

[Declaration and signature](../src/core/social/rally.luau).

## `src/core/social/roster.luau`

### `core.social.roster.roster`

[Declaration and signature](../src/core/social/roster.luau).

## `src/core/social/shape.luau`

### `core.social.shape.array`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.boolean`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.dense`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.denseLength`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.exact`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.freezeDeep`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.freezeDeepWithKeys`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.map`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.number`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.onlyFields`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.opaque`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.raw`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.string`

[Declaration and signature](../src/core/social/shape.luau).

### `core.social.shape.whole`

[Declaration and signature](../src/core/social/shape.luau).

## `src/core/social/warband.luau`

### `core.social.warband.warband`

[Declaration and signature](../src/core/social/warband.luau).

## `src/core/threat/table.luau`

### `core.threat.table.empty`

[Declaration and signature](../src/core/threat/table.luau).

### `core.threat.table.prune`

[Declaration and signature](../src/core/threat/table.luau).

### `core.threat.table.remove`

[Declaration and signature](../src/core/threat/table.luau).

### `core.threat.table.rules`

[Declaration and signature](../src/core/threat/table.luau).

### `core.threat.table.targetFor`

[Declaration and signature](../src/core/threat/table.luau).

## `src/core/trade/exchange.luau`

### `core.trade.exchange.exchange`

[Declaration and signature](../src/core/trade/exchange.luau).

## `src/core/trade/receipt.luau`

### `core.trade.receipt.receipts`

[Declaration and signature](../src/core/trade/receipt.luau).

## `src/core/vendors/exchange.luau`

### `core.vendors.exchange.empty`

[Declaration and signature](../src/core/vendors/exchange.luau).

### `core.vendors.exchange.vendor`

[Declaration and signature](../src/core/vendors/exchange.luau).

## `src/roblox/chat.luau`

### `roblox.chat.directAllowed`

[Declaration and signature](../src/roblox/chat.luau).

### `roblox.chat.permission`

[Declaration and signature](../src/roblox/chat.luau).

### `roblox.chat.removeForeign`

[Declaration and signature](../src/roblox/chat.luau).

### `roblox.chat.seat`

[Declaration and signature](../src/roblox/chat.luau).

## `src/roblox/data-store.luau`

### `roblox.data-store.retryPolicy`

[Declaration and signature](../src/roblox/data-store.luau).

## `src/roblox/messaging.luau`

### `roblox.messaging.bind`

[Declaration and signature](../src/roblox/messaging.luau).

## `src/roblox/profile-sessions.luau`

### `roblox.profile-sessions.new`

[Declaration and signature](../src/roblox/profile-sessions.luau).

## `src/roblox/remote-events.luau`

### `roblox.remote-events.limiter`

[Declaration and signature](../src/roblox/remote-events.luau).

### `roblox.remote-events.transport`

[Declaration and signature](../src/roblox/remote-events.luau).

## `src/roblox/travel-placement.luau`

### `roblox.travel-placement.entrance`

[Declaration and signature](../src/roblox/travel-placement.luau).

### `roblox.travel-placement.place`

[Declaration and signature](../src/roblox/travel-placement.luau).

## `src/test-scene/cast.luau`

### `test-scene.cast.new`

[Declaration and signature](../src/test-scene/cast.luau).

## `src/test-scene/clock.luau`

### `test-scene.clock.new`

[Declaration and signature](../src/test-scene/clock.luau).

## `src/test-scene/effects.luau`

### `test-scene.effects.new`

[Declaration and signature](../src/test-scene/effects.luau).

## `src/test-scene/owner.luau`

### `test-scene.owner.new`

[Declaration and signature](../src/test-scene/owner.luau).

## `src/test-scene/signal.luau`

### `test-scene.signal.new`

[Declaration and signature](../src/test-scene/signal.luau).

## `src/test-scene/threat.luau`

### `test-scene.threat.new`

[Declaration and signature](../src/test-scene/threat.luau).

## `src/test-scene/vendor.luau`

### `test-scene.vendor.new`

[Declaration and signature](../src/test-scene/vendor.luau).

### `core.control.diminishing.empty`

Declaration: [empty](../src/core/control/diminishing.luau). Signature: `empty(): State`.
Creates an empty category and family ledger.

### `core.control.diminishing.clone`

Declaration: [clone](../src/core/control/diminishing.luau). Signature: `clone(state: State): State`.
Copies the ledger and every bucket, retaining expired entries.

### `core.control.diminishing.rules`

Declaration: [rules](../src/core/control/diminishing.luau). Signature: `rules(config: Config)`.
Captures positive `resetSec`, a nonempty list of duration `multipliers` in [0, 1],
and supplied `categories`. Each category supplies a disjoint family key, duration
cap and nonnegative immunity price, minimum and maximum seconds. The maximum must
be at least the minimum. Families may be shared across categories.

Returns `apply(state: State, category: string, baseDurationSec: number, nowSec: number): Result`.
The host owns validated state with nonnegative integer counts, finite deadlines
and a monotonic clock. A live family window blocks the application before counting.
Otherwise the category count selects a multiplier, saturating at the last step.
The first counted application starts the fixed reset window; later applications
retain its deadline. Equality at either expiry permits application or reset.
The cap is applied before multiplication. Positive granted duration starts family
immunity at the application clock, priced by granted duration and clamped to the
configured bounds. A zero maximum disables immunity. Expired family counts carry
forward when the family is rearmed. Expired buckets remain in the returned ledger.

Every result has a detached `dr` ledger, `grantedSec`, `multiplier`, `step` and
`immune`. Unknown categories and nonfinite clocks return an immune result without
changing ledger values. Nonpositive or nonfinite requested durations grant zero
but still consume a category step; `step` and `immune` describe the multiplier,
so zero granted seconds alone does not imply immunity. Configuration is copied.
The host supplies category names and caps computed from game tuning, installs
returned state atomically, owns effect lifetimes and resets the ledger on lifecycle
boundaries. Cleansing an effect must not implicitly clear its ledger.

### `test-scene.diminishing.new`

Declaration: [new](../src/test-scene/diminishing.luau). Signature: `new(config: Config)`.
Creates an isolated ledger host with fake `clock`, `apply(category, durationSec)`
and detached `snapshot()` values. No engine, scheduling or effect installation.
