# input-bindings

[System catalog](../systems.md) · [Play](../../README.md)

Project configured keyboard/gamepad bindings, labels and chords.

## State shape

`Action<C>` rows describe identity, context, keys, chord and touch affordance; the returned binding table indexes them.

Types and configuration are exported from [src/roblox/input-bindings.luau](../../src/roblox/input-bindings.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [input-bindings](../../src/roblox/input-bindings.luau) | `create`, `forContext`, `gamepad`, `gamepadLabel`, `get`, `keyboardLabel`, `keyboardNames`, `matches`, `matchesCode`, `matchesInput`, `primaryKeyboard` | `Action` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply action rows, labels, modifier, enum-like key values and held-button query. Bind native events in the game.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/examples/input-bindings.luau
```

The [complete example](../../tools/examples/input-bindings.luau) includes configuration and executable assertions.

## Invariants

Chorded gamepad actions require the held modifier. Keyboard admission is independent. Context filtering returns only matching actions.
