# chat

[System catalog](../systems.md) · [Play](../../README.md)

Bind admitted users to native channels and check platform privacy.

## State shape

The adapter returns permission/refusal results and lists of removed/refused channels; native channel ownership stays with the game.

Types and configuration are exported from [src/roblox/chat.luau](../../src/roblox/chat.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [chat](../../src/roblox/chat.luau) | `directAllowed`, `permission`, `removeForeign`, `seat` | `DirectQuery` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject privacy queries, wait/retry, channel naming/add/remove and native destruction.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/chat.verify.luau --name "channel seating reports refusal and errors without stopping other seats"
```

The [executable specification](../../src/roblox/chat.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: channel seating reports refusal and errors without stopping other seats.

## Invariants

One failed channel does not stop other seats. Unavailable privacy queries remain distinguishable from denial.
