# professions

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate profession requests with authoritative world/profile commits.

## State shape

`ProfilePort`, `World` and typed payloads describe observed inputs and durable effects.

Types and configuration are exported from [src/roblox/professions.luau](../../src/roblox/professions.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [professions](../../src/roblox/professions.luau) | `decodeIntent`, `forget`, `handle`, `harvestedSlots`, `interrupt`, `new`, `step` | `Fields`, `CommitResult`, `ProfilePort`, `SkinTarget`, `World`, `WorkKind`, `GatherPayload`, `SkinPayload`, `CraftPayload`, `WorkPayload`, `WorkMetadata`, `GatherEntry`, `SkinEntry`, `CraftEntry`, `WorkEntry`, `RecipeView`, `RecipeItemView`, `ProfessionView`, `ProfessionLesson`, `RecipeLesson`, `SupplyView`, `TrainerBook`, `Book`, `ResultExtras`, `ResultMessage`, `Message`, `Handle`, `CorePort`, `Policy`, `Deps`, `IntentPayload` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject skill/craft/gather rules, profile read/commit, world target/session observations, clock, random samples and dispatch.

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

Durable consumption precedes success. Interrupted sessions cannot grant. Replayed node claims do not pay twice.
