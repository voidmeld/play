# cue-playback

[System catalog](../systems.md) · [Play](../../README.md)

Play admitted cue identities and drive bounded frame effects.

## State shape

Voice lifetime belongs to the returned player; `VoiceProps`/`PlaySpec` describe configured native work.

Types and configuration are exported from [src/roblox/cue-playback.luau](../../src/roblox/cue-playback.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [cue-playback](../../src/roblox/cue-playback.luau) | `animator`, `make` | `VoiceProps`, `PlaySpec`, `Source`, `Deps` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Inject catalog/admission, voice mount/play, scheduler, home, tail duration, clock and render-connect operations.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/cue-playback.verify.luau --name "limits voices and retriggers with a clock seam and ducks only active families"
```

The [executable specification](../../src/roblox/cue-playback.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: limits voices and retriggers with a clock seam and ducks only active families.

## Invariants

Voices retire after configured lifetime/tail. Animation begins at zero, clamps progress and disconnects on completion.
