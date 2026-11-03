# Market host

[System catalog](../systems.md) · [Settlement host](roblox-market-settlement.md)

Coordinate market admission, catalog limits, cached book projections, merchant trades and item search.
Import [roblox/market](../../src/roblox/market.luau), call `configure(config)`, then `mount(dependencies)`.

## State shape

`Catalog` describes material identities, labels, merchant prices and operation/search limits.
`Item<R>` contains display and filtering facts with the consumer's rarity type `R`.
Each host instance caches books, per-subject settlement handles, recovery admission and search filters.
Authoritative coin, goods and receipt state remain in the supplied wallets and books.

## Operations and host requirements

`join` and `refresh` heal pending operations, claim receipts and refresh books.
`list`, `buy`, `cancel`, `listItem` and `buyItem` enforce admission and configured limits before
calling settlement. `npcSell` and `npcBuy` make a single durable wallet transition at catalog prices.
`search`, `searchItems`, `listable` and `projection` return server-owned views; `forget` releases caches.

Configure item facts, item-category policy, filter matching, settlement, book search, merchant wallet
transition, fee display and bounds. The instance supplies catalog, book ports, authoritative wallets,
subject realm lookup, trading permission, comparable clock and operation identities. Wallets must expose
available room as well as durable reads/writes. Use one host per owning profile lifetime.
Keep actual catalogs, class/equipment policy, authentication, storage scope and UI in the game.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/market.verify.luau
```

The [executable fixture](../../src/roblox/market.verify.luau) binds real order-book, wallet and
settlement systems to neutral catalogs. It exercises item purchases, custom rarity projections,
merchant prices, refused filters, permission loss and cache readmission.

## Invariants

- Shared-book trading requires permission and completed recovery admission.
- Merchant trades use the catalog's floor/ceiling and do not depend on shared-book permission.
- Purchases which exceed wallet room refuse before holding coin.
- Search filters are decoded and results come from server-owned cached books.
- Recovery failure remains pending and observes the configured retry interval.
- Display projections never write authoritative profiles.
