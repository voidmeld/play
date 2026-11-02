# cast

[System catalog](../systems.md) · [Play](../../README.md)

Queue a cast near its cooldown deadline and reject stale wakeups.

## State shape

`State<T> = { nextToken, queued? }`; queued entries retain payload, due time and a generation token. `Windows` holds independent deadlines.

Types and configuration are exported from [src/core/cast.luau](../../src/core/cast.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [queue](../../src/core/cast/queue.luau) | `cancel`, `delayFor`, `empty`, `enqueue`, `minimumCadenceSec`, `ready`, `remaining`, `rules`, `shouldQueue`, `take`, `windows` | `Config`, `Entry`, `State`, `Windows` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply monotonic time, queue-window/retry tuning and immutable payloads. The game schedules wakeups, checks actor identity and executes the cast.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/cast/queue.verify.luau --name "queue admission preserves reason, inclusive window and finite boundaries"
```

The [executable specification](../../src/core/cast/queue.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: queue admission preserves reason, inclusive window and finite boundaries.

## Invariants

Window admission is inclusive. Only a matching due token is consumed. Refusals retain the previous queue; cancellation invalidates old callbacks.
