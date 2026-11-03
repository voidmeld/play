# quest

[System catalog](../systems.md) · [Play](../../README.md)

Index declarative objectives and coordinate saved journals, quest progress projections, runs and claims.

## State shape

`Objective`, `Binding` and `Event` describe matching; counters hold completions; run `RunState` holds members/phases/history; claims retain invitation and replacement identity.
Journal `Record` holds an exact version, zone/character identity, quest status/step/count maps and semantic
event receipt identities. Its parser copies admitted maps and applies configured bounds and vocabulary.

Types and configuration are exported from [src/core/quest.luau](../../src/core/quest.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [claims](../../src/core/quest/claims.luau) | `carrierFor`, `claimTransform`, `claims`, `closeTransform`, `createTransform`, `inviteReplacementTransform`, `isReservedServer`, `newRecord`, `readRecord`, `readReplacementIdentity`, `rejoinTarget`, `renewTransform`, `replaceRosterTransform`, `retryDelaysSec`, `runKey`, `serverKey`, `teleportData`, `userKey`, `validRecord`, `writeThroughTransform` | `Invitation`, `ReplacementIdentity`, `Member`, `Record`, `Target`, `Transform`, `Config` |
| [counter](../../src/core/quest/counter.luau) | `count`, `counter`, `label`, `questIdFromMarkerName` | `Band`, `Counts`, `Config` |
| [index](../../src/core/quest/index.luau) | `bindingsForEvent`, `byTarget`, `index`, `objectiveBindings` | `Config`, `TargetBinding` |
| [journal](../../src/core/quest/journal.luau) | `journal` configures creation, decoding, bounded copying, saved-quest conversion and identity keys | `QuestProgress`, `Record`, `Config`, `API` |
| [lifecycle](../../src/core/quest/lifecycle.luau) | `bindingForObjective`, `lifecycle`, `projectObjective`, `validateObjective` | `Objective`, `Binding`, `Event`, `Quest`, `Problem`, `Config` |
| [markers](../../src/core/quest/markers.luau) | `colorForState`, `isActionable`, `markers`, `shownState`, `stateForEntry`, `stateForGiver` | `QuestStatus`, `MarkerState`, `QuestEntry`, `Config` |
| [objectives](../../src/core/quest/objectives.luau) | `binding`, `bindings`, `bindingsFor`, `catalog`, `contract`, `eventOf`, `events`, `kinds`, `known`, `matches`, `targetsOf`, `validate` | `Targets`, `KindSpec`, `Objective`, `Quest`, `Event`, `Binding`, `Problem`, `EventContract`, `Aliases`, `Config`, `Catalog` |
| [progress](../../src/core/quest/progress.luau) | `progress` configures admission, prerequisites, exclusive paths, objective lookup, ordered counts and replay status | `QuestProgress`, `Rule`, `Branch`, `Statuses`, `ObjectiveView`, `QuestView`, `ActorView`, `ContentView`, `Config`, `API` |
| [run](../../src/core/quest/run.luau) | `run` | `Package`, `RunStatus`, `Member`, `RunState`, `StartEvent`, `CompletePhaseEvent`, `MemberEvent`, `WipeEvent`, `Event`, `Recovery`, `TransitionApplied`, `TransitionRejected`, `TransitionResult`, `Core`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply objective kinds/targets, quest definitions, level/marker policy, package/run admission and claim transforms. The game installs actor progress and persists rewards.
Journals additionally need the current saved version, bounds, status vocabulary, receipt status and literal
namespace plus semantic-event identity policy. The game owns the known quest catalog, leases, schema migration,
authoritative installation, storage keys and ordered persistence. Journal parsing does not write storage.

Progress uses four typed content/quest/objective/actor projections, a realm-admission policy and six status
names. Definitions and objectives remain generic: lookups return their original game types. Metadata
projections must be pure and stable during a reducer call. Keep content layout, realm/class catalogs,
rewards, objective/spatial policy and authoritative state installation in the game. Align the six progress
statuses with the journal's admitted vocabulary.

`reconcileOrdered` updates the progress map supplied by the actor projection. Call it with a draft owned
by the authoritative reducer. Other progress operations query that state and do not reserve or install it.

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

Run the [journal fixture](../../src/core/quest/journal.verify.luau) with:

```sh
lute run tools/gate.luau --file src/core/quest/journal.verify.luau
```

It uses version seven, a three-record budget, a two-status vocabulary and a namespace containing a pattern
character to prove literal receipt separation, round trips, copied state and strict recovery validation.

The [progress fixture](../../src/core/quest/progress.verify.luau) uses a different model layout and status
vocabulary. Run it with:

```sh
lute run tools/gate.luau --file src/core/quest/progress.verify.luau
```

It exercises original-definition identity, domain/class/level admission, all/any prerequisites, replay
claims, ordered draft reconciliation and malformed/conflicting exclusive paths.

## Invariants

Objective metadata cannot become unintended event targets. Bindings retain authored order. Accepted phases replay safely; conflicting phase identities refuse.
Saved journals refuse unsupported versions, malformed counts, unknown quests and over-budget records.
Semantic receipts have a separate validated shape. Resumed active steps require objective counts.
Quest admission requires known matching realms, current eligibility, satisfied prerequisites, a compatible
exclusive path and no existing progress. Ordered reconciliation advances only the completed prefix and
preserves replay identity. Conflicting or incomplete branch metadata fails closed.
