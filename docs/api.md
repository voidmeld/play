# Public API

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
