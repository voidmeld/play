# Play

Play supplies typed game systems for Luau.
The systems include quests, inventory, mail, groups, trade, and progression.
The game supplies content, configuration, and host operations.

First, run the fast checks from the repository root:

```powershell
$env:PATH = "$env:ROKIT_ROOT/bin;$env:PATH"
lute run tools/gate.luau --tier fast
```

## Documentation

| Page | Use |
| --- | --- |
| [Systems](docs/systems.md) | Select a system and read the host requirements. |
| [API](docs/api.md) | Find exports, declarations, and signatures. |
| [Validation](docs/validation.md) | Run focused checks or the full gate. |
| [Repository rules](AGENTS.md) | Read the code and integration rules. |
| [Change report](ready.md) | Review this simplification and its limits. |

The modules in `src/core` contain deterministic rules without engine operations.
The adapters in `src/roblox` use injected Roblox operations.
The fake hosts in `src/test-scene` run only in Lute.
Exclude `src/test-scene` from Roblox module trees.
