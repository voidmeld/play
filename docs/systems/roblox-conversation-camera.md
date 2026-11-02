# conversation-camera

[System catalog](../systems.md) · [Play](../../README.md)

Own conversation framing while allowing temporary obstruction and player override.

## State shape

`State` tracks conversation identity/ownership and framing; `Rect`/`View` describe measured safe space.

Types and configuration are exported from [src/roblox/conversation-camera.luau](../../src/roblox/conversation-camera.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [conversation-camera](../../src/roblox/conversation-camera.luau) | `cameraGesture`, `choose`, `create`, `new`, `space`, `step`, `views` | `Point`, `Rect`, `View`, `State`, `Tuning` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply spring operations, tuning, conversation/speaker identity, UI bounds and sightline results; apply native transforms.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/camera.verify.luau --name "waits for streaming, survives temporary obstruction and releases until the next conversation"
```

The [executable specification](../../src/roblox/camera.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: waits for streaming, survives temporary obstruction and releases until the next conversation.

## Invariants

Temporary obstruction allows reacquisition. Manual override releases ownership until conversation identity changes.
