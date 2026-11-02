# control

[System catalog](../systems.md) · [Play](../../README.md)

Apply diminishing control durations with fixed reset deadlines.

## State shape

`State` maps families to `Bucket` values; `Category` selects policy and `Result` returns the admitted duration and next state.

Types and configuration are exported from [src/core/control.luau](../../src/core/control.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [diminishing](../../src/core/control/diminishing.luau) | `apply`, `clone`, `empty`, `rules` | `Bucket`, `State`, `Category`, `Config`, `Step`, `Result` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply category definitions, duration steps, reset windows and time. The host applies admitted control and installs state.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/control/diminishing.verify.luau --name "duration steps retain a fixed reset deadline and saturate until exact expiry"
```

The [executable specification](../../src/core/control/diminishing.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: duration steps retain a fixed reset deadline and saturate until exact expiry.

## Invariants

Steps saturate at immunity until reset. Exact expiry resets the bucket. A repeated application does not slide the original reset deadline.
