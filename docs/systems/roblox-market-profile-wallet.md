# Profile market wallet

[System catalog](../systems.md) · [Market settlement](roblox-market-settlement.md)

Project a market wallet from an authoritative profile and apply paired writes as deltas.
Import [roblox/market-profile-wallet](../../src/roblox/market-profile-wallet.luau), call
`configure(config)`, then `create(dependencies)`.

## State shape

The profile type and item source are generic. The configured projections expose coin, inventory,
market ledger and tradeable goods. `Wallet` supplies `read`, `write` and `room` to settlement.
Each instance remembers one paired read; the profile owner retains authoritative state and durability.

## Operations and host requirements

`read` composes the current wallet and captures its baseline. `write` consumes that baseline,
applies the successor's deltas to the latest profile, installs its ledger and requests a durable save.
`room` reports current item room. `applyDelta` exposes the same pure projection for independent checks.

Configure wallet codecs, item source, profile projections, tradeable-goods policy, account writer,
capacity, entries, fit and unbound-count rules. Dependencies supply subject identity, material ids,
profile read/update/save operations and stack/entry bounds. Updates must complete their transform
before returning and may retry. A save must report settled durability. Keep one owning wallet
coordinator per session and retain uncertain writes for settlement recovery.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/market-profile-wallet.verify.luau
```

The [executable fixture](../../src/roblox/market-profile-wallet.verify.luau) uses real wallet/stack
rules with a neutral profile. It checks concurrent rewards, paired-write consumption, bound removals,
capacity, callback retries and uncertain saves.

## Invariants

- Writes preserve rewards or inventory changes received after the paired read.
- A consumed or missing baseline cannot authorize another write.
- Negative balances, bound removal and capacity overflow preserve the refused profile.
- The final transform's acceptance determines whether saving proceeds after a retry.
- Success requires the profile owner to confirm durable saving.
