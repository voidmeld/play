# input-profile

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate device reach, action coverage and rollback-safe sessions.

## State shape

`Profile` lists actions and affordances; `Session` owns admitted bindings until stop.

Types and configuration are exported from [src/roblox/input-profile.luau](../../src/roblox/input-profile.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [input-profile](../../src/roblox/input-profile.luau) | `coverage`, `create`, `parity`, `profile`, `reach`, `start` | `Device`, `TouchAffordance`, `Action`, `Profile`, `Session` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject bind, thumbstick, dispatch, intent and existing screen/button surfaces.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/input-profile.verify.luau --name "routes buttons, screen actions and movement across devices and rejects input after stop"
```

The [executable specification](../../src/roblox/input-profile.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: routes buttons, screen actions and movement across devices and rejects input after stop.

## Invariants

Partial mounts roll back. Coverage is exclusive. Input after stop is ignored and owned bindings are released.
