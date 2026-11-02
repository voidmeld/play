# messaging

[System catalog](../systems.md) · [Play](../../README.md)

Publish and receive typed notices over injected messaging.

## State shape

`Host` carries publication/subscription/decode capabilities; bind returns scoped lifetime operations.

Types and configuration are exported from [src/roblox/messaging.luau](../../src/roblox/messaging.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [messaging](../../src/roblox/messaging.luau) | `bind`, `publish`, `subscribe` | `Host` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject publish, subscribe, notice decode and error reporting; own the returned disconnect.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/messaging.verify.luau --name "fanout decodes notices, isolates unavailable service and disconnects"
```

The [executable specification](../../src/roblox/messaging.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: fanout decodes notices, isolates unavailable service and disconnects.

## Invariants

Unavailable publication is observable. Malformed notices do not dispatch. Cleanup disconnects the subscription.
