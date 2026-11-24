---
name: play
description: Use this skill to adopt or call Play's persistent-world game systems (quests, items, loot, economy, social, combat, persistence) and their Roblox adapters from a game. Do not use it to author game content or to change Play itself.
---

# Use Play

Play supplies the rules of a persistent-world game as pure, strict Luau. Your game supplies the content,
policy, saved schemas and server authority. Use this skill when a game calls a Play family or binds a
Play adapter to the engine.

## Install

Pin an exact commit in the game's `pkg.luau` and install it with Lute `1.0.1-nightly.20261120` or newer:

```luau
return {
	package = {
		dependencies = {
			play = { sourceKind = "github", source = "https://github.com/voidmeld/play", rev = "<commit>" },
		},
	},
}
```

Run `lute pkg install --vendor`, commit `pkg.lock.luau`, ignore `.lpm/`, and alias the copy in
`.config.luau`: `play = "./.lpm/play@<commit>"`. This skill installs at
`.lpm/play@<commit>/.agents/skills/play/SKILL.md`.

## Public surface

- `src/core/<family>`: one module per family (for example `threat`, `quest`, `inventory`, `trade`,
  `market`, `persistence`). Each exports an `API` type with its components.
- `src/roblox/<adapter>`: native adapters over explicit host operations (DataStore sessions, remotes,
  character admission, input, chat, market settlement).
- `src/kernel/<primitive>`: shared primitives (`value`, `codec`, `result`, `lease`, `store`, `event-log`).
- `internal` modules and `tools/fixtures` are not public contracts. Fixtures exist for verification only and
  need a `verify` alias.

The [API reference](../../../docs/api.md) owns signatures, returns, failures and the required host
operations of each area. Start from its task table; read only the area you use.

## Example

```luau
local Threat = require("@play/src/core/threat")

local rules = Threat.table.rules({ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 })
local state = Threat.table.empty()
local nextState, firstTarget = rules.add(state, "actor-a", 10, true)
state = nextState
assert(firstTarget)
state = rules.taunt(state, "actor-b")
assert(state.targetActorId == "actor-b")
```

## Rules

1. Rules take state and return new state or a refusal (`nil, reason`, or a result envelope that needs `ok`
   first). Install the new state under your own authority boundary; never mutate borrowed input.
2. Decode untrusted input with the area's request or record projector. Static types do not admit remote data.
3. Assertions reject invalid trusted configuration. Do not catch them to invent a success.
4. Host failures keep uncertainty and recovery receipts. Never infer a committed write from a callback.
5. Follow [adoption](../../../docs/adoption.md) to cut one consumer over: one binding for policy, schema and
   host operations, the game's own regressions, then removal of the displaced implementation.
