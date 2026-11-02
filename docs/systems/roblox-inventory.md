# Inventory host

[System catalog](../systems.md) · [Inventory rules](inventory.md)

Bind inventory reads, item mutation and receipt-backed reward bundles to an authoritative profile owner.
Import [roblox/inventory](../../src/roblox/inventory.luau) and construct it with `create(config)`.

## State shape

`Inventory` maps item identities to counts. `RewardItem` is `{ id, count }`. The generic `Service<S,R,P>`
uses the game's subject, readable handle and profile types. It keeps no profile schema or durable store.
The game supplies context identity, inventory projection, capacity, receipt reads and reward projection.

## Operations and host requirements

`getItems`, `getCount` and `hasItem` accept the caller's reader, preserving reactive reads.
`addItem` and `removeItem` apply a guarded profile transform. `commitRewardTransaction` validates a
bundle and installs its inventory, rewards and receipt through one caller-provided projection.

Supply context/readable/peek/update operations; item admission, stack arithmetic and fit rules;
profile inventory read/write; receipt admission and reward projection; stack and receipt bounds.
`update` must finish its transform before returning. A true result means the final transform accepted;
the profile owner controls durable saving. Projectors must preserve their borrowed input.

Each transform rechecks its context and clears provisional acceptance when retried. Removal uses the
inventory seen by that transform. Reward bundles copy admitted item identities and counts before host work.
The game owns catalogs, profile shape, XP/currency policy, seasonal tracks, authority and native lifetime.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/inventory.verify.luau
```

The [executable fixture](../../src/roblox/inventory.verify.luau) supplies a profile cell, context,
inventory policy and reward projector. It exercises active and lost authority, retries, capacity,
malformed rewards and receipt replay. See the [API reference](../api.md) for exact generic contracts.

## Invariants

- A refused mutation preserves the profile and its receipts.
- New stacks respect capacity; existing stacks can grow in an overfull bag under supplied fit policy.
- The final transform's context and result govern acceptance after a retry.
- A reward bundle and its receipt are projected together; replay cannot apply twice.
- Returned bags are detached, and caller changes cannot rewrite an admitted reward bundle.
