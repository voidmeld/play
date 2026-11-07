# Quickstart

Run one deterministic fixture before binding a native host.

## Prepare the tools

1. Install the versions in [rokit.toml](../rokit.toml) with `rokit install`.
2. Run `lute setup` from the repository root.
3. Put Rokit's `bin` directory on `PATH`.

## Select and replace state

Run the [complete example](../tools/quickstart.luau):

```console
lute run tools/quickstart.luau
```

The fixture selects a target, applies a takeover and checks a taunt.
It also checks pruning with a supplied clock. It needs no engine or external service.
The expected output is `Threat: takeover, taunt and host pruning passed at t=1`.

The public core entry exposes its components. This fragment uses the same rules without the fixture host:

```luau
local Threat = require(path.to.play.core.threat)
local rules = Threat.table.rules({ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 })
local state = Threat.table.empty()
state = rules.add(state, "actor-a", 100, true)
state = rules.add(state, "actor-b", 120, false)
assert(state.targetActorId == "actor-a")
state = rules.add(state, "actor-b", 11, false)
assert(state.targetActorId == "actor-b")
```

The caller installs each returned state. The rules do no host work.
Run the success and boundary cases with:

```console
lute run tools/gate.luau --file src/core/threat/table.verify.luau
```

## Bind a consumer

Pin an exact commit and tree. Preserve relative paths between `src/kernel`, `src/core` and `src/roblox`.
Keep `tools/fixtures` in verification only.
Read [adoption](adoption.md) for dependency setup and [the API](api.md#host-operations) for host duties.
Use the task table in the API to select the next contract.
