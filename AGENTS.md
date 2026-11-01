# Play

[Return to Play](README.md).

Play supplies reusable systems from games that use them.
Keep each system strict and pure.
Supply system parameters from game data.
Keep game canon, content, credentials, and destinations in the game.

- Use `--!strict` in every module.
- Do not use explicit `any` or escape casts.
- Change a contract only with its consumer.
- Publish, repin, and test the adopter together.
- Add no comments except compiler directives.

## Validate

Follow the [validation procedure](docs/validation.md) for changes and integration.

## Repository

Use a pull request to `main` with the required `Gate` check.
Do not push directly to `main`.
Do not bypass a failing check.
Maintainers must follow this rule when GitHub cannot enforce branch protection.
CI runs the same gate on every pull request and push.

Use author and committer `voidmeld <158495725+voidmeld@users.noreply.github.com>`.
Add no attribution trailers.

Every maintained Luau file requires `--!strict`, zero explicit `any` and zero type assertions
(`::`), including concrete casts. The required gate rejects violations without a baseline or exemptions.
