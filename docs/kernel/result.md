# Result

[Return to systems](../systems.md).

`src/kernel/result` owns the shared success or refusal envelope. Exact exported
types and helpers are in the [generated API](../api.md#kernelresult). It has no
mutable state or host requirements. A refusal has a required reason and optional
detail; a success carries the operation's value, which may itself be nil.

Check `ok` before accessing the payload. The `reason` helper returns nil for success
and the refusal reason otherwise, without changing the envelope. Constructors do
not freeze payloads or decode untrusted data; domain codecs still own admission.

Material ledger append and snapshot operations use this contract, as does the
adopting game's character repository binding. Store-port envelopes move with the
atomic Store primitive; other domain responses remain described by their respective
guides during the kernel migration.

Run the [ledger specification](../../src/roblox/material-ledger.verify.luau):

```sh
lute run tools/gate.luau --only specs --file src/roblox/material-ledger.verify.luau
```

It exercises the real coordinator against fake storage ports: retained receipts
replay without applying twice, old unverifiable receipts refuse, divergent committed
readbacks fail closed, and a speculative callback cannot supply a success after
the final callback refuses. Success carries the append or snapshot payload; refusal
carries its required reason.
