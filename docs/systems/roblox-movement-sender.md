# movement-sender

[System catalog](../systems.md) · [Play](../../README.md)

Send client movement through an epoch handshake and acknowledgment ledger.

## State shape

The connection retains body epoch, pending sequence samples, resend timing and held planar movement.

Types and configuration are exported from [src/roblox/movement-sender.luau](../../src/roblox/movement-sender.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [movement-sender](../../src/roblox/movement-sender.luau) | `start` | `Planar`, `Refused`, `Stopped`, `Started`, `StartResult`, `Payload`, `Connection`, `Dependencies` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject start/stop/heartbeat/ack wiring, body placement observations, clock and network submission.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/movement-sender.verify.luau --name "echoes the acknowledged body epoch and clears held movement when placement invalidates it"
```

The [executable specification](../../src/roblox/movement-sender.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: echoes the acknowledged body epoch and clears held movement when placement invalidates it.

## Invariants

Placement invalidation clears held movement. Acknowledgments reclaim only admitted samples. Invalid authority stops submission.
