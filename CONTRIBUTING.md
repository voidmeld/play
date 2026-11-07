# Contributing to Play

Thank you for helping improve Play. Play supplies typed, deterministic game systems for Luau and Roblox.

## Setup

Install [Rokit](https://github.com/rojo-rbx/rokit), then install the pinned tools from the repository root:

```console
rokit install
```

## Rules

Read [AGENTS.md](AGENTS.md) before you change anything. It owns the code, documentation and integration rules.
The [API reference](docs/api.md) owns public signatures, returns and failures.

## Check your change

While you edit, run the fast checks with `lute run tools/gate.luau --tier fast`, or focus them with `--file <test file>` or `--name <text>`.
Commit the change, then run the full gate once on the clean HEAD with `lute run tools/gate.luau`.

## Pull requests

Open a pull request to `main` from a branch. Keep each pull request to one coherent change, and describe what
it changes and how you checked it. The required checks must pass. Do not push directly to `main` or bypass a
failing check.

## Reporting issues

Open a GitHub issue with the steps to reproduce, the result you expected and the result you saw.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
