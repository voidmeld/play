# Play maintainer guide

Play supplies typed state transitions, recovery protocols and host coordinators for Luau.
Consumers own configuration, content, authority and native operations.
This file owns contribution rules. The [README](README.md) maps the tasks.

First action: find the affected area in [the API](docs/api.md), then read its linked specification and current consumers.
Read only the next required contract. For a first use, follow the [quickstart](docs/quickstart.md).
Then follow the [persistent-world assembly](docs/spine.md) and its executable scenario.

## Rules

- Keep core rules deterministic. Inject clocks, observations and host operations.
- Keep consumer identities, content, credentials and destinations in the consumer.
- Start every maintained Luau file with `--!strict`. Use no explicit `any` or type assertions.
- Write tools in Lute Luau. Add no comments except compiler directives and required license notices.
- Change a contract with its consumers. Preserve ownership, refusal meanings and stored schemas.
- Inspect runtime, dynamic, CLI and test consumers before removing a public surface.
- Keep one current contract in `docs/api.md`. Its generated appendix supplies declarations only.
- Return actual committed readbacks. Preserve receipts after uncertain writes. Do not report uncertainty as success.

## Validate

- During edits, use `lute run tools/gate.luau --file src/core/threat/table.verify.luau` or `--tier fast`.
- Use Verify cases. After changing the specification list, run `lute run tools/check-test-manifest.luau --write`.
- After changing declarations, run `lute run tools/generate-api.luau --write`. Review the hand-written contract too.
- Commit the candidate. Run `lute run tools/gate.luau` on the clean HEAD, including the fresh-clone check.
- Do not change verified bytes before integration. Reuse evidence while its inputs remain unchanged.
- Read [validation](docs/validation.md) only for setup, selectors or failure diagnosis.

## Repository

Use a pull request to `main` and the required `Gate` check.
Do not push directly to `main` or bypass a failed check.
Publish, repin and check affected consumers together under their owner's authority.
Use author and committer `voidmeld <158495725+voidmeld@users.noreply.github.com>` without attribution trailers.
