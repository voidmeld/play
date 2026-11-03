# Formation host

[System catalog](../systems.md) · [Fellowship host](roblox-social-fellowship.md)

Coordinate a multi-founder charter and an idempotent profile fee across durable social records.
Import [roblox/social-formation](../../src/roblox/social-formation.luau), configure home/privacy policy,
founder count, fee display and fallback label, then `create` it with the shared social host and ports.

## State shape

Durable formation state tracks founders, invitations, consent, expiry, fee phase and resulting guild.
A proposer pointer connects an interrupted charter with its fee. Public view types describe incoming
invitations, founders, progress and completion availability. The game retains the actual fee ledger,
currency representation, name/home catalog and persisted namespaces.

## Operations and host requirements

`start`, `invite`, `answer`, `complete`, `projection` and `settle` coordinate the lifecycle.
Supply social records, shared membership custody, grouping-domain/name lookup, fresh privacy relations,
event ids, clock, home catalog and notifications. The fee port supplies idempotent hold/commit/refund
operations returning explicit committed/replayed/rejected/uncertain outcomes. The configured founder
count and fee must match the formation rules behind the record port. Bind durable profile effects and
exact session/character authority in the game; callbacks must reconcile receipts after uncertainty.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-fellowship.verify.luau --name "formation host"
```

The [executable fixture](../../src/roblox/social-fellowship.verify.luau) uses a two-founder charter
and a seven-unit fee. It verifies completion, membership confirmation, repeated settlement and recovery
across uncertain holds, fee commits, refunds and an unreadable charter-write response.

## Invariants

- A durable proposer pointer precedes the fee hold and charter write.
- Uncertain holds and refunds retain their proposer pointer for reconciliation.
- Privacy admission and current membership precede founder consent.
- All required membership claims precede charter completion.
- Completed guild records and membership confirmation remain recoverable across fee-commit failure.
- Proposer pointers clear only after the relevant fee outcome is confirmed.
