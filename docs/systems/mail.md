# mail

[System catalog](../systems.md) · [Play](../../README.md)

Manage attachment custody, claims, returns and uncertain-write recovery.

## State shape

`Envelope` contains phase, sender/recipient, attachments and receipts. `Pointer` indexes mailbox entries; `Account` holds coin and inventory.

Types and configuration are exported from [src/core/mail.luau](../../src/core/mail.luau).

## Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [mailbox](../../src/core/mail/mailbox.luau) | `advance`, `attachments`, `credit`, `debit`, `id`, `mailbox`, `pointers`, `prepare`, `read`, `sameRequest`, `valid` | `Inventory`, `Account`, `Stack`, `Attachments`, `Phase`, `Envelope`, `Pointer`, `Config`, `Mailbox` |

The linked components declare their factories and operations; see the [API reference](../api.md).

## Required host operations

Supply profile/account conversion, bag capacity, item admission, limits, time and identity. Persist mailbox transitions and account effects atomically.

Use the [host-operation contract](../../README.md#host-operation-contract) when installing state,
handling uncertain writes and releasing resources.

## Runnable example

From the repository root after [tool setup](../validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/mail/mailbox.verify.luau --name "reads detached envelopes and refuses malformed or executable stored values"
```

The [executable specification](../../src/core/mail/mailbox.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: reads detached envelopes and refuses malformed or executable stored values.

## Invariants

Malformed/executable records refuse. Accepted reads are detached. Attachments cannot be claimed twice or duplicated by return/recovery.
