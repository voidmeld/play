# net

[System catalog](../systems.md) · [Play](../../README.md)

Apply token buckets independently to network senders.

## State shape

`Bucket` holds token/time state; `KeyedState` partitions buckets by sender identity.

Types and configuration are exported from [src/core/net.luau](../../src/core/net.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [rate-limit](../../src/core/net/rate-limit.luau) | `consume`, `newBucket`, `tryConsume` | `Config`, `Bucket`, `KeyedState` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply token capacity/refill policy, monotonic time, sender identity and requested cost. The host decodes requests and decides when to disconnect.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/net/rate-limit.verify.luau --name "keyed budgets isolate senders and preserve the input state"
```

The [executable specification](../../src/core/net/rate-limit.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: keyed budgets isolate senders and preserve the input state.

## Invariants

One sender cannot spend another sender's budget. Refusal preserves state. Reversed or invalid time cannot manufacture tokens.
