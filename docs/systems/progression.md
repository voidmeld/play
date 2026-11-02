# progression

[System catalog](../systems.md) · [Play](../../README.md)

Compose levels, talents, recovery, consumables, action bars, reputation, seasons and reward settlement.

## State shape

Each component has its own saved shape: talent ranks/loadouts, consumable channels/buffs, death records, actionbar slots, event ledgers, seasonal tracks and settlement receipts.

Types and configuration are exported from [src/core/progression.luau](../../src/core/progression.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [actionbar](../../src/core/progression/actionbar.luau) | `actionbar`, `apply`, `assign`, `clear`, `contextFor`, `copy`, `decodeWire`, `default`, `effective`, `encodeWire`, `itemAction`, `itemId`, `layerEntries`, `normalize`, `placed`, `project`, `resolvePress`, `slotFor`, `swap` | `State`, `Context`, `Layout`, `Intent`, `Config` |
| [consumables](../../src/core/progression/consumables.luau) | `activeStats`, `advance`, `begin`, `copy`, `create`, `eligibility`, `interrupt`, `interruptActor`, `item`, `register`, `registerAll` | `Buff`, `Item`, `Channel`, `ActiveBuff`, `State`, `Actor`, `ActorView`, `Mob`, `Config` |
| [grants](../../src/core/progression/grants.luau) | `compileProductionRegistry`, `forClass`, `gateFor`, `grantedIds`, `grants`, `indexOf`, `isGranted`, `problemsFor`, `problemsForClassSchema` | `Grant`, `GrantIndex`, `ProductionRegistry`, `ProductionRegistryResult`, `Config` |
| [hearth](../../src/core/progression/hearth.luau) | `arrived`, `bind`, `destination`, `hearth`, `homeZone`, `normalize` | `Destination`, `Bind`, `State`, `BoundState`, `Config` |
| [levels](../../src/core/progression/levels.luau) | `awardXp`, `levelForXp`, `levels`, `resolveLevel`, `rewardProjection`, `snapshotFromValues`, `validateCurve`, `xpBracket`, `xpForLevel` | `CurveRow`, `Curve`, `Config`, `Progression`, `Snapshot`, `RewardProjection` |
| [recovery](../../src/core/progression/recovery.luau) | `anchorPosition`, `anchoredLastPosition`, `decodeEcho`, `die`, `echoDistance`, `encodeEcho`, `lowHealth`, `recover`, `recovery`, `release` | `Point`, `Cost`, `Death`, `Position`, `AnchoredPosition`, `Config` |
| [reputation](../../src/core/progression/reputation.luau) | `apply`, `create`, `emptyState`, `pointsFor`, `projectEvent`, `projectLadder`, `projectState`, `rankFor`, `standings` | `EventKind`, `Event`, `State`, `ApplyResult`, `Ladder`, `Standing`, `Config` |
| [season](../../src/core/progression/season.luau) | `apply`, `claim`, `claimIn`, `definition`, `emptyState`, `projectState`, `projectTracks`, `projection`, `projectionIn`, `recordIn`, `season` | `Event`, `State`, `Result`, `PlaySource`, `Objective`, `Reward`, `AuthoredDefinition`, `Definition`, `ProjectionObjective`, `Projection`, `Config` |
| [settlement](../../src/core/progression/settlement.luau) | `applyPersonalReward`, `emptyRewardHistory`, `settlement` | `RewardReceipt`, `RewardHistory`, `RewardRequest`, `RewardGrant`, `RewardApplied`, `RewardRejected`, `RewardResult`, `GrantResult`, `Config` |
| [standing-credit](../../src/core/progression/standing-credit.luau) | `create` | `Outcome`, `Config` |
| [talent-ranks](../../src/core/progression/talent-ranks.luau) | `FULL_RANK`, `INVALID_STATE`, `NO_POINTS`, `TIER_LOCKED`, `UNKNOWN_TALENT`, `addRank`, `availablePoints`, `bucketOf`, `rankRefusal`, `respecRole`, `spendByLine`, `spentPoints`, `stateProblem` | `Loadout`, `Result`, `Node`, `Tier`, `Line`, `Spec`, `Bucket` |
| [talents](../../src/core/progression/talents.luau) | `change`, `decodeIntent`, `default`, `fromLoadout`, `load`, `normalize`, `rules`, `toLoadout` | `State`, `Loadout`, `Intent`, `Result` |
| [tracking](../../src/core/progression/tracking.luau) | `canTrack`, `tracking` | `Config` |
| [transactions](../../src/core/progression/transactions.luau) | `commit`, `isRecorded`, `ledgerKey`, `recordedKeys`, `transactions` | `CollectionSet`, `Outcome`, `Result`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply curves, class/resource/admission policy, catalogs, numeric/time bounds and pure account/profile projectors. Standing-credit coordinates injected authority/readiness/write callbacks.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/progression/actionbar.verify.luau --name "skips malformed and unearned loadout rows while retaining valid entries"
```

The [executable specification](../../src/core/progression/actionbar.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: skips malformed and unearned loadout rows while retaining valid entries.

## Invariants

Refused transitions preserve caller state. Talent budgets and tier gates hold. Recovery deadlines do not pay twice. Personal grants must agree with both settlement ledgers.
