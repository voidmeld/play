# social-host

[System catalog](../systems.md) · [Play](../../README.md)

Coordinate actor exclusion, social caches and membership settlement.

## State shape

`Membership`, `Response` and `Host` bind observed record and per-actor ownership.

Types and configuration are exported from [src/roblox/social-host.luau](../../src/roblox/social-host.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [social-host](../../src/roblox/social-host.luau) | `fellowships` | `Membership`, `Response`, `Host` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject durable records/membership readback, claim/commit operations, clock, identity and actor exclusion.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/social-host.verify.luau --name "confirms a claimed membership once the record commits and serves it from cache"
```

The [executable specification](../../src/roblox/social-host.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: confirms a claimed membership once the record commits and serves it from cache.

## Invariants

Membership is confirmed only after record commit. Cached identity matches authority. Failed/uncertain settlement retains recovery work.
