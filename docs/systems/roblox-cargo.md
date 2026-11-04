# Durable cargo custody

[System catalog](../systems.md) · [Inventory rules](inventory.md) · [Material ledger](roblox-material-ledger.md)

The host store is the kernel `store.Port`: uncached `read` and atomic `update` return the kernel
`Result`. Reads never submit update callbacks. Cancelled cargo and settlement replays require a
fresh complete-record confirmation before acknowledgement. Bind native stores with
`roblox/persistence/store.new`; staged ledger transforms use the same port inside the atomic write.

Coordinate carried claims, recoverable drops and durable extraction through configured cargo rules.
Import [roblox/cargo](../../src/roblox/cargo.luau), `configure` the rules/policy, then call `mount` with
camp loading, store and key ports. `mountFromContent` additionally reports missing source/store wiring.

## State shape

A zone record contains `schemaVersion`, `zoneId` and the configured cargo state: monotonic clock,
claims, drops and extraction receipts. Each claim is carried, dropped, banked or lost. Camps contain
identity, realm, center and safe radius. Outcome projections report custody counts, intent receipts,
replay state and the adopter-owned boundary label.

## Operations and required host operations

`carry`, `release`, `recover` and `expire` validate request envelopes and commit one cargo transition.
`extract` additionally checks the configured realm's camp and radius, commits banked custody, then
settles every produced material intent inside one ledger-record transform. A tear between cargo and
ledger leaves a replayable extraction receipt; retrying the same identity heals its grants without
duplicating them. `read`, `campFor`, `campIds`, `emptyState` and `admitsExtraction` expose projections
and admission facts. Read operations cancel their transforms and require explicit cancellation replies.

Supply a pure cargo core, configured material-ledger API, known realms, schema/text/clock bounds,
carried/banked space labels, banked-space refusal, drop expiry and boundary label. Supply camp rows,
`store.update`, `keyForHaul` and `keyForLedger`. The ledger API must use the provided staged store and
perform no external I/O inside a cargo settlement transform. The backend returns actual committed
readbacks; uncertainty must remain observable. Caller-supplied time must be authoritative.

The game owns authenticated actors, world/content projection, native presence/location/death signals,
camp/realm policy, storage namespaces, migrations, retention and deployment. The host operates on data
positions, not native geometry. It does not discover services or infer that an actor is at its claimed position.

## Runnable example

```sh
lute run tools/gate.luau --file src/roblox/cargo.verify.luau
```

The [fixture](../../src/roblox/cargo.verify.luau) uses short expiry, different space labels, one neutral
realm, schema seven and small bounds. It exercises two-material custody/recovery, torn settlement and
replay, exact-radius admission, expiry, callback retries and divergent readbacks at all write boundaries.

## Invariants

- A material claim has exactly one custody state.
- Banked-space yields cannot enter carried custody.
- Extraction requires the caller's configured realm camp and accepts the exact radius boundary.
- Cargo custody commits before ledger grants; a replay receipt heals the two-record tear.
- All extraction grants are staged inside one atomic ledger transform.
- Callback retries discard earlier speculative results.
- Cargo and ledger writes require exact desired committed readbacks before reporting success.
- Divergent readbacks remain reconcilable through the original claim/extraction receipts.
