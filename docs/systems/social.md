# social

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate parties, fellowships, warbands, formation, shared banks, allies, notes and chronicles.

## State shape

Each component exports its own `State`: membership/invites/transfers, formation consent/fee holds, bank receipts, ally history, note delivery and witnessed vows.

Types and configuration are exported from [src/core/social.luau](../../src/core/social.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [allies](../../src/core/social/allies.luau) | `allies`, `emptyState`, `projectPrivate`, `projectState`, `transition` | `QualificationKind`, `Entry`, `State`, `Policy`, `Result`, `QualifyEvent`, `ReconcileEvent`, `Event`, `Authority`, `Config` |
| [chronicle](../../src/core/social/chronicle.luau) | `chronicle`, `emptyState`, `projectChronicle`, `projectState`, `transition` | `ActiveStatus`, `TerminalStatus`, `Definition`, `ActiveVow`, `Deed`, `State`, `Applied`, `Rejected`, `Result`, `AccessPolicy`, `ContributionAuthority`, `Event`, `Config` |
| [fellowship](../../src/core/social/fellowship.luau) | `create`, `createFromFormation`, `fellowship`, `projectState`, `transition`, `validCreed` | `Member`, `Invite`, `Creed`, `CreedDraft`, `FormationRequest`, `Event`, `EventDraft`, `Audit`, `State`, `FoundRequest`, `Result`, `Config` |
| [formation](../../src/core/social/formation.luau) | `formation`, `projectState`, `start`, `transition` | `Founder`, `State`, `EventDraft`, `Event`, `StartRequest`, `Result`, `Config` |
| [group](../../src/core/social/group.luau) | `admit`, `emptyState`, `group`, `projectRelations`, `projectState`, `transition`, `visibleRoster` | `Relations`, `Admission`, `Ticket`, `State`, `Result`, `Decision`, `Request`, `Authority`, `MemberEvent`, `ReconcileEvent`, `Event`, `Config` |
| [guildbank](../../src/core/social/guildbank.luau) | `apply`, `emptyState`, `guildbank`, `knowsOperation`, `projectState`, `receiptsFor` | `Receipt`, `Operation`, `Entry`, `Withdrawal`, `Command`, `State`, `Result`, `Config` |
| [guildhome](../../src/core/social/guildhome.luau) | `guildhome`, `slotFor`, `slots` | `Slot`, `Config` |
| [guildledger](../../src/core/social/guildledger.luau) | `acked`, `beginDeposit`, `canWithdraw`, `claim`, `claimed`, `emptyLedger`, `guildledger`, `projectLedger`, `refund`, `settle` | `Pending`, `Ledger`, `Limits`, `Receipt`, `ProfileInput`, `Config` |
| [membership](../../src/core/social/membership.luau) | `accept`, `acceptLeaderTransfer`, `decline`, `disband`, `invite`, `kick`, `leave`, `markAbsent`, `markPresent`, `membership`, `open`, `projectState`, `setLootMode`, `sweep`, `transferLeader` | `LootMode`, `Member`, `Invite`, `LeaderTransfer`, `State`, `Result`, `Config`, `Core` |
| [notes](../../src/core/social/notes.luau) | `deliver`, `emptyState`, `live`, `markRead`, `notes`, `phrases`, `projectState` | `Note`, `State`, `Result`, `Phrase`, `Catalog`, `Delivery`, `Config` |
| [profile](../../src/core/social/profile.luau) | `default`, `profile`, `project` | `FellowshipIdentity`, `State`, `Config` |
| [rally](../../src/core/social/rally.luau) | `project`, `rally` | `Row`, `Config` |
| [roster](../../src/core/social/roster.luau) | `reduce`, `roster` | `Member`, `Party`, `Actor`, `Runtime`, `Result`, `Config` |
| [warband](../../src/core/social/warband.luau) | `found`, `project`, `read`, `transition`, `warband` | `Party`, `Unit`, `Invite`, `Transfer`, `Order`, `State`, `Event`, `Parties`, `Result`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply realm/capacity/privacy/rank/admission policy, bounds, clocks and pure projectors. Use injected durable records and host settlement for multi-record effects.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/social/allies.verify.luau --name "combines every denial category without mutating the stored allies"
```

The [executable specification](../../src/core/social/allies.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: combines every denial category without mutating the stored allies.

## Invariants

Invites reserve capacity and name a recipient. A blocked member cannot be bypassed. Foreign ownership and stale fences refuse; shared goods and receipts retain custody.

Membership owns invitation replay, grouped admission, ordered succession, leader-only authority,
transfer consent and expiry, connected-character tie breaking, absence deadlines and rejoin identity.
Changing leadership preserves the roster, reservations and loot state. Repeated absence and transfer
requests do not extend their deadlines. Games supply capacities, allowed realms, timing and reward policy.
Run these rules directly with neutral policy:

```sh
lute run tools/gate.luau --file src/core/social/membership.verify.luau
```
