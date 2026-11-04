# Combat contact lifetime

[System catalog](../systems.md) · [Play](../../README.md) · [API reference](../api.md)

Admit an immutable attack snapshot, reserve one contact after anticipation, recheck current custody
and spatial evidence, and retain recovery until its deadline. Import `src/core/combat/contact` and use
`configure(config)`. The combat family exposes it as `contact`; cast retry windows remain a separate
[cast](cast.md) concern.

## State and operations

`Plan<P>` freezes source/target identities, body/content tokens, movement epochs, equipment token,
sequence, admission tick, phase durations, range and an opaque payload. `State<P>` holds that plan,
elapsed time, last clock tick, contact reservation and consumption. All returned records are immutable.

`admit(unknown)` returns the kernel result envelope. It rejects malformed records, nonfinite or
negative phase/range values and non-data payloads, copies identity and payload maps, then freezes them.
The injected payload decoder validates the adopter's schema and must return detached data without effects.

`advance(state, {tick, dt, source})` returns `waiting`, `contact`, `complete` or `cancelled` and the next
pending state. It skips the admission tick and duplicate clock delivery, rejects backwards/nonfinite
clocks, checks current source identity/liveness/control/equipment, and reserves contact at the configured
epsilon boundary. A large step still reserves only one contact. It does not invoke consequences.

`resolve(state, observation)` consumes that reservation after any intervening authoritative work.
It checks both current identities and liveness again. Invalid custody cancels; missing, blocked,
malformed, negative, nonfinite or out-of-range current distances and spatial observations miss.
Only a caller-approved `spatialExempt` for identical source/target IDs bypasses spatial evidence.
It returns `contact`, `missed` or `cancelled`; a consumed contact cannot repeat. A nil next state after
contact or miss means recovery also completed during that step.

## Host contract

No native host operations are required. Supply a finite fixed-time delta, monotonic integer tick,
current normalized identities, source equipment/control/liveness, target liveness, current physical
distance, current line-of-sight evidence and an explicit legality decision. IDs and tokens are opaque.
Configure identity bounds, epsilon and the payload decoder. Keep catalogs, class/realm legality,
reaction prerequisites, coefficients, resource policy, clock ownership and presentation routing local.

Install every returned state under one authoritative reducer. Resolve the reserved state against fresh
observations, install its successor, then apply at most one game consequence for a `contact` result.
Commit accepted resource/cooldown changes atomically with admission; refuse before modifying game state.
Do not serialize a client-supplied frozen plan as authority or reapply an old returned transition.

## Runnable example and invariants

```sh
lute run tools/gate.luau --file src/core/combat/contact.verify.luau
```

The [test scene](../../src/test-scene/combat.luau) uses the same public API with a numeric impact and
opaque metadata map. Its [specification](../../src/core/combat/contact.verify.luau) exercises admission
isolation, exact/epsilon thresholds, duplicate delivery, zero/oversized phases, single contact and
recovery, invalid clocks, custody replacement, fresh spatial refusal and explicit self-contact.
Inputs remain unchanged on every refusal. These pure fixtures do not establish animation timing,
audible playback, native spatial sampling or a game's atomic resource wiring.
