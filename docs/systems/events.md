# events

[System catalog](../systems.md) · [Play](../../README.md)

Resolve configured event schedules and track participation through reward-ticket recovery.

## State shape

`Catalog` contains configured events; schedule `Context` projects active effects; watch `State` tracks phase, work, participants and tickets.

Types and configuration are exported from [src/core/events.luau](../../src/core/events.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [catalog](../../src/core/events/catalog.luau) | `catalog`, `finite`, `projectEvent`, `validateCatalog` | `Flag`, `Rollout`, `Schedule`, `Event`, `Catalog`, `Config` |
| [schedule](../../src/core/events/schedule.luau) | `resolve`, `schedule`, `stableBucket`, `validateCatalog` | `Event`, `Catalog`, `Context`, `Effect`, `Resolution`, `Config` |
| [watch](../../src/core/events/watch.luau) | `claim`, `emptyState`, `join`, `leave`, `projectEvent`, `protect`, `protectionBindingsValid`, `sync`, `watch`, `work` | `Phase`, `WorkPoint`, `Event`, `State`, `Result`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply calendars, rollout/admission rules, realm/work/protection definitions, clocks and rewards. Persist grants and acknowledgments in the game.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/events/catalog.verify.luau --name "validates supplied schema and content hooks"
```

The [executable specification](../../src/core/events/catalog.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: validates supplied schema and content hooks.

## Invariants

Resolution preserves priority and unique hooks. Returned content lists are detached. Reward tickets retain identity across recovery.
