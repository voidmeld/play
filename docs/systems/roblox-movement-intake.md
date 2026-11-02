# movement-intake

[System catalog](../systems.md) · [Play](../../README.md)

Validate authoritative movement against body epochs, ordering and speed bounds.

## State shape

`State` retains epoch/sequence, baseline and motion budget; `Observation` and `Ack` carry host readback.

Types and configuration are exported from [src/roblox/movement-intake.luau](../../src/roblox/movement-intake.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [movement-intake](../../src/roblox/movement-intake.luau) | `start` | `Point`, `State`, `Observation`, `Normalized`, `Ack`, `Dependencies`, `StopResult`, `Started`, `Refused` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject body/session observations, clock, world admission, movement normalization, correction and acknowledgment.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/movement-intake.verify.luau --name "refuses and restores a same-body frontier displacement"
```

The [executable specification](../../src/roblox/movement-intake.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: refuses and restores a same-body frontier displacement.

## Invariants

Displacement/sustained-speed violations revoke authority. A stale body or epoch cannot move a replacement. Refusals restore the authoritative baseline.
