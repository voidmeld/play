# professions

[System catalog](../systems.md) · [Play](../../README.md)

Run skills, recipe transactions, harvesting, fishing and gathering sessions.

## State shape

Skill `State` holds learned professions/recipes. Crafting `Plan` captures reagents/output. Fishing `Line`, session `Session` and gathering `State` carry timing and claim identity.

Types and configuration are exported from [src/core/professions.luau](../../src/core/professions.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [crafting](../../src/core/professions/crafting.luau) | `craft`, `create`, `plan` | `Plan`, `Outcome`, `Config` |
| [fishing](../../src/core/professions/fishing.luau) | `cast`, `create`, `hook`, `idle`, `isJunk`, `observe`, `pick`, `reel` | `Phase`, `Line`, `Catch`, `Config` |
| [gathering](../../src/core/professions/gathering.luau) | `computeYield`, `create`, `emptyState`, `projectNode`, `step` | `RealmId`, `SpaceKind`, `Phase`, `Node`, `State`, `CommandKind`, `Command`, `Result` |
| [harvest](../../src/core/professions/harvest.luau) | `canAttempt`, `create`, `harvestNode`, `skinCorpse` | `Yield`, `Outcome`, `Config` |
| [session](../../src/core/professions/session.luau) | `begin`, `check`, `create` | `Kind`, `Session`, `Sample` |
| [skills](../../src/core/professions/skills.luau) | `canLearn`, `canLearnRecipe`, `copy`, `create`, `default`, `freezeState`, `knownRecipes`, `knows`, `learn`, `learnFromItem`, `learnRecipe`, `normalize`, `primaryCount`, `primarySlotsFree`, `profession`, `rollSkillUp`, `sameState`, `skillOf`, `skillUpChance`, `trainerRoster`, `unlearn` | `Kind`, `Profession`, `State`, `Color`, `Config` |
| [types](../../src/core/professions/types.luau) |  | `Sustain`, `Reagent`, `QuestInput`, `Thresholds`, `Source`, `Descriptor`, `Recipe`, `Extra`, `NodeKind`, `SkinRow`, `FishRow` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply catalogs, skill curves/chances, quality and yield rules, stations, item/profile operations, clocks and random samples. The adapter commits through injected profile/world ports.

Recipe `source` and `rung` are caller-defined labels. Play does not impose a game's source taxonomy
or activity names; the game owns their admission and presentation.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/professions/professions.verify.luau --name "admits configured skills and releases recipes without changing the prior snapshot"
```

The [executable specification](../../src/core/professions/professions.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: admits configured skills and releases recipes without changing the prior snapshot.

## Invariants

Failed crafting spends nothing. Interrupted sessions cannot complete. Node claims replay safely. Catalogs and game rewards remain caller-owned.
