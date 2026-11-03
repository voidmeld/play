# Guild bank host

[System catalog](../systems.md) · [Guild ledger rules](social.md)

Settle authoritative profile inventory against a shared guild bank with durable holds and receipts.
Import [roblox/guild-bank](../../src/roblox/guild-bank.luau), configure profile/ledger projections
and limits, then call `mount(dependencies)`.

## State shape

The shared bank owns stock, withdrawals, receipt credits, operation fences and logs.
Profiles own pending deposit holds and unacknowledged receipt identities. The profile type is generic.
The host retains per-subject exclusion, recovery admission and cached bank projections.

## Operations and host requirements

`join` reconciles pending holds and receipt acknowledgments before admitting transfers.
`deposit` saves a profile debit before the bank mutation. `withdraw` verifies room, applies the shared
bank decision, saves receipt credits and acknowledges them. `refresh`, `projection` and `forget`
manage recovery and server views.

Configure ledger transitions, profile copy/inventory/ledger/capacity projections, receipt selection,
stack/transfer/display limits and matching recovery/receipt retention. Dependencies supply bank
read/atomic-apply ports, material labels, current/fresh membership, profile read/update/save, clock
and unique operation identities. Profile transforms must complete before returning and may retry.
The final callback acceptance governs saving; a missing callback cannot authorize a bank write.
Store replies must describe committed readback and distinguish uncertainty from definitive refusal.
Keep catalogs, profile schema, storage scope, role policy, session authority and native UI in the game.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/guild-bank.verify.luau
```

The [executable fixture](../../src/roblox/guild-bank.verify.luau) composes actual bank and profile
ledger rules with neutral accounts. It checks deposits/claims, replay, member limits, lost replies,
callback retries, missing callbacks and missing bank readback.

## Invariants

- A durable profile debit precedes a deposit mutation on the shared bank.
- An uncertain deposit stays held until a known/voided operation fence settles it.
- Receipt credits are saved before acknowledgment and cannot be claimed twice.
- Missing bank state never authorizes clearing profile acknowledgment evidence.
- Final transform acceptance controls saving after retries.
- Holds beyond retention remain for audit; stale receipts expire only under current membership policy.
