# inventory

[System catalog](../systems.md) · [Play](../../README.md)

Manage stack capacity, equipment exchanges and wear, plus replay-safe cargo custody, drops, recovery and delivery.

## State shape

`Inventory` maps item IDs to counts; `Holdings` adds equipment/bank views. Cargo `State` contains claims, drops, extraction and delivery history.
Equipment `Wear` tracks accumulated use per equipped slot and per-copy wear lists in bag and bank.
Equipment plans return new inventory/slot maps, displacement and refusal information without installing state.

Types and configuration are exported from [src/core/inventory.luau](../../src/core/inventory.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [cargo](../../src/core/inventory/cargo.luau) | `carriedOf`, `census`, `create`, `emptyState`, `openDrops`, `projectState`, `retireTransient`, `step` | `Status`, `Cause`, `Claim`, `Drop`, `Total`, `Extraction`, `State`, `Intent`, `CommandKind`, `Command`, `Result`, `CensusRow`, `Config` |
| [equipment](../../src/core/inventory/equipment.luau) | `equipment` configures wear normalization/copy transfers, breakage, repair quotes/plans and equip/unequip exchanges | `Requirements`, `ItemDef`, `ItemLookup`, `Equipment`, `Inventory`, `Wear`, `Decision`, `InventoryPort`, `Config`, `Plan`, `API` |
| [stacks](../../src/core/inventory/stacks.luau) | `addToBag`, `capacity`, `copyBag`, `entries`, `fits`, `hasItem`, `isValidCount`, `normalizeBindings`, `permanent`, `removeFromBag`, `stacks`, `unboundCount` | `Inventory`, `Holdings`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply stack/capacity/permanent-item policy and cargo identity, quantity, timestamp and ledger bounds. The game persists inventory and settles emitted credit.
Equipment additionally needs stack operations/limits and eligibility/slot policy. Supply item lookup with
durability bounds, contact/damage wear and repair cost. `repairWear` checks the current quote and funds,
then returns new wear and the exact debit; the game owns profile currency fields and atomic installation.
Keep item catalogs, class/proficiency rules, currency display, balance, bindings and native rig application local.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/inventory/cargo.verify.luau --name "hands off a dropped claim once and deposits it with replay-safe credit"
```

The [executable specification](../../src/core/inventory/cargo.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: hands off a dropped claim once and deposits it with replay-safe credit.

Run the [equipment fixture](../../src/core/inventory/equipment.verify.luau) with:

```sh
lute run tools/gate.luau --file src/core/inventory/equipment.verify.luau
```

It uses a three-unit stack bound, small bag capacity and neutral eligibility policy to exercise exchanges,
per-copy custody, breakage, current repair quotes, insufficient funds and malformed wear.

## Invariants

Capacity and stack limits hold. Bound/worn/permanent rules are explicit. A claim has one custodian and cannot be deposited twice.
Wear follows a particular copy through equipment, bag and bank operations. Plans preserve their input maps.
Broken items contribute no active equipment. A changed quote or insufficient funds cannot produce a repair.
