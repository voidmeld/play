# cue-mixer

[System catalog](../systems.md) · [Play](../../README.md)

Admit cue voices with retrigger, family caps and ducking.

## State shape

`Mixer` retains cue deadlines and active voices by family; `MixSpec`/`DuckSpec` carry policy.

Types and configuration are exported from [src/roblox/cue-mixer.luau](../../src/roblox/cue-mixer.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [cue-mixer](../../src/roblox/cue-mixer.luau) | `activeVoices`, `admit`, `duckGain`, `gate`, `new`, `setVoiceActive` | `MixSpec`, `DuckSpec`, `CueSource`, `Mixer` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply `CueSource`, mix definitions and a clock. Report native voice activity.

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

Unknown cues refuse admission. Retrigger/cap admission is deterministic. Only configured active families cause ducking.
