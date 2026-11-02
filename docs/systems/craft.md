# craft

[System catalog](../systems.md) · [Play](../../README.md)

Validate and project recipe definitions into immutable material requirements.

## State shape

`Recipe` contains material stacks and output; `Catalog` holds projected definitions under caller-provided source rules.

Types and configuration are exported from [src/core/craft.luau](../../src/core/craft.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [recipes](../../src/core/craft/recipes.luau) | `catalog`, `projectRecipe` | `MaterialStack`, `Recipe`, `SourceRule`, `Config`, `Catalog` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply authored rows, source classification, identifiers and bounds. Inventory spending, stations and durable grants belong to the game.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/craft/recipes.verify.luau --name "projects a frozen recipe and rejects malformed authored rows"
```

The [executable specification](../../src/core/craft/recipes.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: projects a frozen recipe and rejects malformed authored rows.

## Invariants

Malformed rows refuse. Accepted recipes are detached and frozen. Material requirements come from game data.
