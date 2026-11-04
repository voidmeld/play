# Codec

[Return to systems](../systems.md).

`src/kernel/codec` owns the shared record-codec contract, versioned record admission
and stored-data copying/equality. Exact declarations are in the
[generated API](../api.md#kernelcodec). It has no persistent state or host operations.

`Record<T>` supplies one `copy` decoder and one domain equality operation. The decoder
returns a value or a refusal reason; it owns the complete domain schema and the returned
value's ownership. Atomic stores use this contract for complete-record comparison and
committed readback. A record-store configuration supplies it as `codec`.

`versioned` captures an owned field set and version. On each call it runs the supplied
pure migration, admits a plain record with no unknown fields, checks `schemaVersion`,
then calls the domain decoder. `required = true` requires every declared field; otherwise
the domain decoder decides which fields are optional. Migrations and domain decoders
remain policy supplied by the consumer. Missing migration means current-format data only.
Migration/decoder exceptions propagate; these are trusted configuration callbacks.

`copyData` returns the shared Result envelope. It copies nil, booleans, strings, finite
numbers and acyclic plain tables with string or finite numeric keys. Shared references
remain shared within the detached result. Cycles, metatables and executable or unsupported
leaves refuse with `value_invalid`. These are the existing fake storage host's value rules;
native storage limits remain the host's responsibility.

`equalData` compares all admitted data fields. Invalid data compares false even against
itself. It is for complete stored-data snapshots; domain-specific equality belongs in
`Record<T>.equal`.

Run the executable migration and snapshot examples:

```sh
lute run tools/gate.luau --only specs --file src/kernel/codec.verify.luau
```

The [specification](../../src/kernel/codec.verify.luau) proves migration before version
admission, detached field policy, decoder refusals, shared-reference copying, rejection
of invalid graphs and complete equality. Account and character records use versioned
admission; storage hosts, material ledgers and cargo use the same data primitives.
