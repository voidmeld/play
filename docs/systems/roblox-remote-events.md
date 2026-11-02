# remote-events

[System catalog](../systems.md) · [Play](../../README.md)

Share one dispatcher per channel and release native handlers safely.

## State shape

A transport retains disconnects by channel and release state per registration.

Types and configuration are exported from [src/roblox/remote-events.luau](../../src/roblox/remote-events.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [remote-events](../../src/roblox/remote-events.luau) | `serve`, `transport` | `Host` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject `Host` register, served count, connect, receive and ownership callbacks.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/remote-events.verify.luau --name "one dispatcher per channel survives partial release and disconnects the last"
```

The [executable specification](../../src/roblox/remote-events.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: one dispatcher per channel survives partial release and disconnects the last.

## Invariants

Partial release retains a shared dispatcher. The last handler disconnects it. Repeated release is harmless.
