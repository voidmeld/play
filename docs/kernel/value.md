# Value

[Return to systems](../systems.md).

`src/kernel/value` is the single boundary primitive for field copies, plain records,
dense sequences and bounded scalar values. It imports no domains or hosts. Exact
operations and exported types are in the [generated API](../api.md#kernelvalue).

There is no persistent state and no required host operation. Callers supply field
sets, numeric bounds and string limits; domain codecs decide which combinations form
valid game state.

`raw` makes a shallow field copy of a table, including a table with a metatable. It
does not admit a record or validate nested values. `hasMetatable` detects that boundary.
`record` and `dense` reject metatables by default; their explicit `plain = false`
option is for callers that already own that decision. Record admission rejects
unknown fields and can require every declared field. Dense admission rejects gaps,
non-sequence keys and lengths above the supplied maximum.

`finite`, `whole`, `opaque` and `identifier` validate scalar constraints without
coercion. `nonempty` accepts any nonempty string, including whitespace. `freezeDeep`
freezes an acyclic table tree; it is not a decoder or a cycle detector. The module's
operation table is frozen.

Run the executable boundary examples from the repository root:

```sh
lute run tools/gate.luau --only specs --file src/kernel/value.verify.luau
```

The [specification](../../src/kernel/value.verify.luau) checks that copying fields
does not retain a metatable or virtual fields, while plain-record admission still
rejects the original table. It also checks finite numbers, nonempty strings and
whole-number bounds. Inventory cargo, material ledgers and identity records consume
these same operations; their system specifications own domain invariants.
