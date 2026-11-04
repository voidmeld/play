# Lease

[Return to systems](../systems.md).

The lease kernel supplies pure acquisition, renewal and release rules. Its state contains a
revision, optional session and acquisition identities, and an expiry. An unowned state has no
owner identities and zero expiry. It has no host operations or persistence schema.

Configure revision, time and identity bounds and whether times must be whole numbers.
Configuration is captured at construction. Each operation returns the shared Result envelope.
The [generated API](../api.md#kernellease) owns exact declarations.

Acquisition replays an unexpired matching acquisition without advancing its revision.
A different owner refuses while its lease is fresh unless the caller has confirmed it dead.
A confirmed live owner refuses takeover even after expiry. Unknown liveness uses expiry.
Successful acquisition, renewal and release advance the revision. Renewal and release require
both owner identities and the expected revision; renewal also requires an unexpired lease.

The copy operation admits only the lease projection of a decoded domain record. Domain codecs
own field sets and saved formats. Account leases retain their version, false owner sentinels,
Unix expiry name and acquisition fence; their adapter maps those fields to the kernel state.
Character leases retain their separate retirement and arrival receipts. The kernel does not
rewrite saved data or equate an acquisition fence with a write revision.

The caller supplies the clock value and any authoritative liveness observation. Never infer
death from an unavailable host operation. These rules decide a proposed transition; an atomic
store must still prove committed readback before an adapter grants authority.

Run the executable lifecycle and refusal examples:

~~~sh
lute run tools/gate.luau --only specs --file src/kernel/lease.verify.luau
~~~

The [specification](../../src/kernel/lease.verify.luau) proves idempotent acquisition,
generation fencing, detached transitions, live and uncertain ownership, and invalid state/time
refusal. The identity account and character specifications prove their stored formats and host
readback contracts while consuming these same rules.
