# persistence

[System catalog](../systems.md) · [Play](../../README.md)

Provide session exclusion, profile save lifetime, ordered stores and bounded shutdown.

## State shape

`LockState` identifies a lease owner/expiry. Profile-session `State` tracks dirty/in-flight generations. Store queues retain per-key ordering and operation outcomes.

Types and configuration are exported from [src/core/persistence.luau](../../src/core/persistence.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [profile-session](../../src/core/persistence/profile-session.luau) | `begin`, `close`, `create`, `dirty`, `due`, `finish`, `open`, `openAcquired` | `FlightKind`, `State`, `Outcome`, `Config` |
| [session-lock](../../src/core/persistence/session-lock.luau) | `isLocked`, `release`, `tryAcquire` | `LockState`, `AcquireResult` |
| [store-host](../../src/core/persistence/store-host.luau) | `create`, `drain`, `memory`, `real` | `Outcome`, `DrainOutcome`, `Operation`, `Observation`, `Observer`, `BudgetKind`, `QueuedWrite`, `Circuit`, `RawStore`, `RealDependencies`, `MemoryStore`, `TestOptions`, `Store`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply clocks, retry/backoff/jitter, backend read/write/update, budgets, circuit policy, lease authority and schema/readback validation. The game owns partition keys.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/persistence/profile-session.verify.luau --name "preserves changes arriving during a successful save"
```

The [executable specification](../../src/core/persistence/profile-session.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: preserves changes arriving during a successful save.

## Invariants

Independent keys can progress while each key stays ordered. Save acknowledgments preserve concurrent dirty work. Expiry fences late completions; close respects its budget.
