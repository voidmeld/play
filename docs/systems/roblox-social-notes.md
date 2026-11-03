# Preset note host

[System catalog](../systems.md) · [Note rules](social.md)

Coordinate preset inbox delivery and projections without accepting arbitrary message text.
Import [roblox/social-notes](../../src/roblox/social-notes.luau), configure phrase parsing,
expiry projection, label and send interval, then call `create` with inbox and recipient ports.

## State shape

Durable inbox records own note identities, authors, phrase identities, read status and receipt history.
The coordinator caches inboxes and the last send attempt time per subject. Catalog text remains external.

## Operations and required host operations

`recipients` deduplicates group and candidate views. `send` validates the preset, throttle, recipient,
sender name, contact policy and platform filter before delivery. `refresh`, `noticed`, `markRead`,
`projection` and `forget` manage readback, privacy, expiry and session lifetime.
Supply durable inbox operations, clock, names and recipients plus current catalog, contact, filter,
read-privacy and notification ports. A missing filter fails closed. The game owns phrase content,
permissions, storage namespace, native filtering and notifications.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-messaging.verify.luau
```

The [fixture](../../src/roblox/social-messaging.verify.luau) uses real note rules and durable inbox
coordination with neutral phrases, a three-second throttle and a fifty-second lifetime.

## Invariants

- Only current catalog phrases reach durable delivery.
- Unknown recipients and refused contact/filter decisions cannot store notes.
- Privacy hides cached inbox contents; expiry removes notes from projections.
- Read acknowledgment changes durable inbox state before cache replacement.
- Forgetting a subject discards its throttle and inbox caches.
