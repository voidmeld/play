# chat

[System catalog](../systems.md) · [Play](../../README.md)

Project channel audiences, parse commands and budget senders.

## State shape

`Member` describes audience admission; `Bucket` and `Budget` track consumption; `Audience` and `Rule` describe channel scope.

Types and configuration are exported from [src/core/chat.luau](../../src/core/chat.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [channels](../../src/core/chat/channels.luau) | `allows`, `consume`, `pairName`, `parse`, `trim`, `window` | `Member`, `Audience`, `Rule`, `Bucket`, `Budget` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply member observations, audience rules, sender budgets, time and history limits. The game performs platform privacy checks and transports admitted text.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/chat/channels.verify.luau --name "membership preserves proximity, realm, group and private pair boundaries"
```

The [executable specification](../../src/core/chat/channels.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: membership preserves proximity, realm, group and private pair boundaries.

## Invariants

Private pair identities are deterministic. Realm/group/proximity filters do not leak membership. Rate refusal does not invent budget.
