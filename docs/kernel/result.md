# Result

[Return to systems](../systems.md).

`src/kernel/result` owns the shared success or refusal envelope. Exact exported
types and helpers are in the [generated API](../api.md#kernelresult). It has no
mutable state or host requirements. A refusal has a required reason and optional
detail; a success carries the operation's value, which may itself be nil.

Check `ok` before accessing the payload. The `reason` helper returns nil for success
and the refusal reason otherwise, without changing the envelope. Constructors do
not freeze payloads or decode untrusted data; domain codecs still own admission.

Persistence store operations and the store ports for party membership, social
records, trade, mail and material ledgers use this contract. Their domain responses
remain described by their respective guides during the kernel migration.

Run the [store specification](../../src/core/persistence/store-host.verify.luau):

```sh
lute run tools/gate.luau --only specs --file src/core/persistence/store-host.verify.luau
```

It exercises the real host against fake native ports: a cancelled atomic transform
returns a refusal, a committed update returns its readback, and a successful missing
read is distinct from storage failure. Trade and mail specifications exercise the
same envelope under an ambiguous write and receipt replay.
