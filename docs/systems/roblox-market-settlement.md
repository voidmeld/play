# Market settlement host

[System catalog](../systems.md) · [Market rules](market.md)

Coordinate an authoritative wallet with a shared order book without assuming cross-store atomicity.
Import [roblox/market-settlement](../../src/roblox/market-settlement.luau) and call
`configure(config).create(dependencies)`.

## State shape

The wallet contains coin, goods, pending consign/buy operations and claimed receipt identities.
The order book contains listings, durable operation fences and unacknowledged receipts.
The coordinator keeps one in-memory exclusion flag per instance; durable recovery lives in those stores.

## Operations and host requirements

`consign` saves a goods debit before listing; `buy` saves a coin hold before filling an order.
`cancel` claims returned goods. `claimAll` saves eligible receipt credits as one wallet batch before
acknowledgment. `heal` resolves pending operations by writing a durable known/voided book fence.

Supply configured wallet transitions, book receipt projection and the wallet's matching recovery
retention. Bind the book's atomic `apply` and `read` ports, authoritative wallet read/durable write,
optional per-item room, comparable clock and unique operation identities. A definitive refusal may
refund; an uncertain outcome must remain pending. Only one coordinator may own a session's wallet.
Wallet writes must report settled durability and preserve the profile transaction/lease policy.
The game retains catalog policy, realm admission, storage namespaces, wallet projection and native UI.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/market-settlement.verify.luau
```

The [executable fixture](../../src/roblox/market-settlement.verify.luau) binds pure configured book
and wallet transitions to in-memory ports. It checks conservation through fees, duplicate claim
recovery, lost replies, failed wallet saves, void fences and retention-bound audit holds.

## Invariants

- A book mutation follows a durable wallet debit or hold.
- An uncertain book outcome never authorizes a refund without a committed void fence.
- Receipt credits are durable before acknowledgment; replay cannot credit them twice.
- Claims which exceed item room remain on the book.
- Expiry sweep failure does not block already-visible claims.
- Holds beyond recovery retention remain for audit rather than risking duplicate credit.
