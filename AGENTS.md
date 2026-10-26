# Play

Play holds reusable game systems extracted from real consumers. Keep each system strict, pure and
parameterized by game-supplied data; game canon, content, credentials and destinations stay in the
consuming game.

- Every module is `--!strict` with no explicit `any` or escape casts.
- Change a contract only with its consumer: publish, repin and prove the adopter together.
- Add no comments except compiler directives.
## Validate

- Run focused checks while editing: `lute run tools/gate.luau --tier fast`, `--only producer`, `--file path.verify.luau` or `--name text`.
- Write tests as Verify cases. After adding or removing a specification, run `lute run tools/check-test-manifest.luau --write`.
- Commit the candidate, then run `lute run tools/gate.luau` on the clean HEAD. Its fresh-clone check must pass before integration. Do not change verified bytes after the gate.
- Reuse evidence while its inputs stay unchanged.

## Repository

Changes use a pull request to `main` and the required `Gate` check. Do not push directly to `main` or bypass a failing check. This private repository requires maintainers to uphold this rule even when GitHub cannot enforce branch protection. CI runs the same gate on every pull request and push.

Use author and committer `voidmeld <158495725+voidmeld@users.noreply.github.com>`. Add no attribution trailers.
