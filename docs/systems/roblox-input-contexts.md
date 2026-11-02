# input-contexts

[System catalog](../systems.md) · [Play](../../README.md)

Resolve native readiness against one deadline and adopt server templates.

## State shape

`Template`, `Surfaces` and frozen `Mounted` readback describe context ownership.

Types and configuration are exported from [src/roblox/input-contexts.luau](../../src/roblox/input-contexts.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [input-contexts](../../src/roblox/input-contexts.luau) | `action`, `context`, `create`, `mount` | `Template`, `Surfaces`, `Mounted` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject find/wait, clock, context/action conversion, names/minimum wait, surface queries and adoption.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/input-contexts.verify.luau --name "reuses existing server contexts and fails closed when their query throws"
```

The [executable specification](../../src/roblox/input-contexts.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: reuses existing server contexts and fails closed when their query throws.

## Invariants

Readiness shares a deadline across the path. Wrong-class/missing actions refuse. Failed adoption/query cannot report a successful mount.
