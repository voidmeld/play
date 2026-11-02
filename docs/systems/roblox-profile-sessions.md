# profile-sessions

[System catalog](../systems.md) · [Play](../../README.md)

Own lease admission, coalesced saves, renewal and bounded close.

## State shape

`Owner` binds profile/session identity; outcomes report save/renew/close state.

Types and configuration are exported from [src/roblox/profile-sessions.luau](../../src/roblox/profile-sessions.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [profile-sessions](../../src/roblox/profile-sessions.luau) | `admit`, `dispose`, `drain`, `isAdmitted`, `new`, `ownedTaskCount`, `requestSave`, `save`, `unload` | `Owner`, `Outcome`, `Dependencies` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject lease operations, profile reads, persistence, scheduling, dirty observation and shutdown budget.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/profile-sessions.verify.luau --name "renews from the current profile and retries failures without releasing ownership"
```

The [executable specification](../../src/roblox/profile-sessions.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: renews from the current profile and retries failures without releasing ownership.

## Invariants

Renewal uses the current profile. Failed saves preserve dirty work. Close does not release a foreign lease.
