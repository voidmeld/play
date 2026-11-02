# quest

[System catalog](../systems.md) · [Play](../../README.md)

Index declarative objectives and coordinate quest progress projections, runs and claims.

## State shape

`Objective`, `Binding` and `Event` describe matching; counters hold completions; run `RunState` holds members/phases/history; claims retain invitation and replacement identity.

Types and configuration are exported from [src/core/quest.luau](../../src/core/quest.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [claims](../../src/core/quest/claims.luau) | `carrierFor`, `claimTransform`, `claims`, `closeTransform`, `createTransform`, `inviteReplacementTransform`, `isReservedServer`, `newRecord`, `readRecord`, `readReplacementIdentity`, `rejoinTarget`, `renewTransform`, `replaceRosterTransform`, `retryDelaysSec`, `runKey`, `serverKey`, `teleportData`, `userKey`, `validRecord`, `writeThroughTransform` | `Invitation`, `ReplacementIdentity`, `Member`, `Record`, `Target`, `Transform`, `Config` |
| [counter](../../src/core/quest/counter.luau) | `count`, `counter`, `label`, `questIdFromMarkerName` | `Band`, `Counts`, `Config` |
| [index](../../src/core/quest/index.luau) | `bindingsForEvent`, `byTarget`, `index`, `objectiveBindings` | `Config`, `TargetBinding` |
| [lifecycle](../../src/core/quest/lifecycle.luau) | `bindingForObjective`, `lifecycle`, `projectObjective`, `validateObjective` | `Objective`, `Binding`, `Event`, `Quest`, `Problem`, `Config` |
| [markers](../../src/core/quest/markers.luau) | `colorForState`, `isActionable`, `markers`, `shownState`, `stateForEntry`, `stateForGiver` | `QuestStatus`, `MarkerState`, `QuestEntry`, `Config` |
| [objectives](../../src/core/quest/objectives.luau) | `binding`, `bindings`, `bindingsFor`, `catalog`, `contract`, `eventOf`, `events`, `kinds`, `known`, `matches`, `targetsOf`, `validate` | `Targets`, `KindSpec`, `Objective`, `Quest`, `Event`, `Binding`, `Problem`, `EventContract`, `Aliases`, `Config`, `Catalog` |
| [run](../../src/core/quest/run.luau) | `run` | `Package`, `RunStatus`, `Member`, `RunState`, `StartEvent`, `CompletePhaseEvent`, `MemberEvent`, `WipeEvent`, `Event`, `Recovery`, `TransitionApplied`, `TransitionRejected`, `TransitionResult`, `Core`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply objective kinds/targets, quest definitions, level/marker policy, package/run admission and claim transforms. The game installs actor progress and persists rewards.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/quest/counter.verify.luau --name "counts level-eligible quests and turned-in completions"
```

The [executable specification](../../src/core/quest/counter.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: counts level-eligible quests and turned-in completions.

## Invariants

Objective metadata cannot become unintended event targets. Bindings retain authored order. Accepted phases replay safely; conflicting phase identities refuse.
