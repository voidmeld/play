# threat

[System catalog](../systems.md) · [Play](../../README.md)

Select threat targets and freeze combat contribution eligibility at encounter end.

## State shape

`table.State = { threat: { [string]: number }, targetActorId: string }`; contribution records hold effective credit, presence and an encounter-end character snapshot.

Types and configuration are exported from [src/core/threat.luau](../../src/core/threat.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [contribution](../../src/core/threat/contribution.luau) | `asParticipant`, `create`, `eligible`, `eligibleAtEnd`, `finish`, `observe`, `record` | `Point`, `DungeonAdmission`, `Relation`, `Observation`, `Credit`, `ActorContribution`, `EndActor`, `Encounter`, `Participant`, `Config` |
| [table](../../src/core/threat/table.luau) | `add`, `empty`, `prune`, `remove`, `rules`, `targetFor`, `taunt` | `Config`, `State`, `Candidate`, `Pruned` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply takeover/taunt tuning, eligible/alive/leash/melee observations, categories, radii and deadlines. The host installs state, drives pursuit and persists rewards.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/threat/contribution.verify.luau --name "credits only effective contested actions against an eligible relation"
```

The [executable specification](../../src/core/threat/contribution.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: credits only effective contested actions against an eligible relation.

## Invariants

Takeover requires exceeding the threshold. Ties use actor identity. Taunts exceed the current maximum. Encounter-end eligibility cannot change with later movement or replacement.
