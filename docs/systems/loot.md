# loot

[System catalog](../systems.md) · [Play](../../README.md)

Draw configured loot and settle party need/greed/pass choices.

## State shape

Roll tables produce `Drop` values with receipt identity. A party `Decision` holds seats, choices, fixed deadline and saved `Result`.

Types and configuration are exported from [src/core/loot.luau](../../src/core/loot.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [decision](../../src/core/loot/decision.luau) | `decision`, `declare`, `due`, `open`, `settle` | `Choice`, `Seat`, `Result`, `Decision`, `Refusal`, `Config` |
| [roll](../../src/core/loot/roll.luau) | `dropFor`, `dropsFor`, `receiptFor`, `roll`, `tableForMob`, `validRoll` | `Roll`, `Table`, `Drop`, `Config` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply authored tables, receipt prefix, random samples, decision window and party eligibility. The host selects recipients and persists grants.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/loot/decision.verify.luau --name "closes thirty seconds after it opens"
```

The [executable specification](../../src/core/loot/decision.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: closes thirty seconds after it opens.

## Invariants

Choice deadlines are fixed. Each seat chooses once under the configured decision rules. The saved result is reused; all-pass fallback advances the configured party cursor.
