# contact-markers

[System catalog](../systems.md) · [Play](../../README.md)

Share animation-track watchers and confirm stamped contacts once.

## State shape

Per-character watches retain track stamps, waiter identity and release callbacks.

Types and configuration are exported from [src/roblox/contact-markers.luau](../../src/roblox/contact-markers.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [contact-markers](../../src/roblox/contact-markers.luau) | `confirmed`, `create`, `onContact`, `retrigger`, `watch` | `Host` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject `Host<C,T>` stamp, listen, marker and admit callbacks.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/contact-markers.verify.luau --name "rejects stale tracks, presents once per stamp, and releases the last watcher"
```

The [executable specification](../../src/roblox/contact-markers.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: rejects stale tracks, presents once per stamp, and releases the last watcher.

## Invariants

Old tracks cannot confirm a new action. A contact presents once per stamp. The last watcher releases subscriptions.
