# Store

[Return to systems](../systems.md).

`src/kernel/store` owns the atomic storage port, compare-and-swap transform and
committed-readback check. Exact types and operations are in the [generated API](../api.md#kernelstore).
The primitive has no domain state, key namespace, clock or host service. Records and
character leases use the same port; their codecs and authority rules remain in their systems.

Readback is untrusted stored data. A successful read may carry nil for absence;
failure is a refused Result. Decode the payload before using it. An update transform
may run repeatedly against different snapshots. It must be pure, return a detached
next value, or return nil to cancel. Only the final committed readback can authorize
success; a value calculated during an earlier callback is not a receipt.

`compareAndSwap` checks absence or the entire decoded expected record, then copies
the desired record for the backend. Revision equality alone does not prove that
private payload fields still match. `committed` decodes and compares the returned
record against the desired value, refusing valid but divergent readback.

The [native binding](../../src/roblox/persistence/store.luau) wraps the existing
budgeted storage backend's uncached read and atomic update operations. It exposes
`read` and `update` through the kernel port and gives backend refusals a reason.
An uncertain backend failure may follow a committed write; a caller must reconcile
durable state rather than infer that nothing happened.

The [fake host](../../src/test-scene/persistence/store.luau) exposes the same port,
with an injected clock, optional initial records, fixture seeding, committed-write and
update-attempt counts, and the backend's retry/fault seams. Its `values` map is a test
control for inspecting or poisoning durable bytes; authoritative consumers use the port,
which detaches readback from that map. Fixture controls are outside the authoritative port.

Run the executable example and invariants:

```sh
lute run tools/gate.luau --only specs --file src/kernel/store.verify.luau
```

The [specification](../../src/kernel/store.verify.luau) checks absent reads, full
record comparison, final-callback cancellation, failure after commit, exact readback
and detached read values. It uses the real binding and fake backend, and does not
claim native cross-server or network proof.
