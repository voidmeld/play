# Mail host

[System catalog](../systems.md) · [Mailbox transitions](mail.md)

Coordinate receipt-backed mail delivery between authoritative profiles and an envelope store.
Import [roblox/mail](../../src/roblox/mail.luau), call `configure(config)`, then `create(dependencies)`.

## State shape

The pure mailbox supplies `Envelope` and `Pointer` shapes. Envelopes contain sender and recipient
identities, optional character identities, attachments, timestamps and a durable decision phase.
Profiles retain pending hold/claim pointers and the transaction ledger under game-owned projections.
The host keeps only in-flight exclusion and rate windows in memory.

## Operations and host requirements

`send` reserves inbox space, prepares an envelope, holds attachments and dispatches it.
`claim`, `returnMail` and `expire` choose durable outcomes. `recover` completes interrupted effects;
`admit` reconciles pointers on profile admission. `status` reads a participant's envelope.

Supply configured mailbox operations, profile lookup/update/commit, character and pointer
projections, identity decoding, storage and transaction namespaces, sender decoding and limits.
The profile commit port must atomically install its effect and transaction receipt, replay without
duplicating effects and report the actual durability outcome. Update callbacks may retry.

Per-instance dependencies supply envelope reads/atomic updates, active contexts, recipient lookup,
tradeability and send policy, inbox reservation/release, clock, TTL and session fencing selection.
Store updates must return the committed readback; uncertain writes are reconciled by reading.
Use comparable persisted timestamps. Keep native player decoding, names, schemas and storage scope
in the game. When session fencing is enabled, both profile and envelope character identities must match.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/mail.verify.luau
```

The [executable fixture](../../src/roblox/mail.verify.luau) uses neutral accounts and injectable
faults. It demonstrates uncertain writes, repeated requests, one-time delivery, interrupted claim
admission, unreadable decisions, character replacement and return to sender.

## Invariants

- Reusing a request with different participants or attachments refuses the conflict.
- A hold and its pointer are installed together through an idempotent transaction.
- A durable decision precedes delivery; retries cannot duplicate the transfer.
- Unreadable decisions remain pending without authorizing new effects.
- Replacement characters cannot receive another character's attachment.
- Inbox release and pointer cleanup remain recoverable after the transfer settles.
