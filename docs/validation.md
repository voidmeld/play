# Validation

[Return to Play](../README.md).

## Tools

Set `ROKIT_ROOT` to your Rokit directory.
Put its `bin` directory first on `PATH`.

## During changes

Run the fast gate:

```sh
lute run tools/gate.luau --tier fast
```

The fast gate checks types, the test manifest, specification style, boundaries, source origin, exports, comments, format, and lint.
It also checks for game data in shared code and runs the specifications and Verify checks.
The fast gate excludes the war benchmark and the clean clone check.

The `game-canon` producer checks runtime modules, specifications and fake hosts for adopter-specific
world, faction, class and group identities. Use neutral fixture identifiers; keep game examples in the adopter.

The `examples` producer runs the standalone threat, input-binding, thumbstick and character-lease examples:

```sh
lute run tools/run-examples.luau
```

Every [system guide](systems.md) also links an executable Verify example and its focused command.

The API reference is generated from parsed exported declarations and public operations.
After changing an exported type, function signature or returned operation, regenerate it:

```sh
lute run tools/generate-api.luau --write
```

`lute run tools/generate-api.luau` checks freshness without writing. The `api-reference`
gate producer runs this check. Core system entries are `src/core/<system>.luau`, with an
exported `API` type and component-prefixed aliases for their exported types. Existing
component imports remain compatible. Helpers live under `src/core/internal`; the old
value/shape paths forward to their implementations for existing adopters.

For a focused check, select a producer:

```sh
lute run tools/gate.luau --only spec-style
```

Use `--file path.verify.luau` to select a specification file.
Use `--name text` to select cases by name.
Use Verify cases for tests.
After you add or remove a specification file, update the manifest:

```sh
lute run tools/check-test-manifest.luau --write
```

Create the BDD interface with `Bdd.create`.
Declare `local describe, it, expect` once in each specification.
Use dot calls for case registration.
Do not use context expectations or dotted `Test.it`, `Test.expect`, and `Test.describe` calls.
The style check includes untracked specifications.
For tests of Verify's raw harness API, use `specStyle.exclude` in `tools/checks-config.luau`.

## Before integration

Commit the candidate before the full gate.
Run the full gate on the clean HEAD:

```sh
lute run tools/gate.luau
```

The full gate includes a fresh clone check.
Make sure this check passes before integration.
Do not change verified bytes after the gate.
Reuse evidence while its inputs stay the same.
Follow the integration rules in `AGENTS.md`.
