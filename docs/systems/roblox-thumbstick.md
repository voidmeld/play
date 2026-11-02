# thumbstick

[System catalog](../systems.md) · [Play](../../README.md)

Convert touch displacement into dead-zone movement and a bounded knob.

## State shape

`Stick = { anchor, knob, vector }`; each `Vec2` is `{ x, y }`.

Types and configuration are exported from [src/roblox/thumbstick.luau](../../src/roblox/thumbstick.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [thumbstick](../../src/roblox/thumbstick.luau) | `anchorAt`, `create`, `drag`, `knobFor`, `release`, `vectorFor` | `Vec2`, `Stick` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply radius/dead-zone/screen-zone tuning and observed touch points. The game tracks touches, draws UI and submits movement.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/examples/thumbstick.luau
```

The [complete example](../../tools/examples/thumbstick.luau) includes configuration and executable assertions.

## Invariants

Dead-zone input yields zero. Movement magnitude and knob displacement clamp at the radius. Release yields zero movement.
