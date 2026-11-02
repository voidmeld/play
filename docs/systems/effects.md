# effects

[System catalog](../systems.md) · [Play](../../README.md)

Advance timed effects, stacks, periodic deadlines and dispels.

## State shape

`Entry` holds source, stack count, duration/expiry and periodic timing. `Application` and `Refresh` describe requested updates.

Types and configuration are exported from [src/core/effects.luau](../../src/core/effects.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [timed](../../src/core/effects/timed.luau) | `advance`, `advanceTimes`, `application`, `count`, `dispelFirst`, `expired`, `refresh`, `remainingFraction`, `remainingSec` | `Entry`, `Application`, `Refresh` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply applications, time/delta, refresh policy and stack caps. The host installs returned timing and applies emitted periodic effects.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/effects/timed.verify.luau --name "applications increment to the authored cap and reset duration and tick phase"
```

The [executable specification](../../src/core/effects/timed.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: applications increment to the authored cap and reset duration and tick phase.

## Invariants

Stack caps hold. Refresh resets the selected duration/tick phase. Expired effects do not continue ticking; dispel selection is deterministic.
