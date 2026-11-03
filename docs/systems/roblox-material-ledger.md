# Durable material ledger

[System catalog](../systems.md) · [Ledger rules](ledger.md) · [Cargo](roblox-cargo.md)

Persist configured material-journal transitions with bounded replay receipts and exact readback.
Import [roblox/material-ledger](../../src/roblox/material-ledger.luau) and call `configure` with ledger
rules, saved schema version, receipt-window size, text bound and an adopter-owned boundary label.

## State shape

A saved record contains `schemaVersion`, the full material event journal, recent event IDs and the
timestamp floor preceding that receipt window. `NO_FLOOR` is the negative sentinel used before the
window fills. Event amounts/kinds/group rules come from the supplied ledger core. Snapshot outcomes
carry existence, balances, torn groups, event count, replay floor and the configured boundary label.

## Operations and required host operations

`append(store, keyForLedger, ledgerId, event)` validates through the configured core, checks replay
admission and applies the event inside an atomic transform. A retained exact replay cancels the write
and acknowledges the existing receipt. An event outside the retained window at or below its floor is
refused as unverifiable. A successful write requires the exact desired committed record in its reply.

`snapshot` reads by cancelling an atomic transform after validating and projecting the current record;
the backend must distinguish callback cancellation from transport failure. Supply `store.update` and
an owned key function. Transforms can repeat: speculative results are cleared on every invocation.
Core operations must be pure. The host owns schema migrations, storage scope, admission/authentication,
native scheduling, backend budgets and eventual reconciliation after uncertainty.

The journal itself is not pruned by the receipt window. The window limits replay evidence, rather than
total storage growth. Keep retention and backend size policy in the adopter.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/cargo.verify.luau
```

The [fixture](../../src/roblox/cargo.verify.luau) uses schema seven, a two-receipt window and a fake
atomic store. It exercises retained and expired replay evidence, final-transform refusal, divergent
readback and cargo-to-ledger reconciliation. It does not establish native multi-server interleaving.

## Invariants

- Malformed records and unrecognized schemas fail closed.
- The saved receipt window and floor must match the validated journal.
- Speculative results from earlier callback invocations cannot authorize a final refusal.
- Backend success with a divergent readback is uncertainty, rather than a granted result.
- Replayed receipts never apply a second material grant.
- A snapshot operation cannot silently write a record or interpret transport failure as absence.
