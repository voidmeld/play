# API reference

This page owns public signatures, return values and failure behavior.
The public-surface check requires an entry here for each public export.
The generated [signature appendix](#signature-appendix) is part of this page. It supplies exact declarations, including factory return operations.
The hand-written sections explain how to use those declarations.

## Task table

| Task | Reference |
| --- | --- |
| Admit values and stored records | [Kernel value](#kernel-value), [codec](#kernel-codec) and [result](#kernel-result) |
| Coordinate atomic writes and leases | [Kernel store](#kernel-store), [lease](#kernel-lease) and [persistence](#persistence) |
| Bind clocks, storage and native effects | [Host operations](#host-operations) |
| Select and update a target | [Threat](#threat) |
| Admit and recover transactions | [Trade](#trade), [mail](#mail) and [market](#market) |
| Decode requests and apply state | [Inventory](#inventory), [progression](#progression) and [quest](#quest) |
| Select another area | [Area index](#area-index) |

## Shared setup

Examples on this page are fragments. Replace `path.to.play` with the pinned runtime surfaces:

```luau
local Threat = require(path.to.play.core.threat)
local rules = Threat.table.rules({ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 })
local state = Threat.table.empty()
```

Require one family through `src/core/<family>`. Its `API` type exposes its components and prefixed type aliases.
Require one native adapter through `src/roblox/<adapter>` and kernel primitives through `src/kernel/<primitive>`.
Use dots for functions and returned operations unless a signature declares a method receiver.
`src/test-scene` supplies fixtures for verification only. `internal` modules are not public contracts.
The [quickstart](quickstart.md) runs a complete fixture. Each area below links executable specifications or examples.

### Returns and failures

Each declaration in the appendix states its return types. A factory returns the operations shown below its signature.
Keep the returned object for that configured instance. Do not assume factories have a common interface.
Pure transitions return new state or a result; the caller installs it under its authority boundary.
Some transitions reuse unchanged state. Treat all borrowed inputs as read-only.
An optional result or `nil, reason` is a refusal. Inspect all declared return values before installing state.
Kernel result envelopes require `ok` before `value` or `reason`. Other response shapes remain operation-specific.
Assertions reject invalid trusted configuration or impossible arithmetic. Do not catch them and invent a successful result.
Decode untrusted input with the selected request or record projector. Static types do not admit remote data.
Host failures retain uncertainty and recovery receipts. Never infer a committed write from a callback observation.

```luau
local nextState, firstTarget = rules.add(state, "actor-a", 10, true)
state = nextState
assert(firstTarget)
state = rules.taunt(state, "actor-b")
assert(state.targetActorId == "actor-b")
```

`Threat.table.rules(config)` returns `add(state, actorId, amount, inMelee) -> (State, boolean)` and `taunt(state, actorId) -> State`.
The boolean reports that the previous holder was absent. Invalid ratios, actor IDs, non-finite additions and overflow raise.
The [threat specification](../src/core/threat/table.verify.luau) exercises takeover thresholds, taunts and invalid inputs.
The linked tests in each remaining area exercise that area's refusal and recovery shapes.

## Host operations

Read the selected `Config`, `Deps`, `Host` or operation-specific type in the appendix before binding an area.
There is no universal native host interface. Supply only its requested capabilities.

- Keep policy callbacks deterministic and stable for one configured instance.
- Supply monotonic time for elapsed deadlines and the declared timestamps for durable records.
- Install related state and profile effects atomically. Atomic-store transforms can retry and must have no external effects.
- Return actual committed readbacks. Retain receipts after missing replies or uncertain writes.
- Fence yielding work against session, body and operation generations.
- Disconnect listeners, cancel work and dispose owned native resources when their lifetime ends.

Core rules discover no services. Adapters use injected operations.
The consumer owns authentication, namespaces, content, policy and deployment.
Headless fixtures prove their configured hosts; they prove no native rendering, live durability or consumer acceptance.

## kernel-codec

`src/kernel/codec` owns the shared record-codec contract, versioned record admission
and stored-data copying/equality. Exact declarations are in the
[signature appendix](api.md#kernelcodec). It has no persistent state or host operations.

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

The [specification](../src/kernel/codec.verify.luau) proves migration before version
admission, detached field policy, decoder refusals, shared-reference copying, rejection
of invalid graphs and complete equality. Account and character records use versioned
admission; storage hosts, material ledgers and cargo use the same data primitives.

## kernel-lease

The lease kernel supplies pure acquisition, renewal and release rules. Its state contains a
revision, optional session and acquisition identities, and an expiry. An unowned state has no
owner identities and zero expiry. It has no host operations or persistence schema.

Configure revision, time and identity bounds and whether times must be whole numbers.
Configuration is captured at construction. Each operation returns the shared Result envelope.
The [signature appendix](api.md#kernellease) owns exact declarations.

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

The [specification](../src/kernel/lease.verify.luau) proves idempotent acquisition,
generation fencing, detached transitions, live and uncertain ownership, and invalid state/time
refusal. The identity account and character specifications prove their stored formats and host
readback contracts while consuming these same rules.

## kernel-result

`src/kernel/result` owns the shared success or refusal envelope. Exact exported
types and helpers are in the [signature appendix](api.md#kernelresult). It has no
mutable state or host requirements. A refusal has a required reason and optional
detail; a success carries the operation's value, which may itself be nil. Envelope
fields are read-only; payload ownership stays with its domain.

Check `ok` before accessing the payload. The `reason` helper returns nil for success
and the refusal reason otherwise, without changing the envelope. Constructors do
not freeze payloads or decode untrusted data; domain codecs still own admission.
`unwrap` returns a successful value, including nil, or raises the refusal reason.
Use it when failure should abort the caller, such as fixture setup. Runtime bindings
that must return a refusal should branch on `ok` instead.

Material ledger append and snapshot operations use this contract, as does the
adopting game's character repository binding. Store-port envelopes move with the
atomic Store primitive; other domain responses remain described by their respective
areas on this page.

Run the [cargo and ledger specification](../src/roblox/cargo.verify.luau):

```sh
lute run tools/gate.luau --only specs --file src/roblox/cargo.verify.luau
```

It exercises the real coordinator against fake storage ports: retained receipts
replay without applying twice, old unverifiable receipts refuse, divergent committed
readbacks fail closed, and a speculative callback cannot supply a success after
the final callback refuses. Success carries the append or snapshot payload; refusal
carries its required reason.

## kernel-store

`src/kernel/store` owns the atomic storage port, compare-and-swap transform and
committed-readback check. Exact types and operations are in the [signature appendix](api.md#kernelstore).
The primitive has no domain state, key namespace, clock or host service. Records and
character leases use the same port; their codecs and authority rules remain in their systems.
The shared [codec contract](api.md#kernel-codec) owns record decoders and domain equality; record-store
configuration supplies that pair as `codec`.

Readback is untrusted stored data. A successful read may carry nil for absence;
failure is a refused Result. Decode the payload before using it. An update transform
may run repeatedly against different snapshots. It must be pure, return a detached
next value, or return nil to cancel. Only the final committed readback can authorize
success; a value calculated during an earlier callback is not a receipt.

`compareAndSwap` checks absence or the entire decoded expected record, then copies
the desired record for the backend. Revision equality alone does not prove that
private payload fields still match. `committed` decodes and compares the returned
record against the desired value, refusing valid but divergent readback.

`confirm` reconciles a cancelled or uncertain update against a captured
`codec.copyData` result. It reads through the injected port and compares the entire
stored value, including known absence. Invalid snapshots, unavailable reads and
divergent rows refuse. Social membership, record, ledger and inbox replays share it.

The [native binding](../src/roblox/persistence/store.luau) wraps the existing
budgeted storage backend's uncached read and atomic update operations. It exposes
`read` and `update` through the kernel port, refuses malformed backend envelopes and
gives backend refusals a reason.
An uncertain backend failure may follow a committed write; a caller must reconcile
durable state rather than infer that nothing happened.

The [fake host](../src/test-scene/persistence/store.luau) exposes the same port,
with an injected clock, optional initial records, fixture seeding, committed-write and
update-attempt counts, and the backend's retry/fault seams. Its `values` map is a test
control for inspecting or poisoning durable bytes; authoritative consumers use the port,
which detaches readback from that map. Fixture controls are outside the authoritative port.

Run the executable example and invariants:

```sh
lute run tools/gate.luau --only specs --file src/kernel/store.verify.luau
```

The [specification](../src/kernel/store.verify.luau) checks absent reads, full
record comparison, final-callback cancellation, failure after commit, exact readback
and detached read values. It uses the real binding and fake backend, and does not
claim native cross-server or network proof.

## kernel-value

`src/kernel/value` is the single boundary primitive for field copies, plain records,
dense sequences and bounded scalar values. It imports no domains or hosts. Exact
operations and exported types are in the [signature appendix](api.md#kernelvalue).

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

The [specification](../src/kernel/value.verify.luau) checks that copying fields
does not retain a metatable or virtual fields, while plain-record admission still
rejects the original table. It also checks finite numbers, nonempty strings and
whole-number bounds. Inventory cargo, material ledgers and identity records consume
these same operations; their system specifications own domain invariants.

## bank

Move items between carried inventory and a vault with bounded receipt replay.

### State shape

`State = { items, receipts, receiptOrder }`; requests identify direction, item, count, banker and receipt.

Types and configuration are exported from [src/core/bank.luau](../src/core/bank.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [vault](../src/core/bank/vault.luau) | `adjust`, `apply`, `default`, `project`, `request`, `sameRequest`, `vault` | `Inventory`, `Request`, `State`, `Config`, `Vault` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply profile read/write, permanent-item admission, capacity/fit and transfer callbacks. Persist inventory and vault together.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/bank/vault.verify.luau --name "refuses permanent carried items without moving or duplicating them"
```

The [executable specification](../src/core/bank/vault.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: refuses permanent carried items without moving or duplicating them.

### Invariants

A refused transfer moves nothing. Receipt replay cannot move an item twice. Permanent items remain carried.

## cast

Queue a cast near its cooldown deadline and reject stale wakeups.

### State shape

`State<T> = { nextToken, queued? }`; queued entries retain payload, due time and a generation token. `Windows` holds independent deadlines.

Types and configuration are exported from [src/core/cast.luau](../src/core/cast.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [queue](../src/core/cast/queue.luau) | `cancel`, `delayFor`, `empty`, `enqueue`, `minimumCadenceSec`, `ready`, `remaining`, `rules`, `shouldQueue`, `take`, `windows` | `Config`, `Entry`, `State`, `Windows` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply monotonic time, queue-window/retry tuning and immutable payloads. The game schedules wakeups, checks actor identity and executes the cast.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/cast/queue.verify.luau --name "queue admission preserves reason, inclusive window and finite boundaries"
```

The [executable specification](../src/core/cast/queue.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: queue admission preserves reason, inclusive window and finite boundaries.

### Invariants

Window admission is inclusive. Only a matching due token is consumed. Refusals retain the previous queue; cancellation invalidates old callbacks.

## character-leases

Keep one character session authoritative across renewal, takeover, departure/arrival and deletion recovery.
Import [core/identity](../src/core/identity.luau); it exports the component APIs and their types.

### State shape

`CharacterLeaseRecord` contains `schemaVersion`, `revision`, `characterId`, optional `zoneId`,
optional `sessionId`/`acquisitionId`, `expiresAt`, and explicit `retirement`/`arrival` slots.
Each slot is either `false` or its typed receipt. A retirement receipt identifies operation,
fingerprint, fence and time; an arrival receipt identifies session, acquisition, fence and time.
An unowned row has both owner fields absent and zero expiry. Returned rows are detached mutable
values, allowing the game's atomic transform to compose them without changing its input.
The owner, revision and expiry projection uses the [kernel lease rules](api.md#kernel-lease).
Retirement and arrival remain domain receipts, validated by the character record codec.

### Operations

| Component | Operations |
| --- | --- |
| [character_lease](../src/core/identity/character-lease.luau) | `create(config)` returns record `create`, `copy`, `equal`, witness/claim decoders, `retire`, `restore`, `arrive`, `retired`, and receipt readers. |
| [character_lease_store](../src/core/identity/character-lease-store.luau) | `create(config)` returns atomic `acquire`, `renew`, `release`, `retire`, `restore`, and `arrive`. |
| [retirement](../src/core/identity/retirement.luau) | `create(config)` returns `view` and `decide`: retire, restore, settled, orphan or invalid. |

The [signature appendix](api.md) contains every configuration field and result type.

### Required host operations

Supply the saved schema, numeric/string bounds and a pure `migrate(unknown) -> unknown` projector.
The projector must leave its input unchanged; its result still passes the full record validator.
An identity projector deliberately refuses older schemas. Migration rules and their rollout belong to the game.
Factories snapshot scalar configuration; retirement also copies its phase maps. Phase sets must be disjoint.

Supply the [atomic store port](api.md#kernel-store) and a character-key builder. The port includes
uncached reads and atomic updates. A canceled callback that observes an apparent replay still
requires an uncached read confirming the expected record or permitted absence. Transport failures retain their
actual reason; an earlier callback observation never substitutes for durable readback.
Restoring an absent key confirms uncached absence and returns the unowned empty record without
a write. Acquisition, retirement and arrival require complete-record receipts.

Pass authoritative timestamps, TTL and session-liveness observations. Optional live-session callbacks
control early takeover and retention of a lapsed lease. Without an early-liveness callback, an
unexpired foreign session holds its lease. Use the same identity/zone limits in the store and record policy.
The game owns the namespace, leases' durable ordering, caller authentication, session scheduling,
deletion phase maps and notices. These modules never discover services or write storage themselves.

### Runnable example

```sh
lute run tools/examples/character-leases.luau
```

The [complete example](../tools/examples/character-leases.luau) uses a distinct schema and small
bounds, then drives the real store coordinator through the [test-scene fake host](../src/test-scene/character-leases.luau).
It acquires, retires, drains the old owner, restores and consumes an arrival receipt once.

```sh
lute run tools/gate.luau --file src/core/identity/character-lease.verify.luau --file src/core/identity/retirement.verify.luau
```

### Invariants

- Renewal and release require exact character, session, acquisition and revision. Expiry is an exact boundary.
- Arrival requires the acquired revision to exceed its departure fence; another holder cannot reuse a consumed departure.
- Only the retirement operation with the matching fingerprint and an adequate fence can restore its tombstone.
- Retired characters cannot acquire or arrive, while their existing owner can drain and release.
- Replay preserves receipts. Callback retries clear provisional results. Unconfirmed, forged or failed readback does not become success.
- Saved rows require both receipt slots. Schema, limits and planner phase admission come from caller policy.

The executable character-lease suite owns generic record, receipt, atomic-store and handoff regressions. It rejects
missing, malformed and foreign receipt fields, fences every holder identity, compares complete records
and preserves detached replay results. Adopters retain checks for their configured schema, migrations,
limits and native persistence wiring. Atomic cases cover replayed acquisitions, malformed stored rows,
foreign identities, exact expiry, terminal revision reserve, retired-owner draining and durable receipt
recovery. Store callback retries and uncached readback remain observable at each adopter's native adapter.

See [adoption](adoption.md) for consumer boundary and cutover requirements.

## character

Coordinate death observations, recovery timers and cancellable body replacement.

### State shape

A `Host<P,C,O>` owns character generations and watches; `Observation<C>` carries current body/death observations.

Types and configuration are exported from [src/core/character.luau](../src/core/character.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [respawn-host](../src/core/character/respawn-host.luau) | `completeSpawn`, `create` | `Refresh`, `Observation`, `Dependencies`, `Host` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject ownership, observe/connect, schedule/cancel, current-session checks, spawn, body validation and destination restoration from `Dependencies`.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/character/respawn-host.verify.luau --name "uses authoritative death state after a previously live body disappears"
```

The [executable specification](../src/core/character/respawn-host.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: uses authoritative death state after a previously live body disappears.

### Invariants

A body change revokes old waits. Spawn retries are bounded. Restoration requires a current session and valid new body.

## chat

Project channel audiences, parse commands and budget senders.

### State shape

`Member` describes audience admission; `Bucket` and `Budget` track consumption; `Audience` and `Rule` describe channel scope.

Types and configuration are exported from [src/core/chat.luau](../src/core/chat.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [channels](../src/core/chat/channels.luau) | `allows`, `consume`, `pairName`, `parse`, `trim`, `window` | `Member`, `Audience`, `Rule`, `Bucket`, `Budget` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply member observations, audience rules, sender budgets, time and history limits. The game performs platform privacy checks and transports admitted text.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/chat/channels.verify.luau --name "membership preserves proximity, realm, group and private pair boundaries"
```

The [executable specification](../src/core/chat/channels.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: membership preserves proximity, realm, group and private pair boundaries.

### Invariants

Private pair identities are deterministic. Realm/group/proximity filters do not leak membership. Rate refusal does not invent budget.

## combat

Admit an immutable attack snapshot, reserve one contact after anticipation, recheck current custody
and spatial evidence, and retain recovery until its deadline. Import `src/core/combat/contact` and use
`configure(config)`. The combat family exposes it as `contact`; cast retry windows remain a separate
[cast](api.md#cast) concern.

### State and operations

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

### Host contract

No native host operations are required. Supply a finite fixed-time delta, monotonic integer tick,
current normalized identities, source equipment/control/liveness, target liveness, current physical
distance, current line-of-sight evidence and an explicit legality decision. IDs and tokens are opaque.
Configure identity bounds, epsilon and the payload decoder. Keep catalogs, class/realm legality,
reaction prerequisites, coefficients, resource policy, clock ownership and presentation routing local.

Install every returned state under one authoritative reducer. Resolve the reserved state against fresh
observations, install its successor, then apply at most one game consequence for a `contact` result.
Commit accepted resource/cooldown changes atomically with admission; refuse before modifying game state.
Do not serialize a client-supplied frozen plan as authority or reapply an old returned transition.

### Runnable example and invariants

```sh
lute run tools/gate.luau --file src/core/combat/contact.verify.luau
```

The [test scene](../src/test-scene/combat.luau) uses the same public API with a numeric impact and
opaque metadata map. Its [specification](../src/core/combat/contact.verify.luau) exercises admission
isolation, exact/epsilon thresholds, duplicate delivery, zero/oversized phases, single contact and
recovery, invalid clocks, custody replacement, fresh spatial refusal and explicit self-contact.
Inputs remain unchanged on every refusal. These pure fixtures do not establish animation timing,
audible playback, native spatial sampling or a game's atomic resource wiring.

## control

Apply diminishing control durations with fixed reset deadlines.

### State shape

`State` maps families to `Bucket` values; `Category` selects policy and `Result` returns the admitted duration and next state.

Types and configuration are exported from [src/core/control.luau](../src/core/control.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [diminishing](../src/core/control/diminishing.luau) | `apply`, `clone`, `empty`, `rules` | `Bucket`, `State`, `Category`, `Config`, `Step`, `Result` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply category definitions, duration steps, reset windows and time. The host applies admitted control and installs state.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/control/diminishing.verify.luau --name "duration steps retain a fixed reset deadline and saturate until exact expiry"
```

The [executable specification](../src/core/control/diminishing.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: duration steps retain a fixed reset deadline and saturate until exact expiry.

### Invariants

Steps saturate at immunity until reset. Exact expiry resets the bucket. A repeated application does not slide the original reset deadline.

## craft

Validate and project recipe definitions into immutable material requirements.

### State shape

`Recipe` contains material stacks and output; `Catalog` holds projected definitions under caller-provided source rules.

Types and configuration are exported from [src/core/craft.luau](../src/core/craft.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [recipes](../src/core/craft/recipes.luau) | `catalog`, `projectRecipe` | `MaterialStack`, `Recipe`, `SourceRule`, `Config`, `Catalog` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply authored rows, source classification, identifiers and bounds. Inventory spending, stations and durable grants belong to the game.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/craft/recipes.verify.luau --name "projects a frozen recipe and rejects malformed authored rows"
```

The [executable specification](../src/core/craft/recipes.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: projects a frozen recipe and rejects malformed authored rows.

### Invariants

Malformed rows refuse. Accepted recipes are detached and frozen. Material requirements come from game data.

## effects

Advance timed effects, stacks, periodic deadlines and dispels.

### State shape

`Entry` holds source, stack count, duration/expiry and periodic timing. `Application` and `Refresh` describe requested updates.

Types and configuration are exported from [src/core/effects.luau](../src/core/effects.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [timed](../src/core/effects/timed.luau) | `advance`, `advanceTimes`, `application`, `count`, `dispelFirst`, `expired`, `refresh`, `remainingFraction`, `remainingSec` | `Entry`, `Application`, `Refresh` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply applications, time/delta, refresh policy and stack caps. The host installs returned timing and applies emitted periodic effects.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/effects/timed.verify.luau --name "applications increment to the authored cap and reset duration and tick phase"
```

The [executable specification](../src/core/effects/timed.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: applications increment to the authored cap and reset duration and tick phase.

### Invariants

Stack caps hold. Refresh resets the selected duration/tick phase. Expired effects do not continue ticking; dispel selection is deterministic.

## events

Resolve configured event schedules and track participation through reward-ticket recovery.

### State shape

`Catalog` contains configured events; schedule `Context` projects active effects; watch `State` tracks phase, work, participants and tickets.

Types and configuration are exported from [src/core/events.luau](../src/core/events.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [catalog](../src/core/events/catalog.luau) | `catalog`, `finite`, `projectEvent`, `validateCatalog` | `Flag`, `Rollout`, `Schedule`, `Event`, `Catalog`, `Config` |
| [schedule](../src/core/events/schedule.luau) | `resolve`, `schedule`, `stableBucket`, `validateCatalog` | `Event`, `Catalog`, `Context`, `Effect`, `Resolution`, `Config` |
| [watch](../src/core/events/watch.luau) | `claim`, `emptyState`, `join`, `leave`, `projectEvent`, `protect`, `protectionBindingsValid`, `sync`, `watch`, `work` | `Phase`, `WorkPoint`, `Event`, `State`, `Result`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply calendars, rollout/admission rules, realm/work/protection definitions, clocks and rewards. Persist grants and acknowledgments in the game.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/events/catalog.verify.luau --name "validates supplied schema and content hooks"
```

The [executable specification](../src/core/events/catalog.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: validates supplied schema and content hooks.

### Invariants

Resolution preserves priority and unique hooks. Returned content lists are detached. Reward tickets retain identity across recovery.

## identity

Coordinate rosters, names, account snapshots, creation, deletion and fenced leases.

[Character leases and retirement](api.md#character-leases) covers the character store, arrival receipts,
retirement planner and a standalone fake-host example. The [adoption guide](adoption.md) identifies
the displaced game implementations and their remaining policy/host bindings.
Account and character leases share the [kernel lease rules](api.md#kernel-lease); their stored schemas
and domain fences remain in their record codecs.

### State shape

`Roster` holds stable character identities. Account snapshots hold profiles and receipts. Creation/deletion `State` records phase, revision and fence; leases record owner and expiry.

Types and configuration are exported from [src/core/identity.luau](../src/core/identity.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [account-lease](../src/core/identity/account-lease.luau) | `MAX_FENCE`, `MAX_ID_BYTES`, `MAX_REVISION`, `MAX_SAFE_INTEGER`, `SCHEMA_VERSION`, `acquire`, `copy`, `empty`, `equal`, `release`, `renew`, `validate` | `Lease` |
| [account](../src/core/identity/account.luau) | `characterCard`, `clearDeletionTerminal`, `clearTerminal`, `copy`, `create`, `empty`, `equal`, `equalStored`, `markCharacterDeparted`, `markCharacterLevel`, `markCharacterPlayed`, `receiptFor`, `removeCharacter`, `transition`, `transitionDeletion`, `validate`, `validateStored` | `DeletionState`, `Base`, `CreationReceipt`, `Account`, `Extension` |
| [character-lease](../src/core/identity/character-lease.luau) | `create`, `copy`, `equal`, `witness`, `claim`, `retire`, `restore`, `arrive`, receipt readers | `Config`, `API`, `Record`, `Retirement`, `Arrival`, `Witness`, `Claim` |
| [character-lease-store](../src/core/identity/character-lease-store.luau) | `create`, `acquire`, `renew`, `release`, `retire`, `restore`, `arrive` | `Config`, `API`, `Store`, `StoreOutcome`, `Outcome`, `Accepted`, `Refused` |
| [creation-record](../src/core/identity/creation-record.luau) | `copy`, `copyReceipt`, `create`, `fromTransaction`, `matchesTransaction`, `receiptFromTransaction`, `receiptMatchesSeed`, `seedMatchesReceipt`, `validate`, `validateReceipt`, `validateStored` | `Seed`, `Receipt` |
| [creation](../src/core/identity/creation.luau) | `copy`, `create`, `fingerprint`, `observeLeaseRelease`, `observeName`, `observeProfile`, `observeRollback`, `observeRoster`, `plan`, `prepare`, `requestRollback`, `takeover`, `validate`, `validateStored` | `Completion`, `Receipt`, `Phase`, `State`, `Prepared`, `Rejected`, `Accepted`, `Result`, `Plan` |
| [deletion](../src/core/identity/deletion.luau) | `copy`, `create`, `fingerprint`, `observeLeaseRelease`, `observeNameRelease`, `observeRollback`, `observeRoster`, `plan`, `prepare`, `requestRollback`, `takeover`, `validate` | `Phase`, `State`, `Prepared`, `Rejected`, `Accepted`, `Result`, `Plan` |
| [name-claims](../src/core/identity/name-claims.luau) | `availability`, `claim`, `create`, `release`, `validate` | `Claim`, `ClaimStatus`, `ReleaseStatus`, `Availability` |
| [name-record](../src/core/identity/name-record.luau) | `availability`, `claim`, `copy`, `create`, `empty`, `equal`, `release`, `validate` | `Record`, `Claim` |
| [policy](../src/core/identity/policy.luau) |  | `Policy` |
| [retirement](../src/core/identity/retirement.luau) | `create`, `view`, `decide` | `Config`, `API`, `View`, `Decision`, `Deletion`, `Retirement` |
| [roster](../src/core/identity/roster.luau) | `add`, `create`, `markDeparted`, `markLevel`, `markPlayed`, `realmCards`, `remove`, `removeStored`, `validate`, `validateStored` | `CharacterIdentity`, `Roster` |
| [routing](../src/core/identity/routing.luau) | `create`, `projectPolicy`, `decide`, `refuse`, `accept`, `boundPlaceIds` | `Config`, `API`, `Policy`, `Binding`, `PlaceBinding`, `Budget`, `Handoff`, `DestinationProjection`, `RefusalRow`, `Session`, `Character`, `Request`, `Route`, `Refusal`, `Decision`, `Arrival` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply `policy.Policy`, pure extension projectors and identity/key/destination validation. Apply transaction plans through ordered durable operations and return actual readbacks.

[Route admission](api.md#route-admission) covers configured destination bindings, request/held-session
fencing, attempt/deadline budgets and arrival source checks. It has no native service dependency.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/identity/account-lease.verify.luau --name "acquires one fenced account lease and permits exact-expiry takeover"
```

The [executable specification](../src/core/identity/account-lease.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: acquires one fenced account lease and permits exact-expiry takeover.

### Invariants

Foreign names survive stale release. Fences reject old owners. Missing or conflicting readbacks do not advance a transaction. Extensions survive detached transitions.

## inventory

Manage stack capacity, equipment exchanges and wear, plus replay-safe cargo custody, drops, recovery and delivery.

### State shape

`Inventory` maps item IDs to counts; `Holdings` adds equipment/bank views. Cargo `State` contains claims, drops, extraction and delivery history.
Equipment `Wear` tracks accumulated use per equipped slot and per-copy wear lists in bag and bank.
Equipment plans return new inventory/slot maps, displacement and refusal information without installing state.

Types and configuration are exported from [src/core/inventory.luau](../src/core/inventory.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [cargo](../src/core/inventory/cargo.luau) | `carriedOf`, `census`, `create`, `emptyState`, `openDrops`, `projectState`, `retireTransient`, `step` | `Status`, `Cause`, `Claim`, `Drop`, `Total`, `Extraction`, `State`, `Intent`, `CommandKind`, `Command`, `Result`, `CensusRow`, `Config` |
| [equipment](../src/core/inventory/equipment.luau) | `equipment` configures wear normalization/copy transfers, breakage, repair quotes/plans and equip/unequip exchanges | `Requirements`, `ItemDef`, `ItemLookup`, `Equipment`, `Inventory`, `Wear`, `Decision`, `InventoryPort`, `Config`, `Plan`, `API` |
| [stacks](../src/core/inventory/stacks.luau) | `addToBag`, `capacity`, `copyBag`, `entries`, `fits`, `hasItem`, `isValidCount`, `normalizeBindings`, `permanent`, `removeFromBag`, `stacks`, `unboundCount` | `Inventory`, `Holdings`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply stack/capacity/permanent-item policy and cargo identity, quantity, timestamp and ledger bounds. The game persists inventory and settles emitted credit.
Equipment additionally needs stack operations/limits and eligibility/slot policy. Supply item lookup with
durability bounds, contact/damage wear and repair cost. `repairWear` checks the current quote and funds,
then returns new wear and the exact debit; the game owns profile currency fields and atomic installation.
Keep item catalogs, class/proficiency rules, currency display, balance, bindings and native rig application local.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/inventory/cargo.verify.luau --name "hands off a dropped claim once and deposits it with replay-safe credit"
```

The [executable specification](../src/core/inventory/cargo.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: hands off a dropped claim once and deposits it with replay-safe credit.

Run the [equipment fixture](../src/core/inventory/equipment.verify.luau) with:

```sh
lute run tools/gate.luau --file src/core/inventory/equipment.verify.luau
```

It uses a three-unit stack bound, small bag capacity and neutral eligibility policy to exercise exchanges,
per-copy custody, breakage, current repair quotes, insufficient funds and malformed wear.

### Invariants

Capacity and stack limits hold. Bound/worn/permanent rules are explicit. A claim has one custodian and cannot be deposited twice.
The [cargo regression suite](../src/core/inventory/cargo.verify.luau) covers malformed commands,
monotonic caller clocks, conflicting identities, terminal carry replays, exact-deadline recovery and loss,
and conservation across death, disconnect, teleport and extraction. Delivery receipts retain their
original settlement time and deterministic per-material credit identities when replayed. Saved records
with torn claim/drop membership, missing deliveries, inconsistent totals or contradictory recovery fail
closed; valid projections are detached and immutable. Settled transient losses can be retired.
Wear follows a particular copy through equipment, bag and bank operations. Plans preserve their input maps.
Broken items contribute no active equipment. A changed quote or insufficient funds cannot produce a repair.

## ledger

Record value events, reservations and grouped economic operations.

### State shape

`State` stores events and derived balances/reservations; `Journal` projects grouped history and torn groups.

Types and configuration are exported from [src/core/ledger.luau](../src/core/ledger.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [ledger](../src/core/ledger/ledger.luau) | `apply`, `available`, `balances`, `emptyState`, `ledger`, `projectEvent`, `projectState`, `tornGroups` | `EventKind`, `Event`, `State`, `ApplyResult`, `TornGroup`, `Config`, `Journal` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply earning/spending kinds, identity and quantity bounds, group policy and event timestamps. Durable event append belongs to the game.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/ledger/ledger.verify.luau --name "settles grants immediately and derives balances"
```

The [executable specification](../src/core/ledger/ledger.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: settles grants immediately and derives balances.

### Invariants

Identical event replay does not regrant value. Conflicting identities refuse. Group accounting exposes incomplete settlement.

## loot

Draw configured loot and settle party need/greed/pass choices.

### State shape

Roll tables produce `Drop` values with receipt identity. A party `Decision` holds seats, choices, fixed deadline and saved `Result`.

Types and configuration are exported from [src/core/loot.luau](../src/core/loot.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [decision](../src/core/loot/decision.luau) | `decision`, `declare`, `due`, `open`, `settle` | `Choice`, `Seat`, `Result`, `Decision`, `Refusal`, `Config` |
| [roll](../src/core/loot/roll.luau) | `dropFor`, `dropsFor`, `receiptFor`, `roll`, `tableForMob`, `validRoll` | `Roll`, `Table`, `Drop`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply authored tables, receipt prefix, random samples, decision window and party eligibility. The host selects recipients and persists grants.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/loot/decision.verify.luau --name "closes thirty seconds after it opens"
```

The [executable specification](../src/core/loot/decision.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: closes thirty seconds after it opens.

### Invariants

Choice deadlines are fixed. Each seat chooses once under the configured decision rules. The saved result is reused; all-pass fallback advances the configured party cursor.

## mail

Manage attachment custody, claims, returns and uncertain-write recovery.

### State shape

`Envelope` contains phase, sender/recipient, attachments and receipts. `Pointer` indexes mailbox entries; `Account` holds coin and inventory.

Types and configuration are exported from [src/core/mail.luau](../src/core/mail.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [mailbox](../src/core/mail/mailbox.luau) | `advance`, `attachments`, `credit`, `debit`, `id`, `mailbox`, `pointers`, `prepare`, `read`, `sameRequest`, `valid` | `Inventory`, `Account`, `Stack`, `Attachments`, `Phase`, `Envelope`, `Pointer`, `Config`, `Mailbox` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply profile/account conversion, bag capacity, item admission, limits, time and identity. Persist mailbox transitions and account effects atomically.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/mail/mailbox.verify.luau --name "reads detached envelopes and refuses malformed or executable stored values"
```

The [executable specification](../src/core/mail/mailbox.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: reads detached envelopes and refuses malformed or executable stored values.

### Invariants

Malformed/executable records refuse. Accepted reads are detached. Attachments cannot be claimed twice or duplicated by return/recovery.

## map

Track discoveries and project normalized world markers into a viewport.

### State shape

`ExploredState` stores discoveries by identity; bounds and points define coordinate conversion. Update `State` records sample/revision cadence; `Viewport` contains projected markers.

Types and configuration are exported from [src/core/map.luau](../src/core/map.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [coordinates](../src/core/map/coordinates.luau) | `mapToWorld`, `worldToMap` | `Bounds`, `WorldPoint`, `NormalizedPoint` |
| [exploration](../src/core/map/exploration.luau) | `new` | `Record`, `CatalogValue`, `ExploredState`, `Identity`, `WorldPoint`, `Poi`, `Observation`, `RevealResult`, `Presentation`, `Transition`, `System` |
| [geometry](../src/core/map/geometry.luau) | `imagePan`, `projectMarker`, `projectTrackedWaypoint` | `PanOffset`, `MarkerProjection` |
| [polyline](../src/core/map/polyline.luau) | `simplifyPolyline`, `smoothPolyline` | `PixelPoint` |
| [renderer](../src/core/map/renderer.luau) | `compose`, `new` | `PreferredInput`, `Surface`, `Input`, `Result` |
| [updates](../src/core/map/updates.luau) | `emptyState`, `new`, `transition` | `NormalizedPoint`, `Sample`, `State`, `PanUpdate`, `MarkerUpdate`, `Output`, `Result` |
| [viewport](../src/core/map/viewport.luau) | `build` | `NormalizedPoint`, `MarkerRow`, `TrackedWaypoint`, `Input`, `PoiMarker`, `Viewport` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply catalog normalization, marker-kind decoding, reveal radius, surface policy, observed position/time and marker revisions. The game renders native UI.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/map/exploration.verify.luau --name "reveals the configured boundary once without mutating prior state or another zone"
```

The [executable specification](../src/core/map/exploration.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: reveals the configured boundary once without mutating prior state or another zone.

### Invariants

A discovery presents once. Zones do not share mutable discoveries. Coordinates clamp to valid bounds; only tracked waypoints clamp to the viewport edge.

## market

Coordinate listings, fills, fees, wallet holds and economic conservation.

### State shape

Book `State` contains listings, operations and receipts. Wallet `State` retains pending holds/claims. Conservation `Totals` and `Audit` compare both sides.

Types and configuration are exported from [src/core/market.luau](../src/core/market.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [book](../src/core/market/book.luau) | `apply`, `book`, `emptyState`, `knowsOperation`, `projectState`, `receiptsFor`, `search` | `Listing`, `ReceiptKind`, `Receipt`, `Operation`, `State`, `Result`, `Command`, `Search`, `Config` |
| [conservation](../src/core/market/conservation.luau) | `audit`, `conservation`, `measure` | `Totals`, `Audit`, `Config` |
| [goods](../src/core/market/goods.luau) | `bookFor`, `bookIds`, `catalog`, `isCategoryBook`, `matches`, `tradeableCount` | `ItemFacts`, `Class`, `Config`, `Filters` |
| [wallet](../src/core/market/wallet.luau) | `beginBuy`, `beginConsign`, `claim`, `compose`, `emptyLedger`, `emptyState`, `heal`, `ledgerOf`, `npcTrade`, `projectLedger`, `projectState`, `refund`, `settleConsign`, `wallet` | `Pending`, `State`, `Ledger`, `Result`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply book/fee/expiry rules, goods classification, account conversion, identifiers, clocks and durable coordination. The game provides realm admission and storage.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/market/book.verify.luau --name "lists into a 48-hour realm-local book at the default 5% burning cut"
```

The [executable specification](../src/core/market/book.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: lists into a 48-hour realm-local book at the default 5% burning cut.

### Invariants

Goods and coin are conserved across holds and settlement except configured burns. Receipt replay is idempotent. Refused or uncertain work cannot silently grant value.

## net

Apply token buckets independently to network senders.

### State shape

`Bucket` holds token/time state; `KeyedState` partitions buckets by sender identity.

Types and configuration are exported from [src/core/net.luau](../src/core/net.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [rate-limit](../src/core/net/rate-limit.luau) | `consume`, `newBucket`, `tryConsume` | `Config`, `Bucket`, `KeyedState` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply token capacity/refill policy, monotonic time, sender identity and requested cost. The host decodes requests and decides when to disconnect.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/net/rate-limit.verify.luau --name "keyed budgets isolate senders and preserve the input state"
```

The [executable specification](../src/core/net/rate-limit.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: keyed budgets isolate senders and preserve the input state.

### Invariants

One sender cannot spend another sender's budget. Refusal preserves state. Reversed or invalid time cannot manufacture tokens.

## orders

Advance work orders and realm patron payouts with durable claims.

### State shape

Work `State` holds orders, steps, phases and claims. Patron `State` holds order progress, calendar carry and payout history.

Types and configuration are exported from [src/core/orders.luau](../src/core/orders.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [patron](../src/core/orders/patron.luau) | `allowance`, `catalog`, `emptyState`, `patron`, `projectState`, `turnIn`, `weekOf` | `Order`, `Catalog`, `State`, `Result`, `Config` |
| [work](../src/core/orders/work.luau) | `emptyState`, `projectOrder`, `projectState`, `step` | `Phase`, `WorkOrderStep`, `WorkOrder`, `State`, `CommandKind`, `Command`, `Result` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply catalog, payout/cap/calendar policy, command identity, clocks and reward settlement. The host persists accepted state with rewards.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/orders/patron.verify.luau --name "accepts the authored catalog and refuses a payout above the weekly cap or a duplicate id"
```

The [executable specification](../src/core/orders/patron.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: accepts the authored catalog and refuses a payout above the weekly cap or a duplicate id.

### Invariants

Malformed definitions refuse. Progress follows declared steps. Claims replay without a second payout and respect configured caps.

## persistence

Provide session exclusion, profile save lifetime, ordered stores and bounded shutdown.

### State shape

`LockState` identifies a lease owner/expiry. Profile-session `State` tracks dirty/in-flight generations. Store queues retain per-key ordering and operation outcomes.

Types and configuration are exported from [src/core/persistence.luau](../src/core/persistence.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [profile-session](../src/core/persistence/profile-session.luau) | `begin`, `close`, `create`, `dirty`, `due`, `finish`, `open`, `openAcquired` | `FlightKind`, `State`, `Outcome`, `Config` |
| [session-lock](../src/core/persistence/session-lock.luau) | `isLocked`, `release`, `tryAcquire` | `LockState`, `AcquireResult` |
| [record-store](../src/core/persistence/record-store.luau) | `configure`, `read`, `update` | `Accepted<R>`, `Refused`, `Outcome<R>`, `View`, `Config<R>`, `API<R>`, `Store`, `StoreOutcome` |
| [store-host](../src/core/persistence/store-host.luau) | `create`, `drain`, `memory`, `real` | `Outcome`, `DrainOutcome`, `Operation`, `Observation`, `Observer`, `BudgetKind`, `QueuedWrite`, `Circuit`, `RawStore`, `RealDependencies`, `MemoryStore`, `TestOptions`, `Store`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply clocks, retry/backoff/jitter, backend read/write/update, budgets, circuit policy, lease authority and schema/readback validation. The game owns partition keys.

`record_store.configure` takes a detached record codec, empty-record constructor, equality, identity/revision
projection and pure revision replacement. Its `read` distinguishes absence from failed reads; `update`
checks the exact captured record inside every atomic callback and verifies the committed readback.
Configure the revision ceiling. Record layouts, migrations, payload validation and partition namespaces
remain in the adopter. Codec functions must reject invalid records and never mutate input or perform effects.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/persistence/profile-session.verify.luau --name "preserves changes arriving during a successful save"
```

The [executable specification](../src/core/persistence/profile-session.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: preserves changes arriving during a successful save.

### Invariants

Independent keys can progress while each key stays ordered. Save acknowledgments preserve concurrent dirty work. Expiry fences late completions; close respects its budget.

The profile-session suite owns acquisition-time validation, renewal retries, expiry fencing,
dirty-generation retention and close draining. Adopters test their configured lease, renewal,
coalescing and shutdown boundaries and their ordinary/immediate dirty-reason vocabulary.

The [leased-record fixture](../src/roblox/leased-record-session.verify.luau) exercises record-store
absence, stored revision zero, mismatched snapshots, callback retries, readback uncertainty and a small
revision ceiling. Run it with `lute run tools/gate.luau --file src/roblox/leased-record-session.verify.luau`.

## professions

Run skills, recipe transactions, harvesting, fishing and gathering sessions.

### State shape

Skill `State` holds learned professions/recipes. Crafting `Plan` captures reagents/output. Fishing `Line`, session `Session` and gathering `State` carry timing and claim identity.

Types and configuration are exported from [src/core/professions.luau](../src/core/professions.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [crafting](../src/core/professions/crafting.luau) | `craft`, `create`, `plan` | `Plan`, `Outcome`, `Config` |
| [fishing](../src/core/professions/fishing.luau) | `cast`, `create`, `hook`, `idle`, `isJunk`, `observe`, `pick`, `reel` | `Phase`, `Line`, `Catch`, `Config` |
| [gathering](../src/core/professions/gathering.luau) | `computeYield`, `create`, `emptyState`, `projectNode`, `step` | `RealmId`, `SpaceKind`, `Phase`, `Node`, `State`, `CommandKind`, `Command`, `Result` |
| [harvest](../src/core/professions/harvest.luau) | `canAttempt`, `create`, `harvestNode`, `skinCorpse` | `Yield`, `Outcome`, `Config` |
| [session](../src/core/professions/session.luau) | `begin`, `check`, `create` | `Kind`, `Session`, `Sample` |
| [skills](../src/core/professions/skills.luau) | `canLearn`, `canLearnRecipe`, `copy`, `create`, `default`, `freezeState`, `knownRecipes`, `knows`, `learn`, `learnFromItem`, `learnRecipe`, `normalize`, `primaryCount`, `primarySlotsFree`, `profession`, `rollSkillUp`, `sameState`, `skillOf`, `skillUpChance`, `trainerRoster`, `unlearn` | `Kind`, `Profession`, `State`, `Color`, `Config` |
| [types](../src/core/professions/types.luau) |  | `Sustain`, `Reagent`, `QuestInput`, `Thresholds`, `Source`, `Descriptor`, `Recipe`, `Extra`, `NodeKind`, `SkinRow`, `FishRow` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply catalogs, skill curves/chances, quality and yield rules, stations, item/profile operations, clocks and random samples. The adapter commits through injected profile/world ports.

Recipe `source` and `rung` are caller-defined labels. Play does not impose a game's source taxonomy
or activity names; the game owns their admission and presentation.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/professions/professions.verify.luau --name "admits configured skills and releases recipes without changing the prior snapshot"
```

The [executable specification](../src/core/professions/professions.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: admits configured skills and releases recipes without changing the prior snapshot.

### Invariants

Failed crafting spends nothing. Interrupted sessions cannot complete. Node claims replay safely. Catalogs and game rewards remain caller-owned.

## progression

Compose levels, talents, recovery, consumables, action bars, reputation, seasons and reward settlement.

### State shape

Each component has its own saved shape: talent ranks/loadouts, consumable channels/buffs, death records, actionbar slots, event ledgers, seasonal tracks and settlement receipts.

Types and configuration are exported from [src/core/progression.luau](../src/core/progression.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [actionbar](../src/core/progression/actionbar.luau) | `actionbar`, `apply`, `assign`, `clear`, `contextFor`, `copy`, `decodeWire`, `default`, `effective`, `encodeWire`, `itemAction`, `itemId`, `layerEntries`, `normalize`, `placed`, `project`, `resolvePress`, `slotFor`, `swap` | `State`, `Context`, `Layout`, `Intent`, `Config` |
| [consumables](../src/core/progression/consumables.luau) | `activeStats`, `advance`, `begin`, `copy`, `create`, `eligibility`, `interrupt`, `interruptActor`, `item`, `register`, `registerAll` | `Buff`, `Item`, `Channel`, `ActiveBuff`, `State`, `Actor`, `ActorView`, `Mob`, `Config` |
| [grants](../src/core/progression/grants.luau) | `compileProductionRegistry`, `forClass`, `gateFor`, `grantedIds`, `grants`, `indexOf`, `isGranted`, `problemsFor`, `problemsForClassSchema` | `Grant`, `GrantIndex`, `ProductionRegistry`, `ProductionRegistryResult`, `Config` |
| [hearth](../src/core/progression/hearth.luau) | `arrived`, `bind`, `destination`, `hearth`, `homeZone`, `normalize` | `Destination`, `Bind`, `State`, `BoundState`, `Config` |
| [levels](../src/core/progression/levels.luau) | `awardXp`, `levelForXp`, `levels`, `resolveLevel`, `rewardProjection`, `snapshotFromValues`, `validateCurve`, `xpBracket`, `xpForLevel` | `CurveRow`, `Curve`, `Config`, `Progression`, `Snapshot`, `RewardProjection` |
| [recovery](../src/core/progression/recovery.luau) | `anchorPosition`, `anchoredLastPosition`, `decodeEcho`, `die`, `echoDistance`, `encodeEcho`, `lowHealth`, `recover`, `recovery`, `release` | `Point`, `Cost`, `Death`, `Position`, `AnchoredPosition`, `Config` |
| [reputation](../src/core/progression/reputation.luau) | `apply`, `create`, `emptyState`, `pointsFor`, `projectEvent`, `projectLadder`, `projectState`, `rankFor`, `standings` | `EventKind`, `Event`, `State`, `ApplyResult`, `Ladder`, `Standing`, `Config` |
| [season](../src/core/progression/season.luau) | `apply`, `claim`, `claimIn`, `definition`, `emptyState`, `projectState`, `projectTracks`, `projection`, `projectionIn`, `recordIn`, `season` | `Event`, `State`, `Result`, `PlaySource`, `Objective`, `Reward`, `AuthoredDefinition`, `Definition`, `ProjectionObjective`, `Projection`, `Config` |
| [settlement](../src/core/progression/settlement.luau) | `applyPersonalReward`, `emptyRewardHistory`, `settlement` | `RewardReceipt`, `RewardHistory`, `RewardRequest`, `RewardGrant`, `RewardApplied`, `RewardRejected`, `RewardResult`, `GrantResult`, `Config` |
| [standing-credit](../src/core/progression/standing-credit.luau) | `create` | `Outcome`, `Config` |
| [talent-ranks](../src/core/progression/talent-ranks.luau) | `FULL_RANK`, `INVALID_STATE`, `NO_POINTS`, `TIER_LOCKED`, `UNKNOWN_TALENT`, `addRank`, `availablePoints`, `bucketOf`, `rankRefusal`, `respecRole`, `spendByLine`, `spentPoints`, `stateProblem` | `Loadout`, `Result`, `Node`, `Tier`, `Line`, `Spec`, `Bucket` |
| [talents](../src/core/progression/talents.luau) | `change`, `decodeIntent`, `default`, `fromLoadout`, `load`, `normalize`, `rules`, `toLoadout` | `State`, `Loadout`, `Intent`, `Result` |
| [tracking](../src/core/progression/tracking.luau) | `canTrack`, `tracking` | `Config` |
| [transactions](../src/core/progression/transactions.luau) | `commit`, `isRecorded`, `ledgerKey`, `recordedKeys`, `transactions` | `CollectionSet`, `Outcome`, `Result`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply curves, class/resource/admission policy, catalogs, numeric/time bounds and pure account/profile projectors. Standing-credit coordinates injected authority/readiness/write callbacks.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/progression/actionbar.verify.luau --name "skips malformed and unearned loadout rows while retaining valid entries"
```

The [executable specification](../src/core/progression/actionbar.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: skips malformed and unearned loadout rows while retaining valid entries.

### Invariants

Refused transitions preserve caller state. Talent budgets and tier gates hold. Recovery deadlines do not pay twice. Personal grants must agree with both settlement ledgers.

## quest

Index declarative objectives and coordinate saved journals, quest progress projections, runs and claims.

### State shape

`Objective`, `Binding` and `Event` describe matching; counters hold completions; run `RunState` holds members/phases/history; claims retain invitation and replacement identity.
Journal `Record` holds an exact version, zone/character identity, quest status/step/count maps and semantic
event receipt identities. Its parser copies admitted maps and applies configured bounds and vocabulary.

Types and configuration are exported from [src/core/quest.luau](../src/core/quest.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [claims](../src/core/quest/claims.luau) | `carrierFor`, `claimTransform`, `claims`, `closeTransform`, `createTransform`, `inviteReplacementTransform`, `isReservedServer`, `newRecord`, `readRecord`, `readReplacementIdentity`, `rejoinTarget`, `renewTransform`, `replaceRosterTransform`, `retryDelaysSec`, `runKey`, `serverKey`, `teleportData`, `userKey`, `validRecord`, `writeThroughTransform` | `Invitation`, `ReplacementIdentity`, `Member`, `Record`, `Target`, `Transform`, `Config` |
| [counter](../src/core/quest/counter.luau) | `count`, `counter`, `label`, `questIdFromMarkerName` | `Band`, `Counts`, `Config` |
| [index](../src/core/quest/index.luau) | `bindingsForEvent`, `byTarget`, `index`, `objectiveBindings` | `Config`, `TargetBinding` |
| [journal](../src/core/quest/journal.luau) | `journal` configures creation, decoding, bounded copying, saved-quest conversion and identity keys | `QuestProgress`, `Record`, `Config`, `API` |
| [lifecycle](../src/core/quest/lifecycle.luau) | `bindingForObjective`, `lifecycle`, `projectObjective`, `validateObjective` | `Objective`, `Binding`, `Event`, `Quest`, `Problem`, `Config` |
| [markers](../src/core/quest/markers.luau) | `colorForState`, `isActionable`, `markers`, `shownState`, `stateForEntry`, `stateForGiver` | `QuestStatus`, `MarkerState`, `QuestEntry`, `Config` |
| [objectives](../src/core/quest/objectives.luau) | `binding`, `bindings`, `bindingsFor`, `catalog`, `contract`, `eventOf`, `events`, `kinds`, `known`, `matches`, `targetsOf`, `validate` | `Targets`, `KindSpec`, `Objective`, `Quest`, `Event`, `Binding`, `Problem`, `EventContract`, `Aliases`, `Config`, `Catalog` |
| [progress](../src/core/quest/progress.luau) | `progress` configures admission, prerequisites, exclusive paths, objective lookup, ordered counts and replay status | `QuestProgress`, `Rule`, `Branch`, `Statuses`, `ObjectiveView`, `QuestView`, `ActorView`, `ContentView`, `Config`, `API` |
| [run](../src/core/quest/run.luau) | `run` | `Package`, `RunStatus`, `Member`, `RunState`, `StartEvent`, `CompletePhaseEvent`, `MemberEvent`, `WipeEvent`, `Event`, `Recovery`, `TransitionApplied`, `TransitionRejected`, `TransitionResult`, `Core`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply objective kinds/targets, quest definitions, level/marker policy, package/run admission and claim transforms. The game installs actor progress and persists rewards.
Journals additionally need the current saved version, bounds, status vocabulary, receipt status and literal
namespace plus semantic-event identity policy. The game owns the known quest catalog, leases, schema migration,
authoritative installation, storage keys and ordered persistence. Journal parsing does not write storage.

Progress uses four typed content/quest/objective/actor projections, a realm-admission policy and six status
names. Definitions and objectives remain generic: lookups return their original game types. Metadata
projections must be pure and stable during a reducer call. Keep content layout, realm/class catalogs,
rewards, objective/spatial policy and authoritative state installation in the game. Align the six progress
statuses with the journal's admitted vocabulary.

`reconcileOrdered` updates the progress map supplied by the actor projection. Call it with a draft owned
by the authoritative reducer. Other progress operations query that state and do not reserve or install it.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/quest/counter.verify.luau --name "counts level-eligible quests and turned-in completions"
```

The [executable specification](../src/core/quest/counter.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: counts level-eligible quests and turned-in completions.

Run the [journal fixture](../src/core/quest/journal.verify.luau) with:

```sh
lute run tools/gate.luau --file src/core/quest/journal.verify.luau
```

It uses version seven, a three-record budget, a two-status vocabulary and a namespace containing a pattern
character to prove literal receipt separation, round trips, copied state and strict recovery validation.

The [progress fixture](../src/core/quest/progress.verify.luau) uses a different model layout and status
vocabulary. Run it with:

```sh
lute run tools/gate.luau --file src/core/quest/progress.verify.luau
```

It exercises original-definition identity, domain/class/level admission, all/any prerequisites, replay
claims, ordered draft reconciliation and malformed/conflicting exclusive paths.

### Invariants

Objective metadata cannot become unintended event targets. Bindings retain authored order. Accepted phases replay safely; conflicting phase identities refuse.
Saved journals refuse unsupported versions, malformed counts, unknown quests and over-budget records.
Semantic receipts have a separate validated shape. Resumed active steps require objective counts.
Quest admission requires known matching realms, current eligibility, satisfied prerequisites, a compatible
exclusive path and no existing progress. Ordered reconciliation advances only the completed prefix and
preserves replay identity. Conflicting or incomplete branch metadata fails closed.

## roblox-bank

Admit authenticated personal-bank transfers and commit them with a durable profile receipt.
Import [roblox/bank](../src/roblox/bank.luau), call `configure(config)`, then `create(dependencies)`.

### State shape

`Result` reports acceptance, durability uncertainty, refusal and the read-back vault state.
`Location` and `Banker` describe place identity, finite position and banker availability.
The host stores only per-subject exclusion and rate windows. Vault items/receipts stay in the profile.

### Operations and host requirements

`intent` decodes a configured vault request, verifies the active subject, context, banker proximity
and item policy, then commits the transfer. `forget` releases rate state. `reachable` exposes the same
place/distance admission used by the coordinator.

Configure vault operations, profile read/commit, vault projection, transaction namespace and numeric
limits. The commit must atomically record its transaction with the effect, replay without applying
twice and return actual durability. Dependencies provide the authoritative subject/context/profile,
positions, banker lookup, item authorization, optional identity decoding and elapsed-time clock.
Keep catalogs, banker placement, profile shape, item-binding policy and remote lifetime in the game.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/bank.verify.luau
```

The [executable fixture](../src/roblox/bank.verify.luau) binds real vault rules and idempotent
profile commits. It checks receipt replay, forged subjects, distance, item admission, uncertain
saves and rate-state release.

### Invariants

- A subject must be the current authenticated instance for its identity.
- Bankers must be enabled and reachable in the same place.
- Item authorization is checked before admission and again inside the profile effect.
- A transfer is successful only after durable commit and receipt readback.
- Lost durability remains pending; replay cannot duplicate the transfer.

## roblox-camera

Project configured follow-camera dynamics and obstruction response.

### State shape

`Spring` holds position/velocity; `Obstruction` holds smoothing state.

Types and configuration are exported from [src/roblox/camera.luau](../src/roblox/camera.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [camera](../src/roblox/camera.luau) | `create`, `fovTarget`, `isCameraStructure`, `newSpring`, `obstructedDistance`, `shoulderOffset`, `smoothObstruction`, `springStep`, `sprintWiden`, `yields`, `zoomLimits` | `Spring`, `Obstruction`, `Tuning` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply tuning, collision observations and elapsed time; apply transforms in the game.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/camera.verify.luau --name "settles without overshoot and is stable across frame rates"
```

The [executable specification](../src/roblox/camera.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: settles without overshoot and is stable across frame rates.

### Invariants

Spring motion stays stable across frame rates. Obstruction pulls inward immediately and eases outward.

## roblox-cargo

The host store is the kernel `store.Port`: uncached `read` and atomic `update` return the kernel
`Result`. Reads never submit update callbacks. Cancelled cargo and settlement replays require a
fresh complete-record confirmation before acknowledgement. Bind native stores with
`roblox/persistence/store.new`; staged ledger transforms use the same port inside the atomic write.

Coordinate carried claims, recoverable drops and durable extraction through configured cargo rules.
Import [roblox/cargo](../src/roblox/cargo.luau), `configure` the rules/policy, then call `mount` with
camp loading, store and key ports. `mountFromContent` additionally reports missing source/store wiring.

### State shape

A zone record contains `schemaVersion`, `zoneId` and the configured cargo state: monotonic clock,
claims, drops and extraction receipts. Each claim is carried, dropped, banked or lost. Camps contain
identity, realm, center and safe radius. Outcome projections report custody counts, intent receipts,
replay state and the adopter-owned boundary label.

### Operations and required host operations

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

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/cargo.verify.luau
```

The [fixture](../src/roblox/cargo.verify.luau) uses short expiry, different space labels, one neutral
realm, schema seven and small bounds. It exercises two-material custody/recovery, torn settlement and
replay, exact-radius admission, expiry, callback retries and divergent readbacks at all write boundaries.

### Invariants

- A material claim has exactly one custody state.
- Banked-space yields cannot enter carried custody.
- Extraction requires the caller's configured realm camp and accepts the exact radius boundary.
- Cargo custody commits before ledger grants; a replay receipt heals the two-record tear.
- All extraction grants are staged inside one atomic ledger transform.
- Callback retries discard earlier speculative results.
- Cargo and ledger writes require exact desired committed readbacks before reporting success.
- Divergent readbacks remain reconcilable through the original claim/extraction receipts.

## roblox-character-admission

Stage a leased character's arrival into a host's profile, session, actor, body and movement owners,
then unwind those owners safely on failure or departure. Import
[roblox/character-admission](../src/roblox/character-admission.luau) and call `start(config, dependencies)`.
The result is a started runtime or a structured setup refusal. Profiles remain opaque generic values.

### State shape

The runtime tracks per-subject context and user/character/session/acquisition/revision identities,
destination, installed-owner flags, renewal state and pending cleanup. Context is a frozen six-field
identity/key/lease-revision record. Return snapshots capture the subject, character, destination,
route identity and fence. Optional per-coroutine timelines record bounded stage/storage observations.

### Operations

`start` validates policy/place/reclaim inputs, installs owned subscriptions and admits current subjects.
Admission validates the subject and native route through injected authority, reserves any group claim,
marks roster departure, acquires character authority and fences it before loading/binding downstream
owners. It compares profile identity facts before projecting the game profile and admitting actor,
body and movement. Optional receipt failure is reported as a stage observation.

`cleanup` removes movement, body and actor owners before releasing session/profile/lease authority.
Failed removal retains its ownership flags for retry. Cleanup during renewal either waits within the
configured budget or reports failure with custody retained. `dispose` stops admission, releases
subscriptions and attempts cleanup for every retained entry. `isAdmitted` observes current movement
and optional group authority. `previewDeparture`, `prepareReturn` and `recover` expose fenced return
snapshots and recovery; preparation reports a separate recoverable snapshot if cleanup fails.

### Required host operations

Supply authenticated carrier/routing, roster/character lease, profile, session, actor, body, movement,
player-presence/subscription and receipt ports. Supply the clock and owned renewal scheduler, optional
wait/reclaim and group-authority/reconnect operations, and optional timeline publication/store observation.
Native operations may yield; return actual outcomes and maintain the supplied acquisition identity.
The game retains authentication, namespaces, native object lifetime and all gameplay authority.

Configuration supplies typed profile-fact and native profile projections, an identity comparison,
lease-failure reporting, identity/timeline limits, lease/retry/renewal/cleanup cadence and retry reasons.
Reclaim attempts, delays and wait operation belong to the runtime dependencies. Profile ports must
validate the full game model; the coordinator only checks the projected user/character/version facts.
Keep profile schemas, identity fields, attribute names, content, labels and telemetry destinations local.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/character-admission.verify.luau
```

The [fixture](../src/roblox/character-admission.verify.luau) supplies fake native owners, synthetic
place identities, an alternate profile layout/version and short lease timings. It checks stage order,
reverse cleanup, retained authority on failed removal, stale renewal callbacks across recovery, expiry
fencing and subscription setup failure. Consumer tests exercise real routing/profile/session ports.

### Invariants

- Actor/body/movement authority is installed only after identity and lease fencing.
- Downstream owner failure unwinds completed owners in reverse order.
- A failed actor removal cannot release session, profile or lease authority underneath it.
- Lease/session/acquisition/revision facts bind renewal and recovery.
- Expired renewal failure fences admission and reports through the game's telemetry port.
- Old scheduled callbacks cannot advance a replacement admission or a disposed runtime.
- Native projection, persistence, routing and gameplay operations remain injected and host-owned.

## roblox-chat

Bind admitted users to native channels and check platform privacy.

### State shape

The adapter returns permission/refusal results and lists of removed/refused channels; native channel ownership stays with the game.

Types and configuration are exported from [src/roblox/chat.luau](../src/roblox/chat.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [chat](../src/roblox/chat.luau) | `directAllowed`, `permission`, `removeForeign`, `seat` | `DirectQuery` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject privacy queries, wait/retry, channel naming/add/remove and native destruction.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/chat.verify.luau --name "channel seating reports refusal and errors without stopping other seats"
```

The [executable specification](../src/roblox/chat.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: channel seating reports refusal and errors without stopping other seats.

### Invariants

One failed channel does not stop other seats. Unavailable privacy queries remain distinguishable from denial.

## roblox-consumables

Coordinate durable item consumption before recovery dispatch.

### State shape

Pending uses retain receipt, character identity and interruption generation; `Status` reports progress/refusal.

Types and configuration are exported from [src/roblox/consumables.luau](../src/roblox/consumables.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [consumables](../src/roblox/consumables.luau) | `create`, `decodeUseRequest`, `enforce`, `forget`, `status`, `use` | `Actor`, `Snapshot`, `Status`, `CommitResult`, `Rules`, `Dependencies`, `Handle`, `UseRequest` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject snapshots, profile readiness, receipt reads, durable commits, begin/cancel commands and time.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/consumables.verify.luau --name "starts recovery only after durable consumption and rejects replayed input"
```

The [executable specification](../src/roblox/consumables.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: starts recovery only after durable consumption and rejects replayed input.

### Invariants

No recovery starts before consumption commits. Uncertain writes retain identity. Character/movement/control admission is checked again after yielding.

## roblox-contact-markers

Share animation-track watchers and confirm stamped contacts once.

### State shape

Per-character watches retain track stamps, waiter identity and release callbacks.

Types and configuration are exported from [src/roblox/contact-markers.luau](../src/roblox/contact-markers.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [contact-markers](../src/roblox/contact-markers.luau) | `confirmed`, `create`, `onContact`, `retrigger`, `watch` | `Host` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject `Host<C,T>` stamp, listen, marker and admit callbacks.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/contact-markers.verify.luau --name "rejects stale tracks, presents once per stamp, and releases the last watcher"
```

The [executable specification](../src/roblox/contact-markers.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: rejects stale tracks, presents once per stamp, and releases the last watcher.

### Invariants

Old tracks cannot confirm a new action. A contact presents once per stamp. The last watcher releases subscriptions.

## roblox-conversation-camera

Own conversation framing while allowing temporary obstruction and player override.

### State shape

`State` tracks conversation identity/ownership and framing; `Rect`/`View` describe measured safe space.

Types and configuration are exported from [src/roblox/conversation-camera.luau](../src/roblox/conversation-camera.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [conversation-camera](../src/roblox/conversation-camera.luau) | `cameraGesture`, `choose`, `create`, `new`, `space`, `step`, `views` | `Point`, `Rect`, `View`, `State`, `Tuning` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply spring operations, tuning, conversation/speaker identity, UI bounds and sightline results; apply native transforms.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/camera.verify.luau --name "waits for streaming, survives temporary obstruction and releases until the next conversation"
```

The [executable specification](../src/roblox/camera.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: waits for streaming, survives temporary obstruction and releases until the next conversation.

### Invariants

Temporary obstruction allows reacquisition. Manual override releases ownership until conversation identity changes.

## roblox-cue-mixer

Admit cue voices with retrigger, family caps and ducking.

### State shape

`Mixer` retains cue deadlines and active voices by family; `MixSpec`/`DuckSpec` carry policy.

Types and configuration are exported from [src/roblox/cue-mixer.luau](../src/roblox/cue-mixer.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [cue-mixer](../src/roblox/cue-mixer.luau) | `activeVoices`, `admit`, `duckGain`, `gate`, `new`, `setVoiceActive` | `MixSpec`, `DuckSpec`, `CueSource`, `Mixer` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply `CueSource`, mix definitions and a clock. Report native voice activity.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/cue-playback.verify.luau --name "limits voices and retriggers with a clock seam and ducks only active families"
```

The [executable specification](../src/roblox/cue-playback.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: limits voices and retriggers with a clock seam and ducks only active families.

### Invariants

Unknown cues refuse admission. Retrigger/cap admission is deterministic. Only configured active families cause ducking.

## roblox-cue-playback

Play admitted cue identities and drive bounded frame effects.

### State shape

Voice lifetime belongs to the returned player; `VoiceProps`/`PlaySpec` describe configured native work.

Types and configuration are exported from [src/roblox/cue-playback.luau](../src/roblox/cue-playback.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [cue-playback](../src/roblox/cue-playback.luau) | `animator`, `make` | `VoiceProps`, `PlaySpec`, `Source`, `Deps` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject catalog/admission, voice mount/play, scheduler, home, tail duration, clock and render-connect operations.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/cue-playback.verify.luau --name "limits voices and retriggers with a clock seam and ducks only active families"
```

The [executable specification](../src/roblox/cue-playback.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: limits voices and retriggers with a clock seam and ducks only active families.

### Invariants

Voices retire after configured lifetime/tail. Animation begins at zero, clamps progress and disconnects on completion.

## roblox-data-store

Retry injected operations with bounded exponential delay and jitter.

### State shape

`RetryPolicy` holds attempts/base/max delay; each run retains its latest result.

Types and configuration are exported from [src/roblox/data-store.luau](../src/roblox/data-store.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [data-store](../src/roblox/data-store.luau) | `delay`, `retryPolicy`, `run` | `RetryPolicy` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject operation, sleep and random jitter; bind the actual backend in the game.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/data-store.verify.luau --name "retries transient failures on the fake host clock and returns the committed result"
```

The [executable specification](../src/roblox/data-store.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: retries transient failures on the fake host clock and returns the committed result.

### Invariants

Attempts are bounded. The final committed result is returned. Delays respect configured maximum before jitter.

## roblox-equipment-queue

Serialize equipment application per owner across yielding work.

### State shape

`Queue<P,C>` retains latest pending body and per-owner generation.

Types and configuration are exported from [src/roblox/equipment-queue.luau](../src/roblox/equipment-queue.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [equipment-queue](../src/roblox/equipment-queue.luau) | `create`, `dispose`, `forget`, `generation`, `invalidate`, `request`, `running` | `Deps`, `Queue` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject spawn, active/current body reads, perform and warn operations.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/equipment-queue.verify.luau --name "returns before stalled gear resolves and fences a stale request"
```

The [executable specification](../src/roblox/equipment-queue.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: returns before stalled gear resolves and fences a stale request.

### Invariants

Pending requests coalesce. Generations fence stale completion. Invalidate/forget/dispose revoke owned work.

## roblox-equipment-rig

Scope construction attempts, join meshes and settle equipment slots.

### State shape

`Ownership<O,C>` supplies lifetime/checkpoints; `MeshCache` and `BatchState` track bounded work and per-slot settlement.

Types and configuration are exported from [src/roblox/equipment-rig.luau](../src/roblox/equipment-rig.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [equipment-rig](../src/roblox/equipment-rig.luau) | `afterExternal`, `applyBatch`, `assertCurrent`, `attempt`, `disposeLoose`, `isInFlight`, `isRefused`, `lifetime`, `meshCache`, `refuse`, `refusedCount`, `reset`, `resolve`, `withOwner` | `Ownership`, `MeshCache`, `Failure`, `BatchState`, `BatchHost` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject ownership run/create/dispose/checkpoint/rollback, native mesh/adopt operations, recipes, fitting and reporting.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/equipment-rig.verify.luau --name "rolls back refused and throwing attempts without disposing the surrounding owner"
```

The [executable specification](../src/roblox/equipment-rig.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: rolls back refused and throwing attempts without disposing the surrounding owner.

### Invariants

Refused or throwing attempts roll back. Stale external results are disposed. Slot settlement does not dispose the surrounding owner.

## roblox-guild-bank

Settle authoritative profile inventory against a shared guild bank with durable holds and receipts.
Import [roblox/guild-bank](../src/roblox/guild-bank.luau), configure profile/ledger projections
and limits, then call `mount(dependencies)`.

### State shape

The shared bank owns stock, withdrawals, receipt credits, operation fences and logs.
Profiles own pending deposit holds and unacknowledged receipt identities. The profile type is generic.
The host retains per-subject exclusion, recovery admission and cached bank projections.

### Operations and host requirements

`join` reconciles pending holds and receipt acknowledgments before admitting transfers.
`deposit` saves a profile debit before the bank mutation. `withdraw` verifies room, applies the shared
bank decision, saves receipt credits and acknowledges them. `refresh`, `projection` and `forget`
manage recovery and server views.

Configure ledger transitions, profile copy/inventory/ledger/capacity projections, receipt selection,
stack/transfer/display limits and matching recovery/receipt retention. Dependencies supply bank
read/atomic-apply ports, material labels, current/fresh membership, profile read/update/save, clock
and unique operation identities. Profile transforms must complete before returning and may retry.
The final callback acceptance governs saving; a missing callback cannot authorize a bank write.
Store replies must describe committed readback and distinguish uncertainty from definitive refusal.
Keep catalogs, profile schema, storage scope, role policy, session authority and native UI in the game.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/guild-bank.verify.luau
```

The [executable fixture](../src/roblox/guild-bank.verify.luau) composes actual bank and profile
ledger rules with neutral accounts. It checks deposits/claims, replay, member limits, lost replies,
callback retries, missing callbacks and missing bank readback.

### Invariants

- A durable profile debit precedes a deposit mutation on the shared bank.
- An uncertain deposit stays held until a known/voided operation fence settles it.
- Receipt credits are saved before acknowledgment and cannot be claimed twice.
- Missing bank state never authorizes clearing profile acknowledgment evidence.
- Final transform acceptance controls saving after retries.
- Holds beyond retention remain for audit; stale receipts expire only under current membership policy.

## roblox-input-bindings

Project configured keyboard/gamepad bindings, labels and chords.

### State shape

`Action<C>` rows describe identity, context, keys, chord and touch affordance; the returned binding table indexes them.

Types and configuration are exported from [src/roblox/input-bindings.luau](../src/roblox/input-bindings.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [input-bindings](../src/roblox/input-bindings.luau) | `create`, `forContext`, `gamepad`, `gamepadLabel`, `get`, `keyboardLabel`, `keyboardNames`, `matches`, `matchesCode`, `matchesInput`, `primaryKeyboard` | `Action` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply action rows, labels, modifier, enum-like key values and held-button query. Bind native events in the game.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/examples/input-bindings.luau
```

The [complete example](../tools/examples/input-bindings.luau) includes configuration and executable assertions.

### Invariants

Chorded gamepad actions require the held modifier. Keyboard admission is independent. Context filtering returns only matching actions.

## roblox-input-contexts

Resolve native readiness against one deadline and adopt server templates.

### State shape

`Template`, `Surfaces` and frozen `Mounted` readback describe context ownership.

Types and configuration are exported from [src/roblox/input-contexts.luau](../src/roblox/input-contexts.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [input-contexts](../src/roblox/input-contexts.luau) | `action`, `context`, `create`, `mount` | `Template`, `Surfaces`, `Mounted` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject find/wait, clock, context/action conversion, names/minimum wait, surface queries and adoption.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/input-contexts.verify.luau --name "reuses existing server contexts and fails closed when their query throws"
```

The [executable specification](../src/roblox/input-contexts.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: reuses existing server contexts and fails closed when their query throws.

### Invariants

Readiness shares a deadline across the path. Wrong-class/missing actions refuse. Failed adoption/query cannot report a successful mount.

## roblox-input-profile

Coordinate device reach, action coverage and rollback-safe sessions.

### State shape

`Profile` lists actions and affordances; `Session` owns admitted bindings until stop.

Types and configuration are exported from [src/roblox/input-profile.luau](../src/roblox/input-profile.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [input-profile](../src/roblox/input-profile.luau) | `coverage`, `create`, `parity`, `profile`, `reach`, `start` | `Device`, `TouchAffordance`, `Action`, `Profile`, `Session` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject bind, thumbstick, dispatch, intent and existing screen/button surfaces.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/input-profile.verify.luau --name "routes buttons, screen actions and movement across devices and rejects input after stop"
```

The [executable specification](../src/roblox/input-profile.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: routes buttons, screen actions and movement across devices and rejects input after stop.

### Invariants

Partial mounts roll back. Coverage is exclusive. Input after stop is ignored and owned bindings are released.

## roblox-inventory

Bind inventory reads, item mutation and receipt-backed reward bundles to an authoritative profile owner.
Import [roblox/inventory](../src/roblox/inventory.luau) and construct it with `create(config)`.

### State shape

`Inventory` maps item identities to counts. `RewardItem` is `{ id, count }`. The generic `Service<S,R,P>`
uses the game's subject, readable handle and profile types. It keeps no profile schema or durable store.
The game supplies context identity, inventory projection, capacity, receipt reads and reward projection.

### Operations and host requirements

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

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/inventory.verify.luau
```

The [executable fixture](../src/roblox/inventory.verify.luau) supplies a profile cell, context,
inventory policy and reward projector. It exercises active and lost authority, retries, capacity,
malformed rewards and receipt replay. See the [API reference](api.md) for exact generic contracts.

### Invariants

- A refused mutation preserves the profile and its receipts.
- New stacks respect capacity; existing stacks can grow in an overfull bag under supplied fit policy.
- The final transform's context and result govern acceptance after a retry.
- A reward bundle and its receipt are projected together; replay cannot apply twice.
- Returned bags are detached, and caller changes cannot rewrite an admitted reward bundle.

## roblox-leased-record-session

Coordinate durable lease acquisition, record hydration, takeover fencing and payload saves over opaque
record schemas. Import [roblox/leased-record-session](../src/roblox/leased-record-session.luau) and
call `configure(config)`. It composes the configured lease store, profile-session rules and record store.

### State shape

`Accepted<R>` contains the acquired lease, mutable profile-session state and authoritative
`record-store.Accepted<R>` snapshot. Saved outcomes carry the renewed lease even when a later stage
fails. The opaque record `R` remains owned by the adopter; projections expose only the subject identity
and payload replacement needed by the save coordinator.

### Operations and required host operations

`acquireAndHydrate` takes dependency ports and zone/subject/session/acquisition identities. It acquires
the lease, fences the previous owner's record partition, reads the requested record and opens a session
from the persisted expiry. On failure it attempts release and reports release uncertainty separately.
An old lease without a known partition requires the host's complete partition family before takeover.

`savePayload` marks the configured dirty reason, begins a save, renews the lease, checks the captured
snapshot and game-provided payload replacement, then runs record compare-and-swap and completes the
session. Supply a monotonic clock and store read/atomic-update operations. These may yield; the stored
expiry and session completion rules fence late replies. Backend transforms must be side-effect free.

Keep storage scope, schemas/migrations, payload policy, subject projection, duration and dirty-reason
selection in the adopter. The record codec and replacement must return detached valid data, preserve
unmodified fields and perform no I/O. Native scheduling and gameplay authority are host responsibilities.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/leased-record-session.verify.luau
```

The [fixture](../src/roblox/leased-record-session.verify.luau) uses an alternate record shape,
numeric payload, four-revision ceiling, schema-seven lease, twenty-unit expiry and fake store/clock.
It includes final callback retry conflicts, uncertain readbacks, hydration failure, takeover fencing,
lease-length reply delays at renewal and storage, and game payload refusal.
It also owns exact acquisition replay, duplicate refusal before hydration, failed release reporting,
expiry during hydration, renewal refusal before record writes and dirty-generation retention after
conflicted or ambiguous saves. Adopters retain their actual schema/payload projection, storage adapter,
partition-family and retirement bindings; these fixtures do not certify native storage durability.

### Invariants

- A failed read is never interpreted as an absent record.
- Compare-and-swap checks the full captured record on every callback invocation.
- A successful store result must contain the exact desired committed record.
- Takeover fences the prior partition before accepting a new session.
- Hydration failure releases the acquired lease or reports why release is uncertain.
- Save failure retains dirty state and reports the renewed lease when one was persisted.
- Lease expiry fences completions even after a successful backend write.
- Payload replacement preserves opaque record fields and leaves the captured snapshot unchanged.

## roblox-mail

Coordinate receipt-backed mail delivery between authoritative profiles and an envelope store.
Import [roblox/mail](../src/roblox/mail.luau), call `configure(config)`, then `create(dependencies)`.

### State shape

The pure mailbox supplies `Envelope` and `Pointer` shapes. Envelopes contain sender and recipient
identities, optional character identities, attachments, timestamps and a durable decision phase.
Profiles retain pending hold/claim pointers and the transaction ledger under game-owned projections.
The host keeps only in-flight exclusion and rate windows in memory.

### Operations and host requirements

`send` reserves inbox space, prepares an envelope, holds attachments and dispatches it.
`claim`, `returnMail` and `expire` choose durable outcomes. `recover` completes interrupted effects;
`admit` reconciles pointers on profile admission. `status` reads a participant's envelope.

Supply configured mailbox operations, profile lookup/update/commit, character and pointer
projections, identity decoding, storage and transaction namespaces, sender decoding and limits.
The profile commit port must atomically install its effect and transaction receipt, replay without
duplicating effects and report the actual durability outcome. Update callbacks may retry.

Per-instance dependencies supply envelope reads/atomic updates, active contexts, recipient lookup,
tradeability and send policy, inbox reservation/release, clock, TTL and session fencing selection.
Store updates must return the committed readback; uncertain writes are reconciled by reading.
Use comparable persisted timestamps. Keep native player decoding, names, schemas and storage scope
in the game. When session fencing is enabled, both profile and envelope character identities must match.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/mail.verify.luau
```

The [executable fixture](../src/roblox/mail.verify.luau) uses neutral accounts and injectable
faults. It demonstrates uncertain writes, repeated requests, one-time delivery, interrupted claim
admission, unreadable decisions, character replacement and return to sender.

### Invariants

- Reusing a request with different participants or attachments refuses the conflict.
- A hold and its pointer are installed together through an idempotent transaction.
- A durable decision precedes delivery; retries cannot duplicate the transfer.
- Unreadable decisions remain pending without authorizing new effects.
- Replacement characters cannot receive another character's attachment.
- Inbox release and pointer cleanup remain recoverable after the transfer settles.

## roblox-market-profile-wallet

Project a market wallet from an authoritative profile and apply paired writes as deltas.
Import [roblox/market-profile-wallet](../src/roblox/market-profile-wallet.luau), call
`configure(config)`, then `create(dependencies)`.

### State shape

The profile type and item source are generic. The configured projections expose coin, inventory,
market ledger and tradeable goods. `Wallet` supplies `read`, `write` and `room` to settlement.
Each instance remembers one paired read; the profile owner retains authoritative state and durability.

### Operations and host requirements

`read` composes the current wallet and captures its baseline. `write` consumes that baseline,
applies the successor's deltas to the latest profile, installs its ledger and requests a durable save.
`room` reports current item room. `applyDelta` exposes the same pure projection for independent checks.

Configure wallet codecs, item source, profile projections, tradeable-goods policy, account writer,
capacity, entries, fit and unbound-count rules. Dependencies supply subject identity, material ids,
profile read/update/save operations and stack/entry bounds. Updates must complete their transform
before returning and may retry. A save must report settled durability. Keep one owning wallet
coordinator per session and retain uncertain writes for settlement recovery.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/market-profile-wallet.verify.luau
```

The [executable fixture](../src/roblox/market-profile-wallet.verify.luau) uses real wallet/stack
rules with a neutral profile. It checks concurrent rewards, paired-write consumption, bound removals,
capacity, callback retries and uncertain saves.

### Invariants

- Writes preserve rewards or inventory changes received after the paired read.
- A consumed or missing baseline cannot authorize another write.
- Negative balances, bound removal and capacity overflow preserve the refused profile.
- The final transform's acceptance determines whether saving proceeds after a retry.
- Success requires the profile owner to confirm durable saving.

## roblox-market-settlement

Coordinate an authoritative wallet with a shared order book without assuming cross-store atomicity.
Import [roblox/market-settlement](../src/roblox/market-settlement.luau) and call
`configure(config).create(dependencies)`.

### State shape

The wallet contains coin, goods, pending consign/buy operations and claimed receipt identities.
The order book contains listings, durable operation fences and unacknowledged receipts.
The coordinator keeps one in-memory exclusion flag per instance; durable recovery lives in those stores.

### Operations and host requirements

`consign` saves a goods debit before listing; `buy` saves a coin hold before filling an order.
`cancel` claims returned goods. `claimAll` saves eligible receipt credits as one wallet batch before
acknowledgment. `heal` resolves pending operations by writing a durable known/voided book fence.

Supply configured wallet transitions, book receipt projection and the wallet's matching recovery
retention. Bind the book's atomic `apply` and `read` ports, authoritative wallet read/durable write,
optional per-item room, comparable clock and unique operation identities. A definitive refusal may
refund; an uncertain outcome must remain pending. Only one coordinator may own a session's wallet.
Wallet writes must report settled durability and preserve the profile transaction/lease policy.
The game retains catalog policy, realm admission, storage namespaces, wallet projection and native UI.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/market-settlement.verify.luau
```

The [executable fixture](../src/roblox/market-settlement.verify.luau) binds pure configured book
and wallet transitions to in-memory ports. It checks conservation through fees, duplicate claim
recovery, lost replies, failed wallet saves, void fences and retention-bound audit holds.

### Invariants

- A book mutation follows a durable wallet debit or hold.
- An uncertain book outcome never authorizes a refund without a committed void fence.
- Receipt credits are durable before acknowledgment; replay cannot credit them twice.
- Claims which exceed item room remain on the book.
- Expiry sweep failure does not block already-visible claims.
- Holds beyond recovery retention remain for audit rather than risking duplicate credit.

## roblox-market

Coordinate market admission, catalog limits, cached book projections, merchant trades and item search.
Import [roblox/market](../src/roblox/market.luau), call `configure(config)`, then `mount(dependencies)`.

### State shape

`Catalog` describes material identities, labels, merchant prices and operation/search limits.
`Item<R>` contains display and filtering facts with the consumer's rarity type `R`.
Each host instance caches books, per-subject settlement handles, recovery admission and search filters.
Authoritative coin, goods and receipt state remain in the supplied wallets and books.

### Operations and host requirements

`join` and `refresh` heal pending operations, claim receipts and refresh books.
`list`, `buy`, `cancel`, `listItem` and `buyItem` enforce admission and configured limits before
calling settlement. `npcSell` and `npcBuy` make a single durable wallet transition at catalog prices.
`search`, `searchItems`, `listable` and `projection` return server-owned views; `forget` releases caches.

Configure item facts, item-category policy, filter matching, settlement, book search, merchant wallet
transition, fee display and bounds. The instance supplies catalog, book ports, authoritative wallets,
subject realm lookup, trading permission, comparable clock and operation identities. Wallets must expose
available room as well as durable reads/writes. Use one host per owning profile lifetime.
Keep actual catalogs, class/equipment policy, authentication, storage scope and UI in the game.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/market.verify.luau
```

The [executable fixture](../src/roblox/market.verify.luau) binds real order-book, wallet and
settlement systems to neutral catalogs. It exercises item purchases, custom rarity projections,
merchant prices, refused filters, permission loss and cache readmission.

### Invariants

- Shared-book trading requires permission and completed recovery admission.
- Merchant trades use the catalog's floor/ceiling and do not depend on shared-book permission.
- Purchases which exceed wallet room refuse before holding coin.
- Search filters are decoded and results come from server-owned cached books.
- Recovery failure remains pending and observes the configured retry interval.
- Display projections never write authoritative profiles.

## roblox-material-ledger

Persist configured material-journal transitions with bounded replay receipts and exact readback.
Import [roblox/material-ledger](../src/roblox/material-ledger.luau) and call `configure` with ledger
rules, saved schema version, receipt-window size, text bound and an adopter-owned boundary label.

### State shape

A saved record contains `schemaVersion`, the full material event journal, recent event IDs and the
timestamp floor preceding that receipt window. `NO_FLOOR` is the negative sentinel used before the
window fills. Event amounts/kinds/group rules come from the supplied ledger core. Snapshot outcomes
carry existence, balances, torn groups, event count, replay floor and the configured boundary label.

### Operations and required host operations

`append(store, keyForLedger, ledgerId, event)` validates through the configured core, checks replay
admission and applies the event inside an atomic transform. A retained exact replay cancels the write
and acknowledges the existing receipt only after a fresh read confirms the complete expected record. An event outside the retained window at or below its floor is
refused as unverifiable. A successful write requires the exact desired committed record in its reply.

`snapshot` validates and projects a fresh `store.read` result without submitting an update.
Supply the kernel `store.Port` with uncached `read` and atomic `update`, both returning the kernel
`Result`, and an owned key function. Native callers can use `roblox/persistence/store.new`.
Transforms can repeat: speculative results are cleared on every invocation.
Core operations must be pure. The host owns schema migrations, storage scope, admission/authentication,
native scheduling, backend budgets and eventual reconciliation after uncertainty.

The journal itself is not pruned by the receipt window. The window limits replay evidence, rather than
total storage growth. Keep retention and backend size policy in the adopter.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/cargo.verify.luau
```

The [fixture](../src/roblox/cargo.verify.luau) uses schema seven, a two-receipt window and a fake
atomic store. It exercises retained and expired replay evidence, final-transform refusal, divergent
readback and cargo-to-ledger reconciliation. It does not establish native multi-server interleaving.

### Invariants

- Malformed records and unrecognized schemas fail closed.
- The saved receipt window and floor must match the validated journal.
- Speculative results from earlier callback invocations cannot authorize a final refusal.
- Backend success with a divergent readback is uncertainty, rather than a granted result.
- Replayed receipts never apply a second material grant and require committed readback.
- A snapshot operation cannot silently write a record or interpret transport failure as absence.

## roblox-messaging

Publish and receive typed notices over injected messaging.

### State shape

`Host` carries publication/subscription/decode capabilities; bind returns scoped lifetime operations.

Types and configuration are exported from [src/roblox/messaging.luau](../src/roblox/messaging.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [messaging](../src/roblox/messaging.luau) | `bind`, `publish`, `subscribe` | `Host` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject publish, subscribe, notice decode and error reporting; own the returned disconnect.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/messaging.verify.luau --name "fanout decodes notices, isolates unavailable service and disconnects"
```

The [executable specification](../src/roblox/messaging.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: fanout decodes notices, isolates unavailable service and disconnects.

### Invariants

Unavailable publication is observable. Malformed notices do not dispatch. Cleanup disconnects the subscription.

## roblox-movement-intake

Validate authoritative movement against body epochs, ordering and speed bounds.

### State shape

`State` retains epoch/sequence, baseline and motion budget; `Observation` and `Ack` carry host readback.

Types and configuration are exported from [src/roblox/movement-intake.luau](../src/roblox/movement-intake.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [movement-intake](../src/roblox/movement-intake.luau) | `start` | `Point`, `State`, `Observation`, `Normalized`, `Ack`, `Dependencies`, `StopResult`, `Started`, `Refused` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject body/session observations, clock, world admission, movement normalization, correction and acknowledgment.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/movement-intake.verify.luau --name "refuses and restores a same-body frontier displacement"
```

The [executable specification](../src/roblox/movement-intake.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: refuses and restores a same-body frontier displacement.

### Invariants

Displacement/sustained-speed violations revoke authority. A stale body or epoch cannot move a replacement. Refusals restore the authoritative baseline.

## roblox-movement-sender

Send client movement through an epoch handshake and acknowledgment ledger.

### State shape

The connection retains body epoch, pending sequence samples, resend timing and held planar movement.

Types and configuration are exported from [src/roblox/movement-sender.luau](../src/roblox/movement-sender.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [movement-sender](../src/roblox/movement-sender.luau) | `start` | `Planar`, `Refused`, `Stopped`, `Started`, `StartResult`, `Payload`, `Connection`, `Dependencies` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject start/stop/heartbeat/ack wiring, body placement observations, clock and network submission.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/movement-sender.verify.luau --name "echoes the acknowledged body epoch and clears held movement when placement invalidates it"
```

The [executable specification](../src/roblox/movement-sender.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: echoes the acknowledged body epoch and clears held movement when placement invalidates it.

### Invariants

Placement invalidation clears held movement. Acknowledgments reclaim only admitted samples. Invalid authority stops submission.

## roblox-npc-motion

Project bounded planar movement and repair externally displaced bodies.

### State shape

`Point`/`Planar` describe geometry; `Projection` and `Changes` compare cached and observed transforms.

Types and configuration are exported from [src/roblox/npc-motion.luau](../src/roblox/npc-motion.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [npc-motion](../src/roblox/npc-motion.luau) | `anchoredSurfaceY`, `distance`, `groundedPivotY`, `insideLeash`, `moveToward`, `movement`, `plan`, `projection` | `Planar`, `Point`, `Observed`, `Projection`, `Changes` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply epsilon/timing tuning, observed position/facing, grounding and native pivot application.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/npc-motion.verify.luau --name "limits planar movement, preserves elevation and admits the leash edge"
```

The [executable specification](../src/roblox/npc-motion.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: limits planar movement, preserves elevation and admits the leash edge.

### Invariants

Steps cannot overshoot. Elevation is preserved. Leash edges are inclusive and displaced bodies receive corrective projection.

## roblox-party

Apply immutable party membership through an atomic store.

### State shape

`PartyOutcome` and `MountResult` distinguish accepted/readback/refused results over configured membership state.

Types and configuration are exported from [src/roblox/party.luau](../src/roblox/party.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [party](../src/roblox/party.luau) | `mount`, `party` | `StoreOutcome`, `Store`, `Dependencies`, `PartyOutcome`, `Service`, `MountResult`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject the [kernel store port](api.md#kernel-store), key builder, membership reader and
exact schema. The port supplies fresh reads and atomic updates through
the kernel Result envelope. Reads do not invoke an update callback.
Pass the configured membership rules directly; their method ports are read-only.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/party.verify.luau --name "retries pure transforms and refuses old schemas without rewriting them"
```

The [executable specification](../src/roblox/party.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: retries pure transforms and refuses old schemas without rewriting them.

### Invariants

Retried transforms do not leak captured results. Foreign schema and mismatched readback refuse.
Creation and updates compare the complete detached record, including fields beyond its clock.
No-write replays confirm that exact snapshot through the real reader before granting authority.
Known absence comes from a successful fresh read; a speculative callback cannot prove it.

## roblox-professions

Coordinate profession requests with authoritative world/profile commits.

### State shape

`ProfilePort`, `World` and typed payloads describe observed inputs and durable effects.

Types and configuration are exported from [src/roblox/professions.luau](../src/roblox/professions.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [professions](../src/roblox/professions.luau) | `decodeIntent`, `forget`, `handle`, `harvestedSlots`, `interrupt`, `new`, `step` | `Fields`, `CommitResult`, `ProfilePort`, `SkinTarget`, `World`, `WorkKind`, `GatherPayload`, `SkinPayload`, `CraftPayload`, `WorkPayload`, `WorkMetadata`, `GatherEntry`, `SkinEntry`, `CraftEntry`, `WorkEntry`, `RecipeView`, `RecipeItemView`, `ProfessionView`, `ProfessionLesson`, `RecipeLesson`, `SupplyView`, `TrainerBook`, `Book`, `ResultExtras`, `ResultMessage`, `Message`, `Handle`, `CorePort`, `Policy`, `Deps`, `IntentPayload` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject skill/craft/gather rules, profile read/commit, world target/session observations, clock, random samples and dispatch.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/professions/professions.verify.luau --name "admits configured skills and releases recipes without changing the prior snapshot"
```

The [executable specification](../src/core/professions/professions.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: admits configured skills and releases recipes without changing the prior snapshot.

### Invariants

Durable consumption precedes success. Interrupted sessions cannot grant. Replayed node claims do not pay twice.

## roblox-profile-sessions

Own lease admission, coalesced saves, renewal and bounded close.

### State shape

`Owner` binds profile/session identity; outcomes report save/renew/close state.

Types and configuration are exported from [src/roblox/profile-sessions.luau](../src/roblox/profile-sessions.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [profile-sessions](../src/roblox/profile-sessions.luau) | `admit`, `dispose`, `drain`, `isAdmitted`, `new`, `ownedTaskCount`, `requestSave`, `save`, `unload` | `Owner`, `Outcome`, `Dependencies` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject lease operations, profile reads, persistence, scheduling, dirty observation and shutdown budget.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/profile-sessions.verify.luau --name "renews from the current profile and retries failures without releasing ownership"
```

The [executable specification](../src/roblox/profile-sessions.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: renews from the current profile and retries failures without releasing ownership.

### Invariants

Renewal uses the current profile. Failed saves preserve dirty work. Close does not release a foreign lease.

## roblox-profile-transfer

Read and settle profiles under exact session identity and per-key exclusion.

### State shape

`Identity` includes all lease fields; `Outcome`/`Result` and `Reader` preserve observed authority.

Types and configuration are exported from [src/roblox/profile-transfer.luau](../src/roblox/profile-transfer.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [profile-transfer](../src/roblox/profile-transfer.luau) | `exclusive`, `profileFor`, `sameSession`, `settle` | `Identity`, `Outcome`, `Result`, `Reader` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject current identity/profile observations, settled writes and keyed exclusion.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/profile-transfer.verify.luau --name "matches a session only when every lease field agrees"
```

The [executable specification](../src/roblox/profile-transfer.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: matches a session only when every lease field agrees.

### Invariants

Every identity field must agree. A stale session cannot settle a newer profile. Conflicting per-key work remains excluded.

## roblox-quest-durability

Coordinate journal hydration, dirty admission, coalesced saves, lease renewal and close draining.
Import [roblox/quest-durability](../src/roblox/quest-durability.luau), call `configure(config)`,
then `new(dependencies)`. Session snapshots remain generic; a typed projection exposes only existence,
revision and encoded quest progress to the coordinator.

### State shape

Each attached character holds its session/acquisition identity, current lease/session state, opaque
snapshot, committed/pending journal, dirty storage map, retry count, scheduling flags and phase.
Phases are active, stopping, release or fenced. Durable records remain owned by the supplied store ports.

### Operations and required host operations

`attach` acquires and hydrates before accepting writes. `markDirty` validates a journal or current draft;
`markDirtyBatch` prepares every subject before installing any dirty record. `flush` serializes a save,
retains work accepted during the operation and handles renewal/readback uncertainty. `overwriteRecord`
requires a validated full journal. `stopWrites`, `detach` and `drain` stop admission, flush and release.
`isAttached`, `canWrite` and `phase` expose bounded lifecycle observations.

Supply journal and lease rules, lease renewal/release operations, session acquire/save ports, snapshot
projection, clock, store/key functions and owned scheduling. Configure failure limits, lease duration,
renewal/retry cadence, default coalescing delay and fence-loss reasons. Session/store ports must report
settled outcomes and uncertainty; snapshot metadata must describe authoritative readback. Keep storage
codecs, current schema/migrations, namespaces, catalog, numeric/status policy and native lifetime in the game.

The actor accepting an attachment must own its gameplay authority. Ordered reconciliation and dirty
admission consume the authoritative reducer's records. Scheduling callbacks may outlive a detach;
the coordinator guards them against a replacement attachment. The host owns scheduled resource cleanup.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/quest-durability.verify.luau
```

The [fixture](../src/roblox/quest-durability.verify.luau) uses actual Play lease and session rules,
a fake storage host, an alternate snapshot layout, short renewal intervals and a different failure limit.
It exercises draining, atomic batch admission, failure retention, stale callbacks, in-flight updates,
renewal and divergent reacquisition.
The same suite owns coalesced newest-journal saves, asymmetric batch retries, scheduler refusal,
admission retry, exact-holder adoption, long-lived renewal, transient and persistent renewal refusal,
and retryable save/release draining. Adopters retain their configured cadence and failure policy,
status/event encoding, storage namespace and actual yielding session/store integration checks.
The fake session ports do not certify native storage durability or an adopter's record compare-and-swap.

### Invariants

- Identity and current lease ownership fence every save.
- An attachment accepts dirty work only while active and writable.
- Reacquisition refuses a changed snapshot rather than overwriting a newer record.
- A failed save retains dirty work; repeated failures stop further admission while allowing drain.
- Batch preparation cannot partially install dirty records.
- Updates accepted during a save remain pending for a later flush.
- Closing releases only after pending work drains; failed release remains retryable.
- Old callbacks cannot advance a replacement attachment, and metatable payloads are refused.

## roblox-remote-events

Share one dispatcher per channel and release native handlers safely.

### State shape

A transport retains disconnects by channel and release state per registration.

Types and configuration are exported from [src/roblox/remote-events.luau](../src/roblox/remote-events.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [remote-events](../src/roblox/remote-events.luau) | `serve`, `transport` | `Host` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject `Host` register, served count, connect, receive and ownership callbacks.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/remote-events.verify.luau --name "one dispatcher per channel survives partial release and disconnects the last"
```

The [executable specification](../src/roblox/remote-events.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: one dispatcher per channel survives partial release and disconnects the last.

### Invariants

Partial release retains a shared dispatcher. The last handler disconnects it. Repeated release is harmless.

## roblox-screen-labels

Admit anchored labels around reserved screen rectangles.

### State shape

`ScreenRect`, `ScreenPlate` and `ScreenPlacement` hold bounds, priority and admission/collapse results.

Types and configuration are exported from [src/roblox/screen-labels.luau](../src/roblox/screen-labels.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [screen-labels](../src/roblox/screen-labels.luau) | `contains`, `create`, `horizontalAvoidance`, `placementForScreen`, `rect`, `rectsOverlap` | `ScreenRect`, `ScreenPlate`, `ScreenPlacement` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply crowd/range/priority limits, projections, screen/topbar bounds and reserves; render labels in the game.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/screen-labels.verify.luau --name "hides conflicting labels without displacing their anchors"
```

The [executable specification](../src/roblox/screen-labels.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: hides conflicting labels without displacing their anchors.

### Invariants

Conflicting labels collapse without moving anchors. Touching edges are clear. Placement stays within screen bounds.

## roblox-social-fellowship

Compose durable guild records with membership custody, privacy admission, invitations and projections.
Import [roblox/social-fellowship](../src/roblox/social-fellowship.luau) and configure the supplied
home/group policies, TTLs, refresh interval, identifiers and fallback labels. `create` takes dependencies,
a shared social host, member-name lookup, event-id source and notification callback.

### State shape

Durable fellowship and membership shapes come from `core/social/fellowship` and `roblox/social-records`.
The coordinator retains pending invitation routes and reconciled-user observations. Public view types
describe guild members, steward audit, pending invitations and home/creed projections. `BankMembership`
projects the member identities and role needed by a bank binding.

### Operations and host requirements

Operations cover direct founding, inviting/answering, member intents, bank membership, projections,
audiences, notices, steward observations, membership settlement and per-user cleanup.
Supply records, grouping-domain lookup, current clock, optional home catalog and fresh privacy relations.
Use the same group admission/visibility policy as the game and TTLs consistent with its configured
fellowship rules. The supplied social host owns actor exclusion, cache/custody and durable record commits.
Keep names, home/catalog data, identifier namespaces, platform observations and native notices in the game.
Use the separate formation coordinator when founding requires multiple consents or a profile fee.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-fellowship.verify.luau --name "fellowship host"
```

The [executable fixture](../src/roblox/social-fellowship.verify.luau) composes real records,
membership custody, home and privacy rules with neutral identities. It covers domain admission,
durable seats, bank-role projection, privacy refusals, invitation expiry and configurable refresh cadence.

### Invariants

- Membership custody precedes durable founding or acceptance.
- Invitations require fresh privacy admission against the current members.
- Projections use the supplied visibility policy and authoritative member identities.
- Expired invitation routes cannot authorize acceptance.
- Steward observations respect the configured refresh interval.
- Forgetting a user releases coordinator caches and invitation routes.

## roblox-social-formation

Coordinate a multi-founder charter and an idempotent profile fee across durable social records.
Import [roblox/social-formation](../src/roblox/social-formation.luau), configure home/privacy policy,
founder count, fee display and fallback label, then `create` it with the shared social host and ports.

### State shape

Durable formation state tracks founders, invitations, consent, expiry, fee phase and resulting guild.
A proposer pointer connects an interrupted charter with its fee. Public view types describe incoming
invitations, founders, progress and completion availability. The game retains the actual fee ledger,
currency representation, name/home catalog and persisted namespaces.

### Operations and host requirements

`start`, `invite`, `answer`, `complete`, `projection` and `settle` coordinate the lifecycle.
Supply social records, shared membership custody, grouping-domain/name lookup, fresh privacy relations,
event ids, clock, home catalog and notifications. The fee port supplies idempotent hold/commit/refund
operations returning explicit committed/replayed/rejected/uncertain outcomes. The configured founder
count and fee must match the formation rules behind the record port. Bind durable profile effects and
exact session/character authority in the game; callbacks must reconcile receipts after uncertainty.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-fellowship.verify.luau --name "formation host"
```

The [executable fixture](../src/roblox/social-fellowship.verify.luau) uses a two-founder charter
and a seven-unit fee. It verifies completion, membership confirmation, repeated settlement and recovery
across uncertain holds, fee commits, refunds and an unreadable charter-write response.

### Invariants

An orphaned fee hold is refunded and its proposer pointer is durably cleared before an immediate
retry can create a fresh charter. Uncertain refunds or pointer-clear failures keep admission closed.

- A durable proposer pointer precedes the fee hold and charter write.
- Uncertain holds and refunds retain their proposer pointer for reconciliation.
- Privacy admission and current membership precede founder consent.
- All required membership claims precede charter completion.
- Completed guild records and membership confirmation remain recoverable across fee-commit failure.
- Proposer pointers clear only after the relevant fee outcome is confirmed.

## roblox-social-host

Coordinate actor exclusion, social caches and membership settlement.

### State shape

`Membership`, `Response` and `Host` bind observed record and per-actor ownership.

Types and configuration are exported from [src/roblox/social-host.luau](../src/roblox/social-host.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [social-host](../src/roblox/social-host.luau) | `fellowships` | `Membership`, `Response`, `Host` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject durable records/membership readback, claim/commit operations, clock, identity and actor exclusion.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/social-host.verify.luau --name "confirms a claimed membership once the record commits and serves it from cache"
```

The [executable specification](../src/roblox/social-host.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: confirms a claimed membership once the record commits and serves it from cache.

### Invariants

Membership is confirmed only after record commit. Cached identity matches authority. Failed/uncertain settlement retains recovery work.

## roblox-social-notes

Coordinate preset inbox delivery and projections without accepting arbitrary message text.
Import [roblox/social-notes](../src/roblox/social-notes.luau), configure phrase parsing,
expiry projection, label and send interval, then call `create` with inbox and recipient ports.

### State shape

Durable inbox records own note identities, authors, phrase identities, read status and receipt history.
The coordinator caches inboxes and the last send attempt time per subject. Catalog text remains external.

### Operations and required host operations

`recipients` deduplicates group and candidate views. `send` validates the preset, throttle, recipient,
sender name, contact policy and platform filter before delivery. `refresh`, `noticed`, `markRead`,
`projection` and `forget` manage readback, privacy, expiry and session lifetime.
Supply durable inbox operations, clock, names and recipients plus current catalog, contact, filter,
read-privacy and notification ports. A missing filter fails closed. The game owns phrase content,
permissions, storage namespace, native filtering and notifications.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-messaging.verify.luau
```

The [fixture](../src/roblox/social-messaging.verify.luau) uses real note rules and durable inbox
coordination with neutral phrases, a three-second throttle and a fifty-second lifetime.

### Invariants

- Only current catalog phrases reach durable delivery.
- Unknown recipients and refused contact/filter decisions cannot store notes.
- Privacy hides cached inbox contents; expiry removes notes from projections.
- Read acknowledgment changes durable inbox state before cache replacement.
- Forgetting a subject discards its throttle and inbox caches.

## roblox-social-party

Compose durable membership with invitation tracking, projections, reconnect/succession and rally admission.
Import [roblox/social-party](../src/roblox/social-party.luau), call `configure(config)`, then
`create(dependencies, partyPort)`.

### State shape

The supplied party port owns durable member, invite, loot and leadership state.
This coordinator tracks projected memberships, pending invitation routes, rally selections and a
bounded refusal log. Exported view types describe candidates, members, invitations and leadership
transfer. Account ids are opaque strings; subject ids use the Roblox host's numeric identity seam.

### Operations and host requirements

Party commands cover invitations, acceptance/decline, leaving/removal, leadership transfer/disband,
disconnect/reconnect and expiry sweep. `partyProjection`, `candidateProjection` and `partyAudience`
derive server views. `rallyBoard`, `joinRally` and `leaveRally` bind authored objectives through the
supplied rally decoder. `pendingInviteCount` and `projectionRefusals` expose host observations.

`admission(readMembership, partyReadPort, soloId)` builds an authoritative numeric-subject roster
query. Supply a committed membership outcome and party readback plus a game-owned solo identifier.
Missing/failed membership reads refuse; a known ungrouped subject receives a solo roster. A grouped
subject must still appear in the live party record, and every member identity must be a positive integer.

Supply the atomic party port plus membership read/projection, optional full snapshot projection,
candidate rows, grouping-domain lookup, current character identity, display names, clock and rally
selection projection. Configure rally policy, loot mode, TTLs, bounded observations/candidates,
party-id construction, fallback labels and refusal reporting. Keep native subscriptions, actual
names/text, visibility policy, objective catalogs and record/index storage scope in the game.
Use clocks and TTLs consistent with the supplied party rules. Readbacks must reflect actual durable
outcomes; projection refusals are observed rather than treated as successful index writes.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-party.verify.luau
```

The [executable fixture](../src/roblox/social-party.verify.luau) composes real membership,
atomic party and rally systems with neutral identities. It tests candidate admission, durable
membership projection, pending-route cleanup, leadership succession, bounded refusals and rally expiry.

### Invariants

- Invitations target visible candidates in the same configured grouping domain.
- Successful member transitions project current seats and clear displaced seats.
- Pending invitation routes are released on accept, decline, replacement and departure.
- Reconnection uses current character identity and durable membership rules.
- Leadership and invitation deadlines use the supplied clock and matching TTLs.
- Refusal observations stay bounded, and expired objectives cannot admit a new rally selection.
- Admission distinguishes a known solo subject from unavailable membership and refuses mismatched rosters.

## roblox-social-records

Coordinate ordered durable records, ledgers, inboxes and indexes.

### State shape

Typed store outcomes feed fellowship/formation/warband ports, settled ledgers, keyed records and bounded indexes.

Types and configuration are exported from [src/roblox/social-records.luau](../src/roblox/social-records.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [social-records](../src/roblox/social-records.luau) | `add`, `apply`, `create`, `deliver`, `getOutcome`, `inbox`, `index`, `keyed`, `ledger`, `list`, `markRead`, `read`, `remove`, `updateOutcome` | `Outcome`, `Store`, `FellowshipPort`, `FormationPort`, `WarbandPort`, `Dependencies`, `Refusal`, `RecordResult`, `Result`, `FormationResult`, `Status`, `ProposerResult`, `Membership`, `MembershipResult`, `WarbandMembership`, `WarbandMembershipResult`, `LedgerOutcome`, `Settled`, `LedgerCore`, `LedgerDependencies`, `Ledger`, `InboxCore`, `InboxDependencies`, `InboxResult`, `Inbox`, `KeyedOutcome`, `KeyedDependencies`, `Keyed`, `IndexDependencies`, `IndexListing`, `Index`, `Service` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject compare-and-swap/update/read operations, record projectors, clocks, keys and bounds.

Every constructor consumes the [kernel store port](api.md#kernel-store): `read` returns
uncached data and `update` returns committed data through the shared kernel Result envelope.
Bind the native budgeted backend with `roblox/persistence/store.new`.
Membership, formation-pointer, record, ledger and inbox replays use the kernel's complete
readback confirmation before granting authority. Failed or different readback refuses.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/social-records.verify.luau --name "refuses foreign guild and formation identities before applying events"
```

The [executable specification](../src/roblox/social-records.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: refuses foreign guild and formation identities before applying events.

### Invariants

Foreign record identity refuses before applying events. Ordered updates preserve readback identity. Duplicate receipts do not settle twice. Index reservation confirms the caller's complete entry through `same`; a matching identifier with another payload is insufficient, including after a lost write reply.

## roblox-social-warband

Coordinate several intact parties through durable membership records, invitations, orders and rally requests.
Import [roblox/social-warband](../src/roblox/social-warband.luau), configure the rule projections,
limits, request lifetime, rally location, identifiers and display fallback, then call `create(dependencies)`.

### State shape

Durable records own warband units, command, invitations, revisions and per-party membership claims.
The coordinator caches observed records and invitations plus short-lived requests for rally invitations.
Each party retains its own membership, leadership and loot state.

### Operations and host requirements

`act` handles founding, invitations, acceptance, departure, removal, command transfer, orders,
markers and rally requests. `project` reads a subject's current view; `refresh` reconciles cached bands.
Supply durable record operations, party membership/read ports, clock, names, contact permission and
objective validation. Reads and mutation replies must describe committed state; unavailable records
refuse admission. The game owns objective catalogs, location policy, storage namespaces and native notices.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-warband.verify.luau
```

The [fixture](../src/roblox/social-warband.verify.luau) uses real party, warband and record rules with
three independent parties, a seven-second request lifetime and a neutral rally location.

### Invariants

- Only current party leaders mutate a warband.
- Claims precede durable enrollment; confirmation and release reconcile interrupted membership changes.
- Commands use the expected durable revision and current party snapshots.
- Parties retain their membership and loot authority.
- Repeated rally requests do not extend their original expiry or enroll a party.
- Contact and objective permissions govern discovery and invitation requests.

## roblox-social-whispers

Coordinate platform-owned direct-chat channels and session projections.
Import [roblox/social-whispers](../src/roblox/social-whispers.luau), configure a symmetric pair
name and display fallback, then call `create` with realm, channel-open/close and name ports.

### State shape

The coordinator holds symmetric per-subject channel views and a per-pair pending flag. It stores no
message text. Native channels, filtering and communication permissions belong to the host platform.

### Operations and required host operations

`open` admits distinct subjects in the same realm, serializes concurrent opens for the pair and
revalidates both realm identities after the host returns. `projection` provides sorted recipient
views. `close` removes both cached sides and closes native channels, returning affected subjects.
The host must enforce current platform direct-chat permission, create/mark/seat channels, return
refusals and dispose channels when requested. The game owns namespace, display policy and native lifetime.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/social-messaging.verify.luau
```

The [fixture](../src/roblox/social-messaging.verify.luau) checks reentrant open exclusion,
symmetric views/disposal and a realm change during the asynchronous host operation.

### Invariants

- Each pair has at most one in-flight open attempt.
- Presence and the admitted realm are rechecked after channel creation.
- A stale successful open is disposed without adding cached views.
- Pending exclusion is cleared even when the platform callback throws.
- Closing a subject removes its peer views; platform message handling remains external.

## roblox-target-selection

Cycle ordered candidates, select pointer hits and release distant targets.

### State shape

`Candidate<P>` carries stable identity/point; `Release` retains out-of-range timing.

Types and configuration are exported from [src/roblox/target-selection.luau](../src/roblox/target-selection.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [target-selection](../src/roblox/target-selection.luau) | `create`, `observe`, `pickNearestToTap`, `pickNext`, `release`, `reset`, `tapSelection` | `Candidate`, `Release` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply ordered candidates, coordinate reader, hit/radius observations, range and grace duration.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/target-selection.verify.luau --name "cycles, wraps and recovers from an absent selection"
```

The [executable specification](../src/roblox/target-selection.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: cycles, wraps and recovers from an absent selection.

### Invariants

Exact hits win. Equal distances use lexical identities. In-range observations reset release timing; missing points count as outside.

## roblox-thumbstick

Convert touch displacement into dead-zone movement and a bounded knob.

### State shape

`Stick = { anchor, knob, vector }`; each `Vec2` is `{ x, y }`.

Types and configuration are exported from [src/roblox/thumbstick.luau](../src/roblox/thumbstick.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [thumbstick](../src/roblox/thumbstick.luau) | `anchorAt`, `create`, `drag`, `knobFor`, `release`, `vectorFor` | `Vec2`, `Stick` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply radius/dead-zone/screen-zone tuning and observed touch points. The game tracks touches, draws UI and submits movement.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/examples/thumbstick.luau
```

The [complete example](../tools/examples/thumbstick.luau) includes configuration and executable assertions.

### Invariants

Dead-zone input yields zero. Movement magnitude and knob displacement clamp at the radius. Release yields zero movement.

## roblox-trade

Coordinate a durable, revisioned two-profile exchange over injected profile and receipt stores.
Import [roblox/trade](../src/roblox/trade.luau), call `configure(config)`, then `create(dependencies)`.

### State shape

`Account` projects coin, inventory and pending receipt pointers from the game's profile.
`State` extends the pure exchange state with captured character and session identities.
Durable receipts contain both offers, characters, the reviewed revision, decision and grant markers.
The game retains its profile schema, storage namespaces, migration and item policy.

### Operations and host requirements

`intent` admits an authenticated subject's open, offer, lock, confirm or cancel request.
`recover` reconciles a durable decision; `admit` recovers pointers for an arriving character.
`playerRemoving` cancels an active exchange; `sweepExpired` cancels expired offers.
`state` and `stateFor` expose the current exchange view.

Supply pure exchange and receipt codecs, account projection, capacity and unbound-item rules,
profile lookup, related-profile policy and transaction receipt admission. Supply a profile commit
operation which atomically records a transaction with its effect and returns the actual durability
outcome. Repeated transaction identifiers must replay without applying their effect again.

The receipt store's update callback may retry. It must return its committed value, or an uncertain
failure which the coordinator can reconcile by reading. `profileFor` must resolve an active exact
session. Context identities, authenticated subject identity, positions, authorization, identifiers,
clock and optional expiry scheduling come from the host. Positions require finite x, y and z.
Use a clock whose timestamps remain comparable after restart; receipt codecs must admit its range.

### Runnable example

```sh
lute run tools/gate.luau --file src/roblox/trade.verify.luau
```

The [executable fixture](../src/roblox/trade.verify.luau) uses two neutral profile accounts,
an idempotent commit port and a receipt map. It tests conservation, repeated recovery, failed grants,
uncertain receipt writes, unreadable decisions, replacement sessions and expiry.

### Invariants

- Consent applies only to the reviewed offer revision and captured sessions.
- Both holds precede a committed decision; a cancelled decision refunds recorded holds once.
- A committed decision remains recoverable until both grants and pointer cleanup settle.
- Unreadable or malformed decisions never authorize moving either account.
- Profile transaction replay cannot duplicate holds, grants or refunds.
- Game policy, profile projection and native remote lifetime remain outside the coordinator.

## roblox-travel-placement

Find clear, grounded arrival/entrance positions through injected geometry.

### State shape

`PlacementHost`/`EntranceHost` describe candidates and floor evidence; operations return a frame or nil.

Types and configuration are exported from [src/roblox/travel-placement.luau](../src/roblox/travel-placement.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [travel-placement](../src/roblox/travel-placement.luau) | `entrance`, `place` | `PlacementHost`, `EntranceHost` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Inject candidate/point generation, collision clearance, ground/near/far floor queries, safe checks and commit/frame construction.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/roblox/travel-placement.verify.luau --name "occupied arrival selects the first clear supported floor before committing"
```

The [executable specification](../src/roblox/travel-placement.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: occupied arrival selects the first clear supported floor before committing.

### Invariants

Placement commits only a clear supported candidate. Search is bounded. An unsafe or absent floor cannot produce a destination.

## route-admission

Validate route policy, decide outgoing handoffs and admit destination arrivals using pure rules.
Import [identity/routing](../src/core/identity/routing.luau) or `Identity.routing`, then call `create`.
The game supplies realm labels, identifier validators, text limits and fallback refusal policy.

### State shape

`Policy` is a frozen projection of a channel/universe/source binding, destination/place index,
attempt/time budgets, handoff freshness and refusal rows. `Request` contains character identity,
request and currently held session/acquisition/revision, selection/issue/current times, attempt
and an authoritative destination resolution. Decisions carry a route or a structured refusal.
`Arrival` carries the expected channel, universe/place and source/character/destination identities.

### Operations

`projectPolicy` validates and detaches game content into a frozen policy, rejecting duplicate
destinations/places, malformed refusal tables and explicitly unrouted channel bindings. `decide`
validates a request, enforces its binding, attempt budget, clock ordering, deadline and held-session
identity, then verifies its resolver result and bound destination. An absent resolution is classified
using known destination facts such as realm, level and unlock policy. `refuse` creates an approved
refusal, using the configured fallback when its reason or policy is invalid. `accept` checks the
arrival's channel/universe/source/place binding. `boundPlaceIds` projects the destination places.

### Required host operations

None are called by the rules. The host owns current time, held lease/session authority, selection,
destination resolution and actual teleport/recovery. A resolver result must come from the game's
authoritative admission path, including unlock and destination eligibility; client-supplied matching
fields are not proof of admission. Arrival checks establish a binding match, not authentication of a
native carrier or ownership of a character. The game must authenticate that carrier and acquire/fence
the destination lease before admitting a player. Never pass client data as the held-session authority.

Configuration includes pure structural/namespaced identifier validators, the realm-key-to-label map,
identity/refusal/unrouted text limits, unknown request label and invalid-binding refusal. The factory
copies its configuration and realm map. Keep actual destinations, place IDs, player-facing lines,
channel policy, budgets, clock and native lifetime in the game.

### Runnable example

```sh
lute run tools/gate.luau --file src/core/identity/routing.verify.luau
```

The [fixture](../src/core/identity/routing.verify.luau) uses neutral realms, named synthetic place
identities, colon-separated destination IDs, smaller text limits and short budgets. It exercises frozen
projection, routing, exact deadlines, session fencing, refused resolutions, arrival binding and fallback text.

### Invariants

- Unrecognized or malformed policy fails closed with the configured invalid-binding refusal.
- Mutable content cannot alter the projected policy or the factory's realm map.
- A request's channel/universe/source and current held session must match its authority.
- Clock regression, exhausted attempts and late requests cannot produce routes.
- Resolver subject/destination facts must match the captured request and projected catalog.
- Arrival place and source bindings must match the projected policy.
- The pure rules perform no storage, scheduling, discovery or native teleport operations.

## social

Coordinate parties, fellowships, warbands, formation, shared banks, allies, notes and chronicles.

### State shape

Each component exports its own `State`: membership/invites/transfers, formation consent/fee holds, bank receipts, ally history, note delivery and witnessed vows.

Types and configuration are exported from [src/core/social.luau](../src/core/social.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [allies](../src/core/social/allies.luau) | `allies`, `emptyState`, `projectPrivate`, `projectState`, `transition` | `QualificationKind`, `Entry`, `State`, `Policy`, `Result`, `QualifyEvent`, `ReconcileEvent`, `Event`, `Authority`, `Config` |
| [chronicle](../src/core/social/chronicle.luau) | `chronicle`, `emptyState`, `projectChronicle`, `projectState`, `transition` | `ActiveStatus`, `TerminalStatus`, `Definition`, `ActiveVow`, `Deed`, `State`, `Applied`, `Rejected`, `Result`, `AccessPolicy`, `ContributionAuthority`, `Event`, `Config` |
| [fellowship](../src/core/social/fellowship.luau) | `create`, `createFromFormation`, `fellowship`, `projectState`, `transition`, `validCreed` | `Member`, `Invite`, `Creed`, `CreedDraft`, `FormationRequest`, `Event`, `EventDraft`, `Audit`, `State`, `FoundRequest`, `Result`, `Config` |
| [formation](../src/core/social/formation.luau) | `formation`, `projectState`, `start`, `transition` | `Founder`, `State`, `EventDraft`, `Event`, `StartRequest`, `Result`, `Config` |
| [group](../src/core/social/group.luau) | `admit`, `emptyState`, `group`, `projectRelations`, `projectState`, `transition`, `visibleRoster` | `Relations`, `Admission`, `Ticket`, `State`, `Result`, `Decision`, `Request`, `Authority`, `MemberEvent`, `ReconcileEvent`, `Event`, `Config` |
| [guildbank](../src/core/social/guildbank.luau) | `apply`, `emptyState`, `guildbank`, `knowsOperation`, `projectState`, `receiptsFor` | `Receipt`, `Operation`, `Entry`, `Withdrawal`, `Command`, `State`, `Result`, `Config` |
| [guildhome](../src/core/social/guildhome.luau) | `guildhome`, `slotFor`, `slots` | `Slot`, `Config` |
| [guildledger](../src/core/social/guildledger.luau) | `acked`, `beginDeposit`, `canWithdraw`, `claim`, `claimed`, `emptyLedger`, `guildledger`, `projectLedger`, `refund`, `settle` | `Pending`, `Ledger`, `Limits`, `Receipt`, `ProfileInput`, `Config` |
| [membership](../src/core/social/membership.luau) | `accept`, `acceptLeaderTransfer`, `decline`, `disband`, `invite`, `kick`, `leave`, `markAbsent`, `markPresent`, `membership`, `open`, `projectState`, `setLootMode`, `sweep`, `transferLeader` | `LootMode`, `Member`, `Invite`, `LeaderTransfer`, `State`, `Result`, `Config`, `Core` |
| [notes](../src/core/social/notes.luau) | `deliver`, `emptyState`, `live`, `markRead`, `notes`, `phrases`, `projectState` | `Note`, `State`, `Result`, `Phrase`, `Catalog`, `Delivery`, `Config` |
| [profile](../src/core/social/profile.luau) | `default`, `profile`, `project` | `FellowshipIdentity`, `State`, `Config` |
| [rally](../src/core/social/rally.luau) | `project`, `rally` | `Row`, `Config` |
| [roster](../src/core/social/roster.luau) | `reduce`, `roster` | `Member`, `Party`, `Actor`, `Runtime`, `Result`, `Config` |
| [warband](../src/core/social/warband.luau) | `found`, `project`, `read`, `transition`, `warband` | `Party`, `Unit`, `Invite`, `Transfer`, `Order`, `State`, `Event`, `Parties`, `Result`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply realm/capacity/privacy/rank/admission policy, bounds, clocks and pure projectors. Use injected durable records and host settlement for multi-record effects.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/social/allies.verify.luau --name "combines every denial category without mutating the stored allies"
```

The [executable specification](../src/core/social/allies.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: combines every denial category without mutating the stored allies.

### Invariants

Invites reserve capacity and name a recipient. A blocked member cannot be bypassed. Foreign ownership and stale fences refuse; shared goods and receipts retain custody.

Membership owns invitation replay, grouped admission, ordered succession, leader-only authority,
transfer consent and expiry, connected-character tie breaking, absence deadlines and rejoin identity.
Changing leadership preserves the roster, reservations and loot state. Repeated absence and transfer
requests do not extend their deadlines. Games supply capacities, allowed realms, timing and reward policy.
Run these rules directly with neutral policy:

```sh
lute run tools/gate.luau --file src/core/social/membership.verify.luau
```

## threat

Select threat targets and freeze combat contribution eligibility at encounter end.

### State shape

`table.State = { threat: { [string]: number }, targetActorId: string }`; contribution records hold effective credit, presence and an encounter-end character snapshot.

Types and configuration are exported from [src/core/threat.luau](../src/core/threat.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [contribution](../src/core/threat/contribution.luau) | `asParticipant`, `create`, `eligible`, `eligibleAtEnd`, `finish`, `observe`, `record` | `Point`, `DungeonAdmission`, `Relation`, `Observation`, `Credit`, `ActorContribution`, `EndActor`, `Encounter`, `Participant`, `Config` |
| [table](../src/core/threat/table.luau) | `add`, `empty`, `prune`, `remove`, `rules`, `targetFor`, `taunt` | `Config`, `State`, `Candidate`, `Pruned` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply takeover/taunt tuning, eligible/alive/leash/melee observations, categories, radii and deadlines. The host installs state, drives pursuit and persists rewards.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/threat/contribution.verify.luau --name "credits only effective contested actions against an eligible relation"
```

The [executable specification](../src/core/threat/contribution.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: credits only effective contested actions against an eligible relation.

### Invariants

Takeover requires exceeding the threshold. Ties use actor identity. Taunts exceed the current maximum. Encounter-end eligibility cannot change with later movement or replacement.

## trade

Settle mutually confirmed, revisioned offers and retain recovery receipts.

### State shape

`State` holds offers, revision, locks, confirmations and settlement phase. Receipt records/wire maps/pointers retain exact grant identity.

Types and configuration are exported from [src/core/trade.luau](../src/core/trade.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [exchange](../src/core/trade/exchange.luau) | `empty`, `exchange`, `offer`, `settled`, `step` | `Stack`, `Offer`, `Phase`, `State`, `Config` |
| [receipt](../src/core/trade/receipt.luau) | `pointers`, `project`, `receipts`, `wire` | `Record`, `Projected`, `Wire`, `Pointer`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply item/count/coin/user/revision bounds, receipt policy and authoritative identities. The game handles proximity/admission and atomically persists both accounts.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/trade/exchange.verify.luau --name "resets both locks and confirmations whenever an offer changes"
```

The [executable specification](../src/core/trade/exchange.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: resets both locks and confirmations whenever an offer changes.

### Invariants

Offer edits clear both parties' locks and confirmations. Stale revisions refuse. Settlement and grant receipts prevent duplicate application.

## vendors

Buy and sell against configured vendors, finite stock and owner-scoped buyback.

### State shape

`State` contains stock and buyback receipts; `Account` contains inventory/coin; operations return next vendor state, account and decision.

Types and configuration are exported from [src/core/vendors.luau](../src/core/vendors.luau).

### Operations

| Component | Operations | Exported types |
| --- | --- | --- |
| [exchange](../src/core/vendors/exchange.luau) | `buy`, `buyBack`, `buyStock`, `empty`, `sell`, `sellBack`, `validateVendor`, `vendor` | `Inventory`, `Account`, `Ware`, `Vendor`, `Decision`, `Receipt`, `State`, `Config` |

Exact signatures and returned operations are in the [signature appendix](#signature-appendix).

### Required host operations

Supply item admission, prices, inventory arithmetic, capacity, bounds, vendor catalog and time. Persist state and account together; choose owner/vendor buyback keys.

### Runnable example

From the repository root after [tool setup](validation.md#tools):

```sh
lute run tools/gate.luau --file src/core/vendors/exchange.verify.luau --name "purchases and sales exchange coin and holdings without mutating inputs"
```

The [executable specification](../src/core/vendors/exchange.verify.luau) supplies complete configured inputs, fake host
operations where needed and expected results. The gate runs it through Verify; a module load alone is not a test.

This example exercises: purchases and sales exchange coin and holdings without mutating inputs.

### Invariants

A refusal returns both original inputs. Receipt IDs increase within state. Consumed buyback receipts cannot apply twice.

## Area index

The area table links each configured rule family and native adapter. Read only the area that the task needs.

| Area | Reference |
| --- | --- |
| codec | [Contract](#kernel-codec) |
| lease | [Contract](#kernel-lease) |
| result | [Contract](#kernel-result) |
| store | [Contract](#kernel-store) |
| value | [Contract](#kernel-value) |
| bank | [Contract](#bank) |
| cast | [Contract](#cast) |
| character-leases | [Contract](#character-leases) |
| character | [Contract](#character) |
| chat | [Contract](#chat) |
| combat | [Contract](#combat) |
| control | [Contract](#control) |
| craft | [Contract](#craft) |
| effects | [Contract](#effects) |
| events | [Contract](#events) |
| identity | [Contract](#identity) |
| inventory | [Contract](#inventory) |
| ledger | [Contract](#ledger) |
| loot | [Contract](#loot) |
| mail | [Contract](#mail) |
| map | [Contract](#map) |
| market | [Contract](#market) |
| net | [Contract](#net) |
| orders | [Contract](#orders) |
| persistence | [Contract](#persistence) |
| professions | [Contract](#professions) |
| progression | [Contract](#progression) |
| quest | [Contract](#quest) |
| roblox-bank | [Contract](#roblox-bank) |
| roblox-camera | [Contract](#roblox-camera) |
| roblox-cargo | [Contract](#roblox-cargo) |
| roblox-character-admission | [Contract](#roblox-character-admission) |
| roblox-chat | [Contract](#roblox-chat) |
| roblox-consumables | [Contract](#roblox-consumables) |
| roblox-contact-markers | [Contract](#roblox-contact-markers) |
| roblox-conversation-camera | [Contract](#roblox-conversation-camera) |
| roblox-cue-mixer | [Contract](#roblox-cue-mixer) |
| roblox-cue-playback | [Contract](#roblox-cue-playback) |
| roblox-data-store | [Contract](#roblox-data-store) |
| roblox-equipment-queue | [Contract](#roblox-equipment-queue) |
| roblox-equipment-rig | [Contract](#roblox-equipment-rig) |
| roblox-guild-bank | [Contract](#roblox-guild-bank) |
| roblox-input-bindings | [Contract](#roblox-input-bindings) |
| roblox-input-contexts | [Contract](#roblox-input-contexts) |
| roblox-input-profile | [Contract](#roblox-input-profile) |
| roblox-inventory | [Contract](#roblox-inventory) |
| roblox-leased-record-session | [Contract](#roblox-leased-record-session) |
| roblox-mail | [Contract](#roblox-mail) |
| roblox-market-profile-wallet | [Contract](#roblox-market-profile-wallet) |
| roblox-market-settlement | [Contract](#roblox-market-settlement) |
| roblox-market | [Contract](#roblox-market) |
| roblox-material-ledger | [Contract](#roblox-material-ledger) |
| roblox-messaging | [Contract](#roblox-messaging) |
| roblox-movement-intake | [Contract](#roblox-movement-intake) |
| roblox-movement-sender | [Contract](#roblox-movement-sender) |
| roblox-npc-motion | [Contract](#roblox-npc-motion) |
| roblox-party | [Contract](#roblox-party) |
| roblox-professions | [Contract](#roblox-professions) |
| roblox-profile-sessions | [Contract](#roblox-profile-sessions) |
| roblox-profile-transfer | [Contract](#roblox-profile-transfer) |
| roblox-quest-durability | [Contract](#roblox-quest-durability) |
| roblox-remote-events | [Contract](#roblox-remote-events) |
| roblox-screen-labels | [Contract](#roblox-screen-labels) |
| roblox-social-fellowship | [Contract](#roblox-social-fellowship) |
| roblox-social-formation | [Contract](#roblox-social-formation) |
| roblox-social-host | [Contract](#roblox-social-host) |
| roblox-social-notes | [Contract](#roblox-social-notes) |
| roblox-social-party | [Contract](#roblox-social-party) |
| roblox-social-records | [Contract](#roblox-social-records) |
| roblox-social-warband | [Contract](#roblox-social-warband) |
| roblox-social-whispers | [Contract](#roblox-social-whispers) |
| roblox-target-selection | [Contract](#roblox-target-selection) |
| roblox-thumbstick | [Contract](#roblox-thumbstick) |
| roblox-trade | [Contract](#roblox-trade) |
| roblox-travel-placement | [Contract](#roblox-travel-placement) |
| route-admission | [Contract](#route-admission) |
| social | [Contract](#social) |
| threat | [Contract](#threat) |
| trade | [Contract](#trade) |
| vendors | [Contract](#vendors) |
## Signature appendix

Declarations below are generated. Edit the contracts above by hand.
Refresh only this appendix with `lute run tools/generate-api.luau --write`.
The gate checks exact declarations and factory return operations against source.

<details>
<summary>Exact declarations and factory returns</summary>

## `core.bank.vault`

[Source](../src/core/bank/vault.luau)

### `core.bank.vault.Inventory`

```luau
export type Inventory = { [string]: number }
```

### `core.bank.vault.Request`

```luau
export type Request =
	{ kind: "deposit" | "withdraw", itemId: string, count: number, bankerId: string, requestId: string }
```

### `core.bank.vault.State`

```luau
export type State = { items: Inventory, receipts: { [string]: Request }, receiptOrder: { string } }
```

### `core.bank.vault.Config`

```luau
export type Config<T> = {
	maxStack: number,
	maxBagSlots: number,
	maxBankSlots: number,
	maxReceipts: number,
	itemIdLimit: number,
	bankerIdLimit: number,
	requestIdLimit: number,
	readProfile: (T) -> unknown,
	writeProfile: (T, Inventory, State) -> T,
	permanent: (string) -> boolean,
	fits: (T, Inventory, Inventory) -> boolean,
	transfer: (T, Request) -> T,
}
```

### `core.bank.vault.Vault`

```luau
export type Vault<T> = {
	sameRequest: (Request, Request) -> boolean,
	default: () -> State,
	request: (unknown) -> Request?,
	project: (unknown) -> State?,
	apply: (T, unknown) -> (T?, string?),
}
```

### `core.bank.vault.adjust`

```luau
function Bank.adjust(
	inventory: Inventory,
	itemId: string,
	delta: number,
	maxCount: number,
	maxEntries: number
): (Inventory?, string?)
```

### `core.bank.vault.vault`

```luau
function Bank.vault<T>(config: Config<T>): Vault<T>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
sameRequest = function sameRequest(first: Request, second: Request): boolean
default = function default(): State
request = function request(value: unknown): Request?
project = function project(value: unknown): State?
apply = function(profile: T, value: unknown): (T?, string?)
```

## `core.bank`

[Source](../src/core/bank.luau)

```luau
local Vault = require("./bank/vault")
```

### `core.bank.VaultInventory`

```luau
export type VaultInventory = Vault.Inventory
```

### `core.bank.VaultRequest`

```luau
export type VaultRequest = Vault.Request
```

### `core.bank.VaultState`

```luau
export type VaultState = Vault.State
```

### `core.bank.VaultConfig`

```luau
export type VaultConfig<T> = Vault.Config<T>
```

### `core.bank.VaultVault`

```luau
export type VaultVault<T> = Vault.Vault<T>
```

### `core.bank.API`

```luau
export type API = {
	read vault: typeof(Vault),
}
```

### `core.bank.vault`

Exported value; see its declaration in [source](../src/core/bank.luau).

## `core.cast.queue`

[Source](../src/core/cast/queue.luau)

### `core.cast.queue.Config`

```luau
export type Config = { windowSec: number, maxRequeues: number, minRetrySec: number }
```

### `core.cast.queue.Entry`

```luau
export type Entry<T> = { token: number, payload: T, requeues: number, dueAt: number }
```

### `core.cast.queue.State`

```luau
export type State<T> = { nextToken: number, queued: Entry<T>? }
```

### `core.cast.queue.Windows`

```luau
export type Windows = { gcdReadyAt: number, castReadyAt: number, channelReadyAt: number }
```

### `core.cast.queue.cancel`

```luau
function Queue.cancel<T>(state: State<T>, token: number?): State<T>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
nextToken = state.nextToken
```

### `core.cast.queue.empty`

```luau
function Queue.empty<T>(): State<T>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
nextToken = 1
```

### `core.cast.queue.ready`

```luau
function Queue.ready(windows: Windows, now: number): boolean
```

### `core.cast.queue.remaining`

```luau
function Queue.remaining(windows: Windows, now: number): (number, number, number)
```

### `core.cast.queue.rules`

```luau
function Queue.rules(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
shouldQueue = function shouldQueue(reason: string?, remainingSec: number?): boolean
delayFor = function delayFor(remainingSec: number): number
minimumCadenceSec = function(gcdSec: number): number
enqueue = function enqueue<T>(
		state: State<T>,
		payload: T,
		requeues: number,
		reason: string?,
		remainingSec: number?,
		now: number
	): (State<T>, Entry<T>?)
```

### `core.cast.queue.take`

```luau
function Queue.take<T>(state: State<T>, token: number, now: number): (State<T>, Entry<T>?)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
nextToken = state.nextToken
```

### `core.cast.queue.windows`

```luau
function Queue.windows(now: number, gcdSec: number, castSec: number, channelSec: number): Windows
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
gcdReadyAt = now + gcdSec
castReadyAt = now + castSec
channelReadyAt = now + channelSec
```

## `core.cast`

[Source](../src/core/cast.luau)

```luau
local Queue = require("./cast/queue")
```

### `core.cast.QueueConfig`

```luau
export type QueueConfig = Queue.Config
```

### `core.cast.QueueEntry`

```luau
export type QueueEntry<T> = Queue.Entry<T>
```

### `core.cast.QueueState`

```luau
export type QueueState<T> = Queue.State<T>
```

### `core.cast.QueueWindows`

```luau
export type QueueWindows = Queue.Windows
```

### `core.cast.API`

```luau
export type API = {
	read queue: typeof(Queue),
}
```

### `core.cast.queue`

Exported value; see its declaration in [source](../src/core/cast.luau).

## `core.character.respawn-host`

[Source](../src/core/character/respawn-host.luau)

### `core.character.respawn-host.Refresh`

```luau
export type Refresh<C> = { previous: C?, character: C?, invalid: boolean? }
```

### `core.character.respawn-host.Observation`

```luau
export type Observation<C> = {
	characterPresent: boolean,
	engineCharacter: C?,
	liveBody: boolean,
	actorPresent: boolean,
	alive: boolean,
	hp: number?,
	zoneId: string,
}
```

### `core.character.respawn-host.Dependencies`

```luau
export type Dependencies<P, C, H, O, S> = {
	owner: O,
	child: (O) -> O,
	dispose: (O) -> (),
	own: (O, () -> ()) -> (),
	clock: () -> number,
	schedule: (number, () -> ()) -> () -> (),
	spawn: (() -> ()) -> () -> (),
	pollSec: number,
	observe: (O, P, (Observation<C>) -> ()) -> (),
	sample: (P) -> Observation<C>,
	stamp: (P, string) -> boolean,
	record: (P, string) -> (),
	error: (P, unknown) -> (),
	characterChanged: (P) -> (),
	rememberBody: (P) -> (),
	nextPending: (boolean?, boolean, number?, number, boolean) -> number?,
	recordDeath: (P) -> (),
	onCancel: (P, string) -> (),
	onUntrack: (P) -> (),
	canSchedule: (P) -> boolean,
	delaySec: () -> number,
	automatic: (P) -> boolean,
	respawn: (P) -> boolean,
	ready: (P) -> (),
	isNative: (P) -> boolean,
	currentCharacter: (P) -> C?,
	observeCharacter: (O, P, (C?) -> ()) -> (),
	findHumanoid: (C) -> H?,
	waitHumanoid: (C) -> H?,
	prepareHumanoid: (H) -> (),
	observeDeath: (O, H, () -> ()) -> (),
	isDead: (H) -> boolean,
	engineDeath: (P) -> (),
	context: (P) -> S?,
	present: (P) -> boolean,
	refreshPending: (P, boolean) -> (),
}
```

### `core.character.respawn-host.Host`

```luau
export type Host<P, C, O> = {
	pendingAt: { [P]: number },
	watchers: { [P]: O },
	plannedRefresh: { [P]: boolean },
	refreshes: { [P]: Refresh<C> },
	cancelPending: (P, string) -> (),
	schedulePending: (P) -> (),
	reschedule: () -> (),
	track: (P) -> (),
	untrack: (P) -> (),
	refresh: <F>(
		P,
		(() -> boolean) -> (unknown, string?, F?),
		() -> boolean,
		() -> (),
		(F?, () -> boolean) -> ()
	) -> boolean,
	dispose: () -> (),
}
```

### `core.character.respawn-host.completeSpawn`

```luau
function Respawn.completeSpawn<F>(
	spawn: () -> (unknown, string?, F?),
	valid: () -> boolean,
	current: () -> boolean,
	pause: () -> (),
	restore: (F?) -> ()
): (boolean, string?)
```

### `core.character.respawn-host.create`

```luau
function Respawn.create<P, C, H, O, S>(deps: Dependencies<P, C, H, O, S>): Host<P, C, O>
```

## `core.character`

[Source](../src/core/character.luau)

```luau
local RespawnHost = require("./character/respawn-host")
```

### `core.character.RespawnHostRefresh`

```luau
export type RespawnHostRefresh<C> = RespawnHost.Refresh<C>
```

### `core.character.RespawnHostObservation`

```luau
export type RespawnHostObservation<C> = RespawnHost.Observation<C>
```

### `core.character.RespawnHostDependencies`

```luau
export type RespawnHostDependencies<P, C, H, O, S> = RespawnHost.Dependencies<P, C, H, O, S>
```

### `core.character.RespawnHostHost`

```luau
export type RespawnHostHost<P, C, O> = RespawnHost.Host<P, C, O>
```

### `core.character.API`

```luau
export type API = {
	read respawn_host: typeof(RespawnHost),
}
```

### `core.character.respawn_host`

Exported value; see its declaration in [source](../src/core/character.luau).

## `core.chat.channels`

[Source](../src/core/chat/channels.luau)

```luau
local Rate = require("../net/rate-limit")
```

### `core.chat.channels.Member`

```luau
export type Member = {
	id: number,
	realm: unknown,
	party: unknown,
	guild: unknown,
	warband: unknown,
}
```

### `core.chat.channels.Audience`

```luau
export type Audience = "say" | "realm" | "party" | "guild" | "warband" | "whisper"
```

### `core.chat.channels.Rule`

```luau
export type Rule = {
	audience: Audience,
	sameRealm: boolean,
	selfDelivery: boolean,
}
```

### `core.chat.channels.Bucket`

```luau
export type Bucket = Rate.Bucket
```

### `core.chat.channels.Budget`

```luau
export type Budget = Rate.Config
```

### `core.chat.channels.allows`

```luau
function Channels.allows(rule: Rule, speaker: Member, listener: Member, reachable: boolean, pair: { number }?): boolean
```

### `core.chat.channels.consume`

```luau
function Channels.consume(bucket: Bucket?, budget: Budget, now: number, cost: number?): (boolean, Bucket)
```

### `core.chat.channels.pairName`

```luau
function Channels.pairName(prefix: string, first: number, second: number): string
```

### `core.chat.channels.parse`

```luau
function Channels.parse(input: string, commands: { [string]: string }): (string?, string)
```

### `core.chat.channels.trim`

```luau
function Channels.trim<T>(lines: { T }, limit: number): { T }
```

### `core.chat.channels.window`

```luau
function Channels.window<T>(lines: { T }, now: number, duration: number, timeOf: (T) -> number): { T }
```

## `core.chat`

[Source](../src/core/chat.luau)

```luau
local Channels = require("./chat/channels")
```

### `core.chat.ChannelsMember`

```luau
export type ChannelsMember = Channels.Member
```

### `core.chat.ChannelsAudience`

```luau
export type ChannelsAudience = Channels.Audience
```

### `core.chat.ChannelsRule`

```luau
export type ChannelsRule = Channels.Rule
```

### `core.chat.ChannelsBucket`

```luau
export type ChannelsBucket = Channels.Bucket
```

### `core.chat.ChannelsBudget`

```luau
export type ChannelsBudget = Channels.Budget
```

### `core.chat.API`

```luau
export type API = {
	read channels: typeof(Channels),
}
```

### `core.chat.channels`

Exported value; see its declaration in [source](../src/core/chat.luau).

## `core.combat.contact`

[Source](../src/core/combat/contact.luau)

```luau
local Codec = require("../../kernel/codec")
```

```luau
local Result = require("../../kernel/result")
```

```luau
local Value = require("../../kernel/value")
```

### `core.combat.contact.Identity`

```luau
export type Identity = { read id: string, read characterId: string?, read epoch: number?, read contentId: string? }
```

### `core.combat.contact.Plan`

```luau
export type Plan<P> = {
	read source: Identity,
	read target: Identity,
	read equipmentToken: string?,
	read sequence: number,
	read startedTick: number,
	read anticipationSec: number,
	read contactSec: number,
	read recoverySec: number,
	read rangeStuds: number,
	read payload: P,
}
```

### `core.combat.contact.State`

```luau
export type State<P> = {
	read plan: Plan<P>,
	read elapsedSec: number,
	read lastTick: number,
	read contacted: boolean,
	read reserved: boolean,
}
```

### `core.combat.contact.Status`

```luau
export type Status = "waiting" | "contact" | "complete" | "cancelled" | "missed"
```

### `core.combat.contact.Transition`

```luau
export type Transition<P> = { read status: Status, read next: State<P>?, read reason: string? }
```

### `core.combat.contact.Config`

```luau
export type Config<P> = { read copyPayload: (unknown) -> (P?, string?), read epsilon: number, read idLimit: number }
```

### `core.combat.contact.API`

```luau
export type API<P> = {
	read admit: (unknown) -> Result.Result<State<P>>,
	read advance: (unknown, unknown) -> Transition<P>,
	read resolve: (unknown, unknown) -> Transition<P>,
}
```

### `core.combat.contact.configure`

```luau
function configure<P>(config: Config<P>): API<P>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
admit = function admit(raw: unknown): Result.Result<State<P>>
advance = function advance(raw: unknown, observation: unknown): Transition<P>
resolve = function resolve(raw: unknown, observation: unknown): Transition<P>
```

## `core.combat`

[Source](../src/core/combat.luau)

```luau
local Contact = require("./combat/contact")
```

### `core.combat.API`

```luau
export type API = { read contact: typeof(Contact) }
```

### `core.combat.contact`

Exported value; see its declaration in [source](../src/core/combat.luau).

## `core.control.diminishing`

[Source](../src/core/control/diminishing.luau)

### `core.control.diminishing.Bucket`

```luau
export type Bucket = { count: number, windowExpiry: number }
```

### `core.control.diminishing.State`

```luau
export type State = { [string]: Bucket }
```

### `core.control.diminishing.Category`

```luau
export type Category = {
	family: string,
	durationCapSec: number,
	immunityPrice: number,
	immunityMinSec: number,
	immunityMaxSec: number,
}
```

### `core.control.diminishing.Config`

```luau
export type Config = { resetSec: number, multipliers: { number }, categories: { [string]: Category } }
```

### `core.control.diminishing.Step`

```luau
export type Step = "full" | "reduced" | "immune"
```

### `core.control.diminishing.Result`

```luau
export type Result = { dr: State, grantedSec: number, multiplier: number, step: Step, immune: boolean }
```

### `core.control.diminishing.clone`

```luau
function Diminishing.clone(state: State): State
```

### `core.control.diminishing.empty`

```luau
function Diminishing.empty(): State
```

### `core.control.diminishing.rules`

```luau
function Diminishing.rules(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
apply = function apply(state: State, category: string, baseDurationSec: number, nowSec: number): Result
```

## `core.control`

[Source](../src/core/control.luau)

```luau
local Diminishing = require("./control/diminishing")
```

### `core.control.DiminishingBucket`

```luau
export type DiminishingBucket = Diminishing.Bucket
```

### `core.control.DiminishingState`

```luau
export type DiminishingState = Diminishing.State
```

### `core.control.DiminishingCategory`

```luau
export type DiminishingCategory = Diminishing.Category
```

### `core.control.DiminishingConfig`

```luau
export type DiminishingConfig = Diminishing.Config
```

### `core.control.DiminishingStep`

```luau
export type DiminishingStep = Diminishing.Step
```

### `core.control.DiminishingResult`

```luau
export type DiminishingResult = Diminishing.Result
```

### `core.control.API`

```luau
export type API = {
	read diminishing: typeof(Diminishing),
}
```

### `core.control.diminishing`

Exported value; see its declaration in [source](../src/core/control.luau).

## `core.craft.recipes`

[Source](../src/core/craft/recipes.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.craft.recipes.MaterialStack`

```luau
export type MaterialStack = { materialId: string, source: string, quantity: number }
```

### `core.craft.recipes.Recipe`

```luau
export type Recipe = { id: string, rung: string, outputItemId: string, inputs: { MaterialStack } }
```

### `core.craft.recipes.SourceRule`

```luau
export type SourceRule = { min: number?, max: number? }
```

### `core.craft.recipes.Config`

```luau
export type Config = { sources: { [string]: boolean }, rungs: { [string]: { [string]: SourceRule } } }
```

### `core.craft.recipes.Catalog`

```luau
export type Catalog = { projectRecipe: (unknown) -> Recipe? }
```

### `core.craft.recipes.catalog`

```luau
function Recipes.catalog(config: Config): Catalog
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
projectRecipe = function(value: unknown): Recipe?
```

## `core.craft`

[Source](../src/core/craft.luau)

```luau
local Recipes = require("./craft/recipes")
```

### `core.craft.RecipesMaterialStack`

```luau
export type RecipesMaterialStack = Recipes.MaterialStack
```

### `core.craft.RecipesRecipe`

```luau
export type RecipesRecipe = Recipes.Recipe
```

### `core.craft.RecipesSourceRule`

```luau
export type RecipesSourceRule = Recipes.SourceRule
```

### `core.craft.RecipesConfig`

```luau
export type RecipesConfig = Recipes.Config
```

### `core.craft.RecipesCatalog`

```luau
export type RecipesCatalog = Recipes.Catalog
```

### `core.craft.API`

```luau
export type API = {
	read recipes: typeof(Recipes),
}
```

### `core.craft.recipes`

Exported value; see its declaration in [source](../src/core/craft.luau).

## `core.effects.timed`

[Source](../src/core/effects/timed.luau)

### `core.effects.timed.Entry`

```luau
export type Entry = {
	remainingSec: number,
	totalSec: number,
	stacks: number?,
	tickInSec: number?,
}
```

### `core.effects.timed.Application`

```luau
export type Application = {
	durationSec: number,
	stacks: number?,
	stackLimit: number?,
	tickInSec: number?,
}
```

### `core.effects.timed.Refresh`

```luau
export type Refresh = "reset" | "extend" | "keep"
```

### `core.effects.timed.advance`

```luau
function Timed.advance(effect: Entry, dt: number): Entry
```

### `core.effects.timed.advanceTimes`

```luau
function Timed.advanceTimes(remainingSec: number, tickInSec: number?, dt: number): (number, number?)
```

### `core.effects.timed.application`

```luau
function Timed.application(prior: Entry?, application: Application): Entry
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
remainingSec = application.durationSec
totalSec = application.durationSec
stacks = stacks
tickInSec = application.tickInSec
```

### `core.effects.timed.count`

```luau
function Timed.count<A, B>(buffs: { [string]: A }, debuffs: { [string]: B }): number
```

### `core.effects.timed.dispelFirst`

```luau
function Timed.dispelFirst<T>(effects: { T }, matches: (T) -> boolean, copy: (T) -> T): ({ T }, T?)
```

### `core.effects.timed.expired`

```luau
function Timed.expired(effect: Entry, epsilon: number): boolean
```

### `core.effects.timed.refresh`

```luau
function Timed.refresh(effect: Entry, duration: number, mode: Refresh): Entry
```

### `core.effects.timed.remainingFraction`

```luau
function Timed.remainingFraction(endsAt: number, totalSec: number, now: number): number
```

### `core.effects.timed.remainingSec`

```luau
function Timed.remainingSec(endsAt: number, now: number): number
```

## `core.effects`

[Source](../src/core/effects.luau)

```luau
local Timed = require("./effects/timed")
```

### `core.effects.TimedEntry`

```luau
export type TimedEntry = Timed.Entry
```

### `core.effects.TimedApplication`

```luau
export type TimedApplication = Timed.Application
```

### `core.effects.TimedRefresh`

```luau
export type TimedRefresh = Timed.Refresh
```

### `core.effects.API`

```luau
export type API = {
	read timed: typeof(Timed),
}
```

### `core.effects.timed`

Exported value; see its declaration in [source](../src/core/effects.luau).

## `core.events.catalog`

[Source](../src/core/events/catalog.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.events.catalog.Flag`

```luau
export type Flag = string | boolean | number
```

### `core.events.catalog.Rollout`

```luau
export type Rollout = { mode: string, percent: number?, salt: string? }
```

### `core.events.catalog.Schedule`

```luau
export type Schedule = { startUnix: number, endUnix: number }
```

### `core.events.catalog.Event`

```luau
export type Event = {
	id: string,
	title: string,
	realm: string,
	priority: number?,
	schedule: Schedule,
	rollout: Rollout?,
	rewards: { [string]: number }?,
	contentScale: { [string]: { string } },
	flags: { [string]: Flag }?,
}
```

### `core.events.catalog.Catalog`

```luau
export type Catalog = { schemaVersion: number, events: { Event } }
```

### `core.events.catalog.Config`

```luau
export type Config = { schemaVersion: number, contentKeys: { string } }
```

### `core.events.catalog.catalog`

```luau
function System.catalog(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
projectEvent = function projectEvent(value: unknown): (Event?, string?)
validateCatalog = function validateCatalog(value: unknown): (boolean, { string })
SCHEMA_VERSION = config.schemaVersion
```

### `core.events.catalog.finite`

```luau
function finite(value: unknown): number?
```

## `core.events.schedule`

[Source](../src/core/events/schedule.luau)

```luau
local Catalog = require("./catalog")
```

### `core.events.schedule.Event`

```luau
export type Event = Catalog.Event
```

### `core.events.schedule.Catalog`

```luau
export type Catalog = Catalog.Catalog
```

### `core.events.schedule.Context`

```luau
export type Context = {
	nowUnix: number,
	shardId: string?,
	playerId: number?,
	liveConfig: { flags: { [string]: Catalog.Flag }, killSwitches: { [string]: boolean } }?,
}
```

### `core.events.schedule.Effect`

```luau
export type Effect = {
	rewards: { [string]: number },
	flags: { [string]: Catalog.Flag },
	contentScale: { [string]: { string } },
}
```

### `core.events.schedule.Resolution`

```luau
export type Resolution = { events: { Event }, effect: Effect }
```

### `core.events.schedule.Config`

```luau
export type Config = {
	catalog: Catalog,
	schemaVersion: number,
	maxRewardMultiplier: number,
	multiplierKeys: { string },
	bonusKeys: { string },
	contentKeys: { string },
	killSwitch: string,
	enabledFlag: string,
}
```

### `core.events.schedule.schedule`

```luau
function System.schedule(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
resolve = function resolve(supplied: Catalog?, context: Context): Resolution
validateCatalog = function validateCatalog(value: Catalog?): (boolean, { string })
stableBucket = function stableBucket(key: string): number
MAX_REWARD_MULTIPLIER = config.maxRewardMultiplier
SCHEMA_VERSION = config.schemaVersion
```

## `core.events.watch`

[Source](../src/core/events/watch.luau)

```luau
local SocialShape = require("../social/shape")
```

### `core.events.watch.Phase`

```luau
export type Phase = "dormant" | "active" | "succeeded" | "failed" | "recovery"
```

### `core.events.watch.WorkPoint`

```luau
export type WorkPoint = { id: string, actionText: string, position: { x: number, y: number, z: number } }
```

### `core.events.watch.Event`

```luau
export type Event = {
	workPoints: { WorkPoint },
	protectionPlacementIds: { string },
	id: string,
	realmId: string,
	zoneKey: string,
	surfacePoiId: string,
	surfaceName: string,
	questId: string,
	mobId: string,
	arrivalText: string,
	activeText: string,
	successText: string,
	failureText: string,
	rewardId: string,
	durationSec: number,
	recoverySec: number,
	maxParticipants: number,
}
```

### `core.events.watch.State`

```luau
export type State = {
	workDone: { [string]: boolean },
	protectionCount: number,
	lastClockSec: number,
	cycle: number,
	phase: Phase,
	startedAtSec: number?,
	endsAtSec: number?,
	recoversAtSec: number?,
	target: number,
	progress: number,
	participantCount: number,
	participants: { [string]: boolean },
	contributions: { [string]: number },
	contributionEvents: { [string]: string },
	claims: { [string]: string },
}
```

### `core.events.watch.Result`

```luau
export type Result = {
	state: State,
	ok: boolean,
	reason: string?,
	replayed: boolean,
	rewardId: string?,
	rewardTicket: string?,
}
```

### `core.events.watch.Config`

```luau
export type Config = {
	realms: { [string]: boolean },
	workPointCount: number,
	minProtectionPlacements: number,
	protectionTarget: number,
	ticketPrefix: string,
	ordinaryTiers: { [string]: boolean },
}
```

### `core.events.watch.watch`

```luau
function System.watch(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
projectEvent = function PublicWatchCore.projectEvent(value: unknown): Event?
protectionBindingsValid = function PublicWatchCore.protectionBindingsValid(event: Event, placements: unknown, mobs: unknown): boolean
emptyState = function PublicWatchCore.emptyState(): State
sync = function PublicWatchCore.sync(state: State, event: Event, nowSec: number): Result
join = function PublicWatchCore.join(
		state: State,
		event: Event,
		actorId: string,
		actorRealmId: string,
		nowSec: number
	): Result
work = function PublicWatchCore.work(
		state: State,
		event: Event,
		actorId: string,
		realmId: string,
		pointId: string,
		nowSec: number
	): Result
protect = function PublicWatchCore.protect(
		state: State,
		event: Event,
		eventId: string,
		actorIds: { string },
		nowSec: number
	): Result
leave = function PublicWatchCore.leave(state: State, event: Event, actorId: string, nowSec: number): Result
claim = function PublicWatchCore.claim(
		state: State,
		event: Event,
		actorId: string,
		actorRealmId: string,
		nowSec: number
	): Result
```

## `core.events`

[Source](../src/core/events.luau)

```luau
local Catalog = require("./events/catalog")
```

```luau
local Schedule = require("./events/schedule")
```

```luau
local Watch = require("./events/watch")
```

### `core.events.CatalogFlag`

```luau
export type CatalogFlag = Catalog.Flag
```

### `core.events.CatalogRollout`

```luau
export type CatalogRollout = Catalog.Rollout
```

### `core.events.CatalogSchedule`

```luau
export type CatalogSchedule = Catalog.Schedule
```

### `core.events.CatalogEvent`

```luau
export type CatalogEvent = Catalog.Event
```

### `core.events.CatalogCatalog`

```luau
export type CatalogCatalog = Catalog.Catalog
```

### `core.events.CatalogConfig`

```luau
export type CatalogConfig = Catalog.Config
```

### `core.events.ScheduleEvent`

```luau
export type ScheduleEvent = Schedule.Event
```

### `core.events.ScheduleCatalog`

```luau
export type ScheduleCatalog = Schedule.Catalog
```

### `core.events.ScheduleContext`

```luau
export type ScheduleContext = Schedule.Context
```

### `core.events.ScheduleEffect`

```luau
export type ScheduleEffect = Schedule.Effect
```

### `core.events.ScheduleResolution`

```luau
export type ScheduleResolution = Schedule.Resolution
```

### `core.events.ScheduleConfig`

```luau
export type ScheduleConfig = Schedule.Config
```

### `core.events.WatchPhase`

```luau
export type WatchPhase = Watch.Phase
```

### `core.events.WatchWorkPoint`

```luau
export type WatchWorkPoint = Watch.WorkPoint
```

### `core.events.WatchEvent`

```luau
export type WatchEvent = Watch.Event
```

### `core.events.WatchState`

```luau
export type WatchState = Watch.State
```

### `core.events.WatchResult`

```luau
export type WatchResult = Watch.Result
```

### `core.events.WatchConfig`

```luau
export type WatchConfig = Watch.Config
```

### `core.events.API`

```luau
export type API = {
	read catalog: typeof(Catalog),
	read schedule: typeof(Schedule),
	read watch: typeof(Watch),
}
```

### `core.events.catalog`

Exported value; see its declaration in [source](../src/core/events.luau).

### `core.events.schedule`

Exported value; see its declaration in [source](../src/core/events.luau).

### `core.events.watch`

Exported value; see its declaration in [source](../src/core/events.luau).

## `core.identity.account-lease`

[Source](../src/core/identity/account-lease.luau)

```luau
local Codec = require("../../kernel/codec")
```

```luau
local Kernel = require("../../kernel/lease")
```

```luau
local Result = require("../../kernel/result")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.account-lease.Lease`

```luau
export type Lease = {
	schemaVersion: number,
	userId: number,
	revision: number,
	fence: number,
	sessionId: string | false,
	acquisitionId: string | false,
	expiresAtUnix: number,
}
```

### `core.identity.account-lease.MAX_FENCE`

Exported value; see its declaration in [source](../src/core/identity/account-lease.luau).

### `core.identity.account-lease.MAX_ID_BYTES`

Exported value; see its declaration in [source](../src/core/identity/account-lease.luau).

### `core.identity.account-lease.MAX_REVISION`

Exported value; see its declaration in [source](../src/core/identity/account-lease.luau).

### `core.identity.account-lease.MAX_SAFE_INTEGER`

Exported value; see its declaration in [source](../src/core/identity/account-lease.luau).

### `core.identity.account-lease.SCHEMA_VERSION`

Exported value; see its declaration in [source](../src/core/identity/account-lease.luau).

### `core.identity.account-lease.acquire`

```luau
function Record.acquire(
	currentRaw: unknown,
	userIdValue: unknown,
	sessionIdValue: unknown,
	acquisitionIdValue: unknown,
	nowValue: unknown,
	ttlValue: unknown
): (Lease?, string)
```

### `core.identity.account-lease.copy`

```luau
function Record.copy(raw: unknown): Lease?
```

### `core.identity.account-lease.empty`

```luau
function Record.empty(userId: unknown): Lease?
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
schemaVersion = Record.SCHEMA_VERSION
userId = userId
revision = 0
fence = 0
sessionId = false
acquisitionId = false
expiresAtUnix = 0
```

### `core.identity.account-lease.equal`

```luau
function Record.equal(leftRaw: unknown, rightRaw: unknown): boolean
```

### `core.identity.account-lease.release`

```luau
function Record.release(
	currentRaw: unknown,
	userIdValue: unknown,
	sessionIdValue: unknown,
	acquisitionIdValue: unknown,
	expectedRevisionValue: unknown,
	expectedFenceValue: unknown
): (Lease?, string)
```

### `core.identity.account-lease.renew`

```luau
function Record.renew(
	currentRaw: unknown,
	userIdValue: unknown,
	sessionIdValue: unknown,
	acquisitionIdValue: unknown,
	expectedRevisionValue: unknown,
	expectedFenceValue: unknown,
	nowValue: unknown,
	ttlValue: unknown
): (Lease?, string)
```

### `core.identity.account-lease.validate`

```luau
function Record.validate(raw: unknown): Lease?
```

## `core.identity.account`

[Source](../src/core/identity/account.luau)

```luau
local Codec = require("../../kernel/codec")
```

```luau
local Shape = require("../social/shape")
```

```luau
local Creation = require("./creation")
```

```luau
local CreationRecord = require("./creation-record")
```

```luau
local Deletion = require("./deletion")
```

```luau
local HasMetatable = require("../../kernel/value")
```

```luau
local Roster = require("./roster")
```

### `core.identity.account.DeletionState`

```luau
export type DeletionState = Deletion.State
```

### `core.identity.account.Base`

```luau
export type Base = {
	schemaVersion: number,
	userId: number,
	revision: number,
	roster: RosterState,
	profiles: { Seed },
	pendingProfile: Seed | false,
	activeCreation: CreationState | false,
	activeDeletion: DeletionState | false,
	receipts: { Receipt },
}
```

### `core.identity.account.CreationReceipt`

```luau
export type CreationReceipt = {
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	receipt: Receipt,
}
```

### `core.identity.account.Account`

```luau
export type Account<E> = Base & E
```

### `core.identity.account.Extension`

```luau
export type Extension<E> = {
	read fields: { read [string]: boolean },
	read project: (Base, unknown, DeletionState?) -> Account<E>?,
}
```

```luau
local Policy = require("./policy")
```

### `core.identity.account.create`

```luau
function create<E>(policy: Policy.Policy, extension: Extension<E>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
transition = function Aggregate.transition(raw: unknown, nextRaw: unknown): (State?, string?)
transitionDeletion = function Aggregate.transitionDeletion(raw: unknown, nextRaw: unknown): (State?, string?)
clearDeletionTerminal = function Aggregate.clearDeletionTerminal(raw: unknown): (State?, string?)
validate = function Aggregate.validate(candidate: unknown): State?
validateStored = function Aggregate.validateStored(candidate: unknown): State?
copy = function Aggregate.copy(raw: unknown): State?
clearTerminal = function Aggregate.clearTerminal(raw: unknown): (State?, string?)
removeCharacter = function Aggregate.removeCharacter(raw: unknown, characterId: unknown): (State?, string?)
markCharacterLevel = function Aggregate.markCharacterLevel(raw: unknown, characterId: unknown, level: unknown): (State?, string?)
markCharacterDeparted = function Aggregate.markCharacterDeparted(
		raw: unknown,
		characterId: unknown,
		destinationId: unknown
	): (State?, string?)
markCharacterPlayed = function Aggregate.markCharacterPlayed(raw: unknown, characterId: unknown, playedAtUnix: unknown): (State?, string?)
characterCard = function Aggregate.characterCard(raw: unknown, characterId: unknown): RosterCharacter?
receiptFor = function Aggregate.receiptFor(raw: unknown, candidate: unknown): CreationReceipt?
equal = function Aggregate.equal(leftRaw: unknown, rightRaw: unknown): boolean
equalStored = function Aggregate.equalStored(leftRaw: unknown, rightRaw: unknown): boolean
empty = function Aggregate.empty(userId: unknown): State?
```

## `core.identity.character-lease-store`

[Source](../src/core/identity/character-lease-store.luau)

```luau
local Atomic = require("../../kernel/store")
```

```luau
local CharacterLease = require("./character-lease")
```

```luau
local Kernel = require("../../kernel/lease")
```

```luau
local Result = require("../../kernel/result")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.character-lease-store.StoreOutcome`

```luau
export type StoreOutcome = Result.Result<Atomic.Readback>
```

### `core.identity.character-lease-store.Store`

```luau
export type Store = Atomic.Port
```

### `core.identity.character-lease-store.Accepted`

```luau
export type Accepted = { ok: true, value: Lease, reason: string?, takeoverPrior: Lease? }
```

### `core.identity.character-lease-store.Refused`

```luau
export type Refused = { ok: false, value: nil, reason: string, takeoverPrior: Lease? }
```

### `core.identity.character-lease-store.Outcome`

```luau
export type Outcome = Accepted | Refused
```

### `core.identity.character-lease-store.Config`

```luau
export type Config = {
	read record: CharacterLease.API,
	read identityLimit: number,
	read zoneIdLimit: number,
}
```

### `core.identity.character-lease-store.API`

```luau
export type API = {
	read acquire: (
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		now: number,
		ttl: number,
		sessionLive: ((string) -> boolean)?,
		lapsedLive: ((string) -> boolean)?,
		zoneId: string?
	) -> Outcome,
	read renew: (
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		expectedRevision: number,
		now: number,
		ttl: number
	) -> Outcome,
	read release: (
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		expectedRevision: number
	) -> Outcome,
	read retire: (store: Store, keyForCharacter: (string) -> string, rawWitness: unknown) -> Outcome,
	read restore: (store: Store, keyForCharacter: (string) -> string, rawWitness: unknown) -> Outcome,
	read arrive: (store: Store, keyForCharacter: (string) -> string, rawClaim: unknown) -> Outcome,
}
```

### `core.identity.character-lease-store.create`

```luau
function create(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
acquire = function Repository.acquire(
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		now: number,
		ttl: number,
		sessionLive: ((string) -> boolean)?,
		lapsedLive: ((string) -> boolean)?,
		zoneId: string?
	): Outcome
renew = function Repository.renew(
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		expectedRevision: number,
		now: number,
		ttl: number
	): Outcome
release = function Repository.release(
		store: Store,
		keyForCharacter: (string) -> string,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		expectedRevision: number
	): Outcome
retire = function Repository.retire(store: Store, keyForCharacter: (string) -> string, rawWitness: unknown): Outcome
restore = function Repository.restore(store: Store, keyForCharacter: (string) -> string, rawWitness: unknown): Outcome
arrive = function Repository.arrive(store: Store, keyForCharacter: (string) -> string, rawClaim: unknown): Outcome
```

## `core.identity.character-lease`

[Source](../src/core/identity/character-lease.luau)

```luau
local Codec = require("../../kernel/codec")
```

```luau
local Kernel = require("../../kernel/lease")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.character-lease.Record`

```luau
export type Record = CharacterLeaseRecord
```

### `core.identity.character-lease.Retirement`

```luau
export type Retirement = {
	operationId: string,
	fingerprint: string,
	fence: number,
	retiredAtUnix: number,
}
```

### `core.identity.character-lease.Arrival`

```luau
export type Arrival = {
	sessionId: string,
	acquisitionId: string,
	fence: number,
	arrivedAtUnix: number,
}
```

### `core.identity.character-lease.CharacterLeaseRecord`

```luau
export type CharacterLeaseRecord = {
	schemaVersion: number,
	revision: number,
	characterId: string,
	zoneId: string?,
	sessionId: string?,
	acquisitionId: string?,
	expiresAt: number,
	retirement: Retirement | false,
	arrival: Arrival | false,
}
```

### `core.identity.character-lease.Witness`

```luau
export type Witness = {
	characterId: string,
	operationId: string,
	fingerprint: string,
	fence: number,
	atUnix: number,
}
```

### `core.identity.character-lease.Claim`

```luau
export type Claim = {
	characterId: string,
	sessionId: string,
	acquisitionId: string,
	revision: number,
	fence: number,
	atUnix: number,
}
```

### `core.identity.character-lease.Config`

```luau
export type Config = {
	read schemaVersion: number,
	read maxRevision: number,
	read maxTime: number,
	read maxFence: number,
	read characterIdLimit: number,
	read zoneIdLimit: number,
	read sessionIdLimit: number,
	read acquisitionIdLimit: number,
	read operationIdLimit: number,
	read fingerprintLimit: number,
	read migrate: (unknown) -> unknown,
}
```

### `core.identity.character-lease.API`

```luau
export type API = {
	read SCHEMA_VERSION: number,
	read MAX_REVISION: number,
	read MAX_TIME: number,
	read MAX_FENCE: number,
	read retirementOf: (record: CharacterLeaseRecord) -> Retirement?,
	read arrivalOf: (record: CharacterLeaseRecord) -> Arrival?,
	read copy: (stored: unknown) -> (CharacterLeaseRecord?, string?),
	read create: (characterId: string) -> (CharacterLeaseRecord?, string?),
	read equal: (left: unknown, right: unknown) -> boolean,
	read witness: (raw: unknown) -> (Witness?, string?),
	read claim: (raw: unknown) -> (Claim?, string?),
	read retire: (raw: unknown, rawWitness: unknown) -> (CharacterLeaseRecord?, string),
	read restore: (raw: unknown, rawWitness: unknown) -> (CharacterLeaseRecord?, string),
	read arrive: (raw: unknown, rawClaim: unknown) -> (CharacterLeaseRecord?, string),
	read retired: (raw: unknown) -> boolean,
}
```

### `core.identity.character-lease.create`

```luau
function create(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
retirementOf = function Record.retirementOf(record: CharacterLeaseRecord): Retirement?
arrivalOf = function Record.arrivalOf(record: CharacterLeaseRecord): Arrival?
copy = function Record.copy(stored: unknown): (CharacterLeaseRecord?, string?)
create = function Record.create(characterId: string): (CharacterLeaseRecord?, string?)
equal = function Record.equal(left: unknown, right: unknown): boolean
witness = function Record.witness(raw: unknown): (Witness?, string?)
claim = function Record.claim(raw: unknown): (Claim?, string?)
retire = function Record.retire(raw: unknown, rawWitness: unknown): (CharacterLeaseRecord?, string)
restore = function Record.restore(raw: unknown, rawWitness: unknown): (CharacterLeaseRecord?, string)
arrive = function Record.arrive(raw: unknown, rawClaim: unknown): (CharacterLeaseRecord?, string)
retired = function Record.retired(raw: unknown): boolean
```

## `core.identity.creation-record`

[Source](../src/core/identity/creation-record.luau)

```luau
local Creation = require("./creation")
```

```luau
local HasMetatable = require("../../kernel/value")
```

```luau
local Policy = require("./policy")
```

```luau
local Roster = require("./roster")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.creation-record.Seed`

```luau
export type Seed = {
	schemaVersion: number,
	userId: number,
	operationId: string,
	fingerprint: string,
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	createdAtUnix: number,
	preparedRevision: number,
	fence: number,
	leaseRevision: number,
}
```

### `core.identity.creation-record.Receipt`

```luau
export type Receipt = {
	schemaVersion: number,
	userId: number,
	operationId: string,
	fingerprint: string,
	characterId: string,
	committedRevision: number,
	fence: number,
	leaseRevision: number,
}
```

### `core.identity.creation-record.create`

```luau
function create(policy: Policy.Policy)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
validate = function Record.validate(candidate: unknown): Seed?
validateStored = function Record.validateStored(candidate: unknown): Seed?
copy = function Record.copy(raw: unknown): Seed?
fromTransaction = function Record.fromTransaction(raw: unknown): Seed?
validateReceipt = function Record.validateReceipt(candidate: unknown): Receipt?
copyReceipt = function Record.copyReceipt(raw: unknown): Receipt?
receiptFromTransaction = function Record.receiptFromTransaction(raw: unknown): Receipt?
receiptMatchesSeed = function Record.receiptMatchesSeed(receiptRaw: unknown, seedRaw: unknown, stored: boolean?): boolean
matchesTransaction = function Record.matchesTransaction(seedRaw: unknown, candidate: unknown, stored: boolean?): boolean
seedMatchesReceipt = function Record.seedMatchesReceipt(seedRaw: unknown, receiptRaw: unknown): boolean
```

## `core.identity.creation`

[Source](../src/core/identity/creation.luau)

```luau
local Codec = require("../../kernel/codec")
```

```luau
local NameRegistry = require("./name-claims")
```

```luau
local Policy = require("./policy")
```

```luau
local Roster = require("./roster")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.creation.Completion`

```luau
export type Completion = {
	[string]: unknown,
	expectedRevision: number,
	expectedFence: number,
	fence: number?,
	leaseRevision: number?,
}
```

### `core.identity.creation.Receipt`

```luau
export type Receipt = {
	[string]: unknown,
	operationId: string,
	fingerprint: string,
	characterId: string,
	revision: number,
	fence: number,
	leaseRevision: number?,
}
```

### `core.identity.creation.Phase`

```luau
export type Phase =
	"prepared"
	| "name_owned"
	| "profile_prepared"
	| "committed"
	| "lease_released"
	| "rolling_back"
	| "aborted"
```

### `core.identity.creation.State`

```luau
export type State = {
	schemaVersion: number,
	userId: number,
	operationId: string,
	fingerprint: string,
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	createdAtUnix: number,
	phase: Phase,
	revision: number,
	fence: number,
	leaseRevision: number,
	initialFence: number,
	initialLeaseRevision: number,
	rollbackNeedsNameRelease: boolean,
}
```

### `core.identity.creation.Prepared`

```luau
export type Prepared = {
	userId: number,
	operationId: string,
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	createdAtUnix: number,
	fence: number,
	leaseRevision: number,
}
```

### `core.identity.creation.Rejected`

```luau
export type Rejected = { ok: false, state: State?, reason: string }
```

### `core.identity.creation.Accepted`

```luau
export type Accepted = { ok: true, state: State, replayed: boolean, reason: nil }
```

### `core.identity.creation.Result`

```luau
export type Result = Rejected | Accepted
```

### `core.identity.creation.Plan`

```luau
export type Plan = {
	expectedRevision: number,
	expectedFence: number,
	kind: string,
	claim: NameClaim?,
	character: RosterCharacter?,
}
```

### `core.identity.creation.create`

```luau
function create(policy: Policy.Policy)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
prepare = function prepare(existing: unknown, request: unknown): Result
plan = function plan(raw: unknown): Plan?
observeName = function observeName(raw: unknown, candidate: unknown): Result
observeProfile = function observeProfile(raw: unknown, candidate: unknown): Result
observeRoster = function observeRoster(raw: unknown, candidate: unknown): Result
requestRollback = function requestRollback(raw: unknown, candidate: unknown): Result
observeRollback = function observeRollback(raw: unknown, candidate: unknown): Result
observeLeaseRelease = function observeLeaseRelease(raw: unknown, candidate: unknown): Result
takeover = function takeover(raw: unknown, candidate: unknown): Result
validate = function(candidate: unknown): State?
validateStored = function(candidate: unknown): State?
fingerprint = function fingerprint(candidate: unknown): string?
copy = function copy(state: State): State
SCHEMA_VERSION = SCHEMA_VERSION
MAX_REVISION = MAX_REVISION
MAX_FENCE = MAX_FENCE
MAX_SAFE_INTEGER = MAX_SAFE_INTEGER
```

## `core.identity.deletion`

[Source](../src/core/identity/deletion.luau)

```luau
local Codec = require("../../kernel/codec")
```

```luau
local NameRegistry = require("./name-claims")
```

```luau
local Policy = require("./policy")
```

```luau
local Roster = require("./roster")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.deletion.Phase`

```luau
export type Phase = "prepared" | "roster_removed" | "name_released" | "lease_released" | "rolling_back" | "aborted"
```

### `core.identity.deletion.State`

```luau
export type State = {
	schemaVersion: number,
	userId: number,
	operationId: string,
	fingerprint: string,
	characterId: string,
	displayName: string,
	requestedAtUnix: number,
	phase: Phase,
	revision: number,
	fence: number,
	leaseRevision: number,
	initialFence: number,
	initialLeaseRevision: number,
}
```

### `core.identity.deletion.Prepared`

```luau
export type Prepared = {
	userId: number,
	operationId: string,
	characterId: string,
	displayName: string,
	requestedAtUnix: number,
	fence: number,
	leaseRevision: number,
}
```

### `core.identity.deletion.Rejected`

```luau
export type Rejected = { ok: false, state: State?, reason: string }
```

### `core.identity.deletion.Accepted`

```luau
export type Accepted = { ok: true, state: State, replayed: boolean, reason: nil }
```

### `core.identity.deletion.Result`

```luau
export type Result = Rejected | Accepted
```

### `core.identity.deletion.Plan`

```luau
export type Plan = {
	expectedRevision: number,
	expectedFence: number,
	kind: string,
	characterId: string?,
	release: { displayName: string, userId: number, characterId: string }?,
}
```

### `core.identity.deletion.create`

```luau
function create(policy: Policy.Policy)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
prepare = function prepare(existing: unknown, request: unknown): Result
plan = function plan(raw: unknown): Plan?
observeRoster = function observeRoster(raw: unknown, candidate: unknown): Result
observeNameRelease = function observeNameRelease(raw: unknown, candidate: unknown): Result
observeLeaseRelease = function observeLeaseRelease(raw: unknown, candidate: unknown): Result
requestRollback = function requestRollback(raw: unknown, candidate: unknown): Result
observeRollback = function observeRollback(raw: unknown, candidate: unknown): Result
takeover = function takeover(raw: unknown, candidate: unknown): Result
validate = function validate(candidate: unknown): State?
fingerprint = function fingerprint(candidate: unknown): string?
copy = function copy(state: State): State
SCHEMA_VERSION = SCHEMA_VERSION
MAX_REVISION = MAX_REVISION
MAX_FENCE = MAX_FENCE
MAX_SAFE_INTEGER = MAX_SAFE_INTEGER
```

## `core.identity.name-claims`

[Source](../src/core/identity/name-claims.luau)

```luau
local Policy = require("./policy")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.name-claims.Claim`

```luau
export type Claim = {
	displayName: string,
	userId: number,
	characterId: string,
	claimedAtUnix: number,
	schemaVersion: number,
}
```

### `core.identity.name-claims.ClaimStatus`

```luau
export type ClaimStatus = "claimed" | "owned" | "taken"
```

### `core.identity.name-claims.ReleaseStatus`

```luau
export type ReleaseStatus = "released" | "absent" | "mismatch"
```

### `core.identity.name-claims.Availability`

```luau
export type Availability = "available" | "owned" | "taken"
```

### `core.identity.name-claims.create`

```luau
function create(policy: Policy.Policy)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
validate = function validate(candidate: unknown): Claim
claim = function claim(current: unknown, requested: unknown): (Claim, ClaimStatus)
release = function release(current: unknown, userId: unknown, characterId: unknown): (Claim?, ReleaseStatus)
availability = function availability(current: unknown, userId: unknown, characterId: unknown): Availability
SCHEMA_VERSION = SCHEMA_VERSION
```

## `core.identity.name-record`

[Source](../src/core/identity/name-record.luau)

```luau
local Policy = require("./policy")
```

```luau
local Registry = require("./name-claims")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.name-record.Record`

```luau
export type Record = NameRecord
```

### `core.identity.name-record.Claim`

```luau
export type Claim = Registry.Claim
```

### `core.identity.name-record.create`

```luau
function create(policy: Policy.Policy)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
validate = function Record.validate(raw: unknown): NameRecord?
copy = function Record.copy(raw: unknown): NameRecord?
empty = function Record.empty(displayNameRaw: unknown): NameRecord?
equal = function Record.equal(leftRaw: unknown, rightRaw: unknown): boolean
claim = function Record.claim(currentRaw: unknown, requestedRaw: unknown): (NameRecord?, string)
release = function Record.release(
		currentRaw: unknown,
		displayNameRaw: unknown,
		userId: unknown,
		characterId: unknown
	): (NameRecord?, string)
availability = function Record.availability(
		currentRaw: unknown,
		displayNameRaw: unknown,
		userId: unknown,
		characterId: unknown
	): string
```

## `core.identity.policy`

[Source](../src/core/identity/policy.luau)

### `core.identity.policy.Policy`

```luau
export type Policy = {
	read validateName: (unknown) -> (boolean, string?, string?),
	read registryKey: (unknown) -> (string?, string?),
	read validRegistryKey: (unknown) -> boolean,
	read validDestination: (unknown) -> boolean,
	read profilePartitionKey: (unknown, unknown) -> string,
	read realms: { [string]: boolean },
	read peoples: { [string]: boolean },
	read accountLimit: number,
	read realmLimit: number,
	read minLevel: number,
	read maxLevel: number,
}
```

## `core.identity.retirement`

[Source](../src/core/identity/retirement.luau)

```luau
local Shape = require("../internal/shape")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.retirement.Deletion`

```luau
export type Deletion = { characterId: string, phase: string, fence: number }
```

### `core.identity.retirement.Retirement`

```luau
export type Retirement = { operationId: string, fingerprint: string, fence: number }
```

### `core.identity.retirement.View`

```luau
export type View = {
	characterId: string,
	rosterHolds: boolean,
	deletion: Deletion | false,
	retirement: Retirement | false,
}
```

### `core.identity.retirement.Decision`

```luau
export type Decision = { action: string, reason: string }
```

### `core.identity.retirement.Config`

```luau
export type Config = {
	read maxFence: number,
	read characterIdLimit: number,
	read operationIdLimit: number,
	read fingerprintLimit: number,
	read phaseLimit: number,
	read retiringPhases: { [string]: boolean },
	read restoringPhases: { [string]: boolean },
}
```

### `core.identity.retirement.API`

```luau
export type API = {
	read MAX_FENCE: number,
	read view: (raw: unknown) -> (View?, string?),
	read decide: (raw: unknown) -> Decision,
}
```

### `core.identity.retirement.create`

```luau
function create(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
view = function Plan.view(raw: unknown): (View?, string?)
decide = function Plan.decide(raw: unknown): Decision
```

## `core.identity.roster`

[Source](../src/core/identity/roster.luau)

```luau
local Policy = require("./policy")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.roster.CharacterIdentity`

```luau
export type CharacterIdentity = {
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	createdAtUnix: number,
	lastPlayedAtUnix: number,
	level: number,
	lastDestinationId: string | false,
}
```

### `core.identity.roster.Roster`

```luau
export type Roster = {
	schemaVersion: number,
	userId: number,
	characters: { CharacterIdentity },
}
```

### `core.identity.roster.create`

```luau
function create(policy: Policy.Policy)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
validate = function(candidate: unknown): Roster
validateStored = function(candidate: unknown): Roster
add = function add(roster: unknown, character: unknown): Roster
remove = function(roster: unknown, characterId: unknown): (Roster, CharacterIdentity)
removeStored = function(roster: unknown, characterId: unknown): (Roster, CharacterIdentity)
markPlayed = function markPlayed(roster: unknown, characterId: unknown, playedAtUnix: unknown): Roster
markLevel = function markLevel(roster: unknown, characterId: unknown, level: unknown): Roster
markDeparted = function markDeparted(roster: unknown, characterId: unknown, destinationId: unknown): Roster
realmCards = function realmCards(roster: unknown, realmId: unknown): { CharacterIdentity }
profilePartitionKey = profilePartitionKey
SCHEMA_VERSION = SCHEMA_VERSION
ACCOUNT_LIMIT = ACCOUNT_LIMIT
REALM_LIMIT = REALM_LIMIT
MIN_LEVEL = MIN_LEVEL
MAX_LEVEL = MAX_LEVEL
NEVER_DEPARTED = NEVER_DEPARTED
REALMS = REALMS
```

## `core.identity.routing`

[Source](../src/core/identity/routing.luau)

```luau
local Shape = require("../social/shape")
```

```luau
local Value = require("../../kernel/value")
```

### `core.identity.routing.DestinationProjection`

```luau
export type DestinationProjection = {
	read id: string,
	read zoneId: string,
	read realm: string,
	read isStarter: boolean,
	read requiresUnlock: boolean,
	read unlockId: string,
	read minLevel: number,
}
```

### `core.identity.routing.PlaceBinding`

```luau
export type PlaceBinding = {
	read destinationId: string,
	read placeId: number,
}
```

### `core.identity.routing.Binding`

```luau
export type Binding = {
	read channel: string,
	read universeId: number,
	read sourcePlaceId: number,
	read places: { PlaceBinding },
}
```

### `core.identity.routing.Budget`

```luau
export type Budget = {
	read targetSeconds: number,
	read maxAttemptsPerSession: number,
}
```

### `core.identity.routing.RefusalRow`

```luau
export type RefusalRow = {
	read id: string,
	read recoverable: boolean,
	read retryable: boolean,
	read holdsAtDoor: boolean,
	read line: string,
}
```

### `core.identity.routing.Handoff`

```luau
export type Handoff = {
	read freshnessSeconds: number,
}
```

### `core.identity.routing.Policy`

```luau
export type Policy = {
	read binding: Binding,
	read budget: Budget,
	read handoff: Handoff,
	read refusals: { [string]: RefusalRow },
	read destinations: { [string]: DestinationProjection },
	read placeByDestinationId: { [string]: number },
}
```

### `core.identity.routing.Session`

```luau
export type Session = {
	read sessionId: string,
	read acquisitionId: string,
	read leaseRevision: number,
}
```

### `core.identity.routing.Character`

```luau
export type Character = {
	read characterId: string,
	read realmId: string,
	read level: number,
}
```

### `core.identity.routing.Request`

```luau
export type Request = {
	read channel: string,
	read universeId: number,
	read sourcePlaceId: number,
	read requestId: string,
	read destinationId: string,
	read character: Character,
	read requestSession: Session,
	read heldSession: Session,
	read selectionAtUnix: number,
	read issuedAtUnix: number,
	read nowUnix: number,
	read attempt: number,
	read resolution: unknown,
}
```

### `core.identity.routing.Route`

```luau
export type Route = {
	read requestId: string,
	read destinationId: string,
	read zoneId: string,
	read realm: string,
	read characterId: string,
	read realmId: string,
	read universeId: number,
	read sourcePlaceId: number,
	read destinationPlaceId: number,
	read sessionId: string,
	read acquisitionId: string,
	read issuedAtUnix: number,
	read deadlineAtUnix: number,
	read carrierExpiresAtUnix: number,
	read attempt: number,
}
```

### `core.identity.routing.Refusal`

```luau
export type Refusal = {
	read requestId: string,
	read reason: string,
	read recoverable: boolean,
	read retryable: boolean,
	read holdsAtDoor: boolean,
	read attempt: number,
	read line: string,
}
```

### `core.identity.routing.Decision`

```luau
export type Decision = {
	read outcome: string,
	read route: Route?,
	read refusal: Refusal?,
}
```

### `core.identity.routing.Arrival`

```luau
export type Arrival = {
	read channel: string,
	read universeId: number,
	read placeId: number,
	read sourceUniverseId: number,
	read sourcePlaceId: number,
	read destinationId: string,
	read characterId: string,
}
```

### `core.identity.routing.Config`

```luau
export type Config = {
	read realms: { [string]: string },
	read structuralId: (unknown) -> string?,
	read namespacedId: (unknown) -> string?,
	read idLimit: number,
	read refusalLineLimit: number,
	read unroutedStatusLimit: number,
	read unroutedReasonLimit: number,
	read unknownRequestId: string,
	read invalidBinding: RefusalRow,
}
```

### `core.identity.routing.API`

```luau
export type API = {
	read projectPolicy: (unknown) -> Policy?,
	read refuse: (unknown, unknown, unknown, unknown) -> Decision,
	read decide: (unknown, unknown) -> Decision,
	read accept: (unknown, unknown) -> Decision,
	read boundPlaceIds: (unknown) -> { number },
	read REASON_IDS: { string },
	read REALMS: { [string]: string },
}
```

### `core.identity.routing.create`

```luau
function create(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
projectPolicy = function Routing.projectPolicy(source: unknown): Policy?
refuse = function Routing.refuse(policy: unknown, requestId: unknown, reason: unknown, attempt: unknown): Decision
decide = function Routing.decide(policy: unknown, request: unknown): Decision
accept = function Routing.accept(policy: unknown, arrival: unknown): Decision
boundPlaceIds = function Routing.boundPlaceIds(policy: unknown): { number }
```

## `core.identity`

[Source](../src/core/identity.luau)

```luau
local Account = require("./identity/account")
```

```luau
local AccountLease = require("./identity/account-lease")
```

```luau
local CharacterLease = require("./identity/character-lease")
```

```luau
local CharacterLeaseStore = require("./identity/character-lease-store")
```

```luau
local Creation = require("./identity/creation")
```

```luau
local CreationRecord = require("./identity/creation-record")
```

```luau
local Deletion = require("./identity/deletion")
```

```luau
local NameClaims = require("./identity/name-claims")
```

```luau
local NameRecord = require("./identity/name-record")
```

```luau
local Policy = require("./identity/policy")
```

```luau
local Retirement = require("./identity/retirement")
```

```luau
local Roster = require("./identity/roster")
```

```luau
local Routing = require("./identity/routing")
```

### `core.identity.AccountLeaseLease`

```luau
export type AccountLeaseLease = AccountLease.Lease
```

### `core.identity.AccountDeletionState`

```luau
export type AccountDeletionState = Account.DeletionState
```

### `core.identity.AccountBase`

```luau
export type AccountBase = Account.Base
```

### `core.identity.AccountCreationReceipt`

```luau
export type AccountCreationReceipt = Account.CreationReceipt
```

### `core.identity.AccountAccount`

```luau
export type AccountAccount<E> = Account.Account<E>
```

### `core.identity.AccountExtension`

```luau
export type AccountExtension<E> = Account.Extension<E>
```

### `core.identity.CharacterLeaseStoreStoreOutcome`

```luau
export type CharacterLeaseStoreStoreOutcome = CharacterLeaseStore.StoreOutcome
```

### `core.identity.CharacterLeaseStoreStore`

```luau
export type CharacterLeaseStoreStore = CharacterLeaseStore.Store
```

### `core.identity.CharacterLeaseStoreAccepted`

```luau
export type CharacterLeaseStoreAccepted = CharacterLeaseStore.Accepted
```

### `core.identity.CharacterLeaseStoreRefused`

```luau
export type CharacterLeaseStoreRefused = CharacterLeaseStore.Refused
```

### `core.identity.CharacterLeaseStoreOutcome`

```luau
export type CharacterLeaseStoreOutcome = CharacterLeaseStore.Outcome
```

### `core.identity.CharacterLeaseStoreConfig`

```luau
export type CharacterLeaseStoreConfig = CharacterLeaseStore.Config
```

### `core.identity.CharacterLeaseStoreAPI`

```luau
export type CharacterLeaseStoreAPI = CharacterLeaseStore.API
```

### `core.identity.CharacterLeaseRecord`

```luau
export type CharacterLeaseRecord = CharacterLease.Record
```

### `core.identity.CharacterLeaseRetirement`

```luau
export type CharacterLeaseRetirement = CharacterLease.Retirement
```

### `core.identity.CharacterLeaseArrival`

```luau
export type CharacterLeaseArrival = CharacterLease.Arrival
```

### `core.identity.CharacterLeaseCharacterLeaseRecord`

```luau
export type CharacterLeaseCharacterLeaseRecord = CharacterLease.CharacterLeaseRecord
```

### `core.identity.CharacterLeaseWitness`

```luau
export type CharacterLeaseWitness = CharacterLease.Witness
```

### `core.identity.CharacterLeaseClaim`

```luau
export type CharacterLeaseClaim = CharacterLease.Claim
```

### `core.identity.CharacterLeaseConfig`

```luau
export type CharacterLeaseConfig = CharacterLease.Config
```

### `core.identity.CharacterLeaseAPI`

```luau
export type CharacterLeaseAPI = CharacterLease.API
```

### `core.identity.CreationRecordSeed`

```luau
export type CreationRecordSeed = CreationRecord.Seed
```

### `core.identity.CreationRecordReceipt`

```luau
export type CreationRecordReceipt = CreationRecord.Receipt
```

### `core.identity.CreationCompletion`

```luau
export type CreationCompletion = Creation.Completion
```

### `core.identity.CreationReceipt`

```luau
export type CreationReceipt = Creation.Receipt
```

### `core.identity.CreationPhase`

```luau
export type CreationPhase = Creation.Phase
```

### `core.identity.CreationState`

```luau
export type CreationState = Creation.State
```

### `core.identity.CreationPrepared`

```luau
export type CreationPrepared = Creation.Prepared
```

### `core.identity.CreationRejected`

```luau
export type CreationRejected = Creation.Rejected
```

### `core.identity.CreationAccepted`

```luau
export type CreationAccepted = Creation.Accepted
```

### `core.identity.CreationResult`

```luau
export type CreationResult = Creation.Result
```

### `core.identity.CreationPlan`

```luau
export type CreationPlan = Creation.Plan
```

### `core.identity.DeletionPhase`

```luau
export type DeletionPhase = Deletion.Phase
```

### `core.identity.DeletionState`

```luau
export type DeletionState = Deletion.State
```

### `core.identity.DeletionPrepared`

```luau
export type DeletionPrepared = Deletion.Prepared
```

### `core.identity.DeletionRejected`

```luau
export type DeletionRejected = Deletion.Rejected
```

### `core.identity.DeletionAccepted`

```luau
export type DeletionAccepted = Deletion.Accepted
```

### `core.identity.DeletionResult`

```luau
export type DeletionResult = Deletion.Result
```

### `core.identity.DeletionPlan`

```luau
export type DeletionPlan = Deletion.Plan
```

### `core.identity.NameClaimsClaim`

```luau
export type NameClaimsClaim = NameClaims.Claim
```

### `core.identity.NameClaimsClaimStatus`

```luau
export type NameClaimsClaimStatus = NameClaims.ClaimStatus
```

### `core.identity.NameClaimsReleaseStatus`

```luau
export type NameClaimsReleaseStatus = NameClaims.ReleaseStatus
```

### `core.identity.NameClaimsAvailability`

```luau
export type NameClaimsAvailability = NameClaims.Availability
```

### `core.identity.NameRecordRecord`

```luau
export type NameRecordRecord = NameRecord.Record
```

### `core.identity.NameRecordClaim`

```luau
export type NameRecordClaim = NameRecord.Claim
```

### `core.identity.PolicyPolicy`

```luau
export type PolicyPolicy = Policy.Policy
```

### `core.identity.RetirementDeletion`

```luau
export type RetirementDeletion = Retirement.Deletion
```

### `core.identity.RetirementRetirement`

```luau
export type RetirementRetirement = Retirement.Retirement
```

### `core.identity.RetirementView`

```luau
export type RetirementView = Retirement.View
```

### `core.identity.RetirementDecision`

```luau
export type RetirementDecision = Retirement.Decision
```

### `core.identity.RetirementConfig`

```luau
export type RetirementConfig = Retirement.Config
```

### `core.identity.RetirementAPI`

```luau
export type RetirementAPI = Retirement.API
```

### `core.identity.RosterCharacterIdentity`

```luau
export type RosterCharacterIdentity = Roster.CharacterIdentity
```

### `core.identity.RosterRoster`

```luau
export type RosterRoster = Roster.Roster
```

### `core.identity.RoutingDestinationProjection`

```luau
export type RoutingDestinationProjection = Routing.DestinationProjection
```

### `core.identity.RoutingPlaceBinding`

```luau
export type RoutingPlaceBinding = Routing.PlaceBinding
```

### `core.identity.RoutingBinding`

```luau
export type RoutingBinding = Routing.Binding
```

### `core.identity.RoutingBudget`

```luau
export type RoutingBudget = Routing.Budget
```

### `core.identity.RoutingRefusalRow`

```luau
export type RoutingRefusalRow = Routing.RefusalRow
```

### `core.identity.RoutingHandoff`

```luau
export type RoutingHandoff = Routing.Handoff
```

### `core.identity.RoutingPolicy`

```luau
export type RoutingPolicy = Routing.Policy
```

### `core.identity.RoutingSession`

```luau
export type RoutingSession = Routing.Session
```

### `core.identity.RoutingCharacter`

```luau
export type RoutingCharacter = Routing.Character
```

### `core.identity.RoutingRequest`

```luau
export type RoutingRequest = Routing.Request
```

### `core.identity.RoutingRoute`

```luau
export type RoutingRoute = Routing.Route
```

### `core.identity.RoutingRefusal`

```luau
export type RoutingRefusal = Routing.Refusal
```

### `core.identity.RoutingDecision`

```luau
export type RoutingDecision = Routing.Decision
```

### `core.identity.RoutingArrival`

```luau
export type RoutingArrival = Routing.Arrival
```

### `core.identity.RoutingConfig`

```luau
export type RoutingConfig = Routing.Config
```

### `core.identity.RoutingAPI`

```luau
export type RoutingAPI = Routing.API
```

### `core.identity.API`

```luau
export type API = {
	read account_lease: typeof(AccountLease),
	read account: typeof(Account),
	read character_lease_store: typeof(CharacterLeaseStore),
	read character_lease: typeof(CharacterLease),
	read creation_record: typeof(CreationRecord),
	read creation: typeof(Creation),
	read deletion: typeof(Deletion),
	read name_claims: typeof(NameClaims),
	read name_record: typeof(NameRecord),
	read policy: typeof(Policy),
	read retirement: typeof(Retirement),
	read roster: typeof(Roster),
	read routing: typeof(Routing),
}
```

### `core.identity.account`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.account_lease`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.character_lease`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.character_lease_store`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.creation`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.creation_record`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.deletion`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.name_claims`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.name_record`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.policy`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.retirement`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.roster`

Exported value; see its declaration in [source](../src/core/identity.luau).

### `core.identity.routing`

Exported value; see its declaration in [source](../src/core/identity.luau).

## `core.inventory.cargo`

[Source](../src/core/inventory/cargo.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.inventory.cargo.Status`

```luau
export type Status = "carried" | "dropped" | "banked" | "lost"
```

### `core.inventory.cargo.Cause`

```luau
export type Cause = "death" | "disconnect" | "teleport"
```

### `core.inventory.cargo.Claim`

```luau
export type Claim = {
	claimId: string,
	materialId: string,
	count: number,
	originActorId: string,
	status: Status,
	holderId: string,
}
```

### `core.inventory.cargo.Drop`

```luau
export type Drop = {
	dropId: string,
	actorId: string,
	cause: Cause,
	droppedAtSec: number,
	expiresAtSec: number,
	claimIds: { string },
	recoveredBy: string?,
	expired: boolean,
}
```

### `core.inventory.cargo.Total`

```luau
export type Total = {
	materialId: string,
	count: number,
}
```

### `core.inventory.cargo.Extraction`

```luau
export type Extraction = {
	extractionId: string,
	actorId: string,
	campId: string,
	atSec: number,
	claimIds: { string },
	totals: { Total },
}
```

### `core.inventory.cargo.State`

```luau
export type State = {
	lastClockSec: number,
	claims: { Claim },
	drops: { Drop },
	extractions: { Extraction },
}
```

### `core.inventory.cargo.Intent`

```luau
export type Intent = {
	eventId: string,
	kind: string,
	materialId: string,
	count: number,
	actorId: string,
	at: number,
}
```

### `core.inventory.cargo.CommandKind`

```luau
export type CommandKind = "carry" | "release" | "recover" | "expire" | "extract"
```

### `core.inventory.cargo.Command`

```luau
export type Command = {
	claimIds: { string }?,
	kind: CommandKind,
	claimId: string?,
	actorId: string?,
	materialId: string?,
	count: number?,
	dropId: string?,
	cause: Cause?,
	expiresAtSec: number?,
	extractionId: string?,
	campId: string?,
}
```

### `core.inventory.cargo.Result`

```luau
export type Result = {
	state: State,
	replayed: boolean,
	carriedCount: number,
	droppedCount: number,
	recoveredCount: number,
	expiredCount: number,
	bankedCount: number,
	dropId: string?,
	extractionId: string?,
	intents: { Intent },
}
```

### `core.inventory.cargo.CensusRow`

```luau
export type CensusRow = {
	materialId: string,
	carried: number,
	dropped: number,
	banked: number,
	lost: number,
}
```

### `core.inventory.cargo.Config`

```luau
export type Config = {
	maxText: number,
	maxCount: number,
	maxAt: number,
	ledgerEventKind: string,
	intentPrefix: string,
	intentSeparator: string,
}
```

### `core.inventory.cargo.create`

```luau
function Cargo.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function Claims.emptyState(): State
projectState = function Claims.projectState(value: unknown): (State?, string?)
retireTransient = function Claims.retireTransient(stateValue: unknown): (State?, string?)
step = function Claims.step(stateValue: unknown, commandValue: unknown, nowSecValue: unknown): (Result?, string?)
carriedOf = function Claims.carriedOf(stateValue: unknown, actorIdValue: unknown): ({ Total }?, string?)
census = function Claims.census(stateValue: unknown): ({ CensusRow }?, string?)
openDrops = function Claims.openDrops(stateValue: unknown, nowSecValue: unknown): ({ Drop }?, string?)
```

## `core.inventory.equipment`

[Source](../src/core/inventory/equipment.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.inventory.equipment.Requirements`

```luau
export type Requirements = {
	read levelReq: number,
	read classReq: { read [number]: string }?,
	read armorFamily: string?,
	read weaponFamily: string?,
	read handTopology: string?,
}
```

### `core.inventory.equipment.ItemDef`

```luau
export type ItemDef = Requirements & {
	read slot: string?,
	read bagSlots: number?,
	read durability: {
		read maximum: number,
		read contactWear: number,
		read damageWear: number,
		read repairCopper: number,
	}?,
}
```

### `core.inventory.equipment.ItemLookup`

```luau
export type ItemLookup = (string) -> ItemDef?
```

### `core.inventory.equipment.Equipment`

```luau
export type Equipment = { [string]: string }
```

### `core.inventory.equipment.Inventory`

```luau
export type Inventory = { [string]: number }
```

### `core.inventory.equipment.Wear`

```luau
export type Wear = { equipped: { [string]: number }, bag: { [string]: { number } }, bank: { [string]: { number } } }
```

### `core.inventory.equipment.Decision`

```luau
export type Decision = { equip: true, slot: string, reason: nil } | { equip: false, slot: nil, reason: string }
```

### `core.inventory.equipment.InventoryPort`

```luau
export type InventoryPort = {
	read removeFromBag: (Inventory, string, number) -> (Inventory, boolean),
	read addToBag: (Inventory, string, number) -> Inventory,
	read entries: (Inventory) -> number,
	read capacity: (string?) -> number,
	read fits: (Inventory, Inventory, number) -> boolean,
}
```

### `core.inventory.equipment.Config`

```luau
export type Config = {
	read inventory: InventoryPort,
	read maxStack: number,
	read decide: (ItemDef, number, string, Equipment, unknown) -> Decision,
	read resolveSlot: (string, Equipment) -> string?,
	read equipDenial: (Requirements, number, string, unknown) -> string?,
}
```

### `core.inventory.equipment.Plan`

```luau
export type Plan = {
	ok: boolean,
	reason: string?,
	bag: Inventory,
	slots: Equipment,
	slot: string?,
	displaced: string?,
	bagItem: string?,
}
```

### `core.inventory.equipment.API`

```luau
export type API = {
	read defaultWear: () -> Wear,
	read normalizeWear: (unknown, Equipment, Inventory, { read [string]: number? }, ItemLookup) -> Wear?,
	read copyWear: (Wear) -> Wear,
	read equipWear: (Wear, Equipment, string, string) -> Wear,
	read unequipWear: (Wear, Equipment, string) -> Wear,
	read reconcileWear: (Wear, Equipment, Equipment) -> Wear,
	read transferWear: (Wear, string, number, "deposit" | "withdraw") -> Wear,
	read discardWear: (Wear, string, number) -> Wear,
	read applyWear: (Wear, Equipment, "contact" | "damage", ItemLookup, number?) -> Wear,
	read activeEquipment: (Wear, Equipment, ItemLookup) -> Equipment,
	read repairQuote: (Wear, Equipment, ItemLookup) -> number,
	read repairWear: (Wear, Equipment, number, number, ItemLookup) -> (Wear?, number, string?),
	read resolveSlot: (string, Equipment) -> string?,
	read equipDenial: (Requirements, number, string, unknown) -> string?,
	read planEquip: (Inventory, Equipment, string, number, string, ItemLookup, unknown, string?) -> Plan,
	read planUnequip: (Inventory, Equipment, string, string?) -> Plan,
}
```

### `core.inventory.equipment.equipment`

```luau
function equipment(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
defaultWear = function defaultWear(): Wear
normalizeWear = function normalizeWear(
		raw: unknown,
		slots: Equipment,
		bag: Inventory,
		bank: { read [string]: number? },
		getDef: ItemLookup
	): Wear?
copyWear = function copyWear(wear: Wear): Wear
equipWear = function equipWear(wear: Wear, slots: Equipment, slot: string, itemId: string): Wear
unequipWear = function unequipWear(wear: Wear, slots: Equipment, slot: string): Wear
reconcileWear = function reconcileWear(wear: Wear, before: Equipment, after: Equipment): Wear
transferWear = function transferWear(wear: Wear, itemId: string, count: number, kind: "deposit" | "withdraw"): Wear
discardWear = function discardWear(wear: Wear, itemId: string, count: number): Wear
applyWear = function applyWear(
		wear: Wear,
		slots: Equipment,
		kind: "contact" | "damage",
		getDef: ItemLookup,
		count: number?
	): Wear
activeEquipment = function activeEquipment(wear: Wear, slots: Equipment, getDef: ItemLookup): Equipment
repairQuote = function repairQuote(wear: Wear, slots: Equipment, getDef: ItemLookup): number
repairWear = function repairWear(
		wear: Wear,
		slots: Equipment,
		funds: number,
		quoted: number,
		getDef: ItemLookup
	): (Wear?, number, string?)
resolveSlot = config.resolveSlot
equipDenial = config.equipDenial
planEquip = function planEquip(
		bag: Inventory,
		slots: Equipment,
		itemId: string,
		level: number,
		class: string,
		getDef: ItemLookup,
		learnedWeapons: unknown,
		bagItem: string?
	): Plan
planUnequip = function planUnequip(bag: Inventory, slots: Equipment, slot: string, bagItem: string?): Plan
```

## `core.inventory.stacks`

[Source](../src/core/inventory/stacks.luau)

```luau
local Value = require("../../kernel/value")
```

```luau
local Vault = require("../bank/vault")
```

### `core.inventory.stacks.Inventory`

```luau
export type Inventory = { [string]: number }
```

### `core.inventory.stacks.Holdings`

```luau
export type Holdings = {
	read inventory: Inventory,
	read equipment: { [string]: string },
	read bank: unknown,
	read itemWear: { equipped: { [string]: number }, bag: { [string]: { number } }, bank: { [string]: { number } } }?,
	read boundItems: Inventory?,
}
```

### `core.inventory.stacks.Config`

```luau
export type Config = {
	maxStack: number,
	baseCapacity: number,
	permanentItems: { [string]: boolean },
	bagBonus: {
		[string]: number,
	},
}
```

### `core.inventory.stacks.stacks`

```luau
function System.stacks(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
isValidCount = function isValidCount(count: unknown): boolean
addToBag = function addToBag(bag: Inventory, itemId: string, count: number): Inventory
removeFromBag = function removeFromBag(bag: Inventory, itemId: string, count: number): (Inventory, boolean)
hasItem = function hasItem(bag: Inventory, itemId: string, count: number?): boolean
copyBag = function copyBag(bag: Inventory): Inventory
MAX_STACK = MAX_STACK
BASE_CAPACITY = BASE_CAPACITY
permanent = function permanent(itemId: string): boolean
capacity = function capacity(bagItem: string?): number
entries = function entries(bag: Inventory): number
fits = function fits(before: Inventory, after: Inventory, limit: number): boolean
normalizeBindings = function normalizeBindings(raw: unknown, profile: Holdings): Inventory
unboundCount = function unboundCount(profile: Holdings, itemId: string): number
```

## `core.inventory`

[Source](../src/core/inventory.luau)

```luau
local Cargo = require("./inventory/cargo")
```

```luau
local Equipment = require("./inventory/equipment")
```

```luau
local Stacks = require("./inventory/stacks")
```

### `core.inventory.CargoStatus`

```luau
export type CargoStatus = Cargo.Status
```

### `core.inventory.CargoCause`

```luau
export type CargoCause = Cargo.Cause
```

### `core.inventory.CargoClaim`

```luau
export type CargoClaim = Cargo.Claim
```

### `core.inventory.CargoDrop`

```luau
export type CargoDrop = Cargo.Drop
```

### `core.inventory.CargoTotal`

```luau
export type CargoTotal = Cargo.Total
```

### `core.inventory.CargoExtraction`

```luau
export type CargoExtraction = Cargo.Extraction
```

### `core.inventory.CargoState`

```luau
export type CargoState = Cargo.State
```

### `core.inventory.CargoIntent`

```luau
export type CargoIntent = Cargo.Intent
```

### `core.inventory.CargoCommandKind`

```luau
export type CargoCommandKind = Cargo.CommandKind
```

### `core.inventory.CargoCommand`

```luau
export type CargoCommand = Cargo.Command
```

### `core.inventory.CargoResult`

```luau
export type CargoResult = Cargo.Result
```

### `core.inventory.CargoCensusRow`

```luau
export type CargoCensusRow = Cargo.CensusRow
```

### `core.inventory.CargoConfig`

```luau
export type CargoConfig = Cargo.Config
```

### `core.inventory.StacksInventory`

```luau
export type StacksInventory = Stacks.Inventory
```

### `core.inventory.StacksHoldings`

```luau
export type StacksHoldings = Stacks.Holdings
```

### `core.inventory.StacksConfig`

```luau
export type StacksConfig = Stacks.Config
```

### `core.inventory.EquipmentRequirements`

```luau
export type EquipmentRequirements = Equipment.Requirements
```

### `core.inventory.EquipmentItemDef`

```luau
export type EquipmentItemDef = Equipment.ItemDef
```

### `core.inventory.EquipmentItemLookup`

```luau
export type EquipmentItemLookup = Equipment.ItemLookup
```

### `core.inventory.EquipmentEquipment`

```luau
export type EquipmentEquipment = Equipment.Equipment
```

### `core.inventory.EquipmentInventory`

```luau
export type EquipmentInventory = Equipment.Inventory
```

### `core.inventory.EquipmentWear`

```luau
export type EquipmentWear = Equipment.Wear
```

### `core.inventory.EquipmentDecision`

```luau
export type EquipmentDecision = Equipment.Decision
```

### `core.inventory.EquipmentInventoryPort`

```luau
export type EquipmentInventoryPort = Equipment.InventoryPort
```

### `core.inventory.EquipmentConfig`

```luau
export type EquipmentConfig = Equipment.Config
```

### `core.inventory.EquipmentPlan`

```luau
export type EquipmentPlan = Equipment.Plan
```

### `core.inventory.EquipmentAPI`

```luau
export type EquipmentAPI = Equipment.API
```

### `core.inventory.API`

```luau
export type API = {
	read cargo: typeof(Cargo),
	read equipment: typeof(Equipment),
	read stacks: typeof(Stacks),
}
```

### `core.inventory.cargo`

Exported value; see its declaration in [source](../src/core/inventory.luau).

### `core.inventory.equipment`

Exported value; see its declaration in [source](../src/core/inventory.luau).

### `core.inventory.stacks`

Exported value; see its declaration in [source](../src/core/inventory.luau).

## `core.ledger.ledger`

[Source](../src/core/ledger/ledger.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.ledger.ledger.EventKind`

```luau
export type EventKind = "grant" | "craft_consume" | "craft_yield" | "trade_out" | "trade_in"
```

### `core.ledger.ledger.Event`

```luau
export type Event = {
	eventId: string,
	kind: EventKind,
	materialId: string,
	count: number,
	actorId: string,
	at: number,
	groupId: string?,
	groupSize: number?,
}
```

### `core.ledger.ledger.State`

```luau
export type State = {
	events: { Event },
}
```

### `core.ledger.ledger.ApplyResult`

```luau
export type ApplyResult = {
	state: State,
	replayed: boolean,
	settled: boolean,
	groupId: string?,
}
```

### `core.ledger.ledger.TornGroup`

```luau
export type TornGroup = {
	groupId: string,
	groupSize: number,
	memberCount: number,
}
```

### `core.ledger.ledger.Config`

```luau
export type Config = {
	maxText: number,
	maxCount: number,
	maxAt: number,
	minGroupSize: number,
	maxGroupSize: number,
}
```

### `core.ledger.ledger.Journal`

```luau
export type Journal = {
	emptyState: () -> State,
	projectEvent: (unknown) -> (Event?, string?),
	projectState: (unknown) -> (State?, string?),
	apply: (unknown, unknown) -> (ApplyResult?, string?),
	balances: (unknown) -> ({ [string]: { [string]: number } }?, string?),
	available: (unknown, unknown, unknown) -> (number?, string?),
	tornGroups: (unknown) -> ({ TornGroup }?, string?),
	REASONS: { string },
	KINDS: { [string]: boolean },
}
```

### `core.ledger.ledger.ledger`

```luau
function Ledger.ledger(config: Config): Journal
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function Journal.emptyState(): State
projectEvent = function Journal.projectEvent(value: unknown): (Event?, string?)
projectState = function Journal.projectState(value: unknown): (State?, string?)
apply = function Journal.apply(stateValue: unknown, eventValue: unknown): (ApplyResult?, string?)
balances = function Journal.balances(stateValue: unknown): ({ [string]: { [string]: number } }?, string?)
available = function Journal.available(stateValue: unknown, actorIdValue: unknown, materialIdValue: unknown): (number?, string?)
tornGroups = function Journal.tornGroups(stateValue: unknown): ({ TornGroup }?, string?)
```

## `core.ledger`

[Source](../src/core/ledger.luau)

```luau
local Ledger = require("./ledger/ledger")
```

### `core.ledger.LedgerEventKind`

```luau
export type LedgerEventKind = Ledger.EventKind
```

### `core.ledger.LedgerEvent`

```luau
export type LedgerEvent = Ledger.Event
```

### `core.ledger.LedgerState`

```luau
export type LedgerState = Ledger.State
```

### `core.ledger.LedgerApplyResult`

```luau
export type LedgerApplyResult = Ledger.ApplyResult
```

### `core.ledger.LedgerTornGroup`

```luau
export type LedgerTornGroup = Ledger.TornGroup
```

### `core.ledger.LedgerConfig`

```luau
export type LedgerConfig = Ledger.Config
```

### `core.ledger.LedgerJournal`

```luau
export type LedgerJournal = Ledger.Journal
```

### `core.ledger.API`

```luau
export type API = {
	read ledger: typeof(Ledger),
}
```

### `core.ledger.ledger`

Exported value; see its declaration in [source](../src/core/ledger.luau).

## `core.loot.decision`

[Source](../src/core/loot/decision.luau)

### `core.loot.decision.Choice`

```luau
export type Choice = "need" | "greed" | "pass"
```

### `core.loot.decision.Seat`

```luau
export type Seat = { userId: string, needLegal: boolean }
```

### `core.loot.decision.Result`

```luau
export type Result = {
	winner: string?,
	by: "need" | "greed" | "round_robin",
	rolls: { [string]: number },
	cursorAfter: number,
}
```

### `core.loot.decision.Decision`

```luau
export type Decision = {
	id: string,
	itemId: string,
	openedAt: number,
	deadline: number,
	seats: { Seat },
	declarations: { [string]: Choice },
	cursor: number,
	result: Result?,
}
```

### `core.loot.decision.Refusal`

```luau
export type Refusal =
	"settled"
	| "closed"
	| "not_eligible"
	| "need_not_legal"
	| "already_declared"
	| "bad_choice"
	| "not_due"
```

### `core.loot.decision.Config`

```luau
export type Config = { windowSeconds: number }
```

### `core.loot.decision.decision`

```luau
function System.decision(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
open = function open(id: string, itemId: string, seats: { Seat }, now: number, cursor: number): Decision?
declare = function declare(decision: Decision, userId: string, choice: unknown, now: number): (Decision?, Refusal?)
due = function due(decision: Decision, now: number): boolean
settle = function settle(decision: Decision, now: number): (Decision?, Refusal?)
```

## `core.loot.roll`

[Source](../src/core/loot/roll.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.loot.roll.Roll`

```luau
export type Roll = {
	itemId: string,
	weight: number,
	minCount: number,
	maxCount: number,
}
```

### `core.loot.roll.Table`

```luau
export type Table = {
	id: string,
	zoneId: string?,
	mobIds: { string },
	rolls: { Roll },
	picks: number?,
}
```

### `core.loot.roll.Drop`

```luau
export type Drop = {
	tableId: string,
	itemId: string,
	count: number,
}
```

### `core.loot.roll.Config`

```luau
export type Config = { receiptPrefix: string }
```

### `core.loot.roll.roll`

```luau
function System.roll(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
validRoll = function validRoll(raw: unknown): Roll?
tableForMob = function tableForMob<T>(tables: { T }?, mobId: unknown): T?
dropFor = function dropFor(tables: unknown, mobId: unknown, actorId: unknown, tickIndex: unknown): Drop?
dropsFor = function dropsFor(tables: unknown, mobId: unknown, actorId: unknown, tickIndex: unknown): { Drop }
receiptFor = function receiptFor(
		drop: Drop,
		mobId: string,
		actorId: string,
		tickIndex: number,
		epoch: number?,
		pick: number?
	): string
```

## `core.loot`

[Source](../src/core/loot.luau)

```luau
local Decision = require("./loot/decision")
```

```luau
local Roll = require("./loot/roll")
```

### `core.loot.DecisionChoice`

```luau
export type DecisionChoice = Decision.Choice
```

### `core.loot.DecisionSeat`

```luau
export type DecisionSeat = Decision.Seat
```

### `core.loot.DecisionResult`

```luau
export type DecisionResult = Decision.Result
```

### `core.loot.DecisionDecision`

```luau
export type DecisionDecision = Decision.Decision
```

### `core.loot.DecisionRefusal`

```luau
export type DecisionRefusal = Decision.Refusal
```

### `core.loot.DecisionConfig`

```luau
export type DecisionConfig = Decision.Config
```

### `core.loot.RollRoll`

```luau
export type RollRoll = Roll.Roll
```

### `core.loot.RollTable`

```luau
export type RollTable = Roll.Table
```

### `core.loot.RollDrop`

```luau
export type RollDrop = Roll.Drop
```

### `core.loot.RollConfig`

```luau
export type RollConfig = Roll.Config
```

### `core.loot.API`

```luau
export type API = {
	read decision: typeof(Decision),
	read roll: typeof(Roll),
}
```

### `core.loot.decision`

Exported value; see its declaration in [source](../src/core/loot.luau).

### `core.loot.roll`

Exported value; see its declaration in [source](../src/core/loot.luau).

## `core.mail.mailbox`

[Source](../src/core/mail/mailbox.luau)

### `core.mail.mailbox.Inventory`

```luau
export type Inventory = { [unknown]: unknown }
```

### `core.mail.mailbox.Account`

```luau
export type Account = { coin: number, inventory: Inventory }
```

### `core.mail.mailbox.Stack`

```luau
export type Stack = { itemId: string, count: number }
```

### `core.mail.mailbox.Attachments`

```luau
export type Attachments = { coin: number, items: { Stack } }
```

### `core.mail.mailbox.Phase`

```luau
export type Phase =
	"prepared"
	| "in_transit"
	| "claiming"
	| "returning"
	| "expired"
	| "claimed"
	| "returned"
	| "cancelled"
```

### `core.mail.mailbox.Envelope`

```luau
export type Envelope = {
	id: string,
	senderId: number,
	recipientId: number,
	attachments: Attachments,
	createdAt: number,
	expiresAt: number,
	phase: Phase,
	senderCharacterId: string?,
	recipientCharacterId: string?,
	returnedAt: number?,
}
```

### `core.mail.mailbox.Pointer`

```luau
export type Pointer = { id: string, envelope: Envelope, intent: "hold" | "claim" }
```

### `core.mail.mailbox.Config`

```luau
export type Config<T> = {
	maxItems: number,
	maxCount: number,
	maxCoin: number,
	maxUserId: number,
	maxTimestamp: number,
	maxTtl: number,
	itemIdLimit: number,
	requestIdLimit: number,
	characterIdLimit: number,
	maxPointers: number,
	readAccount: (T) -> unknown,
	writeAccount: (T, Account) -> T,
	capacity: (T) -> number,
	entries: (Inventory) -> number,
}
```

### `core.mail.mailbox.Mailbox`

```luau
export type Mailbox<T> = {
	attachments: (unknown) -> Attachments?,
	id: (number, unknown) -> string?,
	prepare: (string, number, number, unknown, number, number) -> Envelope?,
	read: (unknown) -> Envelope?,
	valid: (unknown) -> boolean,
	pointers: (unknown) -> { [string]: Pointer }?,
	sameRequest: (unknown, unknown) -> boolean,
	advance: (unknown, string, number?) -> Envelope?,
	debit: (T, Attachments) -> (T?, string?),
	credit: (T, Attachments) -> (T?, string?),
}
```

### `core.mail.mailbox.mailbox`

```luau
function Mail.mailbox<T>(config: Config<T>): Mailbox<T>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
attachments = function attachments(value: unknown): Attachments?
read = function envelope(value: unknown): Envelope?
id = function id(senderId: number, requestId: unknown): string?
prepare = function(
			mailId: string,
			senderId: number,
			recipientId: number,
			value: unknown,
			now: number,
			ttl: number
		): Envelope?
valid = function(value: unknown): boolean
pointers = function(value: unknown): { [string]: Pointer }?
sameRequest = function(first: unknown, second: unknown): boolean
advance = function(value: unknown, action: string, at: number?): Envelope?
debit = function(profile: T, value: Attachments): (T?, string?)
credit = function(profile: T, value: Attachments): (T?, string?)
```

## `core.mail`

[Source](../src/core/mail.luau)

```luau
local Mailbox = require("./mail/mailbox")
```

### `core.mail.MailboxInventory`

```luau
export type MailboxInventory = Mailbox.Inventory
```

### `core.mail.MailboxAccount`

```luau
export type MailboxAccount = Mailbox.Account
```

### `core.mail.MailboxStack`

```luau
export type MailboxStack = Mailbox.Stack
```

### `core.mail.MailboxAttachments`

```luau
export type MailboxAttachments = Mailbox.Attachments
```

### `core.mail.MailboxPhase`

```luau
export type MailboxPhase = Mailbox.Phase
```

### `core.mail.MailboxEnvelope`

```luau
export type MailboxEnvelope = Mailbox.Envelope
```

### `core.mail.MailboxPointer`

```luau
export type MailboxPointer = Mailbox.Pointer
```

### `core.mail.MailboxConfig`

```luau
export type MailboxConfig<T> = Mailbox.Config<T>
```

### `core.mail.MailboxMailbox`

```luau
export type MailboxMailbox<T> = Mailbox.Mailbox<T>
```

### `core.mail.API`

```luau
export type API = {
	read mailbox: typeof(Mailbox),
}
```

### `core.mail.mailbox`

Exported value; see its declaration in [source](../src/core/mail.luau).

## `core.map.coordinates`

[Source](../src/core/map/coordinates.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.map.coordinates.Bounds`

```luau
export type Bounds = {
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
}
```

### `core.map.coordinates.WorldPoint`

```luau
export type WorldPoint = {
	x: number,
	z: number,
}
```

### `core.map.coordinates.NormalizedPoint`

```luau
export type NormalizedPoint = {
	u: number,
	v: number,
}
```

### `core.map.coordinates.mapToWorld`

```luau
function ZoneMapProjectionCore.mapToWorld(boundsValue: unknown, normalizedValue: unknown): WorldPoint?
```

### `core.map.coordinates.worldToMap`

```luau
function ZoneMapProjectionCore.worldToMap(boundsValue: unknown, worldValue: unknown): NormalizedPoint?
```

## `core.map.exploration`

[Source](../src/core/map/exploration.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.map.exploration.Record`

```luau
export type Record<K> = {
	zoneId: string,
	poiId: string,
	displayName: string,
	kind: K,
	position: { u: number, v: number },
	hub: boolean?,
}
```

### `core.map.exploration.CatalogValue`

```luau
export type CatalogValue<K> = { records: { Record<K> }, byZone: { [string]: { Record<K> } } }
```

### `core.map.exploration.ExploredState`

```luau
export type ExploredState = { [string]: { [string]: true } }
```

### `core.map.exploration.Identity`

```luau
export type Identity = { zoneId: string, poiId: string }
```

### `core.map.exploration.WorldPoint`

```luau
export type WorldPoint = { x: number, z: number }
```

### `core.map.exploration.Poi`

```luau
export type Poi = { zoneId: string, poiId: string, position: WorldPoint }
```

### `core.map.exploration.Observation`

```luau
export type Observation = { zoneId: string, position: WorldPoint }
```

### `core.map.exploration.RevealResult`

```luau
export type RevealResult = { ok: boolean, reason: string?, state: ExploredState, discoveries: { Identity } }
```

### `core.map.exploration.Presentation`

```luau
export type Presentation<K> = { zoneId: string, poiId: string, name: string, kind: K, hub: boolean? }
```

### `core.map.exploration.Transition`

```luau
export type Transition<K> = { state: ExploredState, presentations: { Presentation<K> } }
```

### `core.map.exploration.System`

```luau
export type System<K> = {
	catalog: { normalize: (unknown) -> CatalogValue<K>? },
	reveal: {
		emptyState: () -> ExploredState,
		transition: (ExploredState, Observation, { Poi }) -> RevealResult,
		REVEAL_RADIUS_STUDS: number,
	},
	state: {
		defaultState: () -> ExploredState,
		resetState: () -> ExploredState,
		normalize: (unknown, unknown) -> ExploredState?,
		merge: (unknown, unknown, unknown) -> ExploredState?,
		ordered: (unknown, unknown) -> { Identity }?,
	},
	discovery: { project: (unknown, unknown) -> { Presentation<K> }? },
	pipeline: { transition: (unknown, unknown, unknown, unknown) -> Transition<K>? },
}
```

### `core.map.exploration.new`

```luau
function Exploration.new<K>(config: { read readKind: (unknown) -> K?, read revealRadius: number }): System<K>
```

## `core.map.geometry`

[Source](../src/core/map/geometry.luau)

### `core.map.geometry.PanOffset`

```luau
export type PanOffset = {
	x: number,
	y: number,
}
```

### `core.map.geometry.MarkerProjection`

```luau
export type MarkerProjection = {
	x: number,
	y: number,
	withinWindow: boolean,
	edgeClamped: boolean,
}
```

### `core.map.geometry.imagePan`

```luau
function MinimapGeometry.imagePan(playerU: unknown, playerV: unknown, imageScale: unknown): PanOffset?
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
x = 0.5 - playerU * imageScale
y = 0.5 - playerV * imageScale
```

### `core.map.geometry.projectMarker`

```luau
function MinimapGeometry.projectMarker(
	playerU: unknown,
	playerV: unknown,
	markerU: unknown,
	markerV: unknown,
	imageScale: unknown
): MarkerProjection?
```

### `core.map.geometry.projectTrackedWaypoint`

```luau
function MinimapGeometry.projectTrackedWaypoint(
	playerU: unknown,
	playerV: unknown,
	waypointU: unknown,
	waypointV: unknown,
	imageScale: unknown
): MarkerProjection?
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
x = 0.5 + deltaX * edgeScale
y = 0.5 + deltaY * edgeScale
withinWindow = false
edgeClamped = true
```

## `core.map.polyline`

[Source](../src/core/map/polyline.luau)

### `core.map.polyline.PixelPoint`

```luau
export type PixelPoint = { x: number, y: number }
```

### `core.map.polyline.simplifyPolyline`

```luau
function Polyline.simplifyPolyline(points: { PixelPoint }, tolerance: number): { PixelPoint }
```

### `core.map.polyline.smoothPolyline`

```luau
function Polyline.smoothPolyline(points: { PixelPoint }): { PixelPoint }
```

## `core.map.renderer`

[Source](../src/core/map/renderer.luau)

```luau
local Exploration = require("./exploration")
```

```luau
local MapViewportModel = require("./viewport")
```

```luau
local UpdateTypes = require("./updates")
```

```luau
local Value = require("../../kernel/value")
```

### `core.map.renderer.PreferredInput`

```luau
export type PreferredInput = "pointer" | "touch"
```

### `core.map.renderer.Surface`

```luau
export type Surface = {
	preferredInput: PreferredInput,
	enabled: boolean,
	diameterPx: number,
	northLocked: boolean,
	rotates: boolean,
}
```

### `core.map.renderer.Input`

```luau
export type Input<K> = {
	preferredInput: PreferredInput,
	explicitEnabled: boolean?,
	previousUpdateState: UpdateTypes.State,
	sample: UpdateTypes.Sample,
	zoneId: string,
	markerRows: { Exploration.Record<K> },
	exploredMap: Exploration.ExploredState,
	imageScale: number,
	trackedWaypoint: MapViewportModel.TrackedWaypoint?,
}
```

### `core.map.renderer.Result`

```luau
export type Result = {
	surface: Surface,
	updateState: UpdateTypes.State,
	viewportUpdate: MapViewportModel.Viewport?,
}
```

### `core.map.renderer.new`

```luau
function Renderer.new<K>(deps: {
	read normalize: (unknown) -> Exploration.CatalogValue<K>?,
	read resolve: (unknown, unknown) -> Surface?,
	read update: (unknown, unknown) -> UpdateTypes.Result?,
})
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
compose = function MinimapRenderCore.compose(input: unknown): Result?
```

## `core.map.updates`

[Source](../src/core/map/updates.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.map.updates.NormalizedPoint`

```luau
export type NormalizedPoint = {
	u: number,
	v: number,
}
```

### `core.map.updates.Sample`

```luau
export type Sample = {
	atSeconds: number,
	player: NormalizedPoint,
	markerRevision: number,
}
```

### `core.map.updates.State`

```luau
export type State = {
	lastSampleAtSeconds: number?,
	lastPanAtSeconds: number?,
	markerRevision: number?,
}
```

### `core.map.updates.PanUpdate`

```luau
export type PanUpdate = {
	atSeconds: number,
	player: NormalizedPoint,
}
```

### `core.map.updates.MarkerUpdate`

```luau
export type MarkerUpdate = {
	atSeconds: number,
	player: NormalizedPoint,
	revision: number,
}
```

### `core.map.updates.Output`

```luau
export type Output = {
	pan: PanUpdate?,
	markers: MarkerUpdate?,
}
```

### `core.map.updates.Result`

```luau
export type Result = {
	state: State,
	output: Output,
}
```

### `core.map.updates.new`

```luau
function Updates.new(updateHz: number)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function MinimapUpdateCore.emptyState(): State
transition = function MinimapUpdateCore.transition(previous: unknown, nextSample: unknown): Result?
```

## `core.map.viewport`

[Source](../src/core/map/viewport.luau)

```luau
local Value = require("../../kernel/value")
```

```luau
local MapRevealCore = require("./exploration")
```

```luau
local MinimapGeometry = require("./geometry")
```

### `core.map.viewport.NormalizedPoint`

```luau
export type NormalizedPoint = {
	u: number,
	v: number,
}
```

### `core.map.viewport.MarkerRow`

```luau
export type MarkerRow = {
	zoneId: string,
	poiId: string,
	position: NormalizedPoint,
}
```

### `core.map.viewport.TrackedWaypoint`

```luau
export type TrackedWaypoint = {
	zoneId: string,
	position: NormalizedPoint,
}
```

### `core.map.viewport.Input`

```luau
export type Input = {
	zoneId: string,
	exploredMap: MapRevealCore.ExploredState,
	markerRows: { MarkerRow },
	player: NormalizedPoint,
	imageScale: number,
	trackedWaypoint: TrackedWaypoint?,
}
```

### `core.map.viewport.PoiMarker`

```luau
export type PoiMarker = {
	zoneId: string,
	poiId: string,
	projection: MinimapGeometry.MarkerProjection,
}
```

### `core.map.viewport.Viewport`

```luau
export type Viewport = {
	imagePan: MinimapGeometry.PanOffset,
	player: MinimapGeometry.MarkerProjection,
	poiMarkers: { PoiMarker },
	trackedWaypoint: MinimapGeometry.MarkerProjection?,
}
```

### `core.map.viewport.build`

```luau
function MapViewportModel.build(value: unknown): Viewport?
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
imagePan = imagePan
player = player
poiMarkers = markers
trackedWaypoint = tracked
```

## `core.map`

[Source](../src/core/map.luau)

```luau
local Coordinates = require("./map/coordinates")
```

```luau
local Exploration = require("./map/exploration")
```

```luau
local Geometry = require("./map/geometry")
```

```luau
local Polyline = require("./map/polyline")
```

```luau
local Renderer = require("./map/renderer")
```

```luau
local Updates = require("./map/updates")
```

```luau
local Viewport = require("./map/viewport")
```

### `core.map.CoordinatesBounds`

```luau
export type CoordinatesBounds = Coordinates.Bounds
```

### `core.map.CoordinatesWorldPoint`

```luau
export type CoordinatesWorldPoint = Coordinates.WorldPoint
```

### `core.map.CoordinatesNormalizedPoint`

```luau
export type CoordinatesNormalizedPoint = Coordinates.NormalizedPoint
```

### `core.map.ExplorationRecord`

```luau
export type ExplorationRecord<K> = Exploration.Record<K>
```

### `core.map.ExplorationCatalogValue`

```luau
export type ExplorationCatalogValue<K> = Exploration.CatalogValue<K>
```

### `core.map.ExplorationExploredState`

```luau
export type ExplorationExploredState = Exploration.ExploredState
```

### `core.map.ExplorationIdentity`

```luau
export type ExplorationIdentity = Exploration.Identity
```

### `core.map.ExplorationWorldPoint`

```luau
export type ExplorationWorldPoint = Exploration.WorldPoint
```

### `core.map.ExplorationPoi`

```luau
export type ExplorationPoi = Exploration.Poi
```

### `core.map.ExplorationObservation`

```luau
export type ExplorationObservation = Exploration.Observation
```

### `core.map.ExplorationRevealResult`

```luau
export type ExplorationRevealResult = Exploration.RevealResult
```

### `core.map.ExplorationPresentation`

```luau
export type ExplorationPresentation<K> = Exploration.Presentation<K>
```

### `core.map.ExplorationTransition`

```luau
export type ExplorationTransition<K> = Exploration.Transition<K>
```

### `core.map.ExplorationSystem`

```luau
export type ExplorationSystem<K> = Exploration.System<K>
```

### `core.map.GeometryPanOffset`

```luau
export type GeometryPanOffset = Geometry.PanOffset
```

### `core.map.GeometryMarkerProjection`

```luau
export type GeometryMarkerProjection = Geometry.MarkerProjection
```

### `core.map.PolylinePixelPoint`

```luau
export type PolylinePixelPoint = Polyline.PixelPoint
```

### `core.map.RendererPreferredInput`

```luau
export type RendererPreferredInput = Renderer.PreferredInput
```

### `core.map.RendererSurface`

```luau
export type RendererSurface = Renderer.Surface
```

### `core.map.RendererInput`

```luau
export type RendererInput<K> = Renderer.Input<K>
```

### `core.map.RendererResult`

```luau
export type RendererResult = Renderer.Result
```

### `core.map.UpdatesNormalizedPoint`

```luau
export type UpdatesNormalizedPoint = Updates.NormalizedPoint
```

### `core.map.UpdatesSample`

```luau
export type UpdatesSample = Updates.Sample
```

### `core.map.UpdatesState`

```luau
export type UpdatesState = Updates.State
```

### `core.map.UpdatesPanUpdate`

```luau
export type UpdatesPanUpdate = Updates.PanUpdate
```

### `core.map.UpdatesMarkerUpdate`

```luau
export type UpdatesMarkerUpdate = Updates.MarkerUpdate
```

### `core.map.UpdatesOutput`

```luau
export type UpdatesOutput = Updates.Output
```

### `core.map.UpdatesResult`

```luau
export type UpdatesResult = Updates.Result
```

### `core.map.ViewportNormalizedPoint`

```luau
export type ViewportNormalizedPoint = Viewport.NormalizedPoint
```

### `core.map.ViewportMarkerRow`

```luau
export type ViewportMarkerRow = Viewport.MarkerRow
```

### `core.map.ViewportTrackedWaypoint`

```luau
export type ViewportTrackedWaypoint = Viewport.TrackedWaypoint
```

### `core.map.ViewportInput`

```luau
export type ViewportInput = Viewport.Input
```

### `core.map.ViewportPoiMarker`

```luau
export type ViewportPoiMarker = Viewport.PoiMarker
```

### `core.map.ViewportViewport`

```luau
export type ViewportViewport = Viewport.Viewport
```

### `core.map.API`

```luau
export type API = {
	read coordinates: typeof(Coordinates),
	read exploration: typeof(Exploration),
	read geometry: typeof(Geometry),
	read polyline: typeof(Polyline),
	read renderer: typeof(Renderer),
	read updates: typeof(Updates),
	read viewport: typeof(Viewport),
}
```

### `core.map.coordinates`

Exported value; see its declaration in [source](../src/core/map.luau).

### `core.map.exploration`

Exported value; see its declaration in [source](../src/core/map.luau).

### `core.map.geometry`

Exported value; see its declaration in [source](../src/core/map.luau).

### `core.map.polyline`

Exported value; see its declaration in [source](../src/core/map.luau).

### `core.map.renderer`

Exported value; see its declaration in [source](../src/core/map.luau).

### `core.map.updates`

Exported value; see its declaration in [source](../src/core/map.luau).

### `core.map.viewport`

Exported value; see its declaration in [source](../src/core/map.luau).

## `core.market.book`

[Source](../src/core/market/book.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.market.book.Listing`

```luau
export type Listing = {
	listingId: string,
	itemId: string?,
	sellerId: number,
	count: number,
	unitPrice: number,
	listedAtSec: number,
	expiresAtSec: number,
}
```

### `core.market.book.ReceiptKind`

```luau
export type ReceiptKind = "proceeds" | "purchase" | "return"
```

### `core.market.book.Receipt`

```luau
export type Receipt = {
	receiptId: string,
	itemId: string?,
	ownerId: number,
	kind: ReceiptKind,
	opId: string,
	coin: number,
	goods: number,
	issuedAtSec: number,
}
```

### `core.market.book.Operation`

```luau
export type Operation = { fingerprint: string, atSec: number, actorId: number }
```

### `core.market.book.State`

```luau
export type State = {
	schemaVersion: number,
	realmId: string,
	materialId: string,
	feeBps: number,
	lastClockSec: number,
	listings: { Listing },
	receipts: { Receipt },
	operations: { [string]: Operation },
	operationOrder: { string },
	burnedCoin: number,
}
```

### `core.market.book.Result`

```luau
export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	receipts: { Receipt }?,
	fence: string?,
}
```

### `core.market.book.Command`

```luau
export type Command =
	{
		kind: "list",
		opId: string,
		itemId: string?,
		actorId: number,
		actorRealmId: string,
		count: number,
		unitPrice: number,
	}
	| { kind: "cancel", opId: string, itemId: string?, actorId: number, listingId: string }
	| {
		kind: "fill",
		opId: string,
		itemId: string?,
		actorId: number,
		actorRealmId: string,
		quantity: number,
		ceilingUnitPrice: number,
		holdCoin: number,
	}
	| { kind: "ack", opId: string, itemId: string?, actorId: number, receiptIds: { string } }
	| { kind: "sweep", opId: string, itemId: string?, actorId: number? }
	| { kind: "void", opId: string, itemId: string?, actorId: number? }
```

### `core.market.book.Search`

```luau
export type Search = { limit: number?, sellerId: number?, itemId: string?, ceilingUnitPrice: number? }
```

### `core.market.book.Config`

```luau
export type Config = {
	listingTtlSec: number,
	minFeeBps: number,
	maxFeeBps: number,
	defaultFeeBps: number,
	maxListings: number,
	maxReceipts: number,
	operationRetentionSec: number,
	actorWindowSec: number,
	maxReceiptsPerOwner: number,
	maxOperations: number,
	maxOperationsPerActor: number,
	maxListingsPerSeller: number,
	maxCount: number,
	maxPrice: number,
	maxId: number,
	maxTime: number,
	maxCoin: number,
	categoryPrefix: string,
	maxSearch: number,
	realms: { [string]: boolean },
}
```

### `core.market.book.book`

```luau
function Market.book(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function Book.emptyState(realmId: unknown, materialId: unknown, feeBps: unknown): State?
projectState = function Book.projectState(value: unknown): State?
knowsOperation = function Book.knowsOperation(value: unknown, opId: unknown): boolean
apply = function Book.apply(previous: unknown, commandValue: unknown, nowSecValue: unknown): Result
search = function Book.search(value: unknown, query: unknown, nowSecValue: unknown): { Listing }?
receiptsFor = function Book.receiptsFor(value: unknown, ownerId: unknown): { Receipt }?
```

## `core.market.conservation`

[Source](../src/core/market/conservation.luau)

```luau
local Book = require("./book")
```

```luau
local Value = require("../../kernel/value")
```

```luau
local Wallet = require("./wallet")
```

### `core.market.conservation.Totals`

```luau
export type Totals = { coin: number, goods: { [string]: number } }
```

### `core.market.conservation.Audit`

```luau
export type Audit = { ok: boolean, coin: number, goods: { [string]: number }, reason: string? }
```

### `core.market.conservation.Config`

```luau
export type Config = {
	projectBook: (unknown) -> Book.State?,
	projectWallet: (unknown) -> Wallet.State?,
}
```

### `core.market.conservation.conservation`

```luau
function Conservation.conservation(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
measure = function Audit.measure(walletValues: unknown, bookValues: unknown): (Totals?, string?)
audit = function Audit.audit(walletValues: unknown, bookValues: unknown, expected: Totals): Audit
```

## `core.market.goods`

[Source](../src/core/market/goods.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.market.goods.ItemFacts`

```luau
export type ItemFacts = {
	id: string,
	slot: string?,
	levelReq: number?,
	rarity: string?,
	weaponFamily: string?,
	armorFamily: string?,
	classReq: { string }?,
}
```

### `core.market.goods.Class`

```luau
export type Class = { id: string, displayName: string, weaponFamilies: { string }, armorCeiling: string }
```

### `core.market.goods.Config`

```luau
export type Config<T> = {
	books: { [string]: string },
	order: { string },
	slots: { [string]: string },
	bindRules: { [string]: boolean },
	boundSlots: { [string]: boolean },
	recipePrefixes: { string },
	consumablePrefix: string,
	recipeCategory: string,
	consumableCategory: string,
	defaultCategory: string,
	armorRanks: { [string]: number },
	classOf: (string) -> Class?,
	unboundCount: (T, string) -> number,
}
```

### `core.market.goods.Filters`

```luau
export type Filters = {
	slot: string?,
	minLevel: number?,
	maxLevel: number?,
	rarity: string?,
	family: string?,
	classId: string?,
}
```

### `core.market.goods.catalog`

```luau
function Goods.catalog<T>(config: Config<T>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
bookIds = function catalog.bookIds(): { string }
isCategoryBook = function catalog.isCategoryBook(bookId: unknown): boolean
bookFor = function catalog.bookFor(value: unknown): (string?, string?)
tradeableCount = function catalog.tradeableCount(def: unknown, profile: T): number
matches = function catalog.matches(def: ItemFacts, value: unknown): boolean
```

## `core.market.wallet`

[Source](../src/core/market/wallet.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.market.wallet.Pending`

```luau
export type Pending = {
	kind: "consign" | "buy",
	realmId: string,
	materialId: string,
	bookId: string?,
	count: number,
	hold: number,
	startedAtSec: number,
}
```

### `core.market.wallet.State`

```luau
export type State = {
	schemaVersion: number,
	userId: number,
	coin: number,
	goods: { [string]: number },
	pending: { [string]: Pending },
	claimedOrder: { string },
}
```

### `core.market.wallet.Ledger`

```luau
export type Ledger = {
	schemaVersion: number,
	pending: { [string]: Pending },
	claimedOrder: { string },
}
```

### `core.market.wallet.Result`

```luau
export type Result =
	{ ok: true, state: State, replayed: boolean, reason: nil }
	| { ok: false, state: nil, replayed: false, reason: string }
```

### `core.market.wallet.Config`

```luau
export type Config = {
	claimedWindow: number,
	healRetentionSec: number,
	maxPending: number,
	maxId: number,
	maxCount: number,
	maxCoin: number,
	maxTime: number,
	realms: { [string]: boolean },
}
```

### `core.market.wallet.wallet`

```luau
function Wallets.wallet(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function Wallet.emptyState(userId: unknown, coin: unknown, goods: unknown): State?
projectState = function Wallet.projectState(value: unknown): State?
beginConsign = function Wallet.beginConsign(
		previous: unknown,
		opId: unknown,
		realmId: unknown,
		materialId: unknown,
		count: unknown,
		nowSec: unknown,
		bookId: unknown?
	): Result
beginBuy = function Wallet.beginBuy(
		previous: unknown,
		opId: unknown,
		realmId: unknown,
		materialId: unknown,
		hold: unknown,
		nowSec: unknown,
		bookId: unknown?
	): Result
refund = function Wallet.refund(previous: unknown, opId: unknown): Result
settleConsign = function Wallet.settleConsign(previous: unknown, opId: unknown): Result
claim = function Wallet.claim(previous: unknown, receiptValue: unknown, materialId: unknown): Result
heal = function Wallet.heal(previous: unknown, opId: unknown, bookKnowsOperation: unknown, nowSec: unknown): Result
npcTrade = function Wallet.npcTrade(
		previous: unknown,
		side: unknown,
		materialId: unknown,
		count: unknown,
		unitPrice: unknown
	): Result
emptyLedger = function Wallet.emptyLedger(): Ledger
compose = function Wallet.compose(userId: unknown, coin: unknown, goods: unknown, ledgerValue: unknown): State?
projectLedger = function Wallet.projectLedger(userId: unknown, value: unknown): Ledger?
ledgerOf = function Wallet.ledgerOf(stateValue: unknown): Ledger?
```

## `core.market`

[Source](../src/core/market.luau)

```luau
local Book = require("./market/book")
```

```luau
local Conservation = require("./market/conservation")
```

```luau
local Goods = require("./market/goods")
```

```luau
local Wallet = require("./market/wallet")
```

### `core.market.BookListing`

```luau
export type BookListing = Book.Listing
```

### `core.market.BookReceiptKind`

```luau
export type BookReceiptKind = Book.ReceiptKind
```

### `core.market.BookReceipt`

```luau
export type BookReceipt = Book.Receipt
```

### `core.market.BookOperation`

```luau
export type BookOperation = Book.Operation
```

### `core.market.BookState`

```luau
export type BookState = Book.State
```

### `core.market.BookResult`

```luau
export type BookResult = Book.Result
```

### `core.market.BookCommand`

```luau
export type BookCommand = Book.Command
```

### `core.market.BookSearch`

```luau
export type BookSearch = Book.Search
```

### `core.market.BookConfig`

```luau
export type BookConfig = Book.Config
```

### `core.market.ConservationTotals`

```luau
export type ConservationTotals = Conservation.Totals
```

### `core.market.ConservationAudit`

```luau
export type ConservationAudit = Conservation.Audit
```

### `core.market.ConservationConfig`

```luau
export type ConservationConfig = Conservation.Config
```

### `core.market.GoodsItemFacts`

```luau
export type GoodsItemFacts = Goods.ItemFacts
```

### `core.market.GoodsClass`

```luau
export type GoodsClass = Goods.Class
```

### `core.market.GoodsConfig`

```luau
export type GoodsConfig<T> = Goods.Config<T>
```

### `core.market.GoodsFilters`

```luau
export type GoodsFilters = Goods.Filters
```

### `core.market.WalletPending`

```luau
export type WalletPending = Wallet.Pending
```

### `core.market.WalletState`

```luau
export type WalletState = Wallet.State
```

### `core.market.WalletLedger`

```luau
export type WalletLedger = Wallet.Ledger
```

### `core.market.WalletResult`

```luau
export type WalletResult = Wallet.Result
```

### `core.market.WalletConfig`

```luau
export type WalletConfig = Wallet.Config
```

### `core.market.API`

```luau
export type API = {
	read book: typeof(Book),
	read conservation: typeof(Conservation),
	read goods: typeof(Goods),
	read wallet: typeof(Wallet),
}
```

### `core.market.book`

Exported value; see its declaration in [source](../src/core/market.luau).

### `core.market.conservation`

Exported value; see its declaration in [source](../src/core/market.luau).

### `core.market.goods`

Exported value; see its declaration in [source](../src/core/market.luau).

### `core.market.wallet`

Exported value; see its declaration in [source](../src/core/market.luau).

## `core.net.rate-limit`

[Source](../src/core/net/rate-limit.luau)

### `core.net.rate-limit.Config`

```luau
export type Config = {
	capacity: number,
	refillPerSec: number,
}
```

### `core.net.rate-limit.Bucket`

```luau
export type Bucket = {
	tokens: number,
	lastRefill: number,
}
```

### `core.net.rate-limit.KeyedState`

```luau
export type KeyedState = { [string]: Bucket }
```

### `core.net.rate-limit.consume`

Exported value; see its declaration in [source](../src/core/net/rate-limit.luau).

### `core.net.rate-limit.newBucket`

Exported value; see its declaration in [source](../src/core/net/rate-limit.luau).

### `core.net.rate-limit.tryConsume`

Exported value; see its declaration in [source](../src/core/net/rate-limit.luau).

## `core.net`

[Source](../src/core/net.luau)

```luau
local RateLimit = require("./net/rate-limit")
```

### `core.net.RateLimitConfig`

```luau
export type RateLimitConfig = RateLimit.Config
```

### `core.net.RateLimitBucket`

```luau
export type RateLimitBucket = RateLimit.Bucket
```

### `core.net.RateLimitKeyedState`

```luau
export type RateLimitKeyedState = RateLimit.KeyedState
```

### `core.net.API`

```luau
export type API = {
	read rate_limit: typeof(RateLimit),
}
```

### `core.net.rate_limit`

Exported value; see its declaration in [source](../src/core/net.luau).

## `core.orders.patron`

[Source](../src/core/orders/patron.luau)

```luau
local SocialShape = require("../social/shape")
```

### `core.orders.patron.Order`

```luau
export type Order = {
	orderId: string,
	realmId: string,
	itemId: string,
	count: number,
	payout: number,
	label: string,
}
```

### `core.orders.patron.Catalog`

```luau
export type Catalog = {
	weeklyCoinCap: number,
	orders: { [string]: Order },
	ordered: { Order },
}
```

### `core.orders.patron.State`

```luau
export type State = {
	schemaVersion: number,
	weekIndex: number,
	paidThisWeek: number,
	carry: number,
	receiptOrder: { { turnInId: string, payout: number } },
}
```

### `core.orders.patron.Result`

```luau
export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	payout: number,
	consume: number,
	itemId: string?,
}
```

### `core.orders.patron.Config`

```luau
export type Config = {
	weekSec: number,
	weekAnchorSec: number,
	receiptWindow: number,
	maxId: number,
	maxOrders: number,
	maxCount: number,
	maxCoin: number,
	maxTime: number,
	realms: { [string]: boolean },
}
```

### `core.orders.patron.patron`

```luau
function System.patron(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
catalog = function PatronOrderCore.catalog(value: unknown): (Catalog?, string?)
emptyState = function PatronOrderCore.emptyState(): State
projectState = function PatronOrderCore.projectState(value: unknown): State?
weekOf = function PatronOrderCore.weekOf(atSec: number): number
allowance = function PatronOrderCore.allowance(value: unknown, catalogValue: Catalog, atSec: number): number?
turnIn = function PatronOrderCore.turnIn(previous: unknown, catalog: Catalog, turnInValue: unknown): Result
```

## `core.orders.work`

[Source](../src/core/orders/work.luau)

```luau
local SocialShape = require("../social/shape")
```

### `core.orders.work.Phase`

```luau
export type Phase = "unaccepted" | "accepted" | "completed"
```

### `core.orders.work.WorkOrderStep`

```luau
export type WorkOrderStep = {
	id: string,
	tag: string,
	targetCount: number,
}
```

### `core.orders.work.WorkOrder`

```luau
export type WorkOrder = {
	id: string,
	rewardId: string,
	repeatable: boolean,
	steps: { WorkOrderStep },
}
```

### `core.orders.work.State`

```luau
export type State = {
	lastClockSec: number,
	phase: Phase,
	stepProgress: { [string]: number },
	claimed: boolean,
	claims: { [string]: string },
}
```

### `core.orders.work.CommandKind`

```luau
export type CommandKind = "accept" | "progress" | "complete" | "claim"
```

### `core.orders.work.Command`

```luau
export type Command = {
	kind: CommandKind,
	stepTag: string?,
	amount: number?,
	eventId: string?,
}
```

### `core.orders.work.Result`

```luau
export type Result = {
	state: State,
	phase: Phase,
	accepted: boolean,
	progressed: boolean,
	completed: boolean,
	claimed: boolean,
	replayed: boolean,
	rewardId: string?,
	eventId: string?,
}
```

### `core.orders.work.emptyState`

```luau
function WorkOrderCore.emptyState(): State
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
lastClockSec = 0
phase = "unaccepted"
stepProgress = {}
claimed = false
claims = {}
```

### `core.orders.work.projectOrder`

```luau
function WorkOrderCore.projectOrder(value: unknown): WorkOrder?
```

### `core.orders.work.projectState`

```luau
function WorkOrderCore.projectState(value: unknown, orderValue: unknown): State?
```

### `core.orders.work.step`

```luau
function WorkOrderCore.step(
	previousStateValue: unknown,
	orderValue: unknown,
	commandValue: unknown,
	nowSecValue: unknown
): Result?
```

## `core.orders`

[Source](../src/core/orders.luau)

```luau
local Patron = require("./orders/patron")
```

```luau
local Work = require("./orders/work")
```

### `core.orders.PatronOrder`

```luau
export type PatronOrder = Patron.Order
```

### `core.orders.PatronCatalog`

```luau
export type PatronCatalog = Patron.Catalog
```

### `core.orders.PatronState`

```luau
export type PatronState = Patron.State
```

### `core.orders.PatronResult`

```luau
export type PatronResult = Patron.Result
```

### `core.orders.PatronConfig`

```luau
export type PatronConfig = Patron.Config
```

### `core.orders.WorkPhase`

```luau
export type WorkPhase = Work.Phase
```

### `core.orders.WorkWorkOrderStep`

```luau
export type WorkWorkOrderStep = Work.WorkOrderStep
```

### `core.orders.WorkWorkOrder`

```luau
export type WorkWorkOrder = Work.WorkOrder
```

### `core.orders.WorkState`

```luau
export type WorkState = Work.State
```

### `core.orders.WorkCommandKind`

```luau
export type WorkCommandKind = Work.CommandKind
```

### `core.orders.WorkCommand`

```luau
export type WorkCommand = Work.Command
```

### `core.orders.WorkResult`

```luau
export type WorkResult = Work.Result
```

### `core.orders.API`

```luau
export type API = {
	read patron: typeof(Patron),
	read work: typeof(Work),
}
```

### `core.orders.patron`

Exported value; see its declaration in [source](../src/core/orders.luau).

### `core.orders.work`

Exported value; see its declaration in [source](../src/core/orders.luau).

## `core.persistence.profile-session`

[Source](../src/core/persistence/profile-session.luau)

### `core.persistence.profile-session.FlightKind`

```luau
export type FlightKind = "save" | "close" | "renewal"
```

### `core.persistence.profile-session.State`

```luau
export type State = {
	leaseExpiresAt: number,
	dirty: boolean,
	dirtyDueAt: number?,
	generation: number,
	inFlightGeneration: number?,
	inFlightKind: FlightKind?,
	closed: boolean,
	shutdownDueAt: number?,
	failed: boolean,
	leaseLost: boolean,
	released: boolean,
}
```

### `core.persistence.profile-session.Outcome`

```luau
export type Outcome = { ok: boolean, reason: string?, generation: number?, kind: FlightKind? }
```

### `core.persistence.profile-session.Config`

```luau
export type Config = {
	leaseSeconds: number,
	renewBeforeSeconds: number,
	coalesceSeconds: number,
	shutdownSeconds: number,
	ordinaryReason: string,
	immediateReasons: { [string]: boolean },
}
```

### `core.persistence.profile-session.create`

```luau
function Session.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
open = function M.open(now: number)
openAcquired = function M.openAcquired(now: number, persistedExpiry: number): (State?, string?)
dirty = function M.dirty(s: State, now: number, reason: string): Outcome
due = function M.due(s: State, now: number): boolean
begin = function M.begin(s: State, now: number): Outcome
finish = function M.finish(s: State, now: number, ok: boolean): Outcome
close = function M.close(s: State, now: number): Outcome
```

## `core.persistence.record-store`

[Source](../src/core/persistence/record-store.luau)

```luau
local Atomic = require("../../kernel/store")
```

```luau
local Result = require("../../kernel/result")
```

```luau
local Value = require("../../kernel/value")
```

### `core.persistence.record-store.StoreOutcome`

```luau
export type StoreOutcome = Result.Result<Atomic.Readback>
```

### `core.persistence.record-store.Store`

```luau
export type Store = Atomic.Port
```

### `core.persistence.record-store.Accepted`

```luau
export type Accepted<R> = { ok: true, value: R, reason: string?, found: boolean? }
```

### `core.persistence.record-store.Refused`

```luau
export type Refused = { ok: false, value: nil, reason: string?, found: boolean? }
```

### `core.persistence.record-store.Outcome`

```luau
export type Outcome<R> = Accepted<R> | Refused
```

### `core.persistence.record-store.View`

```luau
export type View = { read partitionId: string, read subjectId: string, read revision: number }
```

### `core.persistence.record-store.Config`

```luau
export type Config<R> = {
	read codec: Atomic.Codec<R>,
	read empty: (string, string) -> (R?, string?),
	read view: (R) -> View,
	read withRevision: (R, number) -> R,
	read maxRevision: number,
}
```

### `core.persistence.record-store.API`

```luau
export type API<R> = {
	read read: (Store, (string, string) -> string, string, string) -> Outcome<R>,
	read update: (Store, (string, string) -> string, unknown, unknown) -> Outcome<R>,
}
```

### `core.persistence.record-store.configure`

```luau
function configure<R>(config: Config<R>): API<R>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
read = function read(
		store: Store,
		keyFor: (string, string) -> string,
		partitionId: string,
		subjectId: string
	): Outcome<R>
update = function update(
		store: Store,
		keyFor: (string, string) -> string,
		snapshot: unknown,
		desired: unknown
	): Outcome<R>
```

## `core.persistence.session-lock`

[Source](../src/core/persistence/session-lock.luau)

### `core.persistence.session-lock.LockState`

```luau
export type LockState = {
	sessionId: string?,

	lockExpiry: number,
}
```

### `core.persistence.session-lock.AcquireResult`

```luau
export type AcquireResult = {
	granted: boolean,
	newState: LockState?,
	reason: string,
}
```

### `core.persistence.session-lock.isLocked`

Exported value; see its declaration in [source](../src/core/persistence/session-lock.luau).

### `core.persistence.session-lock.release`

Exported value; see its declaration in [source](../src/core/persistence/session-lock.luau).

### `core.persistence.session-lock.tryAcquire`

Exported value; see its declaration in [source](../src/core/persistence/session-lock.luau).

## `core.persistence.store-host`

[Source](../src/core/persistence/store-host.luau)

```luau
local Codec = require("../../kernel/codec")
```

```luau
local Value = require("../../kernel/value")
```

### `core.persistence.store-host.Outcome`

```luau
export type Outcome = { ok: boolean, value: unknown, reason: string? }
```

### `core.persistence.store-host.DrainOutcome`

```luau
export type DrainOutcome = { ok: boolean, flushed: number, remaining: number, reason: string? }
```

### `core.persistence.store-host.Operation`

```luau
export type Operation = "Get" | "Set" | "Update"
```

### `core.persistence.store-host.Observation`

```luau
export type Observation = {
	store: string,
	operation: Operation,
	durationMs: number,
	budgetWaitMs: number,
	budgetSleeps: number,
	retries: number,
}
```

### `core.persistence.store-host.Observer`

```luau
export type Observer = (Observation) -> ()
```

### `core.persistence.store-host.BudgetKind`

```luau
export type BudgetKind = "get" | "set" | "update"
```

### `core.persistence.store-host.QueuedWrite`

```luau
export type QueuedWrite = { id: string, storeName: string, key: string, nextAttemptAt: number }
```

### `core.persistence.store-host.Circuit`

```luau
export type Circuit = {
	success: () -> (),
	failure: (number, unknown) -> (),
	canAttempt: (number) -> boolean,
	begin: (number) -> (),
	enqueue: (
		{ storeName: string, key: string, kind: "set" | "update", payload: unknown },
		number
	) -> (boolean, string?, QueuedWrite?),
	markFailure: (string, number, unknown) -> (),
	markSuccess: (string) -> (),
	hasQueued: (string, string) -> boolean,
	isReadOnly: () -> boolean,
	list: () -> { QueuedWrite },
}
```

### `core.persistence.store-host.RawStore`

```luau
export type RawStore = {
	GetAsync: (RawStore, string, unknown?) -> unknown,
	SetAsync: (RawStore, string, unknown) -> (),
	UpdateAsync: (RawStore, string, (unknown) -> unknown) -> unknown,
}
```

### `core.persistence.store-host.RealDependencies`

```luau
export type RealDependencies = {
	raw: RawStore,
	sleep: (number) -> (),
	jitter: () -> number,
	now: () -> number,
	clock: () -> number,
	requestBudget: ((BudgetKind) -> number)?,
	waitForBudget: ((BudgetKind) -> (boolean, number?))?,
	observer: (() -> Observer?)?,
	uncachedOptions: () -> unknown,
	validUncachedOptions: (unknown) -> boolean,
}
```

### `core.persistence.store-host.MemoryStore`

```luau
export type MemoryStore = {
	name: string,
	get: (string) -> unknown,
	set: (string, unknown) -> (),
	update: (string, (unknown) -> unknown) -> unknown,
}
```

### `core.persistence.store-host.TestOptions`

```luau
export type TestOptions = { rerun: boolean?, fault: (() -> string?)? }
```

### `core.persistence.store-host.Store`

```luau
export type Store = {
	name: string,
	backend: "real" | "memory",
	get: (string) -> unknown,
	getOutcome: (string) -> Outcome,
	getUncachedOutcome: (string) -> Outcome,
	set: (string, unknown) -> Outcome,
	update: (string, (unknown) -> unknown) -> unknown,
	updateOutcome: (string, (unknown) -> unknown) -> Outcome,
	flushQueuedWrites: () -> number,
	hasPendingWrite: (string) -> boolean,
	isReadOnly: () -> boolean,
	writeBudget: (() -> number)?,
}
```

### `core.persistence.store-host.Config`

```luau
export type Config = {
	clock: () -> number,
	maxKeyBytes: number,
	maxAttempts: number,
	backoff: (number, number) -> number,
	retry: <T>(() -> (boolean, T), (number) -> (), () -> number) -> (boolean, T),
	warning: (string) -> (),
}
```

### `core.persistence.store-host.create`

```luau
function StoreHost.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
memory = function makeMemoryStore(store: MemoryStore, options: TestOptions?, observerOf: () -> Observer?): Store
real = function makeRealStore(name: string, state: unknown, circuit: Circuit, dependencies: RealDependencies): Store
drain = function drainQueuedWrites(
		flush: () -> number,
		remaining: () -> number,
		deadline: number,
		clock: () -> number,
		sleep: (number) -> ()
	): DrainOutcome
```

## `core.persistence`

[Source](../src/core/persistence.luau)

```luau
local ProfileSession = require("./persistence/profile-session")
```

```luau
local RecordStore = require("./persistence/record-store")
```

```luau
local SessionLock = require("./persistence/session-lock")
```

```luau
local StoreHost = require("./persistence/store-host")
```

### `core.persistence.ProfileSessionFlightKind`

```luau
export type ProfileSessionFlightKind = ProfileSession.FlightKind
```

### `core.persistence.ProfileSessionState`

```luau
export type ProfileSessionState = ProfileSession.State
```

### `core.persistence.ProfileSessionOutcome`

```luau
export type ProfileSessionOutcome = ProfileSession.Outcome
```

### `core.persistence.ProfileSessionConfig`

```luau
export type ProfileSessionConfig = ProfileSession.Config
```

### `core.persistence.SessionLockLockState`

```luau
export type SessionLockLockState = SessionLock.LockState
```

### `core.persistence.SessionLockAcquireResult`

```luau
export type SessionLockAcquireResult = SessionLock.AcquireResult
```

### `core.persistence.StoreHostOutcome`

```luau
export type StoreHostOutcome = StoreHost.Outcome
```

### `core.persistence.StoreHostDrainOutcome`

```luau
export type StoreHostDrainOutcome = StoreHost.DrainOutcome
```

### `core.persistence.StoreHostOperation`

```luau
export type StoreHostOperation = StoreHost.Operation
```

### `core.persistence.StoreHostObservation`

```luau
export type StoreHostObservation = StoreHost.Observation
```

### `core.persistence.StoreHostObserver`

```luau
export type StoreHostObserver = StoreHost.Observer
```

### `core.persistence.StoreHostBudgetKind`

```luau
export type StoreHostBudgetKind = StoreHost.BudgetKind
```

### `core.persistence.StoreHostQueuedWrite`

```luau
export type StoreHostQueuedWrite = StoreHost.QueuedWrite
```

### `core.persistence.StoreHostCircuit`

```luau
export type StoreHostCircuit = StoreHost.Circuit
```

### `core.persistence.StoreHostRawStore`

```luau
export type StoreHostRawStore = StoreHost.RawStore
```

### `core.persistence.StoreHostRealDependencies`

```luau
export type StoreHostRealDependencies = StoreHost.RealDependencies
```

### `core.persistence.StoreHostMemoryStore`

```luau
export type StoreHostMemoryStore = StoreHost.MemoryStore
```

### `core.persistence.StoreHostTestOptions`

```luau
export type StoreHostTestOptions = StoreHost.TestOptions
```

### `core.persistence.StoreHostStore`

```luau
export type StoreHostStore = StoreHost.Store
```

### `core.persistence.StoreHostConfig`

```luau
export type StoreHostConfig = StoreHost.Config
```

### `core.persistence.RecordStoreAccepted`

```luau
export type RecordStoreAccepted<R> = RecordStore.Accepted<R>
```

### `core.persistence.RecordStoreRefused`

```luau
export type RecordStoreRefused = RecordStore.Refused
```

### `core.persistence.RecordStoreOutcome`

```luau
export type RecordStoreOutcome<R> = RecordStore.Outcome<R>
```

### `core.persistence.RecordStoreView`

```luau
export type RecordStoreView = RecordStore.View
```

### `core.persistence.RecordStoreConfig`

```luau
export type RecordStoreConfig<R> = RecordStore.Config<R>
```

### `core.persistence.RecordStoreAPI`

```luau
export type RecordStoreAPI<R> = RecordStore.API<R>
```

### `core.persistence.RecordStoreStore`

```luau
export type RecordStoreStore = RecordStore.Store
```

### `core.persistence.RecordStoreStoreOutcome`

```luau
export type RecordStoreStoreOutcome = RecordStore.StoreOutcome
```

### `core.persistence.API`

```luau
export type API = {
	read profile_session: typeof(ProfileSession),
	read session_lock: typeof(SessionLock),
	read store_host: typeof(StoreHost),
	read record_store: typeof(RecordStore),
}
```

### `core.persistence.profile_session`

Exported value; see its declaration in [source](../src/core/persistence.luau).

### `core.persistence.record_store`

Exported value; see its declaration in [source](../src/core/persistence.luau).

### `core.persistence.session_lock`

Exported value; see its declaration in [source](../src/core/persistence.luau).

### `core.persistence.store_host`

Exported value; see its declaration in [source](../src/core/persistence.luau).

## `core.professions.crafting`

[Source](../src/core/professions/crafting.luau)

```luau
local Value = require("../../kernel/value")
```

```luau
local Skills = require("./skills")
```

```luau
local Stacks = require("../inventory/stacks")
```

```luau
local Types = require("./types")
```

### `core.professions.crafting.Plan`

```luau
export type Plan = {
	ok: boolean,
	reason: string?,
	recipe: Recipe?,
	color: string?,
}
```

### `core.professions.crafting.Outcome`

```luau
export type Outcome = {
	ok: boolean,
	reason: string?,
	state: State,
	inventory: Inventory,
	skillUp: boolean,
	color: string?,
	skill: number,
	quality: string?,
	produced: { itemId: string, quantity: number }?,
}
```

### `core.professions.crafting.Config`

```luau
export type Config = {
	core: {
		read knows: (State, string) -> boolean,
		read skillOf: (State, string) -> number,
		read colorFor: (number, Types.Thresholds) -> string?,
		read rollSkillUp: (State, string, Types.Thresholds, number) -> (State, boolean, string?),
	},
	maxStack: number,
	recipes: {
		get: (unknown) -> Recipe?,
		isGear: (Recipe) -> boolean,
		rollQuality: (string?, number?) -> string,
		qualityItemId: (string, string) -> string,
	},
}
```

### `core.professions.crafting.create`

```luau
function System.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
plan = function Crafting.plan(state: State, recipeId: unknown, inventory: Inventory, stations: { [string]: boolean }): Plan
craft = function Crafting.craft(
		state: State,
		recipeId: unknown,
		inventory: Inventory,
		stations: { [string]: boolean },
		roll: number,
		qualityRoll: number?,
		maxInventoryEntries: number?
	): Outcome
```

## `core.professions.fishing`

[Source](../src/core/professions/fishing.luau)

```luau
local Value = require("../../kernel/value")
```

```luau
local Skills = require("./skills")
```

```luau
local Types = require("./types")
```

### `core.professions.fishing.Phase`

```luau
export type Phase = "idle" | "waiting" | "bite"
```

### `core.professions.fishing.Line`

```luau
export type Line = {
	phase: Phase,
	castAt: number,
	biteAt: number,
	missAt: number,
}
```

### `core.professions.fishing.Catch`

```luau
export type Catch = {
	ok: boolean,
	reason: string?,
	state: State,
	itemId: string?,
	isFish: boolean,
	skillUp: boolean,
	color: string?,
	skill: number,
}
```

### `core.professions.fishing.Config`

```luau
export type Config = {
	core: {
		read knows: (State, string) -> boolean,
		read skillOf: (State, string) -> number,
		read colorFor: (number, Types.Thresholds) -> string?,
		read rollSkillUp: (State, string, Types.Thresholds, number) -> (State, boolean, string?),
	},
	professionId: string,
	waitMin: number,
	waitMax: number,
	biteWindow: number,
	fishTable: (string) -> { FishRow },
	junk: { FishRow },
}
```

### `core.professions.fishing.create`

```luau
function System.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
idle = function Fishing.idle(): Line
cast = function Fishing.cast(line: Line, state: State, now: number, waitRoll: number): (Line?, string?)
observe = function Fishing.observe(line: Line, now: number): Line
hook = function Fishing.hook(line: Line, now: number): (boolean, string)
pick = function Fishing.pick(zoneId: string, skill: number, roll: number): FishRow?
isJunk = function Fishing.isJunk(itemId: string): boolean
reel = function Fishing.reel(state: State, zoneId: string, rng: () -> number): Catch
```

## `core.professions.gathering`

[Source](../src/core/professions/gathering.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.professions.gathering.RealmId`

```luau
export type RealmId = string
```

### `core.professions.gathering.SpaceKind`

```luau
export type SpaceKind = "pve" | "contested"
```

### `core.professions.gathering.Phase`

```luau
export type Phase = "ready" | "gathering"
```

### `core.professions.gathering.Node`

```luau
export type Node = {
	id: string,
	materialId: string,
	spaceKind: SpaceKind,
	gatherDurationSec: number,
	respawnPeriodSec: number,
	baseYield: number,
}
```

### `core.professions.gathering.State`

```luau
export type State = {
	lastClockSec: number,
	phase: Phase,
	startedAtSec: number?,
	completesAtSec: number?,
	harvestedSlot: number?,
	claims: { [string]: number },
}
```

### `core.professions.gathering.CommandKind`

```luau
export type CommandKind = "start" | "interrupt" | "complete"
```

### `core.professions.gathering.Command`

```luau
export type Command = {
	kind: CommandKind,
	eventId: string?,
	gatheringRealmId: RealmId?,
	populationMultiplier: number?,
}
```

### `core.professions.gathering.Result`

```luau
export type Result = {
	state: State,
	phase: Phase,
	available: boolean,
	completed: boolean,
	interrupted: boolean,
	replayed: boolean,
	yieldAmount: number,
	materialId: string?,
	eventId: string?,
}
```

### `core.professions.gathering.create`

```luau
function System.create(config: {
	realms: { [string]: boolean },
	minYieldMultiplier: number,
	maxYieldMultiplier: number,
	resolveYield: (Node, unknown, unknown) -> number?,
})
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function GatheringCore.emptyState(): State
projectNode = function GatheringCore.projectNode(value: unknown): Node?
computeYield = function GatheringCore.computeYield(
		nodeValue: unknown,
		gatheringRealmIdValue: unknown,
		populationMultiplierValue: unknown
	): number?
step = function GatheringCore.step(
		previousStateValue: unknown,
		nodeValue: unknown,
		commandValue: unknown,
		nowSecValue: unknown
	): Result?
```

## `core.professions.harvest`

[Source](../src/core/professions/harvest.luau)

```luau
local Value = require("../../kernel/value")
```

```luau
local Skills = require("./skills")
```

```luau
local Types = require("./types")
```

### `core.professions.harvest.Yield`

```luau
export type Yield = { itemId: string, quantity: number }
```

### `core.professions.harvest.Outcome`

```luau
export type Outcome = {
	ok: boolean,
	reason: string?,
	state: State,
	yields: { Yield },
	skillUp: boolean,
	color: string?,
	skill: number,
}
```

### `core.professions.harvest.Config`

```luau
export type Config = {
	core: {
		read profession: (unknown) -> Skills.Profession?,
		read knows: (State, string) -> boolean,
		read skillOf: (State, string) -> number,
		read colorFor: (number, Types.Thresholds) -> string?,
		read rollSkillUp: (State, string, Types.Thresholds, number) -> (State, boolean, string?),
	},
	skinningId: string,
}
```

### `core.professions.harvest.create`

```luau
function System.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
canAttempt = function Gather.canAttempt(state: State, professionId: string, row: NodeKind | SkinRow): (boolean, string?)
harvestNode = function Gather.harvestNode(state: State, nodeKind: NodeKind, rng: () -> number): Outcome
skinCorpse = function Gather.skinCorpse(state: State, skinRow: SkinRow, rng: () -> number): Outcome
```

## `core.professions.session`

[Source](../src/core/professions/session.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.professions.session.Kind`

```luau
export type Kind = "gather" | "skin" | "craft" | "fish"
```

### `core.professions.session.Session`

```luau
export type Session = {
	kind: Kind,
	key: string,
	startedAt: number,
	endsAt: number,
	startX: number,
	startZ: number,
	startHealth: number,
}
```

### `core.professions.session.Sample`

```luau
export type Sample = {
	now: number,
	x: number,
	z: number,
	health: number,
	alive: boolean,
	inCombat: boolean,
	arrivalProtected: boolean?,
}
```

### `core.professions.session.create`

```luau
function System.create(config: { moveTolerance: number, blocked: (Kind, Sample) -> string? })
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
begin = function Session.begin(kind: Kind, key: string, durationSec: number, sample: Sample): (Session?, string?)
check = function Session.check(session: Session, sample: Sample): (string, string?)
```

## `core.professions.skills`

[Source](../src/core/professions/skills.luau)

```luau
local Value = require("../../kernel/value")
```

```luau
local RecipesTypes = require("./types")
```

### `core.professions.skills.Kind`

```luau
export type Kind = "gathering" | "primary_craft" | "secondary"
```

### `core.professions.skills.Profession`

```luau
export type Profession = {
	id: string,
	name: string,
	kind: Kind,
	primary: boolean,
	order: number,
}
```

### `core.professions.skills.State`

```luau
export type State = {
	skills: { [string]: number },
	recipes: { [string]: boolean },
	questInputs: { [string]: boolean }?,
}
```

### `core.professions.skills.Color`

```luau
export type Color = "orange" | "yellow" | "green" | "grey"
```

### `core.professions.skills.Config`

```luau
export type Config = {
	catalogue: { Profession },
	skillCap: number,
	primarySlots: number,
	startSkill: number,
	skillUpChance: { [string]: number },
	questInputs: (unknown) -> { [string]: boolean }?,
	recipes: {
		read get: (unknown) -> Recipe?,
		read forProfession: (string) -> { read [number]: Recipe },
		read forRecipeItem: (unknown) -> Recipe?,
	},
}
```

### `core.professions.skills.create`

```luau
function Skills.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
profession = function Core.profession(id: unknown): Profession?
default = function Core.default(): State
normalize = function Core.normalize(raw: unknown): State
copy = function Core.copy(state: State): State
knows = function Core.knows(state: State, professionId: string): boolean
skillOf = function Core.skillOf(state: State, professionId: string): number
primaryCount = function Core.primaryCount(state: State): number
primarySlotsFree = function Core.primarySlotsFree(state: State): number
canLearn = function Core.canLearn(state: State, professionId: unknown): (boolean, string?)
learn = function Core.learn(state: State, professionId: unknown): (State?, string?)
unlearn = function Core.unlearn(state: State, professionId: unknown): (State?, string?)
skillUpChance = function Core.skillUpChance(color: Color?): number
rollSkillUp = function Core.rollSkillUp(
		state: State,
		professionId: string,
		thresholds: Thresholds,
		roll: number
	): (State, boolean, Color?)
knownRecipes = function Core.knownRecipes(state: State, professionId: string): { Recipe }
canLearnRecipe = function Core.canLearnRecipe(state: State, recipeId: unknown, via: "trainer" | "item"): (boolean, string?)
learnRecipe = function Core.learnRecipe(state: State, recipeId: unknown, via: "trainer" | "item"): (State?, string?)
learnFromItem = function Core.learnFromItem(state: State, itemId: unknown): (State?, string?, Recipe?)
trainerRoster = function Core.trainerRoster(
		state: State,
		professionId: string
	): { { recipe: Recipe, status: string, cost: number } }
sameState = function Core.sameState(left: State, right: State): boolean
freezeState = function Core.freezeState(state: State): State
```

## `core.professions.types`

[Source](../src/core/professions/types.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.professions.types.Sustain`

```luau
export type Sustain = {
	read resource: "hp" | "mana" | "none",
	read verb: string,
	read durationSec: number,
	read fractionPerSec: number,
	read combat: boolean?,
	read buff: { slot: "food" | "elixir", durationSec: number, stats: { [string]: number } }?,
}
```

### `core.professions.types.Reagent`

```luau
export type Reagent = { read itemId: string, read quantity: number }
```

### `core.professions.types.QuestInput`

```luau
export type QuestInput = { read questId: string, read objectiveId: string, read itemId: string, read quantity: number }
```

### `core.professions.types.Thresholds`

```luau
export type Thresholds = { read orange: number, read yellow: number, read green: number, read grey: number }
```

### `core.professions.types.Source`

```luau
export type Source = string
```

### `core.professions.types.Descriptor`

```luau
export type Descriptor = {
	read kind: "gear" | "consumable" | "material",
	read name: string,
	read lore: string,
	read rarity: string,
	read slot: string?,
	read armorFamily: string?,
	read weaponFamily: string?,
	read handTopology: string?,
	read levelReq: number,
	read ladderSource: string?,
	read stack: number?,
	read sustain: Sustain?,
}
```

### `core.professions.types.Recipe`

```luau
export type Recipe = {
	read id: string,
	read realmId: string?,
	read profession: string,
	read slug: string,
	read name: string,
	read requiredSkill: number,
	read thresholds: Thresholds,
	read reagents: { Reagent },
	read output: Reagent,
	read source: Source,
	read rung: string,
	read station: string?,
	read recipeItemId: string?,
	read trainerCost: number?,
	read vendor: { price: number, stock: number }?,
	read dropBosses: { string }?,
	read dropChance: number?,
	read item: Descriptor,
	read questInputs: { QuestInput }?,
}
```

### `core.professions.types.Extra`

```luau
export type Extra = { itemId: string, chance: number, quantity: number }
```

### `core.professions.types.NodeKind`

```luau
export type NodeKind = {
	id: string,
	profession: string,
	name: string,
	itemId: string,
	requiredSkill: number,
	thresholds: Thresholds,
	minYield: number,
	maxYield: number,
	gatherSec: number,
	respawnSec: number,
	extras: { Extra },
}
```

### `core.professions.types.SkinRow`

```luau
export type SkinRow = {
	mobId: string,
	itemId: string,
	requiredSkill: number,
	thresholds: Thresholds,
	minYield: number,
	maxYield: number,
	skinSec: number,
	extras: { Extra },
}
```

### `core.professions.types.FishRow`

```luau
export type FishRow = {
	itemId: string,
	weight: number,
	requiredSkill: number,
	thresholds: Thresholds,
}
```

## `core.professions`

[Source](../src/core/professions.luau)

```luau
local Crafting = require("./professions/crafting")
```

```luau
local Fishing = require("./professions/fishing")
```

```luau
local Gathering = require("./professions/gathering")
```

```luau
local Harvest = require("./professions/harvest")
```

```luau
local Session = require("./professions/session")
```

```luau
local Skills = require("./professions/skills")
```

```luau
local Types = require("./professions/types")
```

### `core.professions.CraftingPlan`

```luau
export type CraftingPlan = Crafting.Plan
```

### `core.professions.CraftingOutcome`

```luau
export type CraftingOutcome = Crafting.Outcome
```

### `core.professions.CraftingConfig`

```luau
export type CraftingConfig = Crafting.Config
```

### `core.professions.FishingPhase`

```luau
export type FishingPhase = Fishing.Phase
```

### `core.professions.FishingLine`

```luau
export type FishingLine = Fishing.Line
```

### `core.professions.FishingCatch`

```luau
export type FishingCatch = Fishing.Catch
```

### `core.professions.FishingConfig`

```luau
export type FishingConfig = Fishing.Config
```

### `core.professions.GatheringRealmId`

```luau
export type GatheringRealmId = Gathering.RealmId
```

### `core.professions.GatheringSpaceKind`

```luau
export type GatheringSpaceKind = Gathering.SpaceKind
```

### `core.professions.GatheringPhase`

```luau
export type GatheringPhase = Gathering.Phase
```

### `core.professions.GatheringNode`

```luau
export type GatheringNode = Gathering.Node
```

### `core.professions.GatheringState`

```luau
export type GatheringState = Gathering.State
```

### `core.professions.GatheringCommandKind`

```luau
export type GatheringCommandKind = Gathering.CommandKind
```

### `core.professions.GatheringCommand`

```luau
export type GatheringCommand = Gathering.Command
```

### `core.professions.GatheringResult`

```luau
export type GatheringResult = Gathering.Result
```

### `core.professions.HarvestYield`

```luau
export type HarvestYield = Harvest.Yield
```

### `core.professions.HarvestOutcome`

```luau
export type HarvestOutcome = Harvest.Outcome
```

### `core.professions.HarvestConfig`

```luau
export type HarvestConfig = Harvest.Config
```

### `core.professions.SessionKind`

```luau
export type SessionKind = Session.Kind
```

### `core.professions.SessionSession`

```luau
export type SessionSession = Session.Session
```

### `core.professions.SessionSample`

```luau
export type SessionSample = Session.Sample
```

### `core.professions.SkillsKind`

```luau
export type SkillsKind = Skills.Kind
```

### `core.professions.SkillsProfession`

```luau
export type SkillsProfession = Skills.Profession
```

### `core.professions.SkillsState`

```luau
export type SkillsState = Skills.State
```

### `core.professions.SkillsColor`

```luau
export type SkillsColor = Skills.Color
```

### `core.professions.SkillsConfig`

```luau
export type SkillsConfig = Skills.Config
```

### `core.professions.TypesSustain`

```luau
export type TypesSustain = Types.Sustain
```

### `core.professions.TypesReagent`

```luau
export type TypesReagent = Types.Reagent
```

### `core.professions.TypesQuestInput`

```luau
export type TypesQuestInput = Types.QuestInput
```

### `core.professions.TypesThresholds`

```luau
export type TypesThresholds = Types.Thresholds
```

### `core.professions.TypesSource`

```luau
export type TypesSource = Types.Source
```

### `core.professions.TypesDescriptor`

```luau
export type TypesDescriptor = Types.Descriptor
```

### `core.professions.TypesRecipe`

```luau
export type TypesRecipe = Types.Recipe
```

### `core.professions.TypesExtra`

```luau
export type TypesExtra = Types.Extra
```

### `core.professions.TypesNodeKind`

```luau
export type TypesNodeKind = Types.NodeKind
```

### `core.professions.TypesSkinRow`

```luau
export type TypesSkinRow = Types.SkinRow
```

### `core.professions.TypesFishRow`

```luau
export type TypesFishRow = Types.FishRow
```

### `core.professions.API`

```luau
export type API = {
	read crafting: typeof(Crafting),
	read fishing: typeof(Fishing),
	read gathering: typeof(Gathering),
	read harvest: typeof(Harvest),
	read session: typeof(Session),
	read skills: typeof(Skills),
	read types: typeof(Types),
}
```

### `core.professions.crafting`

Exported value; see its declaration in [source](../src/core/professions.luau).

### `core.professions.fishing`

Exported value; see its declaration in [source](../src/core/professions.luau).

### `core.professions.gathering`

Exported value; see its declaration in [source](../src/core/professions.luau).

### `core.professions.harvest`

Exported value; see its declaration in [source](../src/core/professions.luau).

### `core.professions.session`

Exported value; see its declaration in [source](../src/core/professions.luau).

### `core.professions.skills`

Exported value; see its declaration in [source](../src/core/professions.luau).

### `core.professions.types`

Exported value; see its declaration in [source](../src/core/professions.luau).

## `core.progression.actionbar`

[Source](../src/core/progression/actionbar.luau)

```luau
local SocialShape = require("../social/shape")
```

### `core.progression.actionbar.State`

```luau
export type State = { custom: boolean, level: number, slots: { [string]: string } }
```

### `core.progression.actionbar.Context`

```luau
export type Context = {
	authored: { [number]: string },
	owned: { [string]: boolean },
	required: { [string]: number },
	level: number,
	carried: { [string]: boolean }?,
}
```

### `core.progression.actionbar.Layout`

```luau
export type Layout = { [number]: string }
```

### `core.progression.actionbar.Intent`

```luau
export type Intent = {
	op: string?,
	slot: number?,
	from: number?,
	actionId: string?,
}
```

### `core.progression.actionbar.Config`

```luau
export type Config = { barSize: number, barCount: number, maxActionId: number, maxLevel: number, itemPrefix: string }
```

### `core.progression.actionbar.actionbar`

```luau
function System.actionbar(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
BAR_SIZE = BAR_SIZE
BAR_COUNT = BAR_COUNT
SLOT_COUNT = SLOT_COUNT
MAX_WIRE_BYTES = MAX_WIRE_BYTES
itemId = function itemId(actionId: string): string?
itemAction = function itemAction(id: string): string
default = function default(): State
copy = function copy(state: State): State
contextFor = function contextFor(loadout: unknown, level: unknown, items: { [string]: boolean }?): Context
effective = function effective(state: unknown, ctx: Context): Layout
normalize = function normalize(raw: unknown, ctx: Context): State
project = function project(raw: unknown): State?
assign = function assign(state: unknown, ctx: Context, slot: unknown, abilityId: unknown): (State?, string?)
swap = function swap(state: unknown, ctx: Context, first: unknown, second: unknown): (State?, string?)
clear = function clear(state: unknown, ctx: Context, slot: unknown): (State?, string?)
apply = function apply(state: unknown, ctx: Context, intent: unknown): (State?, string?)
placed = function placed(layout: Layout, abilityId: string): number?
encodeWire = function encodeWire(layout: Layout): string
decodeWire = function decodeWire(wire: unknown, ctx: Context): Layout?
slotFor = function slotFor(position: unknown, layer: unknown): number?
resolvePress = function resolvePress(layout: Layout, position: unknown, layer: unknown): string?
layerEntries = function layerEntries(
		layout: Layout,
		layer: unknown
	): { { position: number, slot: number, actionId: string } }
```

## `core.progression.consumables`

[Source](../src/core/progression/consumables.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.progression.consumables.Buff`

```luau
export type Buff = { read slot: "food" | "elixir", read durationSec: number, read stats: { [string]: number } }
```

### `core.progression.consumables.Item`

```luau
export type Item = {
	read resource: "hp" | "mana" | "none",
	read verb: string,
	read durationSec: number,
	read fractionPerSec: number,
	read combat: boolean?,
	read buff: Buff?,
}
```

### `core.progression.consumables.Channel`

```luau
export type Channel = { itemId: string, startedAt: number, tickedAt: number, endsAt: number, x: number, z: number }
```

### `core.progression.consumables.ActiveBuff`

```luau
export type ActiveBuff = { itemId: string, endsAt: number, stats: { [string]: number } }
```

### `core.progression.consumables.State`

```luau
export type State = {
	serial: number,
	cue: string,
	hp: Channel?,
	mana: Channel?,
	hpGained: number?,
	manaGained: number?,
	food: ActiveBuff?,
	elixir: ActiveBuff?,
}
```

### `core.progression.consumables.Actor`

```luau
export type Actor = {
	id: string,
	classId: string?,
	hp: number,
	maxHp: number?,
	mana: number?,
	maxMana: number?,
	pos: { x: number, y: number?, z: number },
	sustenance: State?,
	sustenanceGeneration: number?,
	fights: { [string]: number }?,
	pendingControl: unknown?,
	gcdRemainingSec: number?,
	crowdControls: { [string]: { remainingSec: number, totalSec: number? } }?,
}
```

### `core.progression.consumables.ActorView`

```luau
export type ActorView = {
	read id: string,
	read classId: string?,
	read hp: number,
	read maxHp: number?,
	read mana: number?,
	read maxMana: number?,
	read pos: { read x: number, read y: number?, read z: number },
	read sustenance: State?,
	read sustenanceGeneration: number?,
	read fights: { read [string]: number }?,
	read pendingControl: unknown?,
	read gcdRemainingSec: number?,
	read crowdControls: { read [string]: { read remainingSec: number, read totalSec: number? } }?,
}
```

### `core.progression.consumables.Mob`

```luau
export type Mob = { read hp: number, read targetActorId: string?, read threat: { read [string]: number }? }
```

### `core.progression.consumables.Config`

```luau
export type Config = {
	maxBuffStat: number,
	maxBuffSeconds: number,
	movementToleranceSquared: number,
	drinksMana: (ActorView) -> boolean,
	consumedCue: string,
	channelCue: string,
	finishedCue: string,
	interruptedCue: (string) -> string,
}
```

### `core.progression.consumables.create`

```luau
function Consumables.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
register = function Core.register(itemId: unknown, raw: unknown): boolean
registerAll = function Core.registerAll(map: unknown): number
item = function Core.item(itemId: unknown): Item?
copy = function Core.copy(state: State?): State
eligibility = function Core.eligibility(actor: ActorView?, mobs: { read [string]: Mob }?, item: Item?): string?
begin = function Core.begin(
		state: State?,
		actor: ActorView,
		mobs: { read [string]: Mob }?,
		itemId: unknown,
		rawSerial: unknown,
		rawNow: unknown
	): (State?, string?)
interrupt = function Core.interrupt(state: State?, reason: string): State?
interruptActor = function Core.interruptActor(actor: { sustenanceGeneration: number?, sustenance: State? }, reason: string)
activeStats = function Core.activeStats(state: State?, now: number): { [string]: number }
advance = function Core.advance(
		state: State?,
		actor: ActorView,
		mobs: { read [string]: Mob }?,
		now: number
	): (State?, number, number)
```

## `core.progression.grants`

[Source](../src/core/progression/grants.luau)

```luau
local SocialShape = require("../social/shape")
```

### `core.progression.grants.Grant`

```luau
export type Grant = {
	abilityId: string,
	level: number,
}
```

### `core.progression.grants.GrantIndex`

```luau
export type GrantIndex = { [string]: number }
```

### `core.progression.grants.ProductionRegistry`

```luau
export type ProductionRegistry = { [string]: { Grant } }
```

### `core.progression.grants.ProductionRegistryResult`

```luau
export type ProductionRegistryResult = {
	ok: boolean,
	registry: ProductionRegistry?,
	problems: { string },
}
```

### `core.progression.grants.Config`

```luau
export type Config = { slotCount: number, maxLevel: number, kits: ProductionRegistry }
```

### `core.progression.grants.grants`

```luau
function System.grants(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
SLOT_COUNT = SLOT_COUNT
MAX_LEVEL = MAX_LEVEL
CLASS_KITS = CLASS_KITS
forClass = function forClass(classId: string): { Grant }?
indexOf = function indexOf(grants: { Grant }): GrantIndex
gateFor = function gateFor(index: GrantIndex, abilityId: string): number?
isGranted = function isGranted(index: GrantIndex, abilityId: string, level: number): boolean
grantedIds = function grantedIds(grants: { Grant }, level: number): { string }
problemsFor = function problemsFor(grants: { Grant }, curve: string): { string }
problemsForClassSchema = function problemsForClassSchema(grants: { Grant }): { string }
compileProductionRegistry = function compileProductionRegistry(
		authoritiesValue: unknown,
		expectedClassIds: { string }
	): ProductionRegistryResult
```

## `core.progression.hearth`

[Source](../src/core/progression/hearth.luau)

```luau
local SocialShape = require("../social/shape")
```

### `core.progression.hearth.Destination`

```luau
export type Destination = { npcId: string, name: string }
```

### `core.progression.hearth.Bind`

```luau
export type Bind = { zoneId: string, npcId: string }
```

### `core.progression.hearth.State`

```luau
export type State = { bind: Bind?, hearthReadyAt: number, returningTo: Bind? }
```

### `core.progression.hearth.BoundState`

```luau
export type BoundState = { bind: Bind, hearthReadyAt: number, returningTo: Bind? }
```

### `core.progression.hearth.Config`

```luau
export type Config = {
	destinations: { [string]: { Destination } },
	homeZones: { [string]: string },
	cooldownSec: number,
	bindRange: number,
}
```

### `core.progression.hearth.hearth`

```luau
function System.hearth(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
destination = function Core.destination(zoneId: unknown, npcId: unknown): Destination?
homeZone = function Core.homeZone(faction: unknown): string?
normalize = function Core.normalize(raw: unknown): State
bind = function Core.bind(
		state: unknown,
		zoneId: unknown,
		npcId: unknown,
		distance: unknown,
		alive: boolean
	): (BoundState?, string?)
hearth = function Core.hearth(state: unknown, now: unknown, alive: boolean, inCombat: boolean): (BoundState?, string?)
arrived = function Core.arrived(state: unknown): State
```

## `core.progression.levels`

[Source](../src/core/progression/levels.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.progression.levels.CurveRow`

```luau
export type CurveRow = { level: number, totalXp: number }
```

### `core.progression.levels.Curve`

```luau
export type Curve = { id: string, maxLevel: number, rows: { CurveRow } }
```

### `core.progression.levels.Config`

```luau
export type Config = { curve: unknown, curveId: string, maxLevel: number }
```

### `core.progression.levels.Progression`

```luau
export type Progression = {
	read xp: number?,
	read level: number?,
}
```

### `core.progression.levels.Snapshot`

```luau
export type Snapshot = {
	level: number,
	experience: number,
}
```

### `core.progression.levels.RewardProjection`

```luau
export type RewardProjection = {
	previousLevel: number,
	currentLevel: number,
	leveledUp: boolean,
}
```

### `core.progression.levels.levels`

```luau
function System.levels(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
levelForXp = function levelForXp(xp: number): number
xpForLevel = function thresholdForLevel(level: number): number
resolveLevel = function resolveLevel(rows: { CurveRow }, maxLevel: number, xp: number): number
validateCurve = function validateCurve(candidate: unknown): Curve
awardXp = function awardXp<T>(progression: T & Progression, amount: number): T & Progression
xpBracket = function xpBracket(xp: number): (number, number)
rewardProjection = function rewardProjection(xpAfter: number, rewardXp: number): RewardProjection
snapshotFromValues = function snapshotFromValues(_level: unknown, experience: unknown): Snapshot
MAX_LEVEL = MAX_LEVEL
```

## `core.progression.recovery`

[Source](../src/core/progression/recovery.luau)

```luau
local SocialShape = require("../social/shape")
```

### `core.progression.recovery.Point`

```luau
export type Point = { x: number, y: number, z: number }
```

### `core.progression.recovery.Cost`

```luau
export type Cost = { items: number, currency: number, experience: number, durability: number, delaySec: number }
```

### `core.progression.recovery.Death`

```luau
export type Death = {
	generation: number,
	phase: "dead" | "released" | "resolved",
	cause: string,
	zoneId: string,
	corpse: Point,
	anchor: Point,
	cost: Cost,
}
```

### `core.progression.recovery.Position`

```luau
export type Position<Travel> = {
	x: number,
	y: number,
	z: number,
	yaw: number,
	saved: boolean,
	recoveryZoneId: string?,
	travel: Travel?,
}
```

### `core.progression.recovery.AnchoredPosition`

```luau
export type AnchoredPosition = Raw & {
	x: number,
	y: number,
	z: number,
	yaw: number,
	saved: boolean,
	recoveryZoneId: string,
	travel: unknown,
}
```

### `core.progression.recovery.Config`

```luau
export type Config = { coordinateLimit: number, lowHealthRatio: number, defaultCause: string }
```

### `core.progression.recovery.recovery`

```luau
function System.recovery(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
encodeEcho = function encodeEcho(point: Point): string
decodeEcho = function decodeEcho(value: unknown): Point?
lowHealth = function lowHealth(hp: number, maxHp: number): boolean
echoDistance = function echoDistance(position: Point, echo: Point): number
die = function die(
		previous: Death?,
		cause: string,
		zoneId: string,
		corpse: Point,
		anchor: Point,
		delaySec: number
	): Death?
release = function release(death: Death, generation: number): Death?
recover = function recover(death: Death, generation: number): (Death?, Point?)
anchoredLastPosition = function anchoredLastPosition(current: unknown, death: Death): Raw
anchorPosition = function anchorPosition<Travel>(current: Position<Travel>, death: Death): Position<Travel>
```

## `core.progression.reputation`

[Source](../src/core/progression/reputation.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.progression.reputation.EventKind`

```luau
export type EventKind = string
```

### `core.progression.reputation.Event`

```luau
export type Event = {
	eventId: string,
	kind: EventKind,
	accountId: string,
	realmId: string,
	seasonId: string,
	units: number,
	at: number,
}
```

### `core.progression.reputation.State`

```luau
export type State = {
	events: { Event },
}
```

### `core.progression.reputation.ApplyResult`

```luau
export type ApplyResult = {
	state: State,
	replayed: boolean,
	points: number,
}
```

### `core.progression.reputation.Ladder`

```luau
export type Ladder = {
	seasonId: string,
	thresholds: { number },
	pointsPerUnit: { [string]: number },
	rankNames: { [string]: { string } },
}
```

### `core.progression.reputation.Standing`

```luau
export type Standing = {
	accountId: string,
	realmId: string,
	seasonId: string,
	points: number,
	rank: number,
	rankName: string?,
	nextRankAt: number?,
	pointsToNextRank: number?,
	lifetimePoints: number,
}
```

### `core.progression.reputation.Config`

```luau
export type Config = {
	maxText: number,
	maxAt: number,
	maxUnits: number,
	maxPointsPerUnit: number,
	maxThreshold: number,
	kinds: { [string]: boolean },
	realms: { [string]: boolean },
	increasingIncrements: boolean,
	firstGrantReachesRank: boolean,
}
```

### `core.progression.reputation.create`

```luau
function Reputation.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function Ledger.emptyState(): State
projectEvent = function Ledger.projectEvent(value: unknown): (Event?, string?)
projectState = function Ledger.projectState(value: unknown): (State?, string?)
projectLadder = function Ledger.projectLadder(value: unknown): (Ladder?, string?)
pointsFor = function Ledger.pointsFor(ladder: Ladder, kind: EventKind, units: number): number
rankFor = function Ledger.rankFor(ladderValue: unknown, pointsValue: unknown): (number?, string?)
apply = function Ledger.apply(stateValue: unknown, eventValue: unknown, ladderValue: unknown): (ApplyResult?, string?)
standings = function Ledger.standings(stateValue: unknown, ladderValue: unknown): ({ Standing }?, string?)
```

## `core.progression.season`

[Source](../src/core/progression/season.luau)

```luau
local Read = require("../internal/season-read")
```

```luau
local SocialShape = require("../social/shape")
```

### `core.progression.season.Event`

```luau
export type Event = Read.Event
```

### `core.progression.season.State`

```luau
export type State = Read.State
```

### `core.progression.season.Result`

```luau
export type Result = Read.Result
```

### `core.progression.season.PlaySource`

```luau
export type PlaySource = Read.PlaySource
```

### `core.progression.season.Objective`

```luau
export type Objective = Read.Objective
```

### `core.progression.season.Reward`

```luau
export type Reward = Read.Reward
```

### `core.progression.season.AuthoredDefinition`

```luau
export type AuthoredDefinition = Read.AuthoredDefinition
```

### `core.progression.season.Definition`

```luau
export type Definition = Read.Definition
```

### `core.progression.season.ProjectionObjective`

```luau
export type ProjectionObjective = Read.ProjectionObjective
```

### `core.progression.season.Projection`

```luau
export type Projection = Read.Projection
```

### `core.progression.season.Config`

```luau
export type Config = Read.Config
```

### `core.progression.season.season`

```luau
function System.season(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
definition = function SeasonTrackCore.definition(value: unknown): (Definition?, string?)
emptyState = function SeasonTrackCore.emptyState(track: { seasonId: string, endsAtSec: number }): State?
projectState = function SeasonTrackCore.projectState(value: unknown): State?
apply = function SeasonTrackCore.apply(previous: unknown, track: Definition, eventValue: unknown): Result
claim = function SeasonTrackCore.claim(previous: unknown, track: Definition, tierValue: unknown): Result
projection = function SeasonTrackCore.projection(value: unknown, track: Definition, nowSec: number): Projection?
projectTracks = function SeasonTrackCore.projectTracks(value: unknown): { [string]: State }?
recordIn = function SeasonTrackCore.recordIn(
		tracksValue: unknown,
		track: Definition,
		event: unknown
	): ({ [string]: State }?, Result)
claimIn = function SeasonTrackCore.claimIn(
		tracksValue: unknown,
		track: Definition,
		tier: unknown
	): ({ [string]: State }?, Result)
projectionIn = function SeasonTrackCore.projectionIn(tracksValue: unknown, track: Definition, nowSec: number): Projection?
```

## `core.progression.settlement`

[Source](../src/core/progression/settlement.luau)

```luau
local Run = require("../quest/run")
```

```luau
local Value = require("../../kernel/value")
```

### `core.progression.settlement.RewardReceipt`

```luau
export type RewardReceipt<Q> = {
	requestFingerprint: string,
	runId: string,
	roleId: string,
	itemId: string,
	quality: Q,
	clearNumber: number,
}
```

### `core.progression.settlement.RewardHistory`

```luau
export type RewardHistory<Q> = {
	schemaVersion: number,
	expeditionId: string,
	characterId: string,
	revision: number,
	eligibleClears: number,
	receipts: { [string]: RewardReceipt<Q> },
	rewardedRuns: { [string]: string },
}
```

### `core.progression.settlement.RewardRequest`

```luau
export type RewardRequest = {
	transactionId: string,
	expectedRevision: number,
	characterId: string,
	roleId: string,
}
```

### `core.progression.settlement.RewardGrant`

```luau
export type RewardGrant<Q> = {
	transactionId: string,
	itemId: string,
	quality: Q,
	clearNumber: number,
	roleUpgrade: boolean,
}
```

### `core.progression.settlement.RewardApplied`

```luau
export type RewardApplied<S, Q> = {
	ok: true,
	history: RewardHistory<Q>,
	personalState: S,
	reward: RewardGrant<Q>,
	replayed: boolean,
}
```

### `core.progression.settlement.RewardRejected`

```luau
export type RewardRejected<S, Q> = {
	ok: false,
	history: RewardHistory<Q>?,
	personalState: S?,
	reason: string,
}
```

### `core.progression.settlement.RewardResult`

```luau
export type RewardResult<S, Q> = RewardApplied<S, Q> | RewardRejected<S, Q>
```

### `core.progression.settlement.GrantResult`

```luau
export type GrantResult<S> = { ok: true, state: S, replayed: boolean } | { ok: false, reason: string }
```

### `core.progression.settlement.Config`

```luau
export type Config<P, S, C, Q> = {
	readPackage: (unknown) -> P?,
	packageId: (P) -> string,
	readRunState: (unknown, P) -> RunState?,
	copyPersonalState: (unknown) -> S?,
	readQuality: (unknown) -> Q?,
	roleUpgrade: (Q) -> boolean,
	knownRole: (P, string) -> boolean,
	rewardForClear: (P, string, number) -> RewardGrant<Q>?,
	hasReceipt: (S, string) -> boolean,
	grant: (S, string, string, C) -> GrantResult<S>,
}
```

### `core.progression.settlement.settlement`

```luau
function System.settlement<P, S, C, Q>(config: Config<P, S, C, Q>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyRewardHistory = function emptyRewardHistory(expeditionId: unknown, characterId: unknown): RewardHistory<Q>?
applyPersonalReward = function applyPersonalReward(
		packageValue: unknown,
		runStateValue: unknown,
		historyValue: unknown,
		personalStateValue: unknown,
		catalogs: C,
		requestValue: unknown
	): RewardResult<S, Q>
```

## `core.progression.standing-credit`

[Source](../src/core/progression/standing-credit.luau)

### `core.progression.standing-credit.Outcome`

```luau
export type Outcome = {
	read ok: boolean,
	read reason: string?,
	read deferred: boolean?,
	read idle: boolean?,
	read characterId: string?,
	read standing: number?,
	read retryable: boolean?,
}
```

### `core.progression.standing-credit.Config`

```luau
export type Config = {
	clock: () -> number,
	intervalSec: number,
	maxPoints: number,
	capacity: number,
	authority: () -> boolean,
	writeReady: () -> boolean,
	read: () -> { [string]: number },
	validId: (string) -> boolean,
}
```

### `core.progression.standing-credit.create`

```luau
function Credit.create(config: Config)
```

## `core.progression.talent-ranks`

[Source](../src/core/progression/talent-ranks.luau)

```luau
local Talents = require("./talents")
```

### `core.progression.talent-ranks.Loadout`

```luau
export type Loadout = Talents.Loadout
```

### `core.progression.talent-ranks.Result`

```luau
export type Result = Talents.Result
```

### `core.progression.talent-ranks.Node`

```luau
export type Node = { read id: string, read lineId: string, read tier: number, read ranks: number }
```

### `core.progression.talent-ranks.Tier`

```luau
export type Tier = { read tier: number, read gate: number, read costPerRank: number }
```

### `core.progression.talent-ranks.Line`

```luau
export type Line = { read id: string }
```

### `core.progression.talent-ranks.Spec`

```luau
export type Spec = { read class: string, read lines: List<Line>, read tiers: List<Tier>, read nodes: List<Node> }
```

### `core.progression.talent-ranks.Bucket`

```luau
export type Bucket = { ranks: { [string]: number }, respecCount: number }
```

### `core.progression.talent-ranks.FULL_RANK`

Exported value; see its declaration in [source](../src/core/progression/talent-ranks.luau).

### `core.progression.talent-ranks.INVALID_STATE`

Exported value; see its declaration in [source](../src/core/progression/talent-ranks.luau).

### `core.progression.talent-ranks.NO_POINTS`

Exported value; see its declaration in [source](../src/core/progression/talent-ranks.luau).

### `core.progression.talent-ranks.TIER_LOCKED`

Exported value; see its declaration in [source](../src/core/progression/talent-ranks.luau).

### `core.progression.talent-ranks.UNKNOWN_TALENT`

Exported value; see its declaration in [source](../src/core/progression/talent-ranks.luau).

### `core.progression.talent-ranks.addRank`

```luau
function addRank(
	loadout: Talents.Loadout?,
	specs: List<Spec>,
	role: string,
	points: number,
	talentId: string
): Talents.Result
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
ok = true
state = nextLoadout
reason = nil
```

### `core.progression.talent-ranks.availablePoints`

```luau
function availablePoints(loadout: Talents.Loadout?, specs: List<Spec>, role: string, points: number): number
```

### `core.progression.talent-ranks.bucketOf`

```luau
function bucketOf(loadout: Talents.Loadout?, role: string): Bucket
```

### `core.progression.talent-ranks.rankRefusal`

```luau
function rankRefusal(
	loadout: Talents.Loadout?,
	specs: List<Spec>,
	role: string,
	points: number,
	talentId: string
): string?
```

### `core.progression.talent-ranks.respecRole`

```luau
function respecRole(loadout: Talents.Loadout?, specs: List<Spec>, role: string): Talents.Result
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
ok = true
state = nextLoadout
reason = nil
```

### `core.progression.talent-ranks.spendByLine`

```luau
function spendByLine(spec: Spec, ranks: { [string]: number }, belowTier: number?): { [string]: number }
```

### `core.progression.talent-ranks.spentPoints`

```luau
function spentPoints(loadout: Talents.Loadout?, specs: List<Spec>, role: string): number
```

### `core.progression.talent-ranks.stateProblem`

```luau
function stateProblem(spec: Spec, bucket: Bucket, points: number): string?
```

## `core.progression.talents`

[Source](../src/core/progression/talents.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.progression.talents.State`

```luau
export type State = {
	classId: string,
	revision: number,
	ranks: { [string]: number },
	respecCount: number,
}
```

### `core.progression.talents.Loadout`

```luau
export type Loadout = { roles: { [string]: { ranks: { [string]: number }, respecCount: number } } }
```

### `core.progression.talents.Intent`

```luau
export type Intent =
	{ kind: "view" }
	| { kind: "select", revision: number, talentId: string }
	| { kind: "respec", revision: number }
```

### `core.progression.talents.Result`

```luau
export type Result = { ok: boolean, state: Loadout, reason: string? }
```

### `core.progression.talents.change`

```luau
function System.change(
	state: State,
	intent: Intent,
	admission: (true | string)?,
	advance: (Loadout, Intent) -> Result
): (State?, string?)
```

### `core.progression.talents.decodeIntent`

```luau
function System.decodeIntent(value: unknown): (Intent?, string?)
```

### `core.progression.talents.default`

```luau
function System.default(classId: string): State
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
classId = classId
revision = 0
ranks = {}
respecCount = 0
```

### `core.progression.talents.fromLoadout`

```luau
function System.fromLoadout(classId: string, revision: number, loadout: Loadout): State
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
classId = classId
revision = revision
ranks = table.clone(bucket.ranks)
respecCount = bucket.respecCount
```

### `core.progression.talents.rules`

```luau
function System.rules<R, C>(runtimeClass: (R) -> string, compile: (Loadout, string, number, R) -> (C?, string?))
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
normalize = function Core.normalize(raw: unknown, classId: string, level: number, runtime: R?): (State?, string?, C?)
load = function Core.load(raw: unknown, classId: string, level: number, runtime: R?): (State?, string?)
```

### `core.progression.talents.toLoadout`

```luau
function System.toLoadout(state: State): Loadout
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
roles = { [state.classId] = { ranks = table.clone(state.ranks), respecCount = state.respecCount } }
```

## `core.progression.tracking`

[Source](../src/core/progression/tracking.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.progression.tracking.Config`

```luau
export type Config = { statuses: { [string]: boolean } }
```

### `core.progression.tracking.tracking`

```luau
function System.tracking(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
canTrack = function canTrack(progress: unknown): boolean
```

## `core.progression.transactions`

[Source](../src/core/progression/transactions.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.progression.transactions.CollectionSet`

```luau
export type CollectionSet = { [string]: boolean }
```

### `core.progression.transactions.Outcome`

```luau
export type Outcome = "committed" | "replayed" | "rejected"
```

### `core.progression.transactions.Result`

```luau
export type Result<T> = {
	state: T,
	outcome: Outcome,
	reason: string?,
}
```

### `core.progression.transactions.Config`

```luau
export type Config<T> = {
	ledgerPrefix: string,
	orderPrefix: string,
	maxTransactionId: number,
	maxRecords: number,
	copy: (T) -> T,
	collections: (T) -> CollectionSet?,
	withCollections: (T, CollectionSet) -> T,
	pinned: (T, string) -> boolean,
}
```

### `core.progression.transactions.transactions`

```luau
function System.transactions<T>(config: Config<T>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
LEDGER_PREFIX = LEDGER_PREFIX
MAX_TRANSACTION_ID = MAX_TRANSACTION_ID
MAX_RECORDS = MAX_RECORDS
Reason = Reason
ledgerKey = function ledgerKey(transactionId: unknown): string?
isRecorded = function isRecorded(collections: unknown, transactionId: unknown): boolean
recordedKeys = function recordedKeys(collections: CollectionSet): { string }
commit = function commit(profile: T, transactionId: unknown, effect: (T) -> (T?, string?)): Result<T>
```

## `core.progression`

[Source](../src/core/progression.luau)

```luau
local Actionbar = require("./progression/actionbar")
```

```luau
local Consumables = require("./progression/consumables")
```

```luau
local Grants = require("./progression/grants")
```

```luau
local Hearth = require("./progression/hearth")
```

```luau
local Levels = require("./progression/levels")
```

```luau
local Recovery = require("./progression/recovery")
```

```luau
local Reputation = require("./progression/reputation")
```

```luau
local Season = require("./progression/season")
```

```luau
local Settlement = require("./progression/settlement")
```

```luau
local StandingCredit = require("./progression/standing-credit")
```

```luau
local TalentRanks = require("./progression/talent-ranks")
```

```luau
local Talents = require("./progression/talents")
```

```luau
local Tracking = require("./progression/tracking")
```

```luau
local Transactions = require("./progression/transactions")
```

### `core.progression.ActionbarState`

```luau
export type ActionbarState = Actionbar.State
```

### `core.progression.ActionbarContext`

```luau
export type ActionbarContext = Actionbar.Context
```

### `core.progression.ActionbarLayout`

```luau
export type ActionbarLayout = Actionbar.Layout
```

### `core.progression.ActionbarIntent`

```luau
export type ActionbarIntent = Actionbar.Intent
```

### `core.progression.ActionbarConfig`

```luau
export type ActionbarConfig = Actionbar.Config
```

### `core.progression.ConsumablesBuff`

```luau
export type ConsumablesBuff = Consumables.Buff
```

### `core.progression.ConsumablesItem`

```luau
export type ConsumablesItem = Consumables.Item
```

### `core.progression.ConsumablesChannel`

```luau
export type ConsumablesChannel = Consumables.Channel
```

### `core.progression.ConsumablesActiveBuff`

```luau
export type ConsumablesActiveBuff = Consumables.ActiveBuff
```

### `core.progression.ConsumablesState`

```luau
export type ConsumablesState = Consumables.State
```

### `core.progression.ConsumablesActor`

```luau
export type ConsumablesActor = Consumables.Actor
```

### `core.progression.ConsumablesActorView`

```luau
export type ConsumablesActorView = Consumables.ActorView
```

### `core.progression.ConsumablesMob`

```luau
export type ConsumablesMob = Consumables.Mob
```

### `core.progression.ConsumablesConfig`

```luau
export type ConsumablesConfig = Consumables.Config
```

### `core.progression.GrantsGrant`

```luau
export type GrantsGrant = Grants.Grant
```

### `core.progression.GrantsGrantIndex`

```luau
export type GrantsGrantIndex = Grants.GrantIndex
```

### `core.progression.GrantsProductionRegistry`

```luau
export type GrantsProductionRegistry = Grants.ProductionRegistry
```

### `core.progression.GrantsProductionRegistryResult`

```luau
export type GrantsProductionRegistryResult = Grants.ProductionRegistryResult
```

### `core.progression.GrantsConfig`

```luau
export type GrantsConfig = Grants.Config
```

### `core.progression.HearthDestination`

```luau
export type HearthDestination = Hearth.Destination
```

### `core.progression.HearthBind`

```luau
export type HearthBind = Hearth.Bind
```

### `core.progression.HearthState`

```luau
export type HearthState = Hearth.State
```

### `core.progression.HearthBoundState`

```luau
export type HearthBoundState = Hearth.BoundState
```

### `core.progression.HearthConfig`

```luau
export type HearthConfig = Hearth.Config
```

### `core.progression.LevelsCurveRow`

```luau
export type LevelsCurveRow = Levels.CurveRow
```

### `core.progression.LevelsCurve`

```luau
export type LevelsCurve = Levels.Curve
```

### `core.progression.LevelsConfig`

```luau
export type LevelsConfig = Levels.Config
```

### `core.progression.LevelsProgression`

```luau
export type LevelsProgression = Levels.Progression
```

### `core.progression.LevelsSnapshot`

```luau
export type LevelsSnapshot = Levels.Snapshot
```

### `core.progression.LevelsRewardProjection`

```luau
export type LevelsRewardProjection = Levels.RewardProjection
```

### `core.progression.RecoveryPoint`

```luau
export type RecoveryPoint = Recovery.Point
```

### `core.progression.RecoveryCost`

```luau
export type RecoveryCost = Recovery.Cost
```

### `core.progression.RecoveryDeath`

```luau
export type RecoveryDeath = Recovery.Death
```

### `core.progression.RecoveryPosition`

```luau
export type RecoveryPosition<Travel> = Recovery.Position<Travel>
```

### `core.progression.RecoveryAnchoredPosition`

```luau
export type RecoveryAnchoredPosition = Recovery.AnchoredPosition
```

### `core.progression.RecoveryConfig`

```luau
export type RecoveryConfig = Recovery.Config
```

### `core.progression.ReputationEventKind`

```luau
export type ReputationEventKind = Reputation.EventKind
```

### `core.progression.ReputationEvent`

```luau
export type ReputationEvent = Reputation.Event
```

### `core.progression.ReputationState`

```luau
export type ReputationState = Reputation.State
```

### `core.progression.ReputationApplyResult`

```luau
export type ReputationApplyResult = Reputation.ApplyResult
```

### `core.progression.ReputationLadder`

```luau
export type ReputationLadder = Reputation.Ladder
```

### `core.progression.ReputationStanding`

```luau
export type ReputationStanding = Reputation.Standing
```

### `core.progression.ReputationConfig`

```luau
export type ReputationConfig = Reputation.Config
```

### `core.progression.SeasonEvent`

```luau
export type SeasonEvent = Season.Event
```

### `core.progression.SeasonState`

```luau
export type SeasonState = Season.State
```

### `core.progression.SeasonResult`

```luau
export type SeasonResult = Season.Result
```

### `core.progression.SeasonPlaySource`

```luau
export type SeasonPlaySource = Season.PlaySource
```

### `core.progression.SeasonObjective`

```luau
export type SeasonObjective = Season.Objective
```

### `core.progression.SeasonReward`

```luau
export type SeasonReward = Season.Reward
```

### `core.progression.SeasonAuthoredDefinition`

```luau
export type SeasonAuthoredDefinition = Season.AuthoredDefinition
```

### `core.progression.SeasonDefinition`

```luau
export type SeasonDefinition = Season.Definition
```

### `core.progression.SeasonProjectionObjective`

```luau
export type SeasonProjectionObjective = Season.ProjectionObjective
```

### `core.progression.SeasonProjection`

```luau
export type SeasonProjection = Season.Projection
```

### `core.progression.SeasonConfig`

```luau
export type SeasonConfig = Season.Config
```

### `core.progression.SettlementRewardReceipt`

```luau
export type SettlementRewardReceipt<Q> = Settlement.RewardReceipt<Q>
```

### `core.progression.SettlementRewardHistory`

```luau
export type SettlementRewardHistory<Q> = Settlement.RewardHistory<Q>
```

### `core.progression.SettlementRewardRequest`

```luau
export type SettlementRewardRequest = Settlement.RewardRequest
```

### `core.progression.SettlementRewardGrant`

```luau
export type SettlementRewardGrant<Q> = Settlement.RewardGrant<Q>
```

### `core.progression.SettlementRewardApplied`

```luau
export type SettlementRewardApplied<S, Q> = Settlement.RewardApplied<S, Q>
```

### `core.progression.SettlementRewardRejected`

```luau
export type SettlementRewardRejected<S, Q> = Settlement.RewardRejected<S, Q>
```

### `core.progression.SettlementRewardResult`

```luau
export type SettlementRewardResult<S, Q> = Settlement.RewardResult<S, Q>
```

### `core.progression.SettlementGrantResult`

```luau
export type SettlementGrantResult<S> = Settlement.GrantResult<S>
```

### `core.progression.SettlementConfig`

```luau
export type SettlementConfig<P, S, C, Q> = Settlement.Config<P, S, C, Q>
```

### `core.progression.StandingCreditOutcome`

```luau
export type StandingCreditOutcome = StandingCredit.Outcome
```

### `core.progression.StandingCreditConfig`

```luau
export type StandingCreditConfig = StandingCredit.Config
```

### `core.progression.TalentRanksLoadout`

```luau
export type TalentRanksLoadout = TalentRanks.Loadout
```

### `core.progression.TalentRanksResult`

```luau
export type TalentRanksResult = TalentRanks.Result
```

### `core.progression.TalentRanksNode`

```luau
export type TalentRanksNode = TalentRanks.Node
```

### `core.progression.TalentRanksTier`

```luau
export type TalentRanksTier = TalentRanks.Tier
```

### `core.progression.TalentRanksLine`

```luau
export type TalentRanksLine = TalentRanks.Line
```

### `core.progression.TalentRanksSpec`

```luau
export type TalentRanksSpec = TalentRanks.Spec
```

### `core.progression.TalentRanksBucket`

```luau
export type TalentRanksBucket = TalentRanks.Bucket
```

### `core.progression.TalentsState`

```luau
export type TalentsState = Talents.State
```

### `core.progression.TalentsLoadout`

```luau
export type TalentsLoadout = Talents.Loadout
```

### `core.progression.TalentsIntent`

```luau
export type TalentsIntent = Talents.Intent
```

### `core.progression.TalentsResult`

```luau
export type TalentsResult = Talents.Result
```

### `core.progression.TrackingConfig`

```luau
export type TrackingConfig = Tracking.Config
```

### `core.progression.TransactionsCollectionSet`

```luau
export type TransactionsCollectionSet = Transactions.CollectionSet
```

### `core.progression.TransactionsOutcome`

```luau
export type TransactionsOutcome = Transactions.Outcome
```

### `core.progression.TransactionsResult`

```luau
export type TransactionsResult<T> = Transactions.Result<T>
```

### `core.progression.TransactionsConfig`

```luau
export type TransactionsConfig<T> = Transactions.Config<T>
```

### `core.progression.API`

```luau
export type API = {
	read actionbar: typeof(Actionbar),
	read consumables: typeof(Consumables),
	read grants: typeof(Grants),
	read hearth: typeof(Hearth),
	read levels: typeof(Levels),
	read recovery: typeof(Recovery),
	read reputation: typeof(Reputation),
	read season: typeof(Season),
	read settlement: typeof(Settlement),
	read standing_credit: typeof(StandingCredit),
	read talent_ranks: typeof(TalentRanks),
	read talents: typeof(Talents),
	read tracking: typeof(Tracking),
	read transactions: typeof(Transactions),
}
```

### `core.progression.actionbar`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.consumables`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.grants`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.hearth`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.levels`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.recovery`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.reputation`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.season`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.settlement`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.standing_credit`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.talent_ranks`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.talents`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.tracking`

Exported value; see its declaration in [source](../src/core/progression.luau).

### `core.progression.transactions`

Exported value; see its declaration in [source](../src/core/progression.luau).

## `core.quest.claims`

[Source](../src/core/quest/claims.luau)

```luau
local Run = require("./run")
```

```luau
local Value = require("../../kernel/value")
```

### `core.quest.claims.Invitation`

```luau
export type Invitation = {
	userId: number,
	priorId: string,
	leaderUserId: number?,
	expectedRevision: number,
	recoveryWindowSec: number,
	realmId: string?,
	entryLevel: number?,
	roleId: string?,
}
```

### `core.quest.claims.ReplacementIdentity`

```luau
export type ReplacementIdentity = { userId: number, priorId: string, leaderUserId: number }
```

### `core.quest.claims.Member`

```luau
export type Member = {
	userId: number,
	characterId: string,
}
```

### `core.quest.claims.Record`

```luau
export type Record = {
	schemaVersion: number,
	runId: string,
	packageId: string,
	placeId: number,
	accessCode: string,
	privateServerId: string,
	partyId: string,
	leaderUserId: number,
	request: Raw,
	rows: Raw,
	members: { Member },
	createdAtSec: number,
	expiresAtSec: number,
	stateRevision: number,
	runState: Raw?,
	replacementInvitation: Raw?,
	status: "reserved" | "active" | "closed",
	claimedByJobId: string?,
	claimedAtSec: number?,
}
```

### `core.quest.claims.Target`

```luau
export type Target = {
	placeId: number,
	accessCode: string,
	privateServerId: string,
	runId: string,
}
```

### `core.quest.claims.Transform`

```luau
export type Transform = (unknown) -> Record?
```

### `core.quest.claims.Config`

```luau
export type Config = {
	recordTtlSec: number,
	claimLeaseSec: number,
	carrierContract: string,
	memberCount: number,
	maxText: number,
	retryDelaysSec: { number },
}
```

### `core.quest.claims.claims`

```luau
function System.claims(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
runKey = function Core.runKey(runId: string): string
userKey = function Core.userKey(userId: number): string
serverKey = function Core.serverKey(privateServerId: string): string
isReservedServer = function Core.isReservedServer(privateServerId: unknown, privateServerOwnerId: unknown): boolean
retryDelaysSec = function Core.retryDelaysSec(): { number }
readRecord = function Core.readRecord(value: unknown): Record?
validRecord = function Core.validRecord(value: unknown): boolean
newRecord = function Core.newRecord(input: unknown, nowSec: number): (Record?, string?)
readReplacementIdentity = function Core.readReplacementIdentity(value: unknown): ReplacementIdentity?
createTransform = function Core.createTransform(record: Record): Transform
claimTransform = function Core.claimTransform(privateServerId: string, jobId: string, nowSec: number): Transform
renewTransform = function Core.renewTransform(runId: string, jobId: string, nowSec: number): Transform
closeTransform = function Core.closeTransform(runId: string): Transform
writeThroughTransform = function Core.writeThroughTransform(runId: string, runStateValue: unknown, jobId: string, nowSec: number): Transform
inviteReplacementTransform = function Core.inviteReplacementTransform(invitationValue: unknown, jobId: string, nowSec: number): Transform
replaceRosterTransform = function Core.replaceRosterTransform(
		runId: string,
		rawPlan: unknown,
		rawRows: unknown,
		jobId: string,
		nowSec: number
	): Transform
rejoinTarget = function Core.rejoinTarget(record: unknown, userId: number, nowSec: number): (Target?, string?)
teleportData = function Core.teleportData<T>(carriers: { [number]: T }): { contract: string, carriers: { [string]: T } }
carrierFor = function Core.carrierFor(teleportData: unknown, userId: number): unknown
```

## `core.quest.counter`

[Source](../src/core/quest/counter.luau)

### `core.quest.counter.Band`

```luau
export type Band = {
	questId: string,
	minLevel: number,
}
```

### `core.quest.counter.Counts`

```luau
export type Counts = {
	eligible: number,
	completed: number,
}
```

### `core.quest.counter.Config`

```luau
export type Config = { markerPrefix: string, completedStatus: string, labelFormat: string }
```

### `core.quest.counter.counter`

```luau
function System.counter(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
questIdFromMarkerName = function QuestCompletionCounter.questIdFromMarkerName(markerName: string): string?
count = function QuestCompletionCounter.count(
		bands: { Band }?,
		statusByQuestId: { [string]: string },
		level: number
	): Counts?
label = function QuestCompletionCounter.label(counts: Counts?): string
```

## `core.quest.index`

[Source](../src/core/quest/index.luau)

```luau
local Objectives = require("./objectives")
```

### `core.quest.index.Config`

```luau
export type Config = { catalog: Objectives.Catalog, quests: { Objectives.Quest } }
```

### `core.quest.index.TargetBinding`

```luau
export type TargetBinding = { questId: string, objectiveId: string, targetId: string }
```

### `core.quest.index.index`

```luau
function System.index(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
objectiveBindings = function objectiveBindings(): { Objectives.Binding }
bindingsForEvent = function bindingsForEvent(event: Objectives.Event): { Objectives.Binding }
byTarget = function byTarget(event: string, field: string): { [string]: { TargetBinding } }
```

## `core.quest.journal`

[Source](../src/core/quest/journal.luau)

```luau
local Tables = require("../../kernel/value")
```

### `core.quest.journal.QuestProgress`

```luau
export type QuestProgress = { status: string, step: number, counts: { [string]: number }? }
```

### `core.quest.journal.Record`

```luau
export type Record = {
	version: number,
	zoneId: string,
	characterId: string,
	quests: { [string]: QuestProgress },
	semanticEventIds: { [string]: boolean },
}
```

### `core.quest.journal.Config`

```luau
export type Config = {
	read version: number,
	read maxIdLength: number,
	read maxCharacterIdLength: number,
	read maxEventIdLength: number,
	read maxEvents: number,
	read maxQuests: number,
	read maxCounts: number,
	read maxStep: number,
	read maxCount: number,
	read eventPrefix: string,
	read statuses: { [string]: boolean },
	read claimableStatuses: { [string]: boolean },
	read receiptStatus: string,
	read eventIdAllowed: (string) -> boolean,
}
```

### `core.quest.journal.API`

```luau
export type API = {
	read CURRENT_VERSION: number,
	read STATUSES: { [string]: boolean },
	read MAX_EVENT_ID_LENGTH: number,
	read MAX_EVENTS: number,
	read create: (unknown, unknown, unknown, unknown?) -> (Record?, string?),
	read decode: (unknown) -> (Record?, string?),
	read copyQuests: (unknown) -> ({ [string]: QuestProgress }?, string?),
	read copySemanticEventIds: (unknown) -> ({ [string]: boolean }?, string?),
	read storageQuests: (unknown) -> ({ [string]: QuestProgress }?, string?),
	read fromStorageQuests: (unknown, unknown, unknown, { [string]: boolean }?) -> (Record?, string?),
	read key: (string, string) -> string,
}
```

### `core.quest.journal.journal`

```luau
function journal(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
CURRENT_VERSION = CURRENT_VERSION
STATUSES = table.freeze(table.clone(STATUSES))
create = function create(
		zoneId: unknown,
		characterId: unknown,
		quests: unknown,
		semanticEventIds: unknown?
	): (Record?, string?)
decode = function decode(raw: unknown): (Record?, string?)
copyQuests = function copyQuests(raw: unknown): ({ [string]: QuestProgress }?, string?)
copySemanticEventIds = function copySemanticEventIds(raw: unknown): ({ [string]: boolean }?, string?)
storageQuests = function storageQuests(recordRaw: unknown): ({ [string]: QuestProgress }?, string?)
fromStorageQuests = function fromStorageQuests(
		zoneId: unknown,
		characterId: unknown,
		raw: unknown,
		knownQuestIds: { [string]: boolean }?
	): (Record?, string?)
MAX_EVENT_ID_LENGTH = MAX_EVENT_ID_LENGTH
MAX_EVENTS = MAX_EVENTS
key = function key(zoneId: string, characterId: string): string
```

## `core.quest.lifecycle`

[Source](../src/core/quest/lifecycle.luau)

```luau
local Objectives = require("./objectives")
```

```luau
local Value = require("../../kernel/value")
```

### `core.quest.lifecycle.Objective`

```luau
export type Objective = Objectives.Objective
```

### `core.quest.lifecycle.Binding`

```luau
export type Binding = Objectives.Binding
```

### `core.quest.lifecycle.Event`

```luau
export type Event = Objectives.Event
```

### `core.quest.lifecycle.Quest`

```luau
export type Quest = Objectives.Quest
```

### `core.quest.lifecycle.Problem`

```luau
export type Problem = Objectives.Problem
```

### `core.quest.lifecycle.Config`

```luau
export type Config = {
	catalog: Objectives.Catalog,
	targetFields: { string },
	eventField: string,
	targetsField: string,
	bespokeFields: { string },
	stillnessKinds: { [string]: boolean },
}
```

### `core.quest.lifecycle.lifecycle`

```luau
function System.lifecycle(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
projectObjective = function projectObjective(value: unknown): Objective?
validateObjective = function validateObjective(value: unknown): { Problem }
bindingForObjective = function bindingForObjective(questId: string, value: unknown): Binding?
catalog = catalog
```

## `core.quest.markers`

[Source](../src/core/quest/markers.luau)

### `core.quest.markers.QuestStatus`

```luau
export type QuestStatus = string
```

### `core.quest.markers.MarkerState`

```luau
export type MarkerState = "turnIn" | "available" | "inProgress" | "notCurrentlyAcceptable"
```

### `core.quest.markers.QuestEntry`

```luau
export type QuestEntry = {
	status: QuestStatus,
	available: boolean,
}
```

### `core.quest.markers.Config`

```luau
export type Config = {
	aliases: { [string]: string },
	completedStatus: string,
	inProgressStatus: string,
	unstartedStatus: string,
}
```

### `core.quest.markers.markers`

```luau
function System.markers(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
stateForEntry = function stateForEntry(entry: QuestEntry): MarkerState?
stateForGiver = function stateForGiver(entries: { QuestEntry }): MarkerState?
isActionable = function isActionable(state: MarkerState?): boolean
shownState = function shownState(state: MarkerState?, occluded: boolean, visibleAtDistance: boolean): MarkerState?
colorForState = function colorForState<T>(
		palette: {
			questTurnIn: T,
			questAvailable: T,
			questInProgress: T,
			questLocked: T,
		},
		state: MarkerState?
	): T
```

## `core.quest.objectives`

[Source](../src/core/quest/objectives.luau)

### `core.quest.objectives.Targets`

```luau
export type Targets = { [string]: string }
```

### `core.quest.objectives.KindSpec`

```luau
export type KindSpec = {
	event: string,
	required: { string },
	optional: { string }?,
	targetIdField: string?,
}
```

### `core.quest.objectives.Objective`

```luau
export type Objective = {
	id: string,
	kind: string,
	event: string?,
	targetId: string?,
	targets: Targets,
}
```

### `core.quest.objectives.Quest`

```luau
export type Quest = { id: string, objectives: { Objective } }
```

### `core.quest.objectives.Event`

```luau
export type Event = {
	kind: string,
	questId: string?,
	objectiveId: string?,
	targets: Targets,
}
```

### `core.quest.objectives.Binding`

```luau
export type Binding = {
	questId: string,
	objectiveId: string,
	objectiveKind: string,
	event: string,
	targets: Targets,
}
```

### `core.quest.objectives.Problem`

```luau
export type Problem = { kind: string, field: string, detail: string }
```

### `core.quest.objectives.EventContract`

```luau
export type EventContract = { kind: string, required: { string }, allowed: { [string]: boolean } }
```

### `core.quest.objectives.Aliases`

```luau
export type Aliases = { [string]: { [string]: { [string]: { [string]: boolean } } } }
```

### `core.quest.objectives.Config`

```luau
export type Config = {
	order: { string },
	kinds: { [string]: KindSpec },
	aliases: Aliases?,
}
```

### `core.quest.objectives.Catalog`

```luau
export type Catalog = {
	kinds: () -> { string },
	events: () -> { string },
	known: (kind: string) -> boolean,
	contract: (event: string) -> EventContract?,
	eventOf: (objective: Objective) -> string?,
	targetsOf: (objective: Objective) -> Targets,
	validate: (objective: Objective) -> { Problem },
	binding: (questId: string, objective: Objective) -> Binding?,
	bindings: (quest: Quest) -> { Binding },
	matches: (event: Event, binding: Binding) -> boolean,
	bindingsFor: (quests: { Quest }, event: Event) -> { Binding },
}
```

### `core.quest.objectives.catalog`

```luau
function Objectives.catalog(config: Config): Catalog
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
kinds = function(): { string }
events = function(): { string }
known = function(kind: string): boolean
contract = function(event: string): EventContract?
eventOf = function eventOf(objective: Objective): string?
targetsOf = function targetsOf(objective: Objective): Targets
validate = function(objective: Objective): { Problem }
binding = function binding(questId: string, objective: Objective): Binding?
bindings = function bindings(quest: Quest): { Binding }
matches = function matches(event: Event, candidate: Binding): boolean
bindingsFor = function(quests: { Quest }, event: Event): { Binding }
```

## `core.quest.progress`

[Source](../src/core/quest/progress.luau)

```luau
local Journal = require("./journal")
```

### `core.quest.progress.QuestProgress`

```luau
export type QuestProgress = Journal.QuestProgress
```

### `core.quest.progress.Rule`

```luau
export type Rule = { classId: string?, minLevel: number?, ordered: boolean? }
```

### `core.quest.progress.Branch`

```luau
export type Branch = { groupId: string, armId: string }
```

### `core.quest.progress.Statuses`

```luau
export type Statuses = {
	inProgress: string,
	completed: string,
	turnedIn: string,
	replayInProgress: string,
	replayCompleted: string,
	replayTurnedIn: string,
}
```

### `core.quest.progress.ObjectiveView`

```luau
export type ObjectiveView = { read id: string, read mobId: string?, read target: number? }
```

### `core.quest.progress.QuestView`

```luau
export type QuestView<O> = {
	read id: string,
	read objectives: { O },
	read realm: unknown,
	read prereqQuestIds: { string }?,
	read prereqAnyQuestIds: { string }?,
	read exclusiveQuestGroupId: unknown,
	read exclusiveQuestArmId: unknown,
}
```

### `core.quest.progress.ActorView`

```luau
export type ActorView = {
	read quests: { [string]: QuestProgress }?,
	read classId: string?,
	read level: number?,
	read realm: unknown,
}
```

### `core.quest.progress.ContentView`

```luau
export type ContentView<Q> = {
	read quests: { Q }?,
	read questRules: { [string]: Rule }?,
	read exclusiveQuestBranches: { [string]: Branch }?,
	read exclusiveQuestGroups: { [string]: { [string]: boolean } }?,
}
```

### `core.quest.progress.Config`

```luau
export type Config<C, A, Q, O> = {
	read content: (C) -> ContentView<Q>,
	read quest: (Q) -> QuestView<O>,
	read objective: (O) -> ObjectiveView,
	read actor: (A) -> ActorView,
	read canonicalRealm: (unknown) -> boolean,
	read statuses: Statuses,
}
```

### `core.quest.progress.API`

```luau
export type API<C, A, Q, O> = {
	read questRows: (C?) -> { Q },
	read questById: (C?, string) -> Q?,
	read objectiveIndexForMob: (Q, string) -> number?,
	read questForMob: (C?, string) -> (Q?, number),
	read questForObjective: (C?, string) -> Q?,
	read objectiveTarget: (O) -> number,
	read progressFor: (A, string) -> QuestProgress?,
	read seededQuests: ({ [string]: string }?) -> { [string]: QuestProgress }?,
	read questInProgress: (string?) -> boolean,
	read isReplayStatus: (string?) -> boolean,
	read actorIsReplaying: (A) -> boolean,
	read completedQuestStatus: (string?) -> string,
	read questRule: (C?, string) -> Rule?,
	read allowedClass: (C?, Q, A) -> boolean,
	read allowedLevel: (C?, Q, A) -> boolean,
	read canonicalRealm: (unknown) -> boolean,
	read allowedRealm: (Q, A) -> boolean,
	read isOrdered: (C?, string) -> boolean,
	read objectiveComplete: (QuestProgress, O) -> boolean,
	read completedCount: (Q, QuestProgress) -> number,
	read prereqsMet: (Q, A) -> boolean,
	read allowedExclusiveBranch: (C?, Q, A) -> boolean,
	read canAcceptQuest: (C?, A?, Q?) -> boolean,
	read completedPrefix: (Q, QuestProgress) -> number,
	read reconcileOrdered: (C?, A) -> (),
	read claimableObjective: (C?, Q, QuestProgress, string?) -> O?,
	read EMPTY_QUESTS: { Q },
	read NO_QUESTS: { [string]: QuestProgress },
}
```

### `core.quest.progress.progress`

```luau
function progress<C, A, Q, O>(config: Config<C, A, Q, O>): API<C, A, Q, O>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
questRows = function Quest.questRows(content: C?): { Q }
questById = function Quest.questById(content: C?, questId: string): Q?
objectiveIndexForMob = function Quest.objectiveIndexForMob(quest: Q, mobId: string): number?
questForMob = function Quest.questForMob(content: C?, mobId: string): (Q?, number)
questForObjective = function Quest.questForObjective(content: C?, objectiveId: string): Q?
objectiveTarget = function Quest.objectiveTarget(objective: O): number
progressFor = function Quest.progressFor(actor: A, questId: string): QuestProgress?
seededQuests = function Quest.seededQuests(questStatus: { [string]: string }?): { [string]: QuestProgress }?
questInProgress = function Quest.questInProgress(status: string?): boolean
isReplayStatus = function Quest.isReplayStatus(status: string?): boolean
actorIsReplaying = function Quest.actorIsReplaying(actor: A): boolean
completedQuestStatus = function Quest.completedQuestStatus(status: string?): string
questRule = function Quest.questRule(content: C?, questId: string): Rule?
allowedClass = function Quest.allowedClass(content: C?, quest: Q, actor: A): boolean
allowedLevel = function Quest.allowedLevel(content: C?, quest: Q, actor: A): boolean
canonicalRealm = function Quest.canonicalRealm(realm: unknown): boolean
allowedRealm = function Quest.allowedRealm(quest: Q, actor: A): boolean
isOrdered = function Quest.isOrdered(content: C?, questId: string): boolean
objectiveComplete = function Quest.objectiveComplete(progress: QuestProgress, objective: O): boolean
completedCount = function Quest.completedCount(quest: Q, progress: QuestProgress): number
prereqsMet = function Quest.prereqsMet(quest: Q, actor: A): boolean
allowedExclusiveBranch = function Quest.allowedExclusiveBranch(content: C?, quest: Q, actor: A): boolean
canAcceptQuest = function Quest.canAcceptQuest(content: C?, actor: A?, quest: Q?): boolean
completedPrefix = function Quest.completedPrefix(quest: Q, progress: QuestProgress): number
reconcileOrdered = function Quest.reconcileOrdered(content: C?, actor: A)
claimableObjective = function Quest.claimableObjective(content: C?, quest: Q, progress: QuestProgress, objectiveId: string?): O?
```

## `core.quest.run`

[Source](../src/core/quest/run.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.quest.run.Package`

```luau
export type Package = {
	id: string,
	entryId: string,
	returnId: string,
	recoveryWindowSec: number,
	group: { minPlayers: number, maxPlayers: number },
	phases: { { id: string, kind: string, contentId: string } },
}
```

### `core.quest.run.RunStatus`

```luau
export type RunStatus = "active" | "completed"
```

### `core.quest.run.Member`

```luau
export type Member = {
	id: string,
	connected: boolean,
	disconnectedAtSec: number?,
	departed: boolean,
}
```

### `core.quest.run.RunState`

```luau
export type RunState = {
	schemaVersion: number,
	expeditionId: string,
	runId: string,
	revision: number,
	startedAtSec: number,
	lastClockSec: number,
	status: RunStatus,
	phaseIndex: number,
	checkpointId: string?,
	attempt: number,
	leaderId: string,
	members: { Member },
	receipts: { [string]: string },
}
```

### `core.quest.run.StartEvent`

```luau
export type StartEvent = {
	kind: "start",
	eventId: string,
	runId: string,
	leaderId: string,
	memberIds: { string },
}
```

### `core.quest.run.CompletePhaseEvent`

```luau
export type CompletePhaseEvent = {
	kind: "complete_phase",
	eventId: string,
	expectedRevision: number,
	phaseId: string,
}
```

### `core.quest.run.MemberEvent`

```luau
export type MemberEvent = {
	kind: "disconnect" | "reconnect" | "leader_departure" | "depart" | "replace",
	replacementId: string?,
	eventId: string,
	expectedRevision: number,
	memberId: string,
}
```

### `core.quest.run.WipeEvent`

```luau
export type WipeEvent = {
	kind: "wipe",
	eventId: string,
	expectedRevision: number,
	memberIds: { string },
}
```

### `core.quest.run.Event`

```luau
export type Event = StartEvent | CompletePhaseEvent | MemberEvent | WipeEvent
```

### `core.quest.run.Recovery`

```luau
export type Recovery = {
	kind: "wipe" | "reconnect" | "leader_departure",
	returnAnchorId: string,
	memberIds: { string },
}
```

### `core.quest.run.TransitionApplied`

```luau
export type TransitionApplied = {
	ok: true,
	state: RunState,
	replayed: boolean,
	recovery: Recovery?,
}
```

### `core.quest.run.TransitionRejected`

```luau
export type TransitionRejected = {
	ok: false,
	state: RunState?,
	reason: string,
}
```

### `core.quest.run.TransitionResult`

```luau
export type TransitionResult = TransitionApplied | TransitionRejected
```

### `core.quest.run.Core`

```luau
export type Core = {
	transition: (unknown, unknown, unknown, unknown) -> TransitionResult,
	projectRunState: (unknown, unknown) -> RunState?,
	Reason: { [string]: string },
}
```

### `core.quest.run.Config`

```luau
export type Config<P> = {
	readPackage: (unknown) -> P?,
	describe: (P) -> Package,
	validCheckpoint: (P, RunState) -> boolean,
	wipePhase: (P, RunState) -> number,
	replacementAllowed: (P, RunState) -> boolean,
	maxMembers: number,
}
```

### `core.quest.run.run`

```luau
function System.run<P>(config: Config<P>): Core
```

## `core.quest`

[Source](../src/core/quest.luau)

```luau
local Claims = require("./quest/claims")
```

```luau
local Counter = require("./quest/counter")
```

```luau
local Index = require("./quest/index")
```

```luau
local Journal = require("./quest/journal")
```

```luau
local Lifecycle = require("./quest/lifecycle")
```

```luau
local Markers = require("./quest/markers")
```

```luau
local Objectives = require("./quest/objectives")
```

```luau
local Progress = require("./quest/progress")
```

```luau
local Run = require("./quest/run")
```

### `core.quest.ClaimsInvitation`

```luau
export type ClaimsInvitation = Claims.Invitation
```

### `core.quest.ClaimsReplacementIdentity`

```luau
export type ClaimsReplacementIdentity = Claims.ReplacementIdentity
```

### `core.quest.ClaimsMember`

```luau
export type ClaimsMember = Claims.Member
```

### `core.quest.ClaimsRecord`

```luau
export type ClaimsRecord = Claims.Record
```

### `core.quest.ClaimsTarget`

```luau
export type ClaimsTarget = Claims.Target
```

### `core.quest.ClaimsTransform`

```luau
export type ClaimsTransform = Claims.Transform
```

### `core.quest.ClaimsConfig`

```luau
export type ClaimsConfig = Claims.Config
```

### `core.quest.CounterBand`

```luau
export type CounterBand = Counter.Band
```

### `core.quest.CounterCounts`

```luau
export type CounterCounts = Counter.Counts
```

### `core.quest.CounterConfig`

```luau
export type CounterConfig = Counter.Config
```

### `core.quest.IndexConfig`

```luau
export type IndexConfig = Index.Config
```

### `core.quest.IndexTargetBinding`

```luau
export type IndexTargetBinding = Index.TargetBinding
```

### `core.quest.JournalQuestProgress`

```luau
export type JournalQuestProgress = Journal.QuestProgress
```

### `core.quest.JournalRecord`

```luau
export type JournalRecord = Journal.Record
```

### `core.quest.JournalConfig`

```luau
export type JournalConfig = Journal.Config
```

### `core.quest.JournalAPI`

```luau
export type JournalAPI = Journal.API
```

### `core.quest.LifecycleObjective`

```luau
export type LifecycleObjective = Lifecycle.Objective
```

### `core.quest.LifecycleBinding`

```luau
export type LifecycleBinding = Lifecycle.Binding
```

### `core.quest.LifecycleEvent`

```luau
export type LifecycleEvent = Lifecycle.Event
```

### `core.quest.LifecycleQuest`

```luau
export type LifecycleQuest = Lifecycle.Quest
```

### `core.quest.LifecycleProblem`

```luau
export type LifecycleProblem = Lifecycle.Problem
```

### `core.quest.LifecycleConfig`

```luau
export type LifecycleConfig = Lifecycle.Config
```

### `core.quest.MarkersQuestStatus`

```luau
export type MarkersQuestStatus = Markers.QuestStatus
```

### `core.quest.MarkersMarkerState`

```luau
export type MarkersMarkerState = Markers.MarkerState
```

### `core.quest.MarkersQuestEntry`

```luau
export type MarkersQuestEntry = Markers.QuestEntry
```

### `core.quest.MarkersConfig`

```luau
export type MarkersConfig = Markers.Config
```

### `core.quest.ObjectivesTargets`

```luau
export type ObjectivesTargets = Objectives.Targets
```

### `core.quest.ObjectivesKindSpec`

```luau
export type ObjectivesKindSpec = Objectives.KindSpec
```

### `core.quest.ObjectivesObjective`

```luau
export type ObjectivesObjective = Objectives.Objective
```

### `core.quest.ObjectivesQuest`

```luau
export type ObjectivesQuest = Objectives.Quest
```

### `core.quest.ObjectivesEvent`

```luau
export type ObjectivesEvent = Objectives.Event
```

### `core.quest.ObjectivesBinding`

```luau
export type ObjectivesBinding = Objectives.Binding
```

### `core.quest.ObjectivesProblem`

```luau
export type ObjectivesProblem = Objectives.Problem
```

### `core.quest.ObjectivesEventContract`

```luau
export type ObjectivesEventContract = Objectives.EventContract
```

### `core.quest.ObjectivesAliases`

```luau
export type ObjectivesAliases = Objectives.Aliases
```

### `core.quest.ObjectivesConfig`

```luau
export type ObjectivesConfig = Objectives.Config
```

### `core.quest.ObjectivesCatalog`

```luau
export type ObjectivesCatalog = Objectives.Catalog
```

### `core.quest.ProgressQuestProgress`

```luau
export type ProgressQuestProgress = Progress.QuestProgress
```

### `core.quest.ProgressRule`

```luau
export type ProgressRule = Progress.Rule
```

### `core.quest.ProgressBranch`

```luau
export type ProgressBranch = Progress.Branch
```

### `core.quest.ProgressStatuses`

```luau
export type ProgressStatuses = Progress.Statuses
```

### `core.quest.ProgressObjectiveView`

```luau
export type ProgressObjectiveView = Progress.ObjectiveView
```

### `core.quest.ProgressQuestView`

```luau
export type ProgressQuestView<O> = Progress.QuestView<O>
```

### `core.quest.ProgressActorView`

```luau
export type ProgressActorView = Progress.ActorView
```

### `core.quest.ProgressContentView`

```luau
export type ProgressContentView<Q> = Progress.ContentView<Q>
```

### `core.quest.ProgressConfig`

```luau
export type ProgressConfig<C, A, Q, O> = Progress.Config<C, A, Q, O>
```

### `core.quest.ProgressAPI`

```luau
export type ProgressAPI<C, A, Q, O> = Progress.API<C, A, Q, O>
```

### `core.quest.RunPackage`

```luau
export type RunPackage = Run.Package
```

### `core.quest.RunRunStatus`

```luau
export type RunRunStatus = Run.RunStatus
```

### `core.quest.RunMember`

```luau
export type RunMember = Run.Member
```

### `core.quest.RunRunState`

```luau
export type RunRunState = Run.RunState
```

### `core.quest.RunStartEvent`

```luau
export type RunStartEvent = Run.StartEvent
```

### `core.quest.RunCompletePhaseEvent`

```luau
export type RunCompletePhaseEvent = Run.CompletePhaseEvent
```

### `core.quest.RunMemberEvent`

```luau
export type RunMemberEvent = Run.MemberEvent
```

### `core.quest.RunWipeEvent`

```luau
export type RunWipeEvent = Run.WipeEvent
```

### `core.quest.RunEvent`

```luau
export type RunEvent = Run.Event
```

### `core.quest.RunRecovery`

```luau
export type RunRecovery = Run.Recovery
```

### `core.quest.RunTransitionApplied`

```luau
export type RunTransitionApplied = Run.TransitionApplied
```

### `core.quest.RunTransitionRejected`

```luau
export type RunTransitionRejected = Run.TransitionRejected
```

### `core.quest.RunTransitionResult`

```luau
export type RunTransitionResult = Run.TransitionResult
```

### `core.quest.RunCore`

```luau
export type RunCore = Run.Core
```

### `core.quest.RunConfig`

```luau
export type RunConfig<P> = Run.Config<P>
```

### `core.quest.API`

```luau
export type API = {
	read claims: typeof(Claims),
	read counter: typeof(Counter),
	read index: typeof(Index),
	read journal: typeof(Journal),
	read lifecycle: typeof(Lifecycle),
	read markers: typeof(Markers),
	read objectives: typeof(Objectives),
	read progress: typeof(Progress),
	read run: typeof(Run),
}
```

### `core.quest.claims`

Exported value; see its declaration in [source](../src/core/quest.luau).

### `core.quest.counter`

Exported value; see its declaration in [source](../src/core/quest.luau).

### `core.quest.index`

Exported value; see its declaration in [source](../src/core/quest.luau).

### `core.quest.journal`

Exported value; see its declaration in [source](../src/core/quest.luau).

### `core.quest.lifecycle`

Exported value; see its declaration in [source](../src/core/quest.luau).

### `core.quest.markers`

Exported value; see its declaration in [source](../src/core/quest.luau).

### `core.quest.objectives`

Exported value; see its declaration in [source](../src/core/quest.luau).

### `core.quest.progress`

Exported value; see its declaration in [source](../src/core/quest.luau).

### `core.quest.run`

Exported value; see its declaration in [source](../src/core/quest.luau).

## `core.social.allies`

[Source](../src/core/social/allies.luau)

```luau
local SocialShape = require("./shape")
```

### `core.social.allies.QualificationKind`

```luau
export type QualificationKind = string
```

### `core.social.allies.Entry`

```luau
export type Entry = {
	allyUserId: number,
	qualificationKind: QualificationKind,
	qualificationReceiptId: string,
	lastQualifiedAtSec: number,
	expiresAtSec: number,
}
```

### `core.social.allies.State`

```luau
export type State = {
	schemaVersion: number,
	userId: number,
	revision: number,
	lastClockSec: number,
	policyRevision: number,
	entries: { Entry },
	receipts: { [string]: string },
}
```

### `core.social.allies.Policy`

```luau
export type Policy = PolicyFlags & {
	blockedUserIds: { number },
	optedOutUserIds: { number },
	moderationDeniedUserIds: { number },
}
```

### `core.social.allies.Result`

```luau
export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
}
```

### `core.social.allies.QualifyEvent`

```luau
export type QualifyEvent = {
	kind: "qualify",
	eventId: string,
	expectedRevision: number,
	allyUserId: number,
	qualificationKind: QualificationKind,
	qualificationReceiptId: string,
}
```

### `core.social.allies.ReconcileEvent`

```luau
export type ReconcileEvent = {
	kind: "reconcile",
	eventId: string,
	expectedRevision: number,
	allyUserId: nil,
	qualificationKind: nil,
	qualificationReceiptId: nil,
}
```

### `core.social.allies.Event`

```luau
export type Event = QualifyEvent | ReconcileEvent
```

### `core.social.allies.Authority`

```luau
export type Authority = { validate: (string, QualificationKind, number, number, number) -> unknown }
```

### `core.social.allies.Config`

```luau
export type Config = {
	retentionSec: number,
	maxAllies: number,
	maxRevision: number,
	maxTime: number,
	maxId: number,
	maxFingerprint: number,
	qualificationKinds: { [string]: boolean },
}
```

### `core.social.allies.allies`

```luau
function System.allies(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function RecentAlliesCore.emptyState(userId: unknown): State?
projectState = function RecentAlliesCore.projectState(value: unknown): State?
projectPrivate = function RecentAlliesCore.projectPrivate(
		value: unknown,
		policyValue: unknown,
		requesterUserId: unknown,
		nowSecValue: unknown
	): { Entry }?
transition = function RecentAlliesCore.transition(
		previousStateValue: unknown,
		eventValue: unknown,
		nowSecValue: unknown,
		policyValue: unknown,
		qualificationAuthority: Authority?
	): Result
```

## `core.social.chronicle`

[Source](../src/core/social/chronicle.luau)

```luau
local Read = require("../internal/chronicle-read")
```

```luau
local SocialShape = require("./shape")
```

### `core.social.chronicle.ActiveStatus`

```luau
export type ActiveStatus = Read.ActiveStatus
```

### `core.social.chronicle.TerminalStatus`

```luau
export type TerminalStatus = Read.TerminalStatus
```

### `core.social.chronicle.Definition`

```luau
export type Definition = Read.Definition
```

### `core.social.chronicle.ActiveVow`

```luau
export type ActiveVow = Read.ActiveVow
```

### `core.social.chronicle.Deed`

```luau
export type Deed = Read.Deed
```

### `core.social.chronicle.State`

```luau
export type State = Read.State
```

### `core.social.chronicle.Applied`

```luau
export type Applied = Read.Applied
```

### `core.social.chronicle.Rejected`

```luau
export type Rejected = Read.Rejected
```

### `core.social.chronicle.Result`

```luau
export type Result = Read.Result
```

### `core.social.chronicle.AccessPolicy`

```luau
export type AccessPolicy = Read.AccessPolicy
```

### `core.social.chronicle.ContributionAuthority`

```luau
export type ContributionAuthority = Read.ContributionAuthority
```

### `core.social.chronicle.Event`

```luau
export type Event = Read.Event
```

### `core.social.chronicle.Config`

```luau
export type Config = Read.Config
```

### `core.social.chronicle.chronicle`

```luau
function System.chronicle(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function VowChronicleCore.emptyState(characterId: unknown): State?
projectState = function VowChronicleCore.projectState(value: unknown, definitionsValue: unknown): State?
projectChronicle = function VowChronicleCore.projectChronicle(
		value: unknown,
		definitionsValue: unknown,
		requesterCharacterId: unknown
	): { Deed }?
transition = function VowChronicleCore.transition(
		previousStateValue: unknown,
		definitionsValue: unknown,
		eventValue: unknown,
		nowSecValue: unknown,
		accessPolicy: AccessPolicy?,
		contributionAuthority: ContributionAuthority?
	): Result
```

## `core.social.fellowship`

[Source](../src/core/social/fellowship.luau)

```luau
local Read = require("../internal/fellowship-read")
```

```luau
local SocialShape = require("./shape")
```

### `core.social.fellowship.Member`

```luau
export type Member = Read.Member
```

### `core.social.fellowship.Invite`

```luau
export type Invite = Read.Invite
```

### `core.social.fellowship.Creed`

```luau
export type Creed = Read.Creed
```

### `core.social.fellowship.CreedDraft`

```luau
export type CreedDraft = Read.CreedDraft
```

### `core.social.fellowship.FormationRequest`

```luau
export type FormationRequest = Read.FormationRequest
```

### `core.social.fellowship.Event`

```luau
export type Event = Read.Event
```

### `core.social.fellowship.EventDraft`

```luau
export type EventDraft = Read.EventDraft
```

### `core.social.fellowship.Audit`

```luau
export type Audit = Read.Audit
```

### `core.social.fellowship.State`

```luau
export type State = Read.State
```

### `core.social.fellowship.FoundRequest`

```luau
export type FoundRequest = Read.FoundRequest
```

### `core.social.fellowship.Result`

```luau
export type Result = Read.Result
```

### `core.social.fellowship.Config`

```luau
export type Config = Read.Config
```

### `core.social.fellowship.fellowship`

```luau
function System.fellowship(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
validCreed = function FellowshipCore.validCreed(pursuits: unknown, pace: unknown, welcome: unknown): Creed?
create = function FellowshipCore.create(request: unknown, nowSec: unknown): Result
createFromFormation = function FellowshipCore.createFromFormation(request: unknown, nowSec: unknown): Result
projectState = function FellowshipCore.projectState(value: unknown): State?
transition = function FellowshipCore.transition(previous: unknown, eventValue: unknown, nowSecValue: unknown): Result
```

## `core.social.formation`

[Source](../src/core/social/formation.luau)

```luau
local SocialShape = require("./shape")
```

### `core.social.formation.Founder`

```luau
export type Founder = { userId: number, name: string }
```

### `core.social.formation.State`

```luau
export type State = {
	schemaVersion: number,
	formationId: string,
	fellowshipId: string,
	nameId: string,
	realmId: string,
	homeSlotId: string,
	initiatorId: number,
	expiresAtSec: number,
	founders: { Founder },
	invited: { number },
	feeCopper: number,
	feeState: string,
	phase: string,
	revision: number,
	lastClockSec: number,
	receipts: { [string]: string },
	receiptOrder: { string },
}
```

### `core.social.formation.EventDraft`

```luau
export type EventDraft = {
	kind: string,
	eventId: string?,
	expectedRevision: number?,
	actorUserId: number?,
	targetUserId: number?,
	targetRealmId: string?,
	actorRealmId: string?,
	actorName: string?,
}
```

### `core.social.formation.Event`

```luau
export type Event = EventDraft & { eventId: string, expectedRevision: number }
```

### `core.social.formation.StartRequest`

```luau
export type StartRequest = {
	formationId: string,
	nameId: string,
	realmId: string,
	homeSlotId: string,
	initiatorId: number,
	initiatorName: string,
}
```

### `core.social.formation.Result`

```luau
export type Result = { ok: boolean, state: State?, replayed: boolean, reason: string? }
```

### `core.social.formation.Config`

```luau
export type Config = {
	requiredFounders: number,
	fee: number,
	formationTtlSec: number,
	maxReceipts: number,
	maxTime: number,
	maxNameLength: number,
	realms: { [string]: boolean },
	nameIds: { [string]: boolean },
	fellowshipPrefix: string,
	maxFormationId: number,
	maxId: number,
	maxRevision: number,
	maxFingerprint: number,
}
```

### `core.social.formation.formation`

```luau
function System.formation(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
start = function FellowshipFormationCore.start(request: unknown, nowSec: unknown): Result
projectState = function FellowshipFormationCore.projectState(value: unknown): State?
transition = function FellowshipFormationCore.transition(previous: unknown, eventValue: unknown, nowSecValue: unknown): Result
```

## `core.social.group`

[Source](../src/core/social/group.luau)

```luau
local SocialShape = require("./shape")
```

### `core.social.group.Relations`

```luau
export type Relations = {
	readAtSec: number,
	memberUserId: number,
	moderationEligible: boolean,
	blockedUserIds: { number },
	moderationDeniedUserIds: { number },
	optedOutUserIds: { number },
}
```

### `core.social.group.Admission`

```luau
export type Admission = {
	members: { Relations },
	subject: Relations?,
}
```

### `core.social.group.Ticket`

```luau
export type Ticket = {
	userId: number,
	departedAtSec: number,
	expiresAtSec: number,
}
```

### `core.social.group.State`

```luau
export type State = {
	schemaVersion: number,
	groupId: string,
	revision: number,
	lastClockSec: number,
	relationsReadAtSec: number,
	tickets: { Ticket },
	receipts: { [string]: string },
}
```

### `core.social.group.Result`

```luau
export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	recoveredUserId: number?,
}
```

### `core.social.group.Decision`

```luau
export type Decision = {
	ok: boolean,
	reason: string?,
}
```

### `core.social.group.Request`

```luau
export type Request = { groupId: string, inviterUserId: number, candidateUserId: number }
```

### `core.social.group.Authority`

```luau
export type Authority = { validate: (string, string, number, number, number) -> unknown }
```

### `core.social.group.MemberEvent`

```luau
export type MemberEvent = { kind: "depart" | "recover", eventId: string, expectedRevision: number, userId: number }
```

### `core.social.group.ReconcileEvent`

```luau
export type ReconcileEvent = { kind: "reconcile", eventId: string, expectedRevision: number, userId: nil }
```

### `core.social.group.Event`

```luau
export type Event = MemberEvent | ReconcileEvent
```

### `core.social.group.Config`

```luau
export type Config = {
	recoveryTtlSec: number,
	relationsMaxAgeSec: number,
	maxTickets: number,
	maxRoster: number,
	maxRevision: number,
	maxTime: number,
	maxId: number,
	maxFingerprint: number,
}
```

### `core.social.group.group`

```luau
function System.group(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function GroupCore.emptyState(groupId: unknown): State?
projectState = function GroupCore.projectState(value: unknown): State?
projectRelations = function GroupCore.projectRelations(value: unknown, nowSecValue: unknown): Relations?
admit = function GroupCore.admit(
		admissionValue: unknown,
		requestValue: unknown,
		nowSecValue: unknown,
		groupAuthority: Authority?
	): Decision
visibleRoster = function GroupCore.visibleRoster(relationsValue: unknown, rosterValue: unknown, nowSecValue: unknown): { number }?
transition = function GroupCore.transition(
		previousStateValue: unknown,
		eventValue: unknown,
		nowSecValue: unknown,
		admissionValue: unknown,
		groupAuthority: Authority?
	): Result
```

## `core.social.guildbank`

[Source](../src/core/social/guildbank.luau)

```luau
local SocialShape = require("./shape")
```

```luau
local Vault = require("../bank/vault")
```

### `core.social.guildbank.Receipt`

```luau
export type Receipt = { receiptId: string, ownerId: number, materialId: string, count: number, issuedAtSec: number }
```

### `core.social.guildbank.Operation`

```luau
export type Operation = { fingerprint: string, atSec: number, actorId: number, keepUntilSec: number }
```

### `core.social.guildbank.Entry`

```luau
export type Entry = { atSec: number, actorId: number, kind: string, materialId: string, count: number }
```

### `core.social.guildbank.Withdrawal`

```luau
export type Withdrawal = { actorId: number, atSec: number, count: number }
```

### `core.social.guildbank.Command`

```luau
export type Command = {
	kind: string,
	opId: string,
	actorId: number,
	role: string,
	materialId: string,
	count: number,
	receiptIds: { string },
	memberIds: { number },
}
```

### `core.social.guildbank.State`

```luau
export type State = {
	schemaVersion: number,
	fellowshipId: string,
	stock: { [string]: number },
	receipts: { Receipt },
	withdrawals: { Withdrawal },
	log: { Entry },
	operations: { [string]: Operation },
	operationOrder: { string },
	lastClockSec: number,
}
```

### `core.social.guildbank.Result`

```luau
export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	receipts: { Receipt }?,
	fence: string?,
}
```

### `core.social.guildbank.Config`

```luau
export type Config = {
	maxKinds: number,
	maxStack: number,
	maxReceipts: number,
	maxReceiptsPerOwner: number,
	maxLog: number,
	maxWithdrawals: number,
	daySec: number,
	memberDailyWithdrawal: number,
	healRetentionSec: number,
	receiptTtlSec: number,
	maxOperations: number,
	maxOperationsPerActor: number,
	maxId: number,
	maxTime: number,
	maxMembers: number,
	roles: { [string]: boolean },
	privilegedRoles: { [string]: boolean },
}
```

### `core.social.guildbank.guildbank`

```luau
function System.guildbank(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function GuildBankCore.emptyState(fellowshipId: unknown): State?
projectState = function GuildBankCore.projectState(value: unknown): State?
knowsOperation = function GuildBankCore.knowsOperation(value: unknown, opId: unknown): boolean
receiptsFor = function GuildBankCore.receiptsFor(value: unknown, ownerId: unknown): { Receipt }?
apply = function GuildBankCore.apply(previous: unknown, commandValue: unknown, nowSecValue: unknown): Result
```

## `core.social.guildhome`

[Source](../src/core/social/guildhome.luau)

```luau
local Shape = require("./shape")
```

### `core.social.guildhome.Slot`

```luau
export type Slot = { id: string, hubId: string, realmId: string, label: string }
```

### `core.social.guildhome.Config`

```luau
export type Config = { maxIdLength: number, maxLabelLength: number, maxSlots: number, realms: { [string]: boolean } }
```

### `core.social.guildhome.guildhome`

```luau
function Homes.guildhome(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
slots = function Core.slots(catalog: unknown): { Slot }?
slotFor = function Core.slotFor(catalog: unknown, realmId: unknown): Slot?
```

## `core.social.guildledger`

[Source](../src/core/social/guildledger.luau)

```luau
local SocialShape = require("./shape")
```

### `core.social.guildledger.Pending`

```luau
export type Pending = { fellowshipId: string, materialId: string, count: number, startedAtSec: number }
```

### `core.social.guildledger.Ledger`

```luau
export type Ledger = {
	schemaVersion: number,
	pending: { [string]: Pending },
	unacked: { [string]: string },
}
```

### `core.social.guildledger.Limits`

```luau
export type Limits = { maxItemCount: number, maxInventoryEntries: number }
```

```luau
local Vault = require("../bank/vault")
```

### `core.social.guildledger.Receipt`

```luau
export type Receipt = { receiptId: string, ownerId: number, materialId: string, count: number, issuedAtSec: number? }
```

### `core.social.guildledger.ProfileInput`

```luau
export type ProfileInput = { inventory: unknown, guildBank: unknown }
```

### `core.social.guildledger.Config`

```luau
export type Config<T> = {
	readProfile: (T) -> ProfileInput,
	writeProfile: (T, Vault.Inventory?, Ledger) -> T,
	maxUnacked: number,
	withdrawRoom: number,
	maxPending: number,
	maxId: number,
	maxCount: number,
	maxTime: number,
	healRetentionSec: number,
}
```

### `core.social.guildledger.guildledger`

```luau
function System.guildledger<T>(config: Config<T>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyLedger = function GuildBankLedgerCore.emptyLedger(): Ledger
projectLedger = function GuildBankLedgerCore.projectLedger(value: unknown): Ledger?
beginDeposit = function GuildBankLedgerCore.beginDeposit(
		profile: T,
		opId: string,
		fellowshipId: string,
		materialId: string,
		count: number,
		nowSec: number,
		limits: Limits
	): (T?, string?)
settle = function GuildBankLedgerCore.settle(profile: T, opId: string): (T?, string?)
refund = function GuildBankLedgerCore.refund(profile: T, opId: string, limits: Limits): (T?, string?)
claim = function GuildBankLedgerCore.claim(
		profile: T,
		receipt: unknown,
		ownerId: number,
		fellowshipId: string,
		limits: Limits
	): (T?, string?)
acked = function GuildBankLedgerCore.acked(profile: T, receiptIds: { string }): (T?, string?)
claimed = function GuildBankLedgerCore.claimed(profile: T, receiptId: string): boolean
canWithdraw = function GuildBankLedgerCore.canWithdraw(profile: T): boolean
```

## `core.social.membership`

[Source](../src/core/social/membership.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.social.membership.LootMode`

```luau
export type LootMode = "round_robin" | "need_greed"
```

### `core.social.membership.Member`

```luau
export type Member = {
	accountId: string,
	characterId: string?,
	joinedAt: number,
	absentSince: number?,
}
```

### `core.social.membership.Invite`

```luau
export type Invite = {
	accountId: string,
	invitedBy: string,
	at: number,
}
```

### `core.social.membership.LeaderTransfer`

```luau
export type LeaderTransfer = { accountId: string, by: string, at: number }
```

### `core.social.membership.State`

```luau
export type State = {
	partyId: string,
	realmId: string,
	leaderId: string,
	leaderTransfer: LeaderTransfer?,
	members: { Member },
	invites: { Invite },
	lootMode: LootMode,
	lootCursor: string?,
	createdAt: number,
	lastAt: number,
	disbandedAt: number?,
}
```

### `core.social.membership.Result`

```luau
export type Result = {
	state: State,
	replayed: boolean,
}
```

### `core.social.membership.Config`

```luau
export type Config = {
	maxMembers: number,
	minimumPartyMembers: number,
	disconnectGraceSec: number,
	leaderSuccessionSec: number,
	leaderTransferTtlSec: number,
	inviteTtlSec: number,
	maxText: number,
	maxAt: number,
	realms: { [string]: boolean },
	defaultLootMode: LootMode,
}
```

### `core.social.membership.Core`

```luau
export type Core = {
	read projectState: (unknown) -> (State?, string?),
	read open: (unknown) -> (Result?, string?),
	read invite: (unknown, unknown) -> (Result?, string?),
	read accept: (unknown, unknown) -> (Result?, string?),
	read decline: (unknown, unknown) -> (Result?, string?),
	read leave: (unknown, unknown) -> (Result?, string?),
	read kick: (unknown, unknown) -> (Result?, string?),
	read transferLeader: (unknown, unknown) -> (Result?, string?),
	read acceptLeaderTransfer: (unknown, unknown) -> (Result?, string?),
	read disband: (unknown, unknown) -> (Result?, string?),
	read setLootMode: (unknown, unknown) -> (Result?, string?),
	read markAbsent: (unknown, unknown) -> (Result?, string?),
	read markPresent: (unknown, unknown) -> (Result?, string?),
	read sweep: (unknown, unknown) -> (Result?, string?),
}
```

### `core.social.membership.membership`

```luau
function System.membership(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
projectState = function PartyCore.projectState(value: unknown): (State?, string?)
open = function PartyCore.open(requestValue: unknown): (Result?, string?)
invite = function PartyCore.invite(stateValue: unknown, requestValue: unknown): (Result?, string?)
accept = function PartyCore.accept(stateValue: unknown, requestValue: unknown): (Result?, string?)
decline = function PartyCore.decline(stateValue: unknown, requestValue: unknown): (Result?, string?)
leave = function PartyCore.leave(stateValue: unknown, requestValue: unknown): (Result?, string?)
kick = function PartyCore.kick(stateValue: unknown, requestValue: unknown): (Result?, string?)
transferLeader = function PartyCore.transferLeader(stateValue: unknown, requestValue: unknown): (Result?, string?)
acceptLeaderTransfer = function PartyCore.acceptLeaderTransfer(stateValue: unknown, requestValue: unknown): (Result?, string?)
disband = function PartyCore.disband(stateValue: unknown, requestValue: unknown): (Result?, string?)
setLootMode = function PartyCore.setLootMode(stateValue: unknown, requestValue: unknown): (Result?, string?)
markAbsent = function PartyCore.markAbsent(stateValue: unknown, requestValue: unknown): (Result?, string?)
markPresent = function PartyCore.markPresent(stateValue: unknown, requestValue: unknown): (Result?, string?)
sweep = function PartyCore.sweep(stateValue: unknown, requestValue: unknown): (Result?, string?)
```

## `core.social.notes`

[Source](../src/core/social/notes.luau)

```luau
local SocialShape = require("./shape")
```

### `core.social.notes.Note`

```luau
export type Note = {
	id: string,
	fromUserId: number,
	fromName: string,
	phraseId: string,
	sentAtSec: number,
	read: boolean,
}
```

### `core.social.notes.State`

```luau
export type State = {
	schemaVersion: number,
	ownerUserId: number,
	notes: { Note },
	receiptOrder: { string },
}
```

### `core.social.notes.Result`

```luau
export type Result = { ok: boolean, state: State?, changed: boolean, reason: string? }
```

### `core.social.notes.Phrase`

```luau
export type Phrase = { id: string, text: string }
```

### `core.social.notes.Catalog`

```luau
export type Catalog = { label: string, phrases: { Phrase } }
```

### `core.social.notes.Delivery`

```luau
export type Delivery = { noteId: string, fromUserId: number, fromName: string, phraseId: string }
```

### `core.social.notes.Config`

```luau
export type Config = {
	maxNotes: number,
	maxNameLength: number,
	maxIdLength: number,
	maxPhraseIdLength: number,
	maxPhraseTextLength: number,
	maxReceipts: number,
	maxPhrases: number,
	noteTtlSec: number,
	maxTime: number,
	presetLabel: string,
}
```

### `core.social.notes.notes`

```luau
function System.notes(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
emptyState = function PhraseNoteCore.emptyState(ownerUserId: unknown): State?
projectState = function PhraseNoteCore.projectState(value: unknown): State?
phrases = function PhraseNoteCore.phrases(catalog: unknown): { Phrase }?
deliver = function PhraseNoteCore.deliver(previous: unknown, request: unknown, nowSecValue: unknown): Result
markRead = function PhraseNoteCore.markRead(previous: unknown, noteId: unknown): Result
live = function PhraseNoteCore.live(notes: { Note }, nowSec: number): { Note }
```

## `core.social.profile`

[Source](../src/core/social/profile.luau)

```luau
local Allies = require("./allies")
```

```luau
local Chronicle = require("./chronicle")
```

```luau
local Shape = require("./shape")
```

### `core.social.profile.FellowshipIdentity`

```luau
export type FellowshipIdentity = {
	fellowshipId: string,
	nameId: string,
	realmId: string,
	memberUserId: number,
	lastKnownStewardUserId: number,
	observedRevision: number,
}
```

### `core.social.profile.State`

```luau
export type State =
	{ fellowship: FellowshipIdentity | false, recentAllies: Allies.State, vowChronicle: Chronicle.State }
```

### `core.social.profile.Config`

```luau
export type Config = {
	maxId: number,
	realms: { [string]: boolean },
	nameIds: { [string]: boolean },
	definitions: { Chronicle.Definition },
	emptyAllies: (unknown) -> Allies.State?,
	projectAllies: (unknown) -> Allies.State?,
	emptyChronicle: (unknown) -> Chronicle.State?,
	projectChronicle: (unknown, unknown) -> Chronicle.State?,
}
```

### `core.social.profile.profile`

```luau
function Profiles.profile(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
default = function(userId: unknown, characterId: unknown): State?
project = function(value: unknown, userId: unknown, characterId: unknown): State?
```

## `core.social.rally`

[Source](../src/core/social/rally.luau)

```luau
local Shape = require("./shape")
```

### `core.social.rally.Row`

```luau
export type Row = {
	objectiveId: string,
	objectiveKind: string,
	titleId: string,
	landmarkId: string,
	zoneId: string,
	realmId: string,
	expiresAtSec: number,
}
```

### `core.social.rally.Config`

```luau
export type Config = {
	maxRows: number,
	maxTime: number,
	maxId: number,
	kinds: { [string]: boolean },
	titles: { [string]: boolean },
	landmarks: { [string]: boolean },
	realms: { [string]: boolean },
	sharedRealm: string,
}
```

### `core.social.rally.rally`

```luau
function Boards.rally(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
project = function(source: unknown, zone: unknown, realm: unknown, now: unknown): { Row }?
```

## `core.social.roster`

[Source](../src/core/social/roster.luau)

### `core.social.roster.Member`

```luau
export type Member = { accountId: string, characterId: string? }
```

### `core.social.roster.Party`

```luau
export type Party = { partyId: string, realmId: string, disbandedAt: number?, members: { Member } }
```

### `core.social.roster.Actor`

```luau
export type Actor = { id: string, characterId: string?, realm: string?, partyId: string? }
```

### `core.social.roster.Runtime`

```luau
export type Runtime<S> = { state: S, tick: number }
```

### `core.social.roster.Result`

```luau
export type Result<S, A> = { parties: { [string]: Runtime<S> }, actors: { [string]: A } }
```

### `core.social.roster.Config`

```luau
export type Config<S, A> = {
	project: (unknown) -> S?,
	party: (S) -> Party,
	lootCursor: (S) -> string?,
	withLootCursor: (S, string?) -> S,
	actor: (A) -> Actor,
	withParty: (A, string?) -> A,
	subject: (string) -> string,
}
```

### `core.social.roster.roster`

```luau
function System.roster<S, A>(config: Config<S, A>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
reduce = function reduce(
		parties: { [string]: Runtime<S> },
		actors: { [string]: A },
		raw: unknown,
		tick: number
	): Result<S, A>?
subject = config.subject
```

## `core.social.shape`

[Source](../src/core/social/shape.luau)

```luau
local Internal = require("../internal/shape")
```

### `core.social.shape.Raw`

```luau
export type Raw = Internal.Raw
```

### `core.social.shape.array`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.boolean`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.dense`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.denseLength`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.exact`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.freezeDeep`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.freezeDeepWithKeys`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.map`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.number`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.onlyFields`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.opaque`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.raw`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.string`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

### `core.social.shape.whole`

Exported value; see its declaration in [source](../src/core/social/shape.luau).

## `core.social.warband`

[Source](../src/core/social/warband.luau)

```luau
local SocialShape = require("./shape")
```

### `core.social.warband.Party`

```luau
export type Party = {
	realmId: string,
	leaderId: string,
	characterId: string,
	connected: boolean,
	absentSinceSec: number?,
	closed: boolean?,
}
```

### `core.social.warband.Unit`

```luau
export type Unit = { partyId: string, joinedAtSec: number, membershipRevision: number }
```

### `core.social.warband.Invite`

```luau
export type Invite = { byPartyId: string, expiresAtSec: number }
```

### `core.social.warband.Transfer`

```luau
export type Transfer = { partyId: string, expiresAtSec: number }
```

### `core.social.warband.Order`

```luau
export type Order = { kind: string, objectiveId: string, byPartyId: string, byActorId: string?, atSec: number }
```

### `core.social.warband.State`

```luau
export type State = {
	schemaVersion: number,
	warbandId: string,
	realmId: string,
	revision: number,
	lastClockSec: number,
	units: { Unit },
	commanderPartyId: string?,
	commanderAbsentSinceSec: number?,
	assistants: { string },
	invites: { [string]: Invite },
	transfer: Transfer?,
	order: Order?,
	rallyObjectiveId: string?,
	targetObjectiveId: string?,
	rallyByActorId: string?,
	targetByActorId: string?,
}
```

### `core.social.warband.Event`

```luau
export type Event = {
	kind: string,
	actorPartyId: string,
	actorId: string,
	expectedRevision: number,
	targetPartyId: string?,
	membershipRevision: number?,
	orderKind: string?,
	objectiveId: string?,
}
```

### `core.social.warband.Parties`

```luau
export type Parties = { [string]: Party }
```

### `core.social.warband.Result`

```luau
export type Result = { ok: boolean, state: State?, reason: string? }
```

### `core.social.warband.Config`

```luau
export type Config = {
	maxParties: number,
	inviteSeconds: number,
	transferSeconds: number,
	successionSeconds: number,
	orders: { [string]: boolean },
	realms: { [string]: boolean },
	maxId: number,
	maxInteger: number,
	maxAssistants: number,
}
```

### `core.social.warband.warband`

```luau
function System.warband(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
project = function Core.project<T>(value: T): T?
found = function Core.found(
		warbandId: string,
		partyId: string,
		party: Party,
		membershipRevision: number,
		now: number
	): Result
transition = function Core.transition(previous: State, event: Event, parties: Parties, now: number): Result
read = function Core.read(value: unknown): State?
```

## `core.social`

[Source](../src/core/social.luau)

```luau
local Allies = require("./social/allies")
```

```luau
local Chronicle = require("./social/chronicle")
```

```luau
local Fellowship = require("./social/fellowship")
```

```luau
local Formation = require("./social/formation")
```

```luau
local Group = require("./social/group")
```

```luau
local Guildbank = require("./social/guildbank")
```

```luau
local Guildhome = require("./social/guildhome")
```

```luau
local Guildledger = require("./social/guildledger")
```

```luau
local Membership = require("./social/membership")
```

```luau
local Notes = require("./social/notes")
```

```luau
local Profile = require("./social/profile")
```

```luau
local Rally = require("./social/rally")
```

```luau
local Roster = require("./social/roster")
```

```luau
local Warband = require("./social/warband")
```

### `core.social.AlliesQualificationKind`

```luau
export type AlliesQualificationKind = Allies.QualificationKind
```

### `core.social.AlliesEntry`

```luau
export type AlliesEntry = Allies.Entry
```

### `core.social.AlliesState`

```luau
export type AlliesState = Allies.State
```

### `core.social.AlliesPolicy`

```luau
export type AlliesPolicy = Allies.Policy
```

### `core.social.AlliesResult`

```luau
export type AlliesResult = Allies.Result
```

### `core.social.AlliesQualifyEvent`

```luau
export type AlliesQualifyEvent = Allies.QualifyEvent
```

### `core.social.AlliesReconcileEvent`

```luau
export type AlliesReconcileEvent = Allies.ReconcileEvent
```

### `core.social.AlliesEvent`

```luau
export type AlliesEvent = Allies.Event
```

### `core.social.AlliesAuthority`

```luau
export type AlliesAuthority = Allies.Authority
```

### `core.social.AlliesConfig`

```luau
export type AlliesConfig = Allies.Config
```

### `core.social.ChronicleActiveStatus`

```luau
export type ChronicleActiveStatus = Chronicle.ActiveStatus
```

### `core.social.ChronicleTerminalStatus`

```luau
export type ChronicleTerminalStatus = Chronicle.TerminalStatus
```

### `core.social.ChronicleDefinition`

```luau
export type ChronicleDefinition = Chronicle.Definition
```

### `core.social.ChronicleActiveVow`

```luau
export type ChronicleActiveVow = Chronicle.ActiveVow
```

### `core.social.ChronicleDeed`

```luau
export type ChronicleDeed = Chronicle.Deed
```

### `core.social.ChronicleState`

```luau
export type ChronicleState = Chronicle.State
```

### `core.social.ChronicleApplied`

```luau
export type ChronicleApplied = Chronicle.Applied
```

### `core.social.ChronicleRejected`

```luau
export type ChronicleRejected = Chronicle.Rejected
```

### `core.social.ChronicleResult`

```luau
export type ChronicleResult = Chronicle.Result
```

### `core.social.ChronicleAccessPolicy`

```luau
export type ChronicleAccessPolicy = Chronicle.AccessPolicy
```

### `core.social.ChronicleContributionAuthority`

```luau
export type ChronicleContributionAuthority = Chronicle.ContributionAuthority
```

### `core.social.ChronicleEvent`

```luau
export type ChronicleEvent = Chronicle.Event
```

### `core.social.ChronicleConfig`

```luau
export type ChronicleConfig = Chronicle.Config
```

### `core.social.FellowshipMember`

```luau
export type FellowshipMember = Fellowship.Member
```

### `core.social.FellowshipInvite`

```luau
export type FellowshipInvite = Fellowship.Invite
```

### `core.social.FellowshipCreed`

```luau
export type FellowshipCreed = Fellowship.Creed
```

### `core.social.FellowshipCreedDraft`

```luau
export type FellowshipCreedDraft = Fellowship.CreedDraft
```

### `core.social.FellowshipFormationRequest`

```luau
export type FellowshipFormationRequest = Fellowship.FormationRequest
```

### `core.social.FellowshipEvent`

```luau
export type FellowshipEvent = Fellowship.Event
```

### `core.social.FellowshipEventDraft`

```luau
export type FellowshipEventDraft = Fellowship.EventDraft
```

### `core.social.FellowshipAudit`

```luau
export type FellowshipAudit = Fellowship.Audit
```

### `core.social.FellowshipState`

```luau
export type FellowshipState = Fellowship.State
```

### `core.social.FellowshipFoundRequest`

```luau
export type FellowshipFoundRequest = Fellowship.FoundRequest
```

### `core.social.FellowshipResult`

```luau
export type FellowshipResult = Fellowship.Result
```

### `core.social.FellowshipConfig`

```luau
export type FellowshipConfig = Fellowship.Config
```

### `core.social.FormationFounder`

```luau
export type FormationFounder = Formation.Founder
```

### `core.social.FormationState`

```luau
export type FormationState = Formation.State
```

### `core.social.FormationEventDraft`

```luau
export type FormationEventDraft = Formation.EventDraft
```

### `core.social.FormationEvent`

```luau
export type FormationEvent = Formation.Event
```

### `core.social.FormationStartRequest`

```luau
export type FormationStartRequest = Formation.StartRequest
```

### `core.social.FormationResult`

```luau
export type FormationResult = Formation.Result
```

### `core.social.FormationConfig`

```luau
export type FormationConfig = Formation.Config
```

### `core.social.GroupRelations`

```luau
export type GroupRelations = Group.Relations
```

### `core.social.GroupAdmission`

```luau
export type GroupAdmission = Group.Admission
```

### `core.social.GroupTicket`

```luau
export type GroupTicket = Group.Ticket
```

### `core.social.GroupState`

```luau
export type GroupState = Group.State
```

### `core.social.GroupResult`

```luau
export type GroupResult = Group.Result
```

### `core.social.GroupDecision`

```luau
export type GroupDecision = Group.Decision
```

### `core.social.GroupRequest`

```luau
export type GroupRequest = Group.Request
```

### `core.social.GroupAuthority`

```luau
export type GroupAuthority = Group.Authority
```

### `core.social.GroupMemberEvent`

```luau
export type GroupMemberEvent = Group.MemberEvent
```

### `core.social.GroupReconcileEvent`

```luau
export type GroupReconcileEvent = Group.ReconcileEvent
```

### `core.social.GroupEvent`

```luau
export type GroupEvent = Group.Event
```

### `core.social.GroupConfig`

```luau
export type GroupConfig = Group.Config
```

### `core.social.GuildbankReceipt`

```luau
export type GuildbankReceipt = Guildbank.Receipt
```

### `core.social.GuildbankOperation`

```luau
export type GuildbankOperation = Guildbank.Operation
```

### `core.social.GuildbankEntry`

```luau
export type GuildbankEntry = Guildbank.Entry
```

### `core.social.GuildbankWithdrawal`

```luau
export type GuildbankWithdrawal = Guildbank.Withdrawal
```

### `core.social.GuildbankCommand`

```luau
export type GuildbankCommand = Guildbank.Command
```

### `core.social.GuildbankState`

```luau
export type GuildbankState = Guildbank.State
```

### `core.social.GuildbankResult`

```luau
export type GuildbankResult = Guildbank.Result
```

### `core.social.GuildbankConfig`

```luau
export type GuildbankConfig = Guildbank.Config
```

### `core.social.GuildhomeSlot`

```luau
export type GuildhomeSlot = Guildhome.Slot
```

### `core.social.GuildhomeConfig`

```luau
export type GuildhomeConfig = Guildhome.Config
```

### `core.social.GuildledgerPending`

```luau
export type GuildledgerPending = Guildledger.Pending
```

### `core.social.GuildledgerLedger`

```luau
export type GuildledgerLedger = Guildledger.Ledger
```

### `core.social.GuildledgerLimits`

```luau
export type GuildledgerLimits = Guildledger.Limits
```

### `core.social.GuildledgerReceipt`

```luau
export type GuildledgerReceipt = Guildledger.Receipt
```

### `core.social.GuildledgerProfileInput`

```luau
export type GuildledgerProfileInput = Guildledger.ProfileInput
```

### `core.social.GuildledgerConfig`

```luau
export type GuildledgerConfig<T> = Guildledger.Config<T>
```

### `core.social.MembershipLootMode`

```luau
export type MembershipLootMode = Membership.LootMode
```

### `core.social.MembershipMember`

```luau
export type MembershipMember = Membership.Member
```

### `core.social.MembershipInvite`

```luau
export type MembershipInvite = Membership.Invite
```

### `core.social.MembershipLeaderTransfer`

```luau
export type MembershipLeaderTransfer = Membership.LeaderTransfer
```

### `core.social.MembershipState`

```luau
export type MembershipState = Membership.State
```

### `core.social.MembershipResult`

```luau
export type MembershipResult = Membership.Result
```

### `core.social.MembershipConfig`

```luau
export type MembershipConfig = Membership.Config
```

### `core.social.MembershipCore`

```luau
export type MembershipCore = Membership.Core
```

### `core.social.NotesNote`

```luau
export type NotesNote = Notes.Note
```

### `core.social.NotesState`

```luau
export type NotesState = Notes.State
```

### `core.social.NotesResult`

```luau
export type NotesResult = Notes.Result
```

### `core.social.NotesPhrase`

```luau
export type NotesPhrase = Notes.Phrase
```

### `core.social.NotesCatalog`

```luau
export type NotesCatalog = Notes.Catalog
```

### `core.social.NotesDelivery`

```luau
export type NotesDelivery = Notes.Delivery
```

### `core.social.NotesConfig`

```luau
export type NotesConfig = Notes.Config
```

### `core.social.ProfileFellowshipIdentity`

```luau
export type ProfileFellowshipIdentity = Profile.FellowshipIdentity
```

### `core.social.ProfileState`

```luau
export type ProfileState = Profile.State
```

### `core.social.ProfileConfig`

```luau
export type ProfileConfig = Profile.Config
```

### `core.social.RallyRow`

```luau
export type RallyRow = Rally.Row
```

### `core.social.RallyConfig`

```luau
export type RallyConfig = Rally.Config
```

### `core.social.RosterMember`

```luau
export type RosterMember = Roster.Member
```

### `core.social.RosterParty`

```luau
export type RosterParty = Roster.Party
```

### `core.social.RosterActor`

```luau
export type RosterActor = Roster.Actor
```

### `core.social.RosterRuntime`

```luau
export type RosterRuntime<S> = Roster.Runtime<S>
```

### `core.social.RosterResult`

```luau
export type RosterResult<S, A> = Roster.Result<S, A>
```

### `core.social.RosterConfig`

```luau
export type RosterConfig<S, A> = Roster.Config<S, A>
```

### `core.social.WarbandParty`

```luau
export type WarbandParty = Warband.Party
```

### `core.social.WarbandUnit`

```luau
export type WarbandUnit = Warband.Unit
```

### `core.social.WarbandInvite`

```luau
export type WarbandInvite = Warband.Invite
```

### `core.social.WarbandTransfer`

```luau
export type WarbandTransfer = Warband.Transfer
```

### `core.social.WarbandOrder`

```luau
export type WarbandOrder = Warband.Order
```

### `core.social.WarbandState`

```luau
export type WarbandState = Warband.State
```

### `core.social.WarbandEvent`

```luau
export type WarbandEvent = Warband.Event
```

### `core.social.WarbandParties`

```luau
export type WarbandParties = Warband.Parties
```

### `core.social.WarbandResult`

```luau
export type WarbandResult = Warband.Result
```

### `core.social.WarbandConfig`

```luau
export type WarbandConfig = Warband.Config
```

### `core.social.API`

```luau
export type API = {
	read allies: typeof(Allies),
	read chronicle: typeof(Chronicle),
	read fellowship: typeof(Fellowship),
	read formation: typeof(Formation),
	read group: typeof(Group),
	read guildbank: typeof(Guildbank),
	read guildhome: typeof(Guildhome),
	read guildledger: typeof(Guildledger),
	read membership: typeof(Membership),
	read notes: typeof(Notes),
	read profile: typeof(Profile),
	read rally: typeof(Rally),
	read roster: typeof(Roster),
	read warband: typeof(Warband),
}
```

### `core.social.allies`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.chronicle`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.fellowship`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.formation`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.group`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.guildbank`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.guildhome`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.guildledger`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.membership`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.notes`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.profile`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.rally`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.roster`

Exported value; see its declaration in [source](../src/core/social.luau).

### `core.social.warband`

Exported value; see its declaration in [source](../src/core/social.luau).

## `core.threat.contribution`

[Source](../src/core/threat/contribution.luau)

### `core.threat.contribution.Point`

```luau
export type Point = { x: number, y: number?, z: number }
```

### `core.threat.contribution.DungeonAdmission`

```luau
export type DungeonAdmission = { dungeonId: string, cycleId: string, characterId: string }
```

### `core.threat.contribution.Relation`

```luau
export type Relation = "self" | "ally" | "enemy"
```

### `core.threat.contribution.Observation`

```luau
export type Observation = {
	kind: string,
	sourceActorId: string,
	targetActorId: string,
	targetRelation: Relation,
	contested: boolean,
	targetEligible: boolean,
	attemptedAmount: number,
	effectiveAmount: number,
	eligibleAmountCap: number,
}
```

### `core.threat.contribution.Credit`

```luau
export type Credit = {
	category: string,
	amount: number,
	sourceActorId: string,
	targetActorId: string,
}
```

### `core.threat.contribution.ActorContribution`

```luau
export type ActorContribution = {
	activeSec: number,
	firstActionSec: number?,
	lastActionSec: number?,
	interruptSec: number?,
	lastSeenSec: number?,
}
```

### `core.threat.contribution.EndActor`

```luau
export type EndActor = {
	characterId: string,
	pos: { x: number, y: number?, z: number },
	distance: number,
	alive: boolean,
	defeatedAtSec: number?,
	dungeonAdmission: DungeonAdmission?,
}
```

### `core.threat.contribution.Encounter`

```luau
export type Encounter = {
	startedAtSec: number,
	endedAtSec: number?,
	actors: { [string]: ActorContribution },
	endActors: { [string]: EndActor }?,
}
```

### `core.threat.contribution.Participant`

```luau
export type Participant = {
	hp: number,
	pos: Point,
	characterId: string?,
	defeatedAtSec: number?,
	dungeonAdmission: DungeonAdmission?,
}
```

### `core.threat.contribution.Config`

```luau
export type Config = {
	read categories: { read [string]: string },
	read eligibleRelation: (Observation) -> boolean,
	read participationRadius: number,
	read inactiveSeconds: number,
	read recentDefeatSeconds: number,
	read rewardRadius: number,
	read shortEncounterSeconds: number,
	read actionSpanSeconds: number,
	read interruptActiveSeconds: number,
	read interruptKind: string,
}
```

### `core.threat.contribution.create`

```luau
function System.create(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
asParticipant = function CombatContribution.asParticipant(actor: Participant): Participant
record = function CombatContribution.record(encounter: Encounter?, actorId: string, kind: string, nowSec: number): Encounter
observe = function CombatContribution.observe<Actor>(
		encounter: Encounter?,
		actors: { [string]: Actor },
		participant: (Actor) -> Participant,
		center: Point,
		nowSec: number,
		dt: number
	): Encounter?
finish = function CombatContribution.finish<Actor>(
		encounter: Encounter?,
		nowSec: number,
		actors: { [string]: Actor },
		participant: (Actor) -> Participant,
		center: Point
	): Encounter?
eligibleAtEnd = function CombatContribution.eligibleAtEnd(encounter: Encounter?, actorId: string, characterId: string): boolean
eligible = function CombatContribution.eligible(
		encounter: Encounter?,
		actorId: string,
		distance: number,
		aliveOrRecent: boolean
	): boolean
```

## `core.threat.table`

[Source](../src/core/threat/table.luau)

### `core.threat.table.Config`

```luau
export type Config = { meleeTakeover: number, rangedTakeover: number, tauntLead: number }
```

### `core.threat.table.State`

```luau
export type State = { threat: { [string]: number }, targetActorId: string }
```

### `core.threat.table.Candidate`

```luau
export type Candidate = { alive: boolean, eligible: boolean, insideLeash: boolean }
```

### `core.threat.table.Pruned`

```luau
export type Pruned = { removed: { string }, outsideLeash: { string }, wasEngaged: boolean }
```

### `core.threat.table.empty`

```luau
function Threat.empty(): State
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
threat = {}
targetActorId = ""
```

### `core.threat.table.prune`

```luau
function Threat.prune(state: State, candidates: { [string]: Candidate }): (State, Pruned)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
threat = threat
targetActorId = Threat.targetFor(threat)
```

### `core.threat.table.remove`

```luau
function Threat.remove(state: State, actorId: string): State
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
threat = threat
targetActorId = Threat.targetFor(threat)
```

### `core.threat.table.rules`

```luau
function Threat.rules(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
add = function add(state: State, actorId: string, amount: number, inMelee: boolean): (State, boolean)
taunt = function taunt(state: State, actorId: string): State
```

### `core.threat.table.targetFor`

```luau
function Threat.targetFor(threat: { [string]: number }): string
```

## `core.threat`

[Source](../src/core/threat.luau)

```luau
local Contribution = require("./threat/contribution")
```

```luau
local Table = require("./threat/table")
```

### `core.threat.ContributionPoint`

```luau
export type ContributionPoint = Contribution.Point
```

### `core.threat.ContributionDungeonAdmission`

```luau
export type ContributionDungeonAdmission = Contribution.DungeonAdmission
```

### `core.threat.ContributionRelation`

```luau
export type ContributionRelation = Contribution.Relation
```

### `core.threat.ContributionObservation`

```luau
export type ContributionObservation = Contribution.Observation
```

### `core.threat.ContributionCredit`

```luau
export type ContributionCredit = Contribution.Credit
```

### `core.threat.ContributionActorContribution`

```luau
export type ContributionActorContribution = Contribution.ActorContribution
```

### `core.threat.ContributionEndActor`

```luau
export type ContributionEndActor = Contribution.EndActor
```

### `core.threat.ContributionEncounter`

```luau
export type ContributionEncounter = Contribution.Encounter
```

### `core.threat.ContributionParticipant`

```luau
export type ContributionParticipant = Contribution.Participant
```

### `core.threat.ContributionConfig`

```luau
export type ContributionConfig = Contribution.Config
```

### `core.threat.TableConfig`

```luau
export type TableConfig = Table.Config
```

### `core.threat.TableState`

```luau
export type TableState = Table.State
```

### `core.threat.TableCandidate`

```luau
export type TableCandidate = Table.Candidate
```

### `core.threat.TablePruned`

```luau
export type TablePruned = Table.Pruned
```

### `core.threat.API`

```luau
export type API = {
	read contribution: typeof(Contribution),
	read table: typeof(Table),
}
```

### `core.threat.contribution`

Exported value; see its declaration in [source](../src/core/threat.luau).

### `core.threat.table`

Exported value; see its declaration in [source](../src/core/threat.luau).

## `core.trade.exchange`

[Source](../src/core/trade/exchange.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.trade.exchange.Stack`

```luau
export type Stack = { itemId: string, count: number }
```

### `core.trade.exchange.Offer`

```luau
export type Offer = { coin: number, items: { Stack } }
```

### `core.trade.exchange.Phase`

```luau
export type Phase = "open" | "locked" | "confirmed" | "settled" | "cancelled"
```

### `core.trade.exchange.State`

```luau
export type State = {
	tradeId: string,
	expiresAt: number,
	players: { number },
	phase: Phase,
	revision: number,
	offers: { [number]: Offer },
	locks: { [number]: boolean },
	confirms: { [number]: boolean },
}
```

### `core.trade.exchange.Config`

```luau
export type Config = {
	maxItems: number,
	maxCount: number,
	maxCoin: number,
	maxUserId: number,
	maxRevision: number,
	idLimit: number,
}
```

### `core.trade.exchange.exchange`

```luau
function Trade.exchange(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
offer = function Core.offer(value: unknown): Offer?
empty = function Core.empty(tradeId: string, firstUserId: number, secondUserId: number): State?
step = function Core.step(state: State, actorId: number, commandValue: unknown): (State?, string?)
settled = function Core.settled(state: State): State?
```

## `core.trade.receipt`

[Source](../src/core/trade/receipt.luau)

```luau
local Exchange = require("./exchange")
```

```luau
local Value = require("../../kernel/value")
```

### `core.trade.receipt.Record`

```luau
export type Record<K> = {
	tradeId: string,
	players: { number },
	offers: { [K]: Exchange.Offer },
	characters: { [K]: string },
	revision: number,
	expiresAt: number,
	phase: "prepared" | "committed" | "resolved" | "cancelled",
	grants: { [K]: boolean? },
}
```

### `core.trade.receipt.Projected`

```luau
export type Projected = Record<number>
```

### `core.trade.receipt.Wire`

```luau
export type Wire = Record<string>
```

### `core.trade.receipt.Pointer`

```luau
export type Pointer = { tradeId: string, receipt: Wire }
```

### `core.trade.receipt.Config`

```luau
export type Config = {
	offer: (unknown) -> Exchange.Offer?,
	tradeIdLimit: number,
	characterIdLimit: number,
	maxUserId: number,
	maxRevision: number,
	maxTimestamp: number,
	maxPointers: number,
}
```

### `core.trade.receipt.receipts`

```luau
function Receipts.receipts(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
project = function Receipt.project(value: unknown): Projected?
wire = function Receipt.wire(raw: unknown): Wire?
pointers = function Receipt.pointers(value: unknown): { [string]: Pointer }?
```

## `core.trade`

[Source](../src/core/trade.luau)

```luau
local Exchange = require("./trade/exchange")
```

```luau
local Receipt = require("./trade/receipt")
```

### `core.trade.ExchangeStack`

```luau
export type ExchangeStack = Exchange.Stack
```

### `core.trade.ExchangeOffer`

```luau
export type ExchangeOffer = Exchange.Offer
```

### `core.trade.ExchangePhase`

```luau
export type ExchangePhase = Exchange.Phase
```

### `core.trade.ExchangeState`

```luau
export type ExchangeState = Exchange.State
```

### `core.trade.ExchangeConfig`

```luau
export type ExchangeConfig = Exchange.Config
```

### `core.trade.ReceiptRecord`

```luau
export type ReceiptRecord<K> = Receipt.Record<K>
```

### `core.trade.ReceiptProjected`

```luau
export type ReceiptProjected = Receipt.Projected
```

### `core.trade.ReceiptWire`

```luau
export type ReceiptWire = Receipt.Wire
```

### `core.trade.ReceiptPointer`

```luau
export type ReceiptPointer = Receipt.Pointer
```

### `core.trade.ReceiptConfig`

```luau
export type ReceiptConfig = Receipt.Config
```

### `core.trade.API`

```luau
export type API = {
	read exchange: typeof(Exchange),
	read receipt: typeof(Receipt),
}
```

### `core.trade.exchange`

Exported value; see its declaration in [source](../src/core/trade.luau).

### `core.trade.receipt`

Exported value; see its declaration in [source](../src/core/trade.luau).

## `core.vendors.exchange`

[Source](../src/core/vendors/exchange.luau)

```luau
local Value = require("../../kernel/value")
```

### `core.vendors.exchange.Inventory`

```luau
export type Inventory = { [string]: number }
```

### `core.vendors.exchange.Account`

```luau
export type Account = { gold: number, inventory: Inventory }
```

### `core.vendors.exchange.Ware`

```luau
export type Ware = { itemId: string, price: number, stock: number? }
```

### `core.vendors.exchange.Vendor`

```luau
export type Vendor = { id: string, npcId: string, wares: { Ware } }
```

### `core.vendors.exchange.Decision`

```luau
export type Decision = {
	ok: boolean,
	reason: string?,
	itemId: string?,
	quantity: number?,
	price: number?,
	gold: number?,
	action: string?,
}
```

### `core.vendors.exchange.Receipt`

```luau
export type Receipt = { id: number, itemId: string, quantity: number, unitPrice: number, expiresAt: number }
```

### `core.vendors.exchange.State`

```luau
export type State = {
	stock: { [string]: { [string]: number } },
	buyback: { [string]: { Receipt } },
	nextReceipt: number,
}
```

### `core.vendors.exchange.Config`

```luau
export type Config = {
	maxQuantity: number,
	maxStack: number,
	exists: (string) -> boolean,
	sellValue: (string) -> number?,
	add: (Inventory, string, number) -> Inventory,
	remove: (Inventory, string, number) -> (Inventory, boolean),
	canCarry: (Inventory, Inventory, string?) -> boolean,
	buybackLimit: number,
	buybackSeconds: number,
}
```

### `core.vendors.exchange.empty`

```luau
function Exchange.empty(): State
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
stock = {}
buyback = {}
nextReceipt = 1
```

### `core.vendors.exchange.vendor`

```luau
function Exchange.vendor(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
validateVendor = function validateVendor(value: unknown): (boolean, string?)
buy = function buy(
		account: Account,
		vendor: Vendor,
		itemId: unknown,
		quantity: unknown,
		bag: string?
	): (Account, Decision)
sell = function sell(account: Account, vendor: Vendor, itemId: unknown, quantity: unknown): (Account, Decision)
buyStock = function buyStock(
		state: State,
		account: Account,
		vendor: Vendor,
		itemId: unknown,
		quantity: unknown,
		bag: string?
	): (State, Account, Decision)
sellBack = function sellBack(
		state: State,
		account: Account,
		vendor: Vendor,
		sender: string,
		itemId: unknown,
		quantity: unknown,
		now: number
	): (State, Account, Decision)
buyBack = function buyBack(
		state: State,
		account: Account,
		sender: string,
		receiptId: number,
		quantity: unknown,
		bag: string?,
		now: number
	): (State, Account, Decision)
```

## `core.vendors`

[Source](../src/core/vendors.luau)

```luau
local Exchange = require("./vendors/exchange")
```

### `core.vendors.ExchangeInventory`

```luau
export type ExchangeInventory = Exchange.Inventory
```

### `core.vendors.ExchangeAccount`

```luau
export type ExchangeAccount = Exchange.Account
```

### `core.vendors.ExchangeWare`

```luau
export type ExchangeWare = Exchange.Ware
```

### `core.vendors.ExchangeVendor`

```luau
export type ExchangeVendor = Exchange.Vendor
```

### `core.vendors.ExchangeDecision`

```luau
export type ExchangeDecision = Exchange.Decision
```

### `core.vendors.ExchangeReceipt`

```luau
export type ExchangeReceipt = Exchange.Receipt
```

### `core.vendors.ExchangeState`

```luau
export type ExchangeState = Exchange.State
```

### `core.vendors.ExchangeConfig`

```luau
export type ExchangeConfig = Exchange.Config
```

### `core.vendors.API`

```luau
export type API = {
	read exchange: typeof(Exchange),
}
```

### `core.vendors.exchange`

Exported value; see its declaration in [source](../src/core/vendors.luau).

## `kernel.codec`

[Source](../src/kernel/codec.luau)

```luau
local Result = require("./result")
```

```luau
local Value = require("./value")
```

### `kernel.codec.Decoder`

```luau
export type Decoder<T> = (unknown) -> (T?, string?)
```

### `kernel.codec.Record`

```luau
export type Record<T> = { read copy: Decoder<T>, read equal: (T, T) -> boolean }
```

### `kernel.codec.Versioned`

```luau
export type Versioned<T> = {
	read version: number,
	read fields: { [string]: boolean },
	read required: boolean?,
	read migrate: ((unknown) -> unknown)?,
	read decode: (Value.Raw) -> (T?, string?),
}
```

### `kernel.codec.API`

```luau
export type API = {
	read versioned: typeof(versioned),
	read copyData: typeof(copyData),
	read equalData: typeof(equalData),
}
```

### `kernel.codec.copyData`

```luau
function copyData(value: unknown): Result.Result<unknown>
```

### `kernel.codec.equalData`

```luau
function equalData(left: unknown, right: unknown): boolean
```

### `kernel.codec.versioned`

```luau
function versioned<T>(config: Versioned<T>): Decoder<T>
```

## `kernel.lease`

[Source](../src/kernel/lease.luau)

```luau
local Result = require("./result")
```

```luau
local Value = require("./value")
```

### `kernel.lease.State`

```luau
export type State = {
	revision: number,
	sessionId: string?,
	acquisitionId: string?,
	expiresAt: number,
}
```

### `kernel.lease.Grant`

```luau
export type Grant = { read state: State, read kind: "acquired" | "owned" | "renewed" | "released" }
```

### `kernel.lease.Liveness`

```luau
export type Liveness = "alive" | "dead" | "unknown"
```

### `kernel.lease.Acquire`

```luau
export type Acquire = {
	read sessionId: string,
	read acquisitionId: string,
	read now: number,
	read ttl: number,
	read liveness: Liveness?,
}
```

### `kernel.lease.Expected`

```luau
export type Expected = { read sessionId: string, read acquisitionId: string, read revision: number }
```

### `kernel.lease.Renewal`

```luau
export type Renewal = Expected & { read now: number, read ttl: number }
```

### `kernel.lease.Config`

```luau
export type Config = {
	read maxRevision: number,
	read maxTime: number,
	read sessionIdLimit: number,
	read acquisitionIdLimit: number,
	read integerTime: boolean,
}
```

### `kernel.lease.Service`

```luau
export type Service = {
	read copy: (unknown) -> Result.Result<State>,
	read acquire: (unknown, Acquire) -> Result.Result<Grant>,
	read renew: (unknown, Renewal) -> Result.Result<Grant>,
	read release: (unknown, Expected) -> Result.Result<Grant>,
}
```

### `kernel.lease.API`

```luau
export type API = { read configure: typeof(configure), read withState: typeof(withState) }
```

### `kernel.lease.configure`

```luau
function configure(config: Config): Service
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
copy = function copy(raw: unknown): Result.Result<State>
acquire = function acquire(raw: unknown, request: Acquire): Result.Result<Grant>
renew = function renew(raw: unknown, request: Renewal): Result.Result<Grant>
release = function release(raw: unknown, request: Expected): Result.Result<Grant>
```

### `kernel.lease.withState`

```luau
function withState<T>(record: T & State, state: State): T & State
```

## `kernel.result`

[Source](../src/kernel/result.luau)

### `kernel.result.Success`

```luau
export type Success<T> = { read ok: true, read value: T }
```

### `kernel.result.Failure`

```luau
export type Failure = { read ok: false, read reason: string, read detail: string? }
```

### `kernel.result.Result`

```luau
export type Result<T> = Success<T> | Failure
```

### `kernel.result.API`

```luau
export type API = {
	read ok: typeof(ok),
	read fail: typeof(fail),
	read reason: typeof(reason),
	read unwrap: typeof(unwrap),
}
```

### `kernel.result.fail`

```luau
function fail(reason: string, detail: string?): Failure
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
ok = false
reason = function reason<T>(result: Result<T>): string?
detail = detail
```

### `kernel.result.ok`

```luau
function ok<T>(value: T): Success<T>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
ok = true
value = value
```

### `kernel.result.reason`

```luau
function reason<T>(result: Result<T>): string?
```

### `kernel.result.unwrap`

```luau
function unwrap<T>(result: Result<T>): T
```

## `kernel.store`

[Source](../src/kernel/store.luau)

```luau
local Codec = require("./codec")
```

```luau
local Result = require("./result")
```

### `kernel.store.Readback`

```luau
export type Readback = unknown
```

### `kernel.store.Transform`

```luau
export type Transform = (unknown) -> unknown
```

### `kernel.store.Reader`

```luau
export type Reader = { read read: (string) -> Result.Result<Readback> }
```

### `kernel.store.Writer`

```luau
export type Writer = { read update: (string, Transform) -> Result.Result<Readback> }
```

### `kernel.store.Port`

```luau
export type Port = Reader & Writer
```

### `kernel.store.Codec`

```luau
export type Codec<T> = Codec.Record<T>
```

### `kernel.store.API`

```luau
export type API = {
	read compareAndSwap: typeof(compareAndSwap),
	read committed: typeof(committed),
	read confirm: typeof(confirm),
}
```

### `kernel.store.committed`

```luau
function committed<T>(readback: Readback, expected: T, codec: Codec<T>): Result.Result<T>
```

### `kernel.store.compareAndSwap`

```luau
function compareAndSwap<T>(found: boolean, expected: T, desired: T, codec: Codec<T>): Transform
```

### `kernel.store.confirm`

```luau
function confirm(reader: Reader, key: string, expected: Result.Result<unknown>): Result.Result<Readback>
```

## `kernel.value`

[Source](../src/kernel/value.luau)

### `kernel.value.Raw`

```luau
export type Raw = { [unknown]: unknown }
```

### `kernel.value.MetatableProbe`

```luau
export type MetatableProbe = typeof(setmetatable({}, {}))
```

### `kernel.value.API`

```luau
export type API = {
	read raw: typeof(Value.raw),
	read record: typeof(Value.record),
	read finite: typeof(Value.finite),
	read nonempty: typeof(Value.nonempty),
	read whole: typeof(Value.whole),
	read opaque: typeof(Value.opaque),
	read identifier: typeof(Value.identifier),
	read dense: typeof(Value.dense),
	read freezeDeep: typeof(Value.freezeDeep),
	read hasMetatable: typeof(Value.hasMetatable),
}
```

### `kernel.value.dense`

```luau
function Value.dense(value: unknown, maximum: number, plain: boolean?): { unknown }?
```

### `kernel.value.finite`

```luau
function Value.finite(value: unknown): boolean
```

### `kernel.value.freezeDeep`

```luau
function Value.freezeDeep<T>(value: T): T
```

### `kernel.value.hasMetatable`

```luau
function Value.hasMetatable(value: unknown): boolean
```

### `kernel.value.identifier`

```luau
function Value.identifier(value: unknown, limit: number): string?
```

### `kernel.value.nonempty`

```luau
function Value.nonempty(value: unknown): boolean
```

### `kernel.value.opaque`

```luau
function Value.opaque(value: unknown, limit: number): string?
```

### `kernel.value.raw`

```luau
function Value.raw(value: unknown): Raw?
```

### `kernel.value.record`

```luau
function Value.record(value: unknown, fields: { [string]: boolean }, required: boolean?, plain: boolean?): Raw?
```

### `kernel.value.whole`

```luau
function Value.whole(value: unknown, low: number, high: number): number?
```

## `roblox.bank`

[Source](../src/roblox/bank.luau)

```luau
local Bank = require("../core/bank/vault")
```

```luau
local Transfer = require("./profile-transfer")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.bank.Result`

```luau
export type Result = {
	read ok: boolean,
	read pending: boolean?,
	read reason: string?,
	read outcome: string?,
	read bank: Bank.State?,
}
```

### `roblox.bank.Subject`

```luau
export type Subject = { read UserId: number }
```

### `roblox.bank.Point`

```luau
export type Point = { read x: number, read y: number, read z: number }
```

### `roblox.bank.Location`

```luau
export type Location = { read placeId: string | number, read position: Point }
```

### `roblox.bank.Banker`

```luau
export type Banker = { read id: string, read placeId: string | number, read position: Point, read enabled: boolean }
```

### `roblox.bank.Dependencies`

```luau
export type Dependencies<P, C, S> = {
	profiles: S,
	contextFor: (number) -> C?,
	playerFor: (number) -> Subject?,
	positionFor: (number) -> Location?,
	bankerFor: (string) -> Banker?,
	canBank: (number, P, string, string) -> boolean,
	clock: () -> number,
	identity: ((Subject) -> number?)?,
}
```

### `roblox.bank.Handle`

```luau
export type Handle = { read intent: (Subject, unknown) -> Result, read forget: (number) -> () }
```

### `roblox.bank.Core`

```luau
export type Core<P> = {
	read request: (unknown) -> Bank.Request?,
	read project: (unknown) -> Bank.State?,
	read sameRequest: (Bank.Request, Bank.Request) -> boolean,
	read apply: (P, unknown) -> (P?, string?),
}
```

### `roblox.bank.Config`

```luau
export type Config<P, C, S> = {
	read core: Core<P>,
	read read: (S, C) -> P?,
	read commit: (S, C, string, (P) -> (P?, string?)) -> Transfer.Result,
	read bank: (P) -> unknown,
	read transactionId: (number, string) -> string,
	read maxUserId: number,
	read maxReach: number,
	read rateWindowSec: number,
	read rateLimit: number,
}
```

### `roblox.bank.Host`

```luau
export type Host<P, C, S> = {
	read create: (Dependencies<P, C, S>) -> (Handle?, string?),
	read reachable: (Location?, Banker?) -> boolean,
	read MAX_REACH: number,
	read RATE_LIMIT: number,
}
```

### `roblox.bank.configure`

```luau
function configure<P, C, S>(config: Config<P, C, S>): Host<P, C, S>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function BankService.create(raw: Deps): (Handle?, string?)
```

## `roblox.camera`

[Source](../src/roblox/camera.luau)

### `roblox.camera.Spring`

```luau
export type Spring = { position: number, velocity: number }
```

### `roblox.camera.Obstruction`

```luau
export type Obstruction = {
	anchored: boolean,
	transparency: number,
	collidable: boolean,
	structural: boolean,
	actor: boolean,
	effect: boolean,
}
```

### `roblox.camera.Tuning`

```luau
export type Tuning = {
	MIN_ZOOM: number,
	MAX_ZOOM: number,
	CLASSIC_MIN_ZOOM: number,
	CLASSIC_MAX_ZOOM: number,
	SHOULDER_RIGHT: number,
	SHOULDER_UP: number,
	BASE_FOV: number,
	MAX_FOV_WIDEN: number,
	SPRINT_SPEED_RATIO: number,
	STRUCTURE_ALPHA: number,
	OBSTRUCTION_OMEGA: number,
	OBSTRUCTION_PADDING: number,
	SPRINT_LEAD: number,
	SPRINT_SPAN: number,
}
```

### `roblox.camera.create`

```luau
function Module.create(tuning: Tuning)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
zoomLimits = function Camera.zoomLimits(classic: boolean): (number, number)
isCameraStructure = function Camera.isCameraStructure(part: Obstruction): boolean
smoothObstruction = function Camera.smoothObstruction(previous: number, limit: number, dt: number): number
obstructedDistance = function Camera.obstructedDistance(distance: number, hitDistance: number?): number
newSpring = function Camera.newSpring(position: number): Spring
springStep = function Camera.springStep(spring: Spring, target: number, omega: number, dt: number): Spring
shoulderOffset = function Camera.shoulderOffset(blend: number): (number, number)
sprintWiden = function Camera.sprintWiden(speed: number, walkSpeed: number, autoRun: boolean): number
fovTarget = function Camera.fovTarget(widen: number): number
yields = function Camera.yields(cameraIsCustom: boolean, scriptedStateActive: boolean, classic: boolean): boolean
```

## `roblox.cargo`

[Source](../src/roblox/cargo.luau)

```luau
local CoreTypes = require("../core/inventory/cargo")
```

```luau
local Atomic = require("../kernel/store")
```

```luau
local LedgerTypes = require("./material-ledger")
```

```luau
local Result = require("../kernel/result")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.cargo.State`

```luau
export type State = CoreTypes.State
```

### `roblox.cargo.Intent`

```luau
export type Intent = CoreTypes.Intent
```

### `roblox.cargo.StoreOutcome`

```luau
export type StoreOutcome = LedgerTypes.StoreOutcome
```

### `roblox.cargo.Store`

```luau
export type Store = LedgerTypes.Store
```

### `roblox.cargo.Position`

```luau
export type Position = { x: number, y: number, z: number }
```

### `roblox.cargo.Camp`

```luau
export type Camp = {
	read campId: string,
	read realmId: string,
	read center: Position,
	read radiusStuds: number,
}
```

### `roblox.cargo.Dependencies`

```luau
export type Dependencies = {
	loadCamps: () -> unknown,
	store: Store,
	keyForHaul: (string) -> string,
	keyForLedger: (string) -> string,
}
```

### `roblox.cargo.Outcome`

```luau
export type Outcome = {
	read ok: boolean,
	read reason: string?,
	read replayed: boolean,
	read carriedCount: number,
	read droppedCount: number,
	read recoveredCount: number,
	read expiredCount: number,
	read bankedCount: number,
	read ledgerReplayed: boolean,
	read dropId: string?,
	read extractionId: string?,
	read intents: { Intent },
	read boundary: string,
}
```

### `roblox.cargo.ReadOutcome`

```luau
export type ReadOutcome = {
	read ok: boolean,
	read reason: string?,
	read found: boolean,
	read census: { CoreTypes.CensusRow },
	read carried: { CoreTypes.Total },
	read openDrops: { CoreTypes.Drop },
	read boundary: string,
}
```

### `roblox.cargo.Service`

```luau
export type Service = {
	read campIds: { string },
	read campFor: (campId: string) -> Camp?,
	read emptyState: () -> State,
	read admitsExtraction: (campId: string, realmId: string, position: unknown) -> (boolean, string?),
	read carry: (request: unknown) -> Outcome,
	read release: (request: unknown) -> Outcome,
	read recover: (request: unknown) -> Outcome,
	read expire: (request: unknown) -> Outcome,
	read extract: (request: unknown) -> Outcome,
	read read: (zoneId: string, actorId: string, nowSec: number) -> ReadOutcome,
}
```

### `roblox.cargo.MountResult`

```luau
export type MountResult = {
	read ok: boolean,
	read service: Service?,
	read reason: string?,
}
```

### `roblox.cargo.CorePort`

```luau
export type CorePort = {
	read emptyState: () -> State,
	read projectState: (unknown) -> (State?, string?),
	read step: (unknown, unknown, unknown) -> (CoreTypes.Result?, string?),
	read carriedOf: (unknown, unknown) -> ({ CoreTypes.Total }?, string?),
	read census: (unknown) -> ({ CoreTypes.CensusRow }?, string?),
	read openDrops: (unknown, unknown) -> ({ CoreTypes.Drop }?, string?),
}
```

### `roblox.cargo.Config`

```luau
export type Config = {
	read core: CorePort,
	read ledger: LedgerTypes.API,
	read schemaVersion: number,
	read maxText: number,
	read maxAt: number,
	read carriedSpaceKind: string,
	read bankedSpaceKind: string,
	read bankedSpaceReason: string,
	read dropExpirySeconds: number,
	read realms: { [string]: boolean },
	read boundary: string,
}
```

### `roblox.cargo.API`

```luau
export type API = {
	read mount: (Dependencies?) -> MountResult,
	read mountFromContent: (Dependencies?) -> MountResult,
	read SCHEMA_VERSION: number,
	read CARRIED_SPACE_KIND: string,
	read BANKED_SPACE_KIND: string,
	read DROP_EXPIRY_SECONDS: number,
	read REALMS: { [string]: boolean },
	read BOUNDARY: string,
	read REASONS: { string },
}
```

### `roblox.cargo.configure`

```luau
function configure(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
mount = function HaulService.mount(dependencies: Dependencies?): MountResult
mountFromContent = function HaulService.mountFromContent(sources: Dependencies?): MountResult
```

## `roblox.character-admission`

[Source](../src/roblox/character-admission.luau)

```luau
local LeaseRepository = require("../core/identity/character-lease-store")
```

```luau
local Routing = require("../core/identity/routing")
```

```luau
local Stores = require("../core/persistence/store-host")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.character-admission.Subject`

```luau
export type Subject = { read Character: unknown, read UserId: number, read Name: string? }
```

### `roblox.character-admission.Context`

```luau
export type Context = {
	read userId: number,
	read characterId: string,
	read key: string,
	read sessionId: string,
	read acquisitionId: string,
	read leaseRevision: number,
}
```

### `roblox.character-admission.ProfileFacts`

```luau
export type ProfileFacts = { read userId: number, read characterId: string, read version: number }
```

### `roblox.character-admission.CharacterOutcome`

```luau
export type CharacterOutcome<F> = {
	read ok: boolean,
	read reason: string?,
	read profile: F?,
	read lease: { read revision: number }?,
	read context: Context?,
	read releaseReason: string?,
}
```

### `roblox.character-admission.Route`

```luau
export type Route = {
	read userId: number,
	read characterId: string,
	read destinationId: string,
	read routeId: string,
	read fence: number,
	read sourcePlaceId: number?,
}
```

### `roblox.character-admission.Snapshot`

```luau
export type Snapshot = {
	read userId: number,
	read characterId: string,
	read destinationId: string?,
	read routeId: string,
	read fence: number,
}
```

### `roblox.character-admission.Runtime`

```luau
export type Runtime<P> = {
	read phase: "character_admission_started",
	read dispose: () -> boolean,
	read cleanup: (P, boolean?) -> boolean,
	read isAdmitted: (P) -> boolean,
	read previewDeparture: (P) -> { read userId: number, read characterId: string, read fence: number }?,
	read prepareReturn: (P) -> (Snapshot?, Snapshot?),
	read recover: (P, unknown) -> boolean,
}
```

### `roblox.character-admission.Refused`

```luau
export type Refused = { read phase: "character_admission_refused", read reason: string? }
```

### `roblox.character-admission.Dependencies`

```luau
export type Dependencies<P, F> = NativePorts<P & Subject, F>
```

### `roblox.character-admission.NativePorts`

```luau
export type NativePorts<P, F> = {
	zoneKey: string,
	placeId: number,
	localScenarioCapability: boolean?,
	sessionId: string,
	timing: {
		clock: () -> number,
		publish: (P, string) -> (),
		storePrefix: string?,
		observe: (((Stores.Observation) -> ()) -> () -> ())?,
	}?,
	stage: ((P, string) -> ())?,
	routing: { projectPolicy: index<Routing.API, "projectPolicy">, accept: index<Routing.API, "accept"> },
	routingContent: { binding: unknown, budget: unknown, handoff: unknown, refusals: unknown, unroutedChannels: unknown },
	catalog: { destinations: unknown },
	reclaim: { attempts: number, seconds: number, wait: (number) -> () }?,
	clear: (P) -> boolean,
	preflight: (P) -> boolean,
	refuse: (P, string) -> boolean,
	clock: () -> number,
	identity: ((P) -> unknown)?,
	acquisitionId: (number, number) -> string,
	waitLeaseRenewal: (() -> ())?,
	scheduleLeaseRenewal: ((number, () -> ()) -> ())?,
	character: {
		admit: (unknown) -> CharacterOutcome<F>,
		release: (number, string, string, string, number) -> { read ok: boolean, read reason: string? },
		renew: ((string, string, string, number) -> LeaseRepository.Outcome)?,
	},
	fence: (unknown) -> { read ok: boolean },
	profile: { load: (Context?) -> F?, unload: (Context?) -> boolean, level: (Context?) -> number? },
	session: { bind: (P, Context?) -> (boolean, string?), release: (P, Context?) -> boolean },
	actor: { admitPlayer: (P, F) -> (boolean, string?), removePlayer: (P) -> boolean },
	body: { admitPlayer: (P, string) -> (boolean, string?), removePlayer: (P) -> boolean },
	movement: { admitPlayer: (P) -> (boolean, string?), removePlayer: (P) -> boolean },
	players: {
		present: (P) -> boolean,
		getJoinData: (P) -> unknown,
		getPlayers: () -> { P },
		connectRemoving: ((P) -> boolean) -> () -> (),
		connectAdded: ((P) -> ()) -> () -> (),
	},
	route: { arrive: (unknown, unknown) -> Route? },
	roster: {
		owns: (number, string) -> (boolean, unknown),
		markDeparted: (number, string, string, unknown) -> (boolean, unknown),
		markLevel: (number, string, number) -> boolean,
		markPlayed: (number, string, number) -> boolean,
	},
	warAdmission: {
		depart: (Route, boolean) -> boolean,
		authority: () -> boolean,
		reconnect: (number) -> Route?,
		claim: (Route) -> (boolean, string?),
		restoreDeparture: (Route) -> (boolean, string?),
		refusalCodes: { [string]: boolean },
	}?,
	receipt: (
		P,
		{ read userId: number, read characterId: string, read profileVersion: number, read zoneKey: string }
	) -> (boolean, string?),
}
```

### `roblox.character-admission.Config`

```luau
export type Config<F> = {
	read profileFacts: (F) -> ProfileFacts,
	read projectProfile: (Subject, F, string?) -> (),
	read sameIdentity: (unknown, unknown) -> boolean,
	read leaseFailure: () -> (),
	read idLimit: number,
	read timingRecordLimit: number,
	read timingOperationLimit: number,
	read timingReasonLimit: number,
	read reclaimReason: string,
	read actorRetryReasons: { [string]: boolean },
	read cleanupSeconds: number,
	read retrySeconds: number,
	read renewSeconds: number,
	read leaseSeconds: number,
}
```

### `roblox.character-admission.API`

```luau
export type API = { read start: typeof(start) }
```

### `roblox.character-admission.start`

```luau
function start<P, F>(config: Config<F>, deps: Dependencies<P, F>): Runtime<P & Subject> | Refused
```

## `roblox.chat`

[Source](../src/roblox/chat.luau)

### `roblox.chat.DirectQuery`

```luau
export type DirectQuery = (number, { number }) -> { number }
```

### `roblox.chat.directAllowed`

```luau
function Chat.directAllowed(query: DirectQuery, requester: number, target: number): boolean
```

### `roblox.chat.permission`

```luau
function Chat.permission(
	query: () -> boolean,
	waitFor: (number) -> (),
	studio: boolean,
	userId: number,
	attempts: number,
	retry: number
): string
```

### `roblox.chat.removeForeign`

```luau
function Chat.removeForeign<Channel>(
	children: { Channel },
	nameOf: (Channel) -> string,
	isChannel: (Channel) -> boolean,
	keep: (string) -> boolean,
	destroy: (Channel) -> ()
): { string }
```

### `roblox.chat.seat`

```luau
function Chat.seat<Channel>(
	channels: { Channel },
	userId: number,
	nameOf: (Channel) -> string,
	addUser: (Channel, number) -> boolean
): { string }
```

## `roblox.consumables`

[Source](../src/roblox/consumables.luau)

```luau
local Consumables = require("../core/progression/consumables")
```

### `roblox.consumables.Actor`

```luau
export type Actor = Consumables.ActorView & { read characterId: string? }
```

### `roblox.consumables.Snapshot`

```luau
export type Snapshot = { actor: Actor?, mobs: { read [string]: Consumables.Mob }?, now: number }
```

### `roblox.consumables.Status`

```luau
export type Status = { cue: string, hpRemaining: number, manaRemaining: number, hpGained: number?, manaGained: number? }
```

### `roblox.consumables.CommitResult`

```luau
export type CommitResult = { read ok: boolean, read outcome: string, read reason: string? }
```

### `roblox.consumables.Rules`

```luau
export type Rules = {
	read item: (unknown) -> Consumables.Item?,
	read begin: (
		Consumables.State?,
		Consumables.ActorView,
		{ read [string]: Consumables.Mob }?,
		unknown,
		unknown,
		unknown
	) -> (Consumables.State?, string?),
}
```

### `roblox.consumables.Dependencies`

```luau
export type Dependencies<P, C, B> = {
	core: Rules,
	present: (P) -> boolean,
	contextFor: (P) -> C?,
	characterFor: (P) -> B?,
	snapshotFor: (P) -> Snapshot?,
	characterIdFor: (C) -> string,
	alive: (P) -> boolean,
	stationary: (P) -> boolean,
	profilePresent: (C) -> boolean,
	recorded: (C, string) -> boolean,
	commit: (P, C, B, string, string) -> CommitResult,
	receipt: () -> string,
	begin: (P, string, number) -> boolean,
	cancel: ((P) -> ())?,
	unavailableCue: string,
	idleCue: string,
	movementToleranceSquared: number,
}
```

### `roblox.consumables.Handle`

```luau
export type Handle<P> = {
	read use: (P, unknown, unknown) -> (boolean, string),
	read status: (P) -> Status,
	read enforce: (P) -> (),
	read forget: (P) -> (),
}
```

### `roblox.consumables.UseRequest`

```luau
export type UseRequest = { kind: "use", itemId: string, order: number } | { kind: "refused" }
```

### `roblox.consumables.create`

```luau
function Service.create<P, C, B>(deps: Dependencies<P, C, B>): Handle<P>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
use = function use(player: P, rawItemId: unknown, rawOrder: unknown): (boolean, string)
status = function status(player: P): Status
enforce = function enforce(player: P)
forget = function(player)
```

### `roblox.consumables.decodeUseRequest`

```luau
function Service.decodeUseRequest(item: (unknown) -> Consumables.Item?, itemId: unknown, order: unknown): UseRequest
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
kind = "use"
itemId = itemId
order = order
```

## `roblox.contact-markers`

[Source](../src/roblox/contact-markers.luau)

### `roblox.contact-markers.Host`

```luau
export type Host<C, T> = {
	stamp: (C) -> (string?, number?),
	listen: (C, (T) -> ()) -> () -> (),
	marker: (T, () -> ()) -> () -> (),
	admit: (C, T, string, number) -> boolean,
}
```

### `roblox.contact-markers.create`

```luau
function Module.create<C, T>(host: Host<C, T>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
watch = function Contacts.watch(character: C): () -> ()
onContact = function Contacts.onContact(character: C, id: string, at: number, present: () -> (), confirmed: boolean?): () -> ()
confirmed = function Contacts.confirmed(character: C, id: string, at: number?): boolean
retrigger = function Contacts.retrigger(character: C, track: T, id: string?, at: number?)
```

## `roblox.conversation-camera`

[Source](../src/roblox/conversation-camera.luau)

```luau
local Dynamics = require("./camera")
```

### `roblox.conversation-camera.Point`

```luau
export type Point = { x: number, y: number, z: number }
```

### `roblox.conversation-camera.Rect`

```luau
export type Rect = { x: number, y: number, width: number, height: number }
```

### `roblox.conversation-camera.View`

```luau
export type View = { eye: Point, look: Point }
```

### `roblox.conversation-camera.State`

```luau
export type State = { key: string?, released: boolean, blend: Dynamics.Spring }
```

### `roblox.conversation-camera.Tuning`

```luau
export type Tuning = {
	gap: number,
	minimumSpace: number,
	omega: number,
	minimumDistance: number,
	coverage: number,
	eyeLift: number,
	angles: { number },
	touchThresholdSquared: number,
	stickThresholdSquared: number,
}
```

### `roblox.conversation-camera.create`

```luau
function Module.create(
	Action: {
		newSpring: (number) -> Dynamics.Spring,
		springStep: (Dynamics.Spring, number, number, number) -> Dynamics.Spring,
	},
	tuning: Tuning
)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
new = function Core.new(): State
step = function Core.step(
		state: State,
		key: string?,
		available: boolean,
		override: boolean,
		dt: number,
		departed: boolean?
	): State
space = function Core.space(safe: Rect, card: Rect): Rect?
views = function Core.views(
		focus: Point,
		toward: Point,
		width: number,
		height: number,
		fov: number,
		region: Rect,
		radius: number?
	): { View }
choose = function Core.choose(views: { View }, clear: (View) -> boolean): View?
cameraGesture = function Core.cameraGesture(kind: string, x: number, y: number, rotating: boolean, processed: boolean): boolean
```

## `roblox.cue-mixer`

[Source](../src/roblox/cue-mixer.luau)

### `roblox.cue-mixer.MixSpec`

```luau
export type MixSpec = { family: string, maxVoices: number, minIntervalSec: number, voiceSec: number }
```

### `roblox.cue-mixer.DuckSpec`

```luau
export type DuckSpec = { bedGain: number, voiceBedGain: number, families: { string } }
```

### `roblox.cue-mixer.CueSource`

```luau
export type CueSource = {
	specFor: (cueId: string) -> MixSpec?,
	duck: () -> DuckSpec,
}
```

### `roblox.cue-mixer.Mixer`

```luau
export type Mixer = {
	admit: (self: Mixer, cueId: string) -> boolean,
	gate: (self: Mixer, cueId: string) -> boolean,
	activeVoices: (self: Mixer, family: string) -> number,
	duckGain: (self: Mixer) -> number,
	setVoiceActive: (self: Mixer, active: boolean) -> (),
}
```

### `roblox.cue-mixer.new`

```luau
function SoundCueMix.new(catalog: CueSource, clock: () -> number): Mixer
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
admit = function admit(_self: Mixer, cueId: string): boolean
gate = function gate(self: Mixer, cueId: string): boolean
activeVoices = function activeVoices(_self: Mixer, family: string): number
duckGain = function duckGain(self: Mixer): number
setVoiceActive = function setVoiceActive(_self: Mixer, active: boolean)
```

## `roblox.cue-playback`

[Source](../src/roblox/cue-playback.luau)

### `roblox.cue-playback.VoiceProps`

```luau
export type VoiceProps = {
	SoundId: string,
	Volume: number,
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
}
```

### `roblox.cue-playback.PlaySpec`

```luau
export type PlaySpec = {
	soundId: string,
	volume: number,
	spatial: boolean,
	rollOffMinDistance: number,
	rollOffMaxDistance: number,
	voiceSec: number,
}
```

### `roblox.cue-playback.Source`

```luau
export type Source = { specFor: (string) -> PlaySpec? }
```

### `roblox.cue-playback.Deps`

```luau
export type Deps<N, V> = {
	mountVoice: (string, VoiceProps, N) -> (() -> (), V),
	play: (V) -> (),
	schedule: (number, () -> ()) -> (),
	home: N,
	admit: (string) -> boolean,
	catalog: Source,
	tailSec: number,
}
```

### `roblox.cue-playback.animator`

```luau
function Playback.animator(host: { clock: () -> number, connect: (() -> ()) -> () -> () })
```

### `roblox.cue-playback.make`

```luau
function Playback.make<N, V>(deps: Deps<N, V>): (cueId: string, at: N?) -> boolean
```

## `roblox.data-store`

[Source](../src/roblox/data-store.luau)

### `roblox.data-store.RetryPolicy`

```luau
export type RetryPolicy = { attempts: number, baseDelay: number, maxDelay: number }
```

### `roblox.data-store.retryPolicy`

```luau
function DataStore.retryPolicy(policy: RetryPolicy)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
delay = function delay(attempt: number, jitter: number): number
run = function run<T>(op: () -> (boolean, T), sleep: (number) -> (), jitter: () -> number): (boolean, T)
```

## `roblox.equipment-queue`

[Source](../src/roblox/equipment-queue.luau)

### `roblox.equipment-queue.Deps`

```luau
export type Deps<P, C> = {
	spawn: (() -> ()) -> (),
	active: () -> boolean,
	current: (P, C) -> boolean,
	perform: (P, C, () -> boolean) -> (),
	warn: (string) -> (),
}
```

### `roblox.equipment-queue.Queue`

```luau
export type Queue<P, C> = {
	request: (P, C) -> (),
	invalidate: (P) -> (),
	forget: (P) -> (),
	generation: (P) -> number?,
	running: (P) -> boolean,
	dispose: () -> (),
}
```

### `roblox.equipment-queue.create`

```luau
function EquipmentApplyQueue.create<P, C>(deps: Deps<P, C>): Queue<P, C>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
request = function queue.request(player: P, character: C)
invalidate = function queue.invalidate(player: P)
forget = function queue.forget(player: P)
generation = function queue.generation(player: P): number?
running = function queue.running(player: P): boolean
dispose = function queue.dispose()
```

## `roblox.equipment-rig`

[Source](../src/roblox/equipment-rig.luau)

### `roblox.equipment-rig.Ownership`

```luau
export type Ownership<O, C> = {
	read current: () -> O?,
	read create: () -> O,
	read run: <T...>(O, () -> T...) -> T...,
	read dispose: (O) -> (),
	read checkpoint: (O) -> C,
	read rollback: (O, C) -> (),
}
```

### `roblox.equipment-rig.MeshCache`

```luau
export type MeshCache<K, V> = {
	read peek: (K) -> V?,
	read get: (K) -> V?,
}
```

### `roblox.equipment-rig.Failure`

```luau
export type Failure<A> = { application: A, reason: string }
```

### `roblox.equipment-rig.BatchState`

```luau
export type BatchState<P, O> = { accessoryOwners: { [P]: O } }
```

### `roblox.equipment-rig.BatchHost`

```luau
export type BatchHost<A, P, O> = {
	read slot: (A) -> string,
	read pieceSlot: (P) -> string?,
	read permitted: (A) -> string?,
	read createOwner: () -> O,
	read run: <T...>(O, () -> T...) -> T...,
	read dispose: (O) -> (),
	read make: (A) -> ({ P }?, string?),
	read attach: (A, P) -> string?,
	read assertCurrent: () -> (),
	read refused: (A, string) -> (),
}
```

### `roblox.equipment-rig.applyBatch`

```luau
function applyBatch<A, P, O>(
	host: BatchHost<A, P, O>,
	state: BatchState<P, O>,
	applications: { A },
	reused: { [A]: boolean },
	reusedPieces: { [P]: boolean },
	previous: { P },
	retiredOwners: { [O]: boolean },
	retiredPieces: { [P]: boolean }
): ({ A }, { Failure<A> })
```

### `roblox.equipment-rig.lifetime`

```luau
function lifetime<O, C, N>(ownership: Ownership<O, C>, adopt: (N) -> (), report: (string) -> ())
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
withOwner = function withOwner<T...>(build: () -> T...): T...
attempt = function attempt<T...>(build: () -> T...): T...
assertCurrent = function assertCurrent(fence: (() -> boolean)?)
afterExternal = function afterExternal(fence: (() -> boolean)?, ok: boolean, value: N)
stale = stale
disposeLoose = function()
```

### `roblox.equipment-rig.meshCache`

```luau
function meshCache<K, V>(cache: MeshCache<K, V>, ceiling: number)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
resolve = function resolve(key: K, step: () -> (), clock: () -> number): V
refuse = function(key: K)
isRefused = function(key: K): boolean
isInFlight = function(key: K): boolean
refusedCount = function(): number
reset = function()
```

## `roblox.guild-bank`

[Source](../src/roblox/guild-bank.luau)

```luau
local BankTypes = require("../core/social/guildbank")
```

```luau
local LedgerTypes = require("../core/social/guildledger")
```

```luau
local Records = require("./social-records")
```

```luau
local Transfer = require("./profile-transfer")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.guild-bank.Bank`

```luau
export type Bank = Records.Ledger<string, BankTypes.State, BankTypes.Receipt>
```

### `roblox.guild-bank.BankResult`

```luau
export type BankResult = Records.Settled<BankTypes.State, BankTypes.Receipt>
```

### `roblox.guild-bank.Material`

```luau
export type Material = { read id: string, read label: string }
```

### `roblox.guild-bank.MaterialRow`

```luau
export type MaterialRow = { read materialId: string, read label: string, read held: number, read stock: number }
```

### `roblox.guild-bank.LogRow`

```luau
export type LogRow = { read kind: string, read actorId: number, read materialId: string, read count: number }
```

### `roblox.guild-bank.Projection`

```luau
export type Projection = {
	read available: boolean,
	read role: "member" | "steward",
	read dailyLimit: number,
	read materials: { MaterialRow },
	read log: { LogRow },
}
```

### `roblox.guild-bank.ProfileAccess`

```luau
export type ProfileAccess<P> = { read read: () -> P?, read update: ((P) -> P) -> (), read save: () -> boolean }
```

### `roblox.guild-bank.Membership`

```luau
export type Membership = { fellowshipId: string, role: "member" | "steward", memberIds: { number } }
```

### `roblox.guild-bank.Dependencies`

```luau
export type Dependencies<P> = {
	bank: Bank,
	materials: { Material },
	profileFor: (number) -> ProfileAccess<P>?,
	membershipFor: (number, boolean) -> (Membership?, string?),
	clock: () -> number,
	newOpId: () -> string,
}
```

### `roblox.guild-bank.Outcome`

```luau
export type Outcome = { ok: boolean, reason: string?, pending: boolean }
```

### `roblox.guild-bank.Handle`

```luau
export type Handle = {
	read join: (number) -> Outcome,
	read deposit: (number, unknown, unknown) -> Outcome,
	read withdraw: (number, unknown, unknown) -> Outcome,
	read projection: (number) -> Projection | false,
	read refresh: (number) -> Outcome,
	read forget: (number) -> (),
}
```

### `roblox.guild-bank.ProfileLedger`

```luau
export type ProfileLedger<P> = {
	read projectLedger: (unknown) -> LedgerTypes.Ledger?,
	read beginDeposit: (P, string, string, string, number, number, LedgerTypes.Limits) -> (P?, string?),
	read settle: (P, string) -> (P?, string?),
	read refund: (P, string, LedgerTypes.Limits) -> (P?, string?),
	read claim: (P, unknown, number, string, LedgerTypes.Limits) -> (P?, string?),
	read acked: (P, { string }) -> (P?, string?),
	read claimed: (P, string) -> boolean,
	read canWithdraw: (P) -> boolean,
}
```

### `roblox.guild-bank.Config`

```luau
export type Config<P> = {
	read ledger: ProfileLedger<P>,
	read copy: (P) -> P,
	read profileLedger: (P) -> unknown,
	read inventory: (P) -> { [string]: number },
	read capacity: (P?) -> number,
	read receiptsFor: (unknown, unknown) -> { BankTypes.Receipt }?,
	read maxItemCount: number,
	read maxMove: number,
	read joinRetrySec: number,
	read healRetentionSec: number,
	read receiptTtlSec: number,
	read memberDailyWithdrawal: number,
	read logRows: number,
}
```

### `roblox.guild-bank.API`

```luau
export type API<P> = { read mount: (Dependencies<P>) -> (Handle?, string?) }
```

### `roblox.guild-bank.configure`

```luau
function configure<P>(config: Config<P>): API<P>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
mount = function GuildBankService.mount(deps: Dependencies<P>): (Handle?, string?)
```

## `roblox.input-bindings`

[Source](../src/roblox/input-bindings.luau)

### `roblox.input-bindings.Action`

```luau
export type Action<C> = {
	id: string,
	context: C,
	keyboard: { string },
	gamepad: string?,
	chord: string?,
	release: boolean?,
	gamepadAlt: string?,
	touch: "thumbstick" | "button" | "screen",
	affordance: string,
}
```

### `roblox.input-bindings.create`

```luau
function Module.create<C>(actions: { Action<C> }, labels: { [string]: string }, modifier: string)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
get = function Bindings.get(id: string): Action<C>
keyboardNames = function Bindings.keyboardNames(id: string): { string }
primaryKeyboard = function Bindings.primaryKeyboard(id: string): string
gamepad = function Bindings.gamepad(id: string): string?
matches = function Bindings.matches(id: string, name: string): boolean
keyboardLabel = function Bindings.keyboardLabel(id: string): string
gamepadLabel = function Bindings.gamepadLabel(id: string): string?
matchesCode = function Bindings.matchesCode<K>(id: string, code: unknown, keys: { [string]: K }): boolean
matchesInput = function Bindings.matchesInput<K>(id: string, code: unknown, keys: { [string]: K }, held: (string) -> boolean): boolean
forContext = function Bindings.forContext(context: C): { Action<C> }
```

## `roblox.input-contexts`

[Source](../src/roblox/input-contexts.luau)

### `roblox.input-contexts.Template`

```luau
export type Template = { folder: string, name: string }
```

### `roblox.input-contexts.Surfaces`

```luau
export type Surfaces = {
	template: (string, string) -> unknown?,
	existing: (string) -> unknown?,
	adopt: (unknown, string) -> unknown?,
}
```

### `roblox.input-contexts.Mounted`

```luau
export type Mounted = typeof(mounted("", {}, nil))
```

### `roblox.input-contexts.create`

```luau
function Contexts.create<N, A>(host: {
	find: (N, string) -> N?,
	wait: (N, string, number) -> N?,
	clock: () -> number,
	isContext: (N) -> boolean,
	asAction: (N) -> A?,
	name: (N) -> string,
	minimumWait: number,
})
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
action = function Input.action(context: N, name: string): A
context = function Input.context(root: N, path: { string }, required: { string }, deadline: number): N
```

### `roblox.input-contexts.mount`

```luau
function Contexts.mount(plan: { Template }, raw: Surfaces?, phases: { mounted: string, refused: string }): Mounted
```

## `roblox.input-profile`

[Source](../src/roblox/input-profile.luau)

```luau
local Value = require("../kernel/value")
```

### `roblox.input-profile.Device`

```luau
export type Device = "keyboard" | "gamepad" | "touch"
```

### `roblox.input-profile.TouchAffordance`

```luau
export type TouchAffordance = "thumbstick" | "button" | "screen"
```

### `roblox.input-profile.Action`

```luau
export type Action = {
	id: string,
	keyboard: string,
	gamepad: string,
	touch: TouchAffordance,
}
```

### `roblox.input-profile.Profile`

```luau
export type Profile = {
	id: string,
	actions: { Action },
}
```

### `roblox.input-profile.Session`

```luau
export type Session = typeof(session("", nil, nil, nil, nil))
```

### `roblox.input-profile.create`

```luau
function Module.create(profiles: { [string]: Profile }, phases: { mounted: string, refused: string })
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
profile = function Input.profile(name: unknown): Profile?
reach = function Input.reach(profile: unknown, device: unknown): { string }
parity = function Input.parity(profile: unknown): boolean
coverage = function Input.coverage(profile: unknown, hosts: unknown): boolean
start = function Input.start(rawDependencies: Dependencies): Session
```

## `roblox.inventory`

[Source](../src/roblox/inventory.luau)

```luau
local Stacks = require("../core/inventory/stacks")
```

### `roblox.inventory.Inventory`

```luau
export type Inventory = Stacks.Inventory
```

### `roblox.inventory.RewardItem`

```luau
export type RewardItem = { id: string, count: number }
```

### `roblox.inventory.Reader`

```luau
export type Reader<R, P> = (R) -> P?
```

### `roblox.inventory.Service`

```luau
export type Service<S, R, P> = {
	read getItems: (Reader<R, P>, S) -> Inventory,
	read getCount: (Reader<R, P>, S, string) -> number,
	read hasItem: (Reader<R, P>, S, string, number?) -> boolean,
	read addItem: (S, string, number) -> boolean,
	read removeItem: (S, string, number) -> boolean,
	read commitRewardTransaction: (S, string, { RewardItem }, number, number?, string?) -> boolean,
}
```

### `roblox.inventory.Config`

```luau
export type Config<S, C, R, P> = {
	read context: (S) -> C?,
	read readable: (C) -> R,
	read peek: (R) -> P?,
	read update: (C, (P) -> P) -> (),
	read inventory: (P) -> Inventory,
	read withInventory: (P, Inventory) -> P,
	read capacity: (P) -> number,
	read exists: (string) -> boolean,
	read permanent: (string) -> boolean,
	read maxStack: number,
	read transactionIdLimit: number,
	read copyBag: (Inventory) -> Inventory,
	read validCount: (unknown) -> boolean,
	read addToBag: (Inventory, string, number) -> Inventory,
	read removeFromBag: (Inventory, string, number) -> (Inventory, boolean),
	read fits: (Inventory, Inventory, number) -> boolean,
	read recorded: (P, string) -> boolean,
	read reward: (P, string, Inventory, number, number, string?) -> P,
}
```

### `roblox.inventory.create`

```luau
function create<S, C, R, P>(config: Config<S, C, R, P>): Service<S, R, P>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
getItems = function getItems(read: Reader<R, P>, subject: S): Inventory
getCount = function getCount(read: Reader<R, P>, subject: S, id: string): number
hasItem = function(read: Reader<R, P>, subject: S, id: string, count: number?): boolean
addItem = function addItem(subject: S, id: string, count: number): boolean
removeItem = function removeItem(subject: S, id: string, count: number): boolean
commitRewardTransaction = function commitRewardTransaction(
		subject: S,
		id: string,
		items: { RewardItem },
		experience: number,
		gold: number?,
		season: string?
	): boolean
```

## `roblox.leased-record-session`

[Source](../src/roblox/leased-record-session.luau)

```luau
local LeaseRecords = require("../core/identity/character-lease")
```

```luau
local LeaseStores = require("../core/identity/character-lease-store")
```

```luau
local Records = require("../core/persistence/record-store")
```

```luau
local Sessions = require("../core/persistence/profile-session")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.leased-record-session.Lease`

```luau
export type Lease = LeaseRecords.Record
```

### `roblox.leased-record-session.SessionState`

```luau
export type SessionState = Sessions.State
```

### `roblox.leased-record-session.StoreOutcome`

```luau
export type StoreOutcome = Records.StoreOutcome
```

### `roblox.leased-record-session.OutcomeStore`

```luau
export type OutcomeStore = Records.Store
```

### `roblox.leased-record-session.Dependencies`

```luau
export type Dependencies = {
	store: OutcomeStore,
	leaseKeyFor: (string) -> string,
	zoneKeyFor: (string, string) -> string,
	leaseZoneFamily: { string }?,
	clock: () -> number,
}
```

### `roblox.leased-record-session.Accepted`

```luau
export type Accepted<R> = {
	ok: true,
	reason: string?,
	releaseReason: string?,
	session: SessionState,
	lease: Lease,
	zoneSnapshot: Records.Accepted<R>,
}
```

### `roblox.leased-record-session.Refused`

```luau
export type Refused =
	{ ok: false, reason: string?, releaseReason: string?, session: nil, lease: nil, zoneSnapshot: nil }
```

### `roblox.leased-record-session.Outcome`

```luau
export type Outcome<R> = Accepted<R> | Refused
```

### `roblox.leased-record-session.SaveAccepted`

```luau
export type SaveAccepted<R> = { ok: true, reason: string?, lease: Lease, zoneSnapshot: Records.Accepted<R> }
```

### `roblox.leased-record-session.SaveRefused`

```luau
export type SaveRefused = { ok: false, reason: string?, lease: Lease?, zoneSnapshot: nil }
```

### `roblox.leased-record-session.SaveOutcome`

```luau
export type SaveOutcome<R> = SaveAccepted<R> | SaveRefused
```

### `roblox.leased-record-session.SessionPort`

```luau
export type SessionPort = {
	read openAcquired: (number, number) -> (SessionState?, string?),
	read dirty: (SessionState, number, string) -> Sessions.Outcome,
	read begin: (SessionState, number) -> Sessions.Outcome,
	read finish: (SessionState, number, boolean) -> Sessions.Outcome,
}
```

### `roblox.leased-record-session.Config`

```luau
export type Config<R> = {
	read leaseRecord: LeaseRecords.API,
	read leaseStore: LeaseStores.API,
	read session: SessionPort,
	read records: Records.API<R>,
	read copyRecord: (unknown) -> (R?, string?),
	read withPayload: (R, unknown) -> (R?, string?),
	read characterId: (R) -> string,
	read leaseSeconds: number,
	read dirtyReason: string,
}
```

### `roblox.leased-record-session.API`

```luau
export type API<R> = {
	read acquireAndHydrate: (Dependencies, string, string, string, string) -> Outcome<R>,
	read savePayload: (Dependencies, SessionState, unknown, unknown, unknown) -> SaveOutcome<R>,
}
```

### `roblox.leased-record-session.configure`

```luau
function configure<R>(config: Config<R>): API<R>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
acquireAndHydrate = function Coordinator.acquireAndHydrate(
		dependencies: Dependencies,
		zoneId: string,
		characterId: string,
		sessionId: string,
		acquisitionId: string
	): Outcome<R>
savePayload = function Coordinator.savePayload(
		dependencies: Dependencies,
		session: SessionState,
		leaseRaw: unknown,
		zoneSnapshot: unknown,
		questsRaw: unknown
	): SaveOutcome<R>
```

## `roblox.mail`

[Source](../src/roblox/mail.luau)

```luau
local Mail = require("../core/mail/mailbox")
```

```luau
local Transfer = require("./profile-transfer")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.mail.Context`

```luau
export type Context = Transfer.Identity
```

### `roblox.mail.Envelope`

```luau
export type Envelope = Mail.Envelope
```

### `roblox.mail.Pointer`

```luau
export type Pointer = Mail.Pointer
```

### `roblox.mail.Result`

```luau
export type Result = {
	ok: boolean,
	reason: string?,
	pending: boolean?,
	envelope: Envelope?,
	outcomes: { [string]: Result }?,
}
```

### `roblox.mail.Outcome`

```luau
export type Outcome = { read ok: boolean, read value: unknown, read reason: string? }
```

### `roblox.mail.Effect`

```luau
export type Effect<P> = (P) -> (P?, string?)
```

### `roblox.mail.Dependencies`

```luau
export type Dependencies<P, Surface> = {
	profiles: Surface,
	envelopes: {
		read getOutcome: (string) -> Outcome,
		read updateOutcome: (string, (Envelope?) -> Envelope?) -> Outcome,
	},
	contextFor: (number) -> Context?,
	identity: ((unknown) -> unknown)?,
	resolveRecipient: (number, unknown, number) -> unknown,
	tradeable: (number, P, string, number) -> boolean,
	allowed: (number, number) -> boolean,
	reserveInbox: (number, string, Envelope) -> (boolean, string?),
	releaseInbox: (number, string, Envelope) -> boolean,
	releaseRecipientInbox: ((number, string, Envelope) -> boolean)?,
	clock: () -> number,
	ttlSec: number,
	requireSessions: boolean?,
}
```

### `roblox.mail.Service`

```luau
export type Service = {
	read send: (unknown, unknown) -> Result,
	read claim: (unknown, string) -> Result,
	read returnMail: (unknown, string) -> Result,
	read expire: (string) -> Result,
	read recover: (string, number?, Context?) -> Result,
	read admit: (number) -> Result,
	read status: (unknown, string) -> Result,
}
```

### `roblox.mail.Config`

```luau
export type Config<P, Surface> = {
	read identity: (unknown) -> unknown,
	read core: Mail.Mailbox<P>,
	read profileFor: (Surface, (number) -> Context?, number) -> (P?, Context?),
	read commit: (Surface, Context, string, Effect<P>) -> Transfer.Result,
	read update: (Surface, Context, (P) -> P) -> (),
	read characterId: (P) -> string?,
	read pointers: (P) -> { [string]: Pointer }?,
	read withPointers: (P, { [string]: Pointer }) -> P,
	read envelopeKey: (string) -> string,
	read transactionId: (string, string) -> string,
	read senderId: (string) -> number?,
	read maxUserId: number,
	read maxPointers: number,
	read maxTtlSec: number,
	read idLimit: number,
	read rateWindowSec: number,
	read rateLimit: number,
}
```

### `roblox.mail.Host`

```luau
export type Host<P, Surface> = {
	read create: (Dependencies<P, Surface>?) -> (Service?, string?),
	read RATE_LIMIT: number,
}
```

### `roblox.mail.configure`

```luau
function configure<P, Surface>(config: Config<P, Surface>): Host<P, Surface>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function MailService.create(depsValue: Deps?): (Service?, string?)
```

## `roblox.market-profile-wallet`

[Source](../src/roblox/market-profile-wallet.luau)

```luau
local Wallets = require("../core/market/wallet")
```

### `roblox.market-profile-wallet.Inventory`

```luau
export type Inventory = { [string]: number }
```

### `roblox.market-profile-wallet.Wallet`

```luau
export type Wallet =
	{ read read: () -> Wallets.State?, read write: (unknown) -> boolean, read room: (string) -> number }
```

### `roblox.market-profile-wallet.Dependencies`

```luau
export type Dependencies<P, I> = {
	userId: number,
	materials: { string },
	readProfile: () -> P?,
	updateProfile: ((P) -> P) -> (),
	saveProfile: () -> boolean,
	maxItemCount: number,
	maxInventoryEntries: number,
	items: I?,
}
```

### `roblox.market-profile-wallet.Core`

```luau
export type Core = {
	read ledgerOf: (unknown) -> Wallets.Ledger?,
	read compose: (unknown, unknown, unknown, unknown) -> Wallets.State?,
	read projectState: (unknown) -> Wallets.State?,
}
```

### `roblox.market-profile-wallet.Config`

```luau
export type Config<P, I> = {
	read wallet: Core,
	read items: I,
	read goods: (P, { string }, I) -> Inventory,
	read coin: (P) -> number,
	read inventory: (P) -> Inventory,
	read ledger: (P) -> unknown,
	read withAccount: (P, number, Inventory, Wallets.Ledger) -> P,
	read capacity: (P) -> number,
	read entries: (Inventory) -> number,
	read fits: (Inventory, Inventory, number) -> boolean,
	read unboundCount: (P, string) -> number,
}
```

### `roblox.market-profile-wallet.Host`

```luau
export type Host<P, I> = {
	read create: (Dependencies<P, I>) -> (Wallet?, string?),
	read applyDelta: (P, Wallets.State, Wallets.State, number, number) -> (P?, string?),
}
```

### `roblox.market-profile-wallet.configure`

```luau
function configure<P, I>(config: Config<P, I>): Host<P, I>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
applyDelta = function MarketProfileWallet.applyDelta(
		profile: Profile,
		base: State,
		nextState: State,
		maxItemCount: number,
		maxInventoryEntries: number
	): (Profile?, string?)
create = function MarketProfileWallet.create(raw: Dependencies<P, I>): (Wallet?, string?)
```

## `roblox.market-settlement`

[Source](../src/roblox/market-settlement.luau)

```luau
local Book = require("../core/market/book")
```

```luau
local Records = require("./social-records")
```

```luau
local Value = require("../kernel/value")
```

```luau
local Wallet = require("../core/market/wallet")
```

### `roblox.market-settlement.BookResult`

```luau
export type BookResult = Records.Settled<Book.State, Book.Receipt>
```

### `roblox.market-settlement.BookService`

```luau
export type BookService = {
	read read: (string, string) -> BookResult,
	read apply: (string, string, unknown) -> BookResult,
}
```

### `roblox.market-settlement.WalletAccess`

```luau
export type WalletAccess = {
	read read: () -> Wallet.State?,
	read write: (Wallet.State) -> boolean,
	read room: ((string) -> number)?,
}
```

### `roblox.market-settlement.Dependencies`

```luau
export type Dependencies = { book: BookService, wallet: WalletAccess, clock: () -> number, newOpId: () -> string }
```

### `roblox.market-settlement.Outcome`

```luau
export type Outcome = { ok: boolean, reason: string?, opId: string?, pending: boolean }
```

### `roblox.market-settlement.Service`

```luau
export type Service = {
	read consign: (string, string, number, number, string?) -> Outcome,
	read buy: (string, string, number, number, string?) -> Outcome,
	read cancel: (string, string, string) -> Outcome,
	read claimAll: (string, string) -> Outcome,
	read heal: () -> Outcome,
}
```

### `roblox.market-settlement.WalletOps`

```luau
export type WalletOps = {
	read beginConsign: (unknown, unknown, unknown, unknown, unknown, unknown, unknown?) -> Wallet.Result,
	read beginBuy: (unknown, unknown, unknown, unknown, unknown, unknown, unknown?) -> Wallet.Result,
	read refund: (unknown, unknown) -> Wallet.Result,
	read settleConsign: (unknown, unknown) -> Wallet.Result,
	read claim: (unknown, unknown, unknown) -> Wallet.Result,
	read heal: (unknown, unknown, unknown, unknown) -> Wallet.Result,
}
```

### `roblox.market-settlement.Config`

```luau
export type Config = {
	read wallet: WalletOps,
	read receiptsFor: (unknown, unknown) -> { Book.Receipt }?,
	read healRetentionSec: number,
}
```

### `roblox.market-settlement.Host`

```luau
export type Host = { read create: (Dependencies?) -> (Service?, string?) }
```

### `roblox.market-settlement.configure`

```luau
function configure(config: Config): Host
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function MarketSettlement.create(raw: Dependencies?): (Service?, string?)
```

## `roblox.market`

[Source](../src/roblox/market.luau)

```luau
local Books = require("../core/market/book")
```

```luau
local SettlementHost = require("./market-settlement")
```

```luau
local Value = require("../kernel/value")
```

```luau
local Wallets = require("../core/market/wallet")
```

### `roblox.market.Wallet`

```luau
export type Wallet = {
	read read: () -> Wallets.State?,
	read write: (Wallets.State) -> boolean,
	read room: (string) -> number,
}
```

### `roblox.market.Item`

```luau
export type Item<R> = {
	read id: string,
	read name: string,
	read rarity: R,
	read slot: string?,
	read levelReq: number?,
	read weaponFamily: string?,
	read armorFamily: string?,
	read classReq: { string }?,
	read sellValue: number?,
}
```

### `roblox.market.Items`

```luau
export type Items<R> = { read get: (string) -> Item<R>? }
```

### `roblox.market.Material`

```luau
export type Material = { id: string, label: string, npcFloor: number, npcCeiling: number }
```

### `roblox.market.Catalog`

```luau
export type Catalog = {
	materials: { Material },
	maxQuantity: number,
	maxUnitPrice: number,
	maxItemQuantity: number?,
	maxItemUnitPrice: number?,
	visibleListings: number,
	searchLimit: number,
}
```

### `roblox.market.ItemRow`

```luau
export type ItemRow<R> = {
	read listingId: string?,
	read bookId: string,
	read itemId: string,
	read name: string,
	read slot: string?,
	read levelReq: number?,
	read rarity: R,
	read family: string?,
	read count: number,
	read unitPrice: number,
	read own: boolean,
	read expiresAtSec: number,
}
```

### `roblox.market.ItemPage`

```luau
export type ItemPage<R> = {
	read ok: boolean,
	read reason: string?,
	read rows: { ItemRow<R> },
	read total: number,
	read page: number,
}
```

### `roblox.market.ListableItem`

```luau
export type ListableItem<R> = {
	read itemId: string,
	read name: string,
	read slot: string?,
	read levelReq: number?,
	read rarity: R,
	read count: number,
	read suggestedPrice: number,
}
```

### `roblox.market.Projection`

```luau
export type Projection = {
	read available: boolean,
	read realmId: string | false,
	read feeBps: number,
	read materials: { MaterialProjection },
	read coin: number?,
	read maxQuantity: number?,
	read maxUnitPrice: number?,
	read search: SearchProjection?,
}
```

### `roblox.market.Dependencies`

```luau
export type Dependencies<R> = {
	read book: BookService,
	read catalog: Catalog,
	read walletFor: (number) -> Wallet?,
	read realmFor: (number) -> string?,
	read clock: () -> number,
	read newOpId: () -> string,
	read tradingAllowed: (number) -> boolean,
	read items: Items<R>?,
}
```

### `roblox.market.Service`

```luau
export type Service<R> = {
	read join: (number) -> Outcome,
	read list: (number, unknown, unknown, unknown) -> Outcome,
	read buy: (number, unknown, unknown, unknown) -> Outcome,
	read cancel: (number, unknown, unknown) -> Outcome,
	read refresh: (number) -> Outcome,
	read npcSell: (number, unknown, unknown) -> Outcome,
	read npcBuy: (number, unknown, unknown) -> Outcome,
	read listItem: (number, unknown, unknown, unknown) -> Outcome,
	read buyItem: (number, unknown, unknown, unknown) -> Outcome,
	read searchItems: (number, unknown) -> ItemPage<R>,
	read listable: (number) -> { ListableItem<R> },
	read search: (number, unknown, unknown) -> Outcome,
	read projection: (number) -> Projection,
	read forget: (number) -> (),
}
```

### `roblox.market.ItemFilters`

```luau
export type ItemFilters = {
	read page: number?,
	read ceilingUnitPrice: number?,
	read minLevel: number?,
	read maxLevel: number?,
	read bookId: string?,
	read itemId: string?,
	read own: boolean?,
	read slot: string?,
	read rarity: string?,
	read family: string?,
	read classId: string?,
}
```

### `roblox.market.GoodsOps`

```luau
export type GoodsOps = {
	read bookIds: () -> { string },
	read isCategoryBook: (unknown) -> boolean,
	read bookFor: (unknown) -> (string?, string?),
}
```

### `roblox.market.Config`

```luau
export type Config<R> = {
	read items: Items<R>,
	read goods: GoodsOps,
	read matchesItem: (Item<R>, ItemFilters) -> boolean,
	read settlement: SettlementHost.Host,
	read search: (unknown, unknown, unknown) -> { Books.Listing }?,
	read npcTrade: (unknown, unknown, unknown, unknown, unknown) -> Wallets.Result,
	read feeBps: number,
	read joinRetrySec: number,
	read maxActiveListings: number,
	read maxCatalogUnitPrice: number,
	read maxSearchLimit: number,
	read maxSearchPrice: number,
}
```

### `roblox.market.Host`

```luau
export type Host<R> = { read mount: (Dependencies<R>) -> (Service<R>?, string?), read MAX_ACTIVE_LISTINGS: number }
```

### `roblox.market.configure`

```luau
function configure<R>(config: Config<R>): Host<R>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
mount = function MarketService.mount(raw: Dependencies<R>): (Service<R>?, string?)
```

## `roblox.material-ledger`

[Source](../src/roblox/material-ledger.luau)

```luau
local CoreTypes = require("../core/ledger/ledger")
```

```luau
local Atomic = require("../kernel/store")
```

```luau
local Result = require("../kernel/result")
```

```luau
local Shape = require("../core/social/shape")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.material-ledger.State`

```luau
export type State = CoreTypes.State
```

### `roblox.material-ledger.Event`

```luau
export type Event = CoreTypes.Event
```

### `roblox.material-ledger.AppendValue`

```luau
export type AppendValue = { replayed: boolean, settled: boolean, groupId: string? }
```

### `roblox.material-ledger.SnapshotValue`

```luau
export type SnapshotValue = {
	found: boolean,
	balances: { [string]: { [string]: number } },
	tornGroups: { CoreTypes.TornGroup },
	eventCount: number,
	windowFloorAt: number,
	boundary: string,
}
```

### `roblox.material-ledger.Failure`

```luau
export type Failure = Result.Failure
```

### `roblox.material-ledger.StoreOutcome`

```luau
export type StoreOutcome = Result.Result<Atomic.Readback>
```

### `roblox.material-ledger.Store`

```luau
export type Store = Atomic.Port
```

### `roblox.material-ledger.Outcome`

```luau
export type Outcome<T> = Result.Result<T>
```

### `roblox.material-ledger.CorePort`

```luau
export type CorePort = {
	read emptyState: () -> State,
	read projectEvent: (unknown) -> (Event?, string?),
	read projectState: (unknown) -> (State?, string?),
	read apply: (unknown, unknown) -> (CoreTypes.ApplyResult?, string?),
	read balances: (unknown) -> ({ [string]: { [string]: number } }?, string?),
	read tornGroups: (unknown) -> ({ CoreTypes.TornGroup }?, string?),
}
```

### `roblox.material-ledger.Config`

```luau
export type Config = {
	read core: CorePort,
	read schemaVersion: number,
	read windowLimit: number,
	read maxText: number,
	read boundary: string,
}
```

### `roblox.material-ledger.API`

```luau
export type API = {
	read append: (Store, (string) -> string, string, unknown) -> Outcome<AppendValue>,
	read snapshot: (Store, (string) -> string, string) -> Outcome<SnapshotValue>,
	read SCHEMA_VERSION: number,
	read WINDOW_LIMIT: number,
	read NO_FLOOR: number,
	read BOUNDARY: string,
	read REASONS: { string },
}
```

### `roblox.material-ledger.configure`

```luau
function configure(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
append = function Service.append(
		store: Store,
		keyForLedger: (string) -> string,
		ledgerId: string,
		eventValue: unknown
	): Outcome<AppendValue>
snapshot = function Service.snapshot(store: Store, keyForLedger: (string) -> string, ledgerId: string): Outcome<SnapshotValue>
```

## `roblox.messaging`

[Source](../src/roblox/messaging.luau)

### `roblox.messaging.Host`

```luau
export type Host<T> = {
	available: () -> boolean,
	spawn: (() -> ()) -> (),
	publish: (string, T) -> (),
	subscribe: (string, (unknown) -> ()) -> () -> (),
	warn: (string, string) -> (),
}
```

### `roblox.messaging.bind`

```luau
function Messaging.bind<T>(host: Host<T>, topic: string, decode: (unknown) -> T?)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
publish = function publish(payload: T)
subscribe = function subscribe(onNotice: (T) -> ()): (() -> ())
```

## `roblox.movement-intake`

[Source](../src/roblox/movement-intake.luau)

```luau
local Value = require("../kernel/value")
```

### `roblox.movement-intake.Point`

```luau
export type Point = { x: number, z: number }
```

### `roblox.movement-intake.State`

```luau
export type State = {
	hp: number,
	facing: Point?,
	movement: Point?,
	movementEpoch: number?,
	movementSequence: number?,
}
```

### `roblox.movement-intake.Observation`

```luau
export type Observation = { x: number, z: number, hp: number }
```

### `roblox.movement-intake.Normalized`

```luau
export type Normalized = { sequence: number, intent: Point, strafe: boolean?, epoch: number? }
```

### `roblox.movement-intake.Ack`

```luau
export type Ack = { epoch: number, sequence: number, intent: Point, acceptedCount: number }
```

### `roblox.movement-intake.Dependencies`

```luau
export type Dependencies<P, B> = {
	clock: () -> number,
	registerClose: (() -> ()) -> () -> (),
	remote: {
		connect: ((boolean, P, unknown) -> ()) -> () -> (),
		acknowledge: (P, Ack) -> (),
	},
	step: { connect: (() -> ()) -> () -> () },
	players: {
		validatePlayer: (P) -> boolean,
		isPresent: (P) -> boolean,
		identity: (P) -> number,
		currentBody: (P) -> B?,
	},
	normalize: (unknown) -> Normalized?,
	control: {
		apply: (B, Point, Point?) -> boolean,
		restore: (B, number, number) -> boolean,
	},
	snapshot: {
		state: (P) -> State?,
		reset: (P, number) -> (),
		move: (P, Point, boolean, number, number) -> boolean,
		observe: (B) -> Observation?,
		setPlayerSnapshot: (P, number, number, number, boolean?) -> boolean,
		travelRevision: (B) -> number,
	},
	mark: (string, string?) -> (),
}
```

### `roblox.movement-intake.StopResult`

```luau
export type StopResult = { phase: string }
```

### `roblox.movement-intake.Started`

```luau
export type Started<P> = {
	phase: "movement_authority_started",
	admitPlayer: (P) -> boolean,
	removePlayer: (P) -> boolean,
	stop: () -> StopResult,
	dispose: () -> StopResult,
}
```

### `roblox.movement-intake.Refused`

```luau
export type Refused = { read phase: "movement_authority_refused", read reason: string }
```

### `roblox.movement-intake.start`

```luau
function MovementIntake.start<P, B>(dependencies: Dependencies<P, B>): Started<P> | Refused
```

## `roblox.movement-sender`

[Source](../src/roblox/movement-sender.luau)

### `roblox.movement-sender.Planar`

```luau
export type Planar = { read x: number, read z: number }
```

### `roblox.movement-sender.Refused`

```luau
export type Refused = { read phase: "movement_sender_refused", read reason: string }
```

### `roblox.movement-sender.Stopped`

```luau
export type Stopped = { read phase: "movement_sender_stopped" | "movement_sender_stop_failed" }
```

### `roblox.movement-sender.Started`

```luau
export type Started = {
	read phase: "movement_sender_started",
	read activate: (unknown) -> boolean,
	read revoke: (unknown) -> boolean,
	read sample: (unknown) -> boolean,
	read stop: () -> Stopped,
	read dispose: () -> Stopped,
}
```

### `roblox.movement-sender.StartResult`

```luau
export type StartResult = Started | Refused
```

### `roblox.movement-sender.Payload`

```luau
export type Payload = { read intent: Planar, read sequence: number, read sentAt: number, read epoch: number? }
```

```luau
local Value = require("../kernel/value")
```

### `roblox.movement-sender.Connection`

```luau
export type Connection = { read Disconnect: ((Connection) -> ())? }
```

### `roblox.movement-sender.Dependencies`

```luau
export type Dependencies = {
	clock: () -> number,
	remote: { send: (Payload) -> boolean, connect: ((unknown) -> ()) -> Connection },
	heartbeat: { connect: (() -> ()) -> Connection },
	action: { connect: ((unknown) -> boolean) -> Connection, setEnabled: (boolean) -> boolean },
	motion: { resendDecision: (Planar, Planar, Planar, Planar?, number, number, number, number) -> (Planar, boolean) },
	camera: { read: () -> unknown },
	mark: (string) -> (),
}
```

### `roblox.movement-sender.start`

```luau
function MovementSender.start(dependencies: Dependencies): StartResult
```

## `roblox.npc-motion`

[Source](../src/roblox/npc-motion.luau)

### `roblox.npc-motion.Planar`

```luau
export type Planar = { x: number, z: number }
```

### `roblox.npc-motion.Point`

```luau
export type Point = { x: number, y: number?, z: number }
```

### `roblox.npc-motion.Observed`

```luau
export type Observed = { position: Planar, facing: Planar }
```

### `roblox.npc-motion.Projection`

```luau
export type Projection = { position: Planar, facing: Planar, planarSpeed: number }
```

### `roblox.npc-motion.Changes`

```luau
export type Changes = { transform: boolean, planarSpeed: boolean }
```

### `roblox.npc-motion.distance`

```luau
function Motion.distance(a: Point, b: Point): number
```

### `roblox.npc-motion.movement`

```luau
function Motion.movement(epsilon: number)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
insideLeash = function Movement.insideLeash(origin: Point?, radius: number?, point: Point): boolean
moveToward = function Movement.moveToward(pos: Point, target: Point, maxDistance: number): Point
```

### `roblox.npc-motion.projection`

```luau
function Motion.projection(tuning: { epsilon: number, facingEpsilon: number, minimumDt: number })
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
anchoredSurfaceY = function anchoredSurfaceY(anchorY: number, hitY: number?): number
groundedPivotY = function groundedPivotY(
		terrainY: number,
		hipHeight: number,
		rootHalfHeight: number,
		rootToPivotY: number
	): number
plan = function plan(
		previous: Projection?,
		observed: Observed,
		position: Planar,
		target: Planar?,
		dt: number
	): (Projection, Changes)
```

## `roblox.party`

[Source](../src/roblox/party.luau)

```luau
local Codec = require("../kernel/codec")
```

```luau
local Membership = require("../core/social/membership")
```

```luau
local Result = require("../kernel/result")
```

```luau
local Store = require("../kernel/store")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.party.StoreOutcome`

```luau
export type StoreOutcome = Result.Result<unknown>
```

### `roblox.party.Store`

```luau
export type Store = Store.Port
```

### `roblox.party.Dependencies`

```luau
export type Dependencies = {
	store: Store,
	keyForParty: (string) -> string,
	readMembership: (string) -> unknown,
}
```

### `roblox.party.PartyOutcome`

```luau
export type PartyOutcome = {
	ok: boolean,
	reason: string?,
	replayed: boolean,
	found: boolean,
	party: CoreState?,
}
```

### `roblox.party.Service`

```luau
export type Service = {
	open: (request: unknown) -> PartyOutcome,
	invite: (request: unknown) -> PartyOutcome,
	accept: (request: unknown) -> PartyOutcome,
	decline: (request: unknown) -> PartyOutcome,
	leave: (request: unknown) -> PartyOutcome,
	kick: (request: unknown) -> PartyOutcome,
	transferLeader: (request: unknown) -> PartyOutcome,
	acceptLeaderTransfer: (request: unknown) -> PartyOutcome,
	disband: (request: unknown) -> PartyOutcome,
	setLootMode: (request: unknown) -> PartyOutcome,
	markAbsent: (request: unknown) -> PartyOutcome,
	markPresent: (request: unknown) -> PartyOutcome,
	sweep: (request: unknown) -> PartyOutcome,
	read: (partyId: unknown) -> PartyOutcome,
}
```

### `roblox.party.MountResult`

```luau
export type MountResult = {
	ok: boolean,
	service: Service?,
	reason: string?,
}
```

### `roblox.party.Config`

```luau
export type Config = { core: Membership.Core, schemaVersion: number, maxText: number }
```

### `roblox.party.party`

```luau
function System.party(config: Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
mount = function PartyService.mount(dependencies: Dependencies?): MountResult
```

## `roblox.persistence.store`

[Source](../src/roblox/persistence/store.luau)

```luau
local Host = require("../../core/persistence/store-host")
```

```luau
local Result = require("../../kernel/result")
```

```luau
local Store = require("../../kernel/store")
```

```luau
local Value = require("../../kernel/value")
```

### `roblox.persistence.store.Port`

```luau
export type Port = Store.Port
```

### `roblox.persistence.store.Backend`

```luau
export type Backend = {
	read getUncachedOutcome: (string) -> Host.Outcome,
	read updateOutcome: (string, Store.Transform) -> Host.Outcome,
}
```

### `roblox.persistence.store.API`

```luau
export type API = { read new: typeof(new) }
```

### `roblox.persistence.store.new`

```luau
function new(host: Backend): Port
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
read = function read(key: string): Result.Result<Store.Readback>
update = function update(key: string, transform: Store.Transform): Result.Result<Store.Readback>
```

## `roblox.professions`

[Source](../src/roblox/professions.luau)

```luau
local Craft = require("../core/professions/crafting")
```

```luau
local Fish = require("../core/professions/fishing")
```

```luau
local Harvest = require("../core/professions/harvest")
```

```luau
local Sessions = require("../core/professions/session")
```

```luau
local Skills = require("../core/professions/skills")
```

```luau
local Types = require("../core/professions/types")
```

### `roblox.professions.Fields`

```luau
export type Fields = {
	inventory: { [string]: number },
	gold: number,
	read faction: string,
	read bagItem: string?,
	professions: State,
}
```

### `roblox.professions.CommitResult`

```luau
export type CommitResult = {
	ok: boolean,
	outcome: "committed" | "replayed" | "rejected" | "not_durable",
	reason: string?,
}
```

### `roblox.professions.ProfilePort`

```luau
export type ProfilePort<C, F> = {
	read: (C) -> F?,
	updateProfile: (C, (F) -> F) -> (),
	removeGold: (C, number) -> boolean,
	addGold: (C, number) -> (),
	requestSave: ((C) -> ())?,
	saveProfile: ((C) -> boolean)?,
}
```

### `roblox.professions.SkinTarget`

```luau
export type SkinTarget = { key: string, mobId: string, x: number, z: number }
```

### `roblox.professions.World`

```luau
export type World<P> = {
	node: (string) -> { kindId: string, x: number, z: number }?,
	sample: (P) -> Sample?,
	stations: (P) -> { [string]: boolean },
	trainerGroup: (P) -> string?,
	nearWater: (P) -> boolean,
	corpse: (P) -> SkinTarget?,
}
```

### `roblox.professions.WorkKind`

```luau
export type WorkKind = "gather" | "skin" | "craft"
```

### `roblox.professions.GatherPayload`

```luau
export type GatherPayload = { nodeId: string, nodeKind: Types.NodeKind }
```

### `roblox.professions.SkinPayload`

```luau
export type SkinPayload = { corpseKey: string, skinRow: Types.SkinRow }
```

### `roblox.professions.CraftPayload`

```luau
export type CraftPayload = { recipeId: string }
```

### `roblox.professions.WorkPayload`

```luau
export type WorkPayload = GatherPayload | SkinPayload | CraftPayload
```

### `roblox.professions.WorkMetadata`

```luau
export type WorkMetadata = { session: ActionSession, trackReceipt: string }
```

### `roblox.professions.GatherEntry`

```luau
export type GatherEntry = WorkMetadata & { kind: "gather", payload: GatherPayload }
```

### `roblox.professions.SkinEntry`

```luau
export type SkinEntry = WorkMetadata & { kind: "skin", payload: SkinPayload }
```

### `roblox.professions.CraftEntry`

```luau
export type CraftEntry = WorkMetadata & { kind: "craft", payload: CraftPayload }
```

### `roblox.professions.WorkEntry`

```luau
export type WorkEntry = GatherEntry | SkinEntry | CraftEntry
```

### `roblox.professions.RecipeView`

```luau
export type RecipeView = {
	id: string,
	name: string,
	profession: string,
	requiredSkill: number,
	color: string?,
	canCraft: boolean,
	reason: string?,
	source: Types.Source,
	station: string?,
	outputItemId: string,
	outputQuantity: number,
	reagents: { Types.Reagent },
}
```

### `roblox.professions.RecipeItemView`

```luau
export type RecipeItemView = { itemId: string, name: string, canLearn: boolean, reason: string? }
```

### `roblox.professions.ProfessionView`

```luau
export type ProfessionView = {
	id: string,
	name: string,
	kind: Skills.Kind,
	skill: number,
	cap: number,
	recipes: { RecipeView },
	recipeItems: { RecipeItemView },
}
```

### `roblox.professions.ProfessionLesson`

```luau
export type ProfessionLesson = {
	id: string,
	name: string,
	known: boolean,
	canLearn: boolean,
	reason: string?,
	cost: number,
}
```

### `roblox.professions.RecipeLesson`

```luau
export type RecipeLesson = {
	id: string,
	name: string,
	profession: string,
	status: string,
	cost: number,
	requiredSkill: number,
	preview: string,
}
```

### `roblox.professions.SupplyView`

```luau
export type SupplyView = { itemId: string, price: number, stock: number?, canBuy: boolean, reason: string? }
```

### `roblox.professions.TrainerBook`

```luau
export type TrainerBook = {
	group: string,
	professions: { ProfessionLesson },
	recipes: { RecipeLesson },
	supplies: { SupplyView },
}
```

### `roblox.professions.Book`

```luau
export type Book<X> = {
	professions: { ProfessionView },
	primaryFree: number,
	trainer: TrainerBook?,
	stations: { [string]: boolean },
	chapterProgress: X?,
	repair: { price: number, requestId: string, pending: boolean, canRepair: boolean }?,
}
```

### `roblox.professions.ResultExtras`

```luau
export type ResultExtras = {
	yields: { Harvest.Yield }?,
	produced: { itemId: string, quantity: number }?,
	quality: string?,
	skillUp: boolean?,
	skill: number?,
	profession: string?,
	color: string?,
	chapterProgressAwarded: number?,
	nodeId: string?,
	recipeId: string?,
	itemId: string?,
	price: number?,
}
```

### `roblox.professions.ResultMessage`

```luau
export type ResultMessage = ResultExtras & { kind: "result", action: string, ok: boolean, reason: string? }
```

### `roblox.professions.Message`

```luau
export type Message<X> =
	ResultMessage
	| { kind: "book", book: Book<X>, open: boolean? }
	| { kind: "cast", action: WorkKind | "fish", key: string, duration: number, endsAt: number }
	| { kind: "bite" }
```

### `roblox.professions.Handle`

```luau
export type Handle<P> = {
	handle: (P, unknown, unknown, unknown) -> (),
	interrupt: (P, string) -> (),
	step: () -> (),
	forget: (P) -> (),
	harvestedSlots: () -> { [string]: number },
}
```

### `roblox.professions.CorePort`

```luau
export type CorePort = {
	read SKILL_CAP: number,
	read catalogue: { Profession },
	read normalize: (unknown) -> State,
	read profession: (unknown) -> Profession?,
	read skillOf: (State, string) -> number,
	read colorFor: (number, Types.Thresholds) -> string?,
	read primarySlotsFree: (State) -> number,
	read canLearn: (State, unknown) -> (boolean, string?),
	read learn: (State, unknown) -> (State?, string?),
	read unlearn: (State, unknown) -> (State?, string?),
	read learnRecipe: (State, unknown, "trainer" | "item") -> (State?, string?),
	read learnFromItem: (State, unknown) -> (State?, string?, Recipe?),
	read trainerRoster: (State, string) -> { { recipe: Recipe, status: string, cost: number } },
}
```

### `roblox.professions.Policy`

```luau
export type Policy<F, X> = {
	read core: CorePort,
	read crafting: {
		read plan: (State, unknown, { [string]: number }, { [string]: boolean }) -> Craft.Plan,
		read craft: (
			State,
			unknown,
			{ [string]: number },
			{ [string]: boolean },
			number,
			number?,
			number?
		) -> Craft.Outcome,
	},
	read fishing: {
		read idle: () -> Fish.Line,
		read cast: (Fish.Line, State, number, number) -> (Fish.Line?, string?),
		read observe: (Fish.Line, number) -> Fish.Line,
		read hook: (Fish.Line, number) -> (boolean, string),
		read reel: (State, string, () -> number) -> Fish.Catch,
	},
	read gather: {
		read harvestNode: (State, Types.NodeKind, () -> number) -> Harvest.Outcome,
		read skinCorpse: (State, Types.SkinRow, () -> number) -> Harvest.Outcome,
		read canAttempt: (State, string, Types.NodeKind | Types.SkinRow) -> (boolean, string?),
	},
	read session: {
		read begin: (Sessions.Kind, string, number, Sample) -> (ActionSession?, string?),
		read check: (ActionSession, Sample) -> (string, string?),
	},
	read nodes: {
		read available: ({ [string]: number }, string, number, number) -> boolean,
		read slotAt: (number, number) -> number,
		read kind: (unknown) -> Types.NodeKind?,
		read skinFor: (unknown) -> Types.SkinRow?,
		read GATHER_RANGE_STUDS: number,
		read CORPSE_RANGE_STUDS: number,
		read CRAFT_SEC: number,
	},
	read recipes: {
		read all: { Recipe },
		read get: (unknown) -> Recipe?,
		read forProfession: (string) -> { Recipe },
		read forRecipeItem: (unknown) -> Recipe?,
	},
	read trainers: {
		read LEARN_COST: number,
		read group: (unknown) -> { professions: { string }, supplies: { { itemId: string, price: number } } }?,
		read groupOfProfession: (string) -> string?,
		read supplyPrice: (string, string) -> number?,
	},
	read inventory: {
		read capacity: (string?) -> number,
		read entries: ({ [string]: number }) -> number,
		read addToBag: ({ [string]: number }, string, number) -> { [string]: number },
		read removeFromBag: ({ [string]: number }, string, number) -> ({ [string]: number }, boolean),
	},
	read maxStack: number,
	read maxIdLength: number,
	read vendorWindow: number,
	read repairGroup: string,
	read fishingTool: string,
	read fishingId: string,
	read skinningId: string,
	read itemName: (string) -> string,
	read recipeAllowed: (F, Recipe) -> boolean,
	read recordProgress: (F, string, string, string?) -> number,
	read progress: (F) -> X?,
	read repairQuote: (F) -> number,
	read repair: (F, number) -> (F?, string?),
	read earnQuestInputs: (
		State,
		{ [string]: number },
		{ [string]: { [string]: number } }
	) -> (State, { [string]: number }, boolean),
}
```

### `roblox.professions.Deps`

```luau
export type Deps<P, C, F, X> = {
	read questCounts: ((P) -> { [string]: { [string]: number } }?)?,
	read profiles: ProfilePort<C, F>,
	read context: (P) -> C?,
	read zoneId: string,
	read clock: () -> number,
	read rng: () -> number,
	read world: World<P>,
	read send: (P, Message<X>) -> (),
	read eventId: () -> string,
	read commit: (C, string, (F) -> (F?, string?)) -> CommitResult,
}
```

### `roblox.professions.IntentPayload`

```luau
export type IntentPayload = { action: string, arg: string?, extra: string? }
```

### `roblox.professions.decodeIntent`

```luau
function Service.decodeIntent(action: unknown, arg: unknown, extra: unknown): IntentPayload?
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
action = action
arg = arg
extra = extra
```

### `roblox.professions.new`

```luau
function Service.new<P, C, F, X>(deps: Deps<P, C, F & Fields, X>, policy: Policy<F & Fields, X>): Handle<P>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
handle = function service.handle(player: P, action: unknown, arg: unknown, extra: unknown)
interrupt = function service.interrupt(player: P, reason: string)
step = function service.step()
forget = function service.forget(player: P)
harvestedSlots = function service.harvestedSlots(): { [string]: number }
```

## `roblox.profile-sessions`

[Source](../src/roblox/profile-sessions.luau)

### `roblox.profile-sessions.Owner`

```luau
export type Owner = {
	own: (() -> ()) -> () -> (),
	createChild: () -> Owner,
	dispose: () -> (),
	size: () -> number,
}
```

### `roblox.profile-sessions.Outcome`

```luau
export type Outcome = { ok: boolean, reason: string?, expiresAt: number? }
```

### `roblox.profile-sessions.Dependencies`

```luau
export type Dependencies<C, P> = {
	clock: () -> number,
	schedule: (number, () -> ()) -> () -> (),
	spawn: ((() -> ()) -> () -> ())?,
	wait: (() -> ())?,
	report: ("write" | "drain" | "held", string, string?) -> (),
	renewalDelay: number,
	retryDelay: number,
	drainBudget: number,
	jitter: () -> number,
	jitterFraction: number,
	keyFor: (C) -> string,
	same: (C, C) -> boolean,
	write: (P, C, number, () -> boolean, boolean, number) -> Outcome,
}
```

### `roblox.profile-sessions.new`

```luau
function Sessions.new<C, P>(owner: Owner, deps: Dependencies<C, P>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
admit = function admit(context: C, leaseExpiresAt: number, profile: () -> P?, onReleased: () -> ())
save = function save(context: C): Outcome
requestSave = function requestSave(context: C): boolean
unload = function unload(context: C): Outcome
drain = function drain(): { [string]: Outcome }
isAdmitted = function isAdmitted(context: C): boolean
ownedTaskCount = function ownedTaskCount(context: C): number
dispose = function dispose()
```

## `roblox.profile-transfer`

[Source](../src/roblox/profile-transfer.luau)

### `roblox.profile-transfer.Identity`

```luau
export type Identity = {
	read userId: number,
	read characterId: string,
	read key: string,
	read sessionId: string,
	read acquisitionId: string,
	read leaseRevision: number,
}
```

### `roblox.profile-transfer.Outcome`

```luau
export type Outcome = "committed" | "replayed" | "rejected" | "not_durable"
```

### `roblox.profile-transfer.Result`

```luau
export type Result = {
	ok: boolean,
	outcome: Outcome,
	reason: string?,
}
```

### `roblox.profile-transfer.Reader`

```luau
export type Reader<P> = {
	read profile: (Identity) -> Readable<P?>?,
}
```

### `roblox.profile-transfer.exclusive`

```luau
function exclusive<K, T, F>(busy: { [K]: boolean }, key: K, refused: F, body: () -> T): T | F
```

### `roblox.profile-transfer.profileFor`

```luau
function profileFor<P>(reader: Reader<P>, contextFor: (number) -> Identity?, userId: number): (P?, Identity?)
```

### `roblox.profile-transfer.sameSession`

```luau
function sameSession(left: Identity?, right: Identity?): boolean
```

### `roblox.profile-transfer.settle`

```luau
function settle(
	contextFor: (number) -> Identity?,
	userId: number,
	context: Identity,
	strict: boolean,
	run: () -> Result
): Result
```

## `roblox.quest-durability`

[Source](../src/roblox/quest-durability.luau)

```luau
local Atomic = require("../kernel/store")
```

```luau
local Journal = require("../core/quest/journal")
```

```luau
local LeaseRecordTypes = require("../core/identity/character-lease")
```

```luau
local LeaseStore = require("../core/identity/character-lease-store")
```

```luau
local ProfileSessionTypes = require("../core/persistence/profile-session")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.quest-durability.Lease`

```luau
export type Lease = LeaseRecordTypes.Record
```

### `roblox.quest-durability.SessionState`

```luau
export type SessionState = ProfileSessionTypes.State
```

### `roblox.quest-durability.Quests`

```luau
export type Quests = { [string]: Journal.QuestProgress }
```

### `roblox.quest-durability.QuestRecord`

```luau
export type QuestRecord = Journal.Record
```

### `roblox.quest-durability.OutcomeStore`

```luau
export type OutcomeStore = Atomic.Port
```

### `roblox.quest-durability.SessionDependencies`

```luau
export type SessionDependencies = {
	store: OutcomeStore,
	leaseKeyFor: (string) -> string,
	zoneKeyFor: (string, string) -> string,
	leaseZoneFamily: { string }?,
	clock: () -> number,
}
```

### `roblox.quest-durability.Deps`

```luau
export type Deps = SessionDependencies & {
	schedule: (number, () -> ()) -> (),
	scheduleLeaseRenewal: ((number, () -> ()) -> ())?,
	saveDelaySeconds: number?,
}
```

### `roblox.quest-durability.Acquired`

```luau
export type Acquired<Z> = { ok: true, reason: string?, session: SessionState, lease: Lease, zoneSnapshot: Z }
```

### `roblox.quest-durability.Refused`

```luau
export type Refused = { ok: false, reason: string?, session: nil, lease: nil, zoneSnapshot: nil }
```

### `roblox.quest-durability.Acquisition`

```luau
export type Acquisition<Z> = Acquired<Z> | Refused
```

### `roblox.quest-durability.Saved`

```luau
export type Saved<Z> = { ok: true, reason: string?, lease: Lease, zoneSnapshot: Z }
```

### `roblox.quest-durability.SaveRefused`

```luau
export type SaveRefused = { ok: false, reason: string?, lease: Lease?, zoneSnapshot: nil }
```

### `roblox.quest-durability.SaveOutcome`

```luau
export type SaveOutcome<Z> = Saved<Z> | SaveRefused
```

### `roblox.quest-durability.SessionPort`

```luau
export type SessionPort<Z> = {
	read acquireAndHydrate: (SessionDependencies, string, string, string, string) -> Acquisition<Z>,
	read saveZoneQuests: (SessionDependencies, SessionState, Lease, Z, Quests) -> SaveOutcome<Z>,
}
```

### `roblox.quest-durability.SnapshotView`

```luau
export type SnapshotView = { read found: boolean, read revision: number, read quests: unknown }
```

### `roblox.quest-durability.Config`

```luau
export type Config<Z> = {
	read journal: Journal.API,
	read copyLease: index<LeaseRecordTypes.API, "copy">,
	read renew: index<LeaseStore.API, "renew">,
	read release: index<LeaseStore.API, "release">,
	read session: SessionPort<Z>,
	read snapshot: (Z) -> SnapshotView,
	read leaseSeconds: number,
	read renewSeconds: number,
	read retrySeconds: number,
	read defaultSaveDelay: number,
	read maxConsecutiveSaveFailures: number,
	read fenceLossReasons: { [string]: boolean },
}
```

### `roblox.quest-durability.AttachAccepted`

```luau
export type AttachAccepted = {
	ok: true,
	reason: string?,
	found: boolean?,
	quests: Quests,
	semanticEventIds: { [string]: boolean },
	record: QuestRecord,
}
```

### `roblox.quest-durability.AttachRefused`

```luau
export type AttachRefused = {
	ok: false,
	reason: string?,
	found: nil?,
	quests: nil?,
	semanticEventIds: nil?,
	record: nil?,
}
```

### `roblox.quest-durability.AttachOutcome`

```luau
export type AttachOutcome = AttachAccepted | AttachRefused
```

### `roblox.quest-durability.Result`

```luau
export type Result = { ok: boolean, reason: string?, skipped: boolean? }
```

### `roblox.quest-durability.Handle`

```luau
export type Handle = {
	read attach: (string, string, string, string) -> AttachOutcome,
	read flush: (string) -> Result,
	read markDirty: (string, unknown) -> boolean,
	read markDirtyBatch: ({ unknown }) -> boolean,
	read stopWrites: (string) -> boolean,
	read overwriteRecord: (string, unknown) -> Result,
	read detach: (string) -> { ok: boolean, reason: string? },
	read drain: () -> { [string]: { ok: boolean, reason: string? } },
	read isAttached: (string) -> boolean,
	read canWrite: (string) -> boolean,
	read phase: (string) -> string?,
}
```

### `roblox.quest-durability.API`

```luau
export type API = { read new: (Deps) -> Handle }
```

### `roblox.quest-durability.configure`

```luau
function configure<Z>(config: Config<Z>): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
new = function new(deps: Deps): Handle
```

## `roblox.remote-events`

[Source](../src/roblox/remote-events.luau)

### `roblox.remote-events.Host`

```luau
export type Host<Event, Player, Handler, Options> = {
	register: (string, Handler, Options?) -> () -> (),
	served: (string) -> number,
	connect: (Event, (Player, ...unknown) -> ()) -> () -> (),
	receive: (string, Player, ...unknown) -> (),
	own: (() -> ()) -> (),
}
```

### `roblox.remote-events.transport`

```luau
function Events.transport<Event, Player, Handler, Options>(host: Host<Event, Player, Handler, Options>)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
serve = function serve(name: string, event: Event, handler: Handler, options: Options?): () -> ()
```

## `roblox.screen-labels`

[Source](../src/roblox/screen-labels.luau)

### `roblox.screen-labels.ScreenRect`

```luau
export type ScreenRect = {
	left: number,
	top: number,
	right: number,
	bottom: number,
}
```

### `roblox.screen-labels.ScreenPlate`

```luau
export type ScreenPlate = {
	id: string,
	distanceStuds: number,
	rect: ScreenRect,
	priority: number?,
}
```

### `roblox.screen-labels.ScreenPlacement`

```luau
export type ScreenPlacement = {
	rect: ScreenRect,
	collapsed: boolean,
}
```

### `roblox.screen-labels.contains`

```luau
function Labels.contains(outer: ScreenRect, inner: ScreenRect): boolean
```

### `roblox.screen-labels.create`

```luau
function Labels.create(tuning: {
	maximum: number,
	farDistance: number,
	farCount: number,
	focusPriority: number,
	defaultPriority: number,
})
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
placementForScreen = function placementForScreen(
		plates: { ScreenPlate },
		hudReserves: { ScreenRect }?,
		topbarFloorY: number?,
		screenBounds: ScreenRect?
	): { [string]: ScreenPlacement }
```

### `roblox.screen-labels.horizontalAvoidance`

```luau
function Labels.horizontalAvoidance(label: ScreenRect, band: ScreenRect, gap: number): number
```

### `roblox.screen-labels.rect`

```luau
function Labels.rect(left: number, top: number, width: number, height: number): ScreenRect
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
left = left
top = top
right = left + math.max(width, 0)
bottom = top + math.max(height, 0)
```

### `roblox.screen-labels.rectsOverlap`

```luau
function rectsOverlap(left: ScreenRect, right: ScreenRect): boolean
```

## `roblox.social-fellowship`

[Source](../src/roblox/social-fellowship.luau)

```luau
local FellowshipTypes = require("../core/social/fellowship")
```

```luau
local GroupCoreTypes = require("../core/social/group")
```

```luau
local Homes = require("../core/social/guildhome")
```

```luau
local RecordsTypes = require("./social-records")
```

```luau
local SocialHost = require("./social-host")
```

```luau
local Value = require("../kernel/value")
```

```luau
local Views = require("./internal/social-views")
```

### `roblox.social-fellowship.BankMembership`

```luau
export type BankMembership = { fellowshipId: string, role: "member" | "steward", memberIds: { number } }
```

### `roblox.social-fellowship.FellowshipMemberView`

```luau
export type FellowshipMemberView = Views.FellowshipMemberView
```

### `roblox.social-fellowship.StewardAuditView`

```luau
export type StewardAuditView = Views.StewardAuditView
```

### `roblox.social-fellowship.PendingFellowshipInviteView`

```luau
export type PendingFellowshipInviteView = Views.PendingFellowshipInviteView
```

### `roblox.social-fellowship.FellowshipView`

```luau
export type FellowshipView = Views.FellowshipView
```

### `roblox.social-fellowship.FellowshipResponse`

```luau
export type FellowshipResponse = {
	read ok: boolean,
	read state: FellowshipState?,
	read replayed: boolean,
	read reason: string?,
}
```

### `roblox.social-fellowship.Dependencies`

```luau
export type Dependencies = {
	read fellowshipRecords: RecordService?,
	read realmFor: (number) -> string?,
	read clock: () -> number,
	read guildHomeCatalog: (() -> unknown)?,
	read relationsFor: ((number, { number }, number) -> GroupCoreTypes.Relations?)?,
}
```

### `roblox.social-fellowship.Service`

```luau
export type Service = {
	read createFellowship: (number, string) -> FellowshipResponse,
	read fellowshipInvite: (number, number) -> FellowshipResponse,
	read pendingFellowshipInvite: (number) -> PendingFellowshipInviteView | false,
	read answerFellowshipInvite: (number, boolean) -> FellowshipResponse,
	read fellowshipMemberIntent: (number, string, number?, unknown?) -> FellowshipResponse,
	read bankMembership: (number, boolean) -> (BankMembership?, string?),
	read fellowshipProjection: (number) -> FellowshipView | false,
	read fellowshipAudience: (number) -> { number },
	read fellowshipNoticed: (string) -> { number },
	read fellowshipSeen: (number) -> FellowshipResponse,
	read fellowshipSettle: (number) -> string?,
	read fellowshipEnsureSettled: (number) -> (),
	read forgetPlayer: (number) -> (),
}
```

### `roblox.social-fellowship.Config`

```luau
export type Config = {
	read slots: (unknown) -> { Homes.Slot }?,
	read slotFor: (unknown, unknown) -> Homes.Slot?,
	read admit: (unknown, unknown, unknown, GroupCoreTypes.Authority?) -> GroupCoreTypes.Decision,
	read visibleRoster: (unknown, unknown, unknown) -> { number }?,
	read inviteTtlSec: number,
	read stewardAbsenceSec: number,
	read seenRefreshSec: number,
	read fellowshipId: (string) -> string,
	read memberFallback: (number) -> string,
}
```

### `roblox.social-fellowship.API`

```luau
export type API = {
	read create: (Dependencies, SocialHost.Host, (number) -> string?, () -> string, (string) -> ()) -> Service,
}
```

### `roblox.social-fellowship.configure`

```luau
function configure(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function create(
		deps: Dependencies,
		host: SocialHost.Host,
		memberNameFor: (number) -> string?,
		newEventId: () -> string,
		notifyFellowship: (string) -> ()
	): Service
```

## `roblox.social-formation`

[Source](../src/roblox/social-formation.luau)

```luau
local FellowshipFormationCoreTypes = require("../core/social/formation")
```

```luau
local GroupCoreTypes = require("../core/social/group")
```

```luau
local Homes = require("../core/social/guildhome")
```

```luau
local RecordsTypes = require("./social-records")
```

```luau
local SocialHost = require("./social-host")
```

```luau
local Transfer = require("./profile-transfer")
```

```luau
local Value = require("../kernel/value")
```

```luau
local Views = require("./internal/social-views")
```

### `roblox.social-formation.FeePort`

```luau
export type FeePort = {
	read hold: (number, string) -> Transfer.Result,
	read commit: (number, string) -> Transfer.Result,
	read refund: (number, string) -> Transfer.Result,
}
```

### `roblox.social-formation.FormationInviteView`

```luau
export type FormationInviteView = Views.FormationInviteView
```

### `roblox.social-formation.FounderView`

```luau
export type FounderView = Views.FounderView
```

### `roblox.social-formation.ActiveFormationView`

```luau
export type ActiveFormationView = Views.ActiveFormationView
```

### `roblox.social-formation.FormationView`

```luau
export type FormationView = Views.FormationView
```

### `roblox.social-formation.FormationResponse`

```luau
export type FormationResponse = {
	read ok: boolean,
	read state: FormationState?,
	read replayed: boolean,
	read reason: string?,
	read fellowshipId: string?,
}
```

### `roblox.social-formation.Dependencies`

```luau
export type Dependencies = {
	read fellowshipRecords: RecordService?,
	read realmFor: (number) -> string?,
	read clock: () -> number,
	read guildHomeCatalog: (() -> unknown)?,
	read relationsFor: ((number, { number }, number) -> GroupCoreTypes.Relations?)?,
	read guildFee: FeePort?,
}
```

### `roblox.social-formation.Service`

```luau
export type Service = {
	read start: (number, string) -> FormationResponse,
	read invite: (number, number) -> FormationResponse,
	read answer: (number, string) -> FormationResponse,
	read complete: (number) -> FormationResponse,
	read projection: (number) -> FormationView | false,
	read settle: (number) -> FormationResponse,
}
```

### `roblox.social-formation.Config`

```luau
export type Config = {
	read slotFor: (unknown, unknown) -> Homes.Slot?,
	read admit: (unknown, unknown, unknown, GroupCoreTypes.Authority?) -> GroupCoreTypes.Decision,
	read requiredFounders: number,
	read fee: number,
	read proposerFallback: string,
}
```

### `roblox.social-formation.API`

```luau
export type API = {
	read create: (Dependencies, SocialHost.Host, (number) -> string?, () -> string, (string) -> ()) -> Service,
}
```

### `roblox.social-formation.configure`

```luau
function configure(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function create(
		deps: Dependencies,
		host: SocialHost.Host,
		memberNameFor: (number) -> string?,
		newEventId: () -> string,
		notifyFellowship: (string) -> ()
	): Service
```

## `roblox.social-host`

[Source](../src/roblox/social-host.luau)

```luau
local Fellowship = require("../core/social/fellowship")
```

```luau
local Records = require("./social-records")
```

```luau
local Transfer = require("./profile-transfer")
```

### `roblox.social-host.Membership`

```luau
export type Membership = Records.Membership
```

### `roblox.social-host.Response`

```luau
export type Response = Records.Result | Fellowship.Result
```

### `roblox.social-host.Host`

```luau
export type Host = {
	read serially: <T>(actorUserId: number, body: () -> T) -> T | Records.Refusal,
	read loadRecord: (fellowshipId: string, fresh: boolean) -> Records.Result,
	read cachedRecord: (fellowshipId: string) -> Fellowship.State?,
	read remember: (state: Fellowship.State) -> (),
	read membershipOf: (userId: number, fresh: boolean) -> Membership?,
	read cachedMembership: (userId: number) -> Membership?,
	read adopt: (userId: number, membership: Membership?) -> (),
	read forget: (userId: number) -> (),
	read settle: (userId: number) -> string?,
	read settleUnlessBusy: (userId: number) -> string?,
	read commitRecord: (fellowshipId: string, event: unknown) -> Records.Result,
	read claimThenCommit: (actorUserId: number, fellowshipId: string, commit: () -> Records.Result) -> Response,
	read isMember: (state: Fellowship.State, userId: number) -> boolean,
}
```

### `roblox.social-host.fellowships`

```luau
function SocialHost.fellowships(source: Records.Service?): Host
```

## `roblox.social-notes`

[Source](../src/roblox/social-notes.luau)

```luau
local PhraseNoteCore = require("../core/social/notes")
```

```luau
local Records = require("./social-records")
```

### `roblox.social-notes.Response`

```luau
export type Response = { ok: boolean, reason: string? }
```

### `roblox.social-notes.Recipient`

```luau
export type Recipient = { read userId: number, read displayName: string, read source: "guild" | "nearby" | "recent" }
```

### `roblox.social-notes.Candidate`

```luau
export type Candidate = { read userId: number, read displayName: string, read source: "nearby" | "recent" }
```

### `roblox.social-notes.Projection`

```luau
export type Projection = {
	read available: boolean,
	read hidden: boolean,
	read loaded: boolean,
	read notes: { { read id: string, read fromName: string, read text: string, read read: boolean } },
	read phrases: { PhraseNoteCore.Phrase },
	read label: string?,
}
```

### `roblox.social-notes.Dependencies`

```luau
export type Dependencies = {
	read phraseNotes: Records.Inbox?,
	read phraseCatalog: (() -> unknown)?,
	read clock: () -> number,
	read notePermitted: ((number, number) -> string?)?,
	read filterPreset: ((number, string) -> string?)?,
	read notifyNote: ((number) -> ())?,
	read canReadNotes: ((number) -> boolean)?,
}
```

### `roblox.social-notes.FellowshipView`

```luau
export type FellowshipView = { read members: { { read userId: number, read displayName: string } } }
```

### `roblox.social-notes.Service`

```luau
export type Service = {
	read recipients: (number) -> { Recipient },
	read projection: (number) -> Projection,
	read send: (number, number, string) -> Response,
	read refresh: (number) -> Response,
	read markRead: (number, string) -> Response,
	read noticed: (number) -> (),
	read forget: (number) -> (),
}
```

### `roblox.social-notes.Config`

```luau
export type Config = {
	read phrases: (unknown) -> { PhraseNoteCore.Phrase }?,
	read live: ({ PhraseNoteCore.Note }, number) -> { PhraseNoteCore.Note },
	read presetLabel: string,
	read sendIntervalSec: number,
}
```

### `roblox.social-notes.API`

```luau
export type API = {
	read create: (
		Dependencies,
		(number) -> FellowshipView | false,
		(number) -> { Candidate },
		(number) -> string?
	) -> Service,
}
```

### `roblox.social-notes.configure`

```luau
function configure(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function create(
		deps: Dependencies,
		fellowshipProjection: (number) -> FellowshipView | false,
		candidateProjection: (number) -> { Candidate },
		memberNameFor: (number) -> string?
	): Service
```

## `roblox.social-party`

[Source](../src/roblox/social-party.luau)

```luau
local PartyHost = require("./party")
```

```luau
local PartyTypes = require("../core/social/membership")
```

```luau
local Rally = require("../core/social/rally")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.social-party.Handle`

```luau
export type Handle = {
	read open: (unknown) -> PartyOutcome,
	read invite: (unknown) -> PartyOutcome,
	read accept: (unknown) -> PartyOutcome,
	read decline: (unknown) -> PartyOutcome,
	read leave: (unknown) -> PartyOutcome,
	read kick: (unknown) -> PartyOutcome,
	read transferLeader: (unknown) -> PartyOutcome,
	read acceptLeaderTransfer: (unknown) -> PartyOutcome,
	read disband: (unknown) -> PartyOutcome,
	read setLootMode: (unknown) -> PartyOutcome,
	read markAbsent: (unknown) -> PartyOutcome,
	read markPresent: (unknown) -> PartyOutcome,
	read sweep: (unknown) -> PartyOutcome,
	read read: (unknown) -> PartyOutcome,
}
```

### `roblox.social-party.Admission`

```luau
export type Admission = { read ok: true, read partyId: string, read members: { number }, read reason: nil }
```

### `roblox.social-party.AdmissionOutcome`

```luau
export type AdmissionOutcome = Admission | { read ok: false, read reason: string, read partyId: nil, read members: nil }
```

### `roblox.social-party.MembershipOutcome`

```luau
export type MembershipOutcome = { read ok: boolean, read partyId: unknown }
```

### `roblox.social-party.AdmissionParty`

```luau
export type AdmissionParty = { read read: (unknown) -> PartyOutcome }
```

### `roblox.social-party.RallyJoinResult`

```luau
export type RallyJoinResult = { ok: false, reason: string } | { ok: true, objectiveId: string, replayed: boolean }
```

### `roblox.social-party.Dependencies`

```luau
export type Dependencies = {
	read projectPartyMembership: (string, string?) -> string?,
	read projectPartySnapshot: ((PartyTypes.State) -> string?)?,
	read partyMembership: (string) -> unknown,
	read candidateRows: (number) -> unknown,
	read realmFor: (number) -> string?,
	read characterFor: (number) -> string?,
	read displayNameFor: (number) -> string?,
	read clock: () -> number,
	read projectRallyJoin: (number, string?) -> (),
	read objectiveRows: () -> unknown,
}
```

### `roblox.social-party.PartyResponse`

```luau
export type PartyResponse = {
	read ok: boolean,
	read reason: string?,
	read party: PartyTypes.State?,
	read replayed: boolean?,
	read found: boolean?,
	read dissolved: boolean?,
	read strandedUserIds: { number }?,
}
```

### `roblox.social-party.CandidateView`

```luau
export type CandidateView = { read userId: number, read displayName: string, read source: "nearby" | "recent" }
```

### `roblox.social-party.PartyMemberView`

```luau
export type PartyMemberView = {
	read userId: number,
	read displayName: string,
	read leader: boolean,
	read present: boolean,
	read canRemove: boolean,
	read canPromote: boolean,
}
```

### `roblox.social-party.PendingPartyInvite`

```luau
export type PendingPartyInvite = { read partyId: string, read inviterUserId: number?, read inviterName: string }
```

### `roblox.social-party.PartyLeaderTransferView`

```luau
export type PartyLeaderTransferView = {
	read recipientUserId: number?,
	read fromUserId: number?,
	read expiresAtSec: number,
	read canAccept: boolean,
}
```

### `roblox.social-party.PartyView`

```luau
export type PartyView = {
	read partyId: string,
	read viewerUserId: number,
	read leaderUserId: number?,
	read members: { PartyMemberView },
	read leaderTransfer: PartyLeaderTransferView | false,
}
```

### `roblox.social-party.PartyProjection`

```luau
export type PartyProjection = {
	read candidates: { CandidateView },
	read incoming: PendingPartyInvite | false,
	read party: PartyView | false,
	read joinedRallyObjectiveId: string | false,
}
```

### `roblox.social-party.ProjectionRefusal`

```luau
export type ProjectionRefusal = { accountId: string, reason: string }
```

### `roblox.social-party.Config`

```luau
export type Config = {
	read lootMode: PartyTypes.LootMode,
	read rally: (unknown, string, string, number) -> { Rally.Row }?,
	read inviteTtlSec: number,
	read leaderTransferTtlSec: number,
	read maxProjectionRefusals: number,
	read maxDisplayName: number,
	read maxCandidates: number,
	read partyId: (number, number, number) -> string,
	read memberFallback: (string) -> string,
	read inviterFallback: string,
	read reportProjectionRefusal: (string, string) -> (),
}
```

### `roblox.social-party.Service`

```luau
export type Service = {
	read party: Handle,
	read partyInvite: (number, number) -> PartyResponse,
	read partyAccept: (number) -> PartyResponse,
	read partyDecline: (number) -> PartyResponse,
	read partyLeave: (number) -> PartyResponse,
	read partyRemove: (number, number) -> PartyResponse,
	read partyTransferLeader: (number, number) -> PartyResponse,
	read partyAcceptLeaderTransfer: (number) -> PartyResponse,
	read partyDisband: (number) -> PartyResponse,
	read partyDisconnect: (number) -> PartyResponse,
	read partyReconnect: (number) -> PartyResponse,
	read partySweep: (string) -> PartyResponse,
	read partyProjection: (number) -> PartyProjection,
	read candidateProjection: (number) -> { CandidateView },
	read candidateNamed: (number, number) -> boolean,
	read partyAudience: (number) -> { number },
	read pendingInviteCount: () -> number,
	read rallyBoard: (string, string) -> { Rally.Row }?,
	read joinRally: (number, string, string) -> RallyJoinResult,
	read leaveRally: (number) -> { ok: boolean, replayed: boolean },
}
```

### `roblox.social-party.Host`

```luau
export type Host = {
	read create: (Dependencies, Handle) -> Service,
	read projectionRefusals: () -> { ProjectionRefusal },
}
```

### `roblox.social-party.admission`

```luau
function admission(
	readMembership: ((string) -> MembershipOutcome)?,
	party: AdmissionParty,
	soloId: (number) -> string
): (number) -> AdmissionOutcome
```

### `roblox.social-party.configure`

```luau
function configure(config: Config): Host
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function create(deps: Dependencies, partySource: PartyHandle): Service
projectionRefusals = function()
```

## `roblox.social-records`

[Source](../src/roblox/social-records.luau)

```luau
local Codec = require("../kernel/codec")
```

```luau
local Fellowship = require("../core/social/fellowship")
```

```luau
local Formation = require("../core/social/formation")
```

```luau
local Notes = require("../core/social/notes")
```

```luau
local ResultEnvelope = require("../kernel/result")
```

```luau
local StorePort = require("../kernel/store")
```

```luau
local Value = require("../kernel/value")
```

```luau
local Warband = require("../core/social/warband")
```

### `roblox.social-records.Outcome`

```luau
export type Outcome = ResultEnvelope.Result<unknown>
```

### `roblox.social-records.Store`

```luau
export type Store = StorePort.Port
```

### `roblox.social-records.FellowshipPort`

```luau
export type FellowshipPort = {
	create: (unknown, unknown) -> Fellowship.Result,
	createFromFormation: (unknown, unknown) -> Fellowship.Result,
	projectState: (unknown) -> Fellowship.State?,
	transition: (unknown, unknown, unknown) -> Fellowship.Result,
}
```

### `roblox.social-records.FormationPort`

```luau
export type FormationPort = {
	start: (unknown, unknown) -> Formation.Result,
	projectState: (unknown) -> Formation.State?,
	transition: (unknown, unknown, unknown) -> Formation.Result,
}
```

### `roblox.social-records.WarbandPort`

```luau
export type WarbandPort = {
	project: (unknown) -> Warband.State?,
	found: (string, string, Warband.Party, number, number) -> Warband.Result,
	transition: (Warband.State, Warband.Event, Warband.Parties, number) -> Warband.Result,
}
```

### `roblox.social-records.Dependencies`

```luau
export type Dependencies = {
	store: Store,
	keyFor: (string) -> string,
	memberKeyFor: (number) -> string,
	formationKeyFor: ((string) -> string)?,
	warbandKeyFor: ((string, string) -> string)?,
	clock: () -> number,
	fellowship: FellowshipPort,
	formation: FormationPort,
	warband: WarbandPort,
}
```

### `roblox.social-records.Refusal`

```luau
export type Refusal = { ok: false, state: nil, replayed: boolean, reason: string }
```

### `roblox.social-records.RecordResult`

```luau
export type RecordResult<T> = { ok: true, state: T, replayed: boolean, reason: nil } | Refusal
```

### `roblox.social-records.Result`

```luau
export type Result = RecordResult<Fellowship.State>
```

### `roblox.social-records.FormationResult`

```luau
export type FormationResult = RecordResult<Formation.State>
```

### `roblox.social-records.Status`

```luau
export type Status = { ok: boolean, reason: string? }
```

### `roblox.social-records.ProposerResult`

```luau
export type ProposerResult = Status & { formationId: string? }
```

### `roblox.social-records.Membership`

```luau
export type Membership = { read fellowshipId: string, read pending: boolean, read revision: number }
```

### `roblox.social-records.MembershipResult`

```luau
export type MembershipResult = { ok: boolean, membership: Membership?, reason: string? }
```

### `roblox.social-records.WarbandMembership`

```luau
export type WarbandMembership = { warbandId: string, revision: number, pending: boolean }
```

### `roblox.social-records.WarbandMembershipResult`

```luau
export type WarbandMembershipResult = { ok: boolean, membership: WarbandMembership?, reason: string? }
```

### `roblox.social-records.LedgerOutcome`

```luau
export type LedgerOutcome<State, Receipt> = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	receipts: { Receipt }?,
	fence: string?,
}
```

### `roblox.social-records.Settled`

```luau
export type Settled<State, Receipt> = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	receipts: { Receipt }?,
	ambiguous: boolean,
	fence: string?,
}
```

### `roblox.social-records.LedgerCore`

```luau
export type LedgerCore<Subject, State, Receipt> = {
	empty: (Subject) -> State?,
	project: (unknown) -> State?,
	apply: (State, unknown, number) -> LedgerOutcome<State, Receipt>,
	invalid: string,
}
```

### `roblox.social-records.LedgerDependencies`

```luau
export type LedgerDependencies<Subject, State, Receipt> = {
	store: Store,
	keyFor: (Subject) -> string,
	clock: () -> number,
	core: LedgerCore<Subject, State, Receipt>,
}
```

### `roblox.social-records.Ledger`

```luau
export type Ledger<Subject, State, Receipt> = {
	read read: (Subject) -> Settled<State, Receipt>,
	read apply: (Subject, unknown) -> Settled<State, Receipt>,
}
```

### `roblox.social-records.InboxCore`

```luau
export type InboxCore = {
	emptyState: (unknown) -> Notes.State?,
	projectState: (unknown) -> Notes.State?,
	deliver: (unknown, unknown, unknown) -> Notes.Result,
	markRead: (unknown, unknown) -> Notes.Result,
}
```

### `roblox.social-records.InboxDependencies`

```luau
export type InboxDependencies = {
	store: Store,
	keyFor: (number) -> string,
	clock: () -> number,
	guid: () -> string,
	core: InboxCore,
	invalid: string,
}
```

### `roblox.social-records.InboxResult`

```luau
export type InboxResult = { ok: boolean, notes: { Notes.Note }?, reason: string? }
```

### `roblox.social-records.Inbox`

```luau
export type Inbox = {
	read inbox: (number) -> InboxResult,
	read deliver: (number, string, number, string) -> InboxResult,
	read markRead: (number, string) -> InboxResult,
}
```

### `roblox.social-records.KeyedOutcome`

```luau
export type KeyedOutcome<Item> = { ok: boolean, value: Item?, reason: string? }
```

### `roblox.social-records.KeyedDependencies`

```luau
export type KeyedDependencies<Item> = {
	store: Store,
	keyFor: (string) -> string,
	project: (unknown) -> Item?,
	wire: (Item) -> unknown?,
	idOf: (Item) -> string,
	prefix: string,
	invalid: string,
}
```

### `roblox.social-records.Keyed`

```luau
export type Keyed<Item> = {
	read getOutcome: (string) -> KeyedOutcome<Item>,
	read updateOutcome: (string, (Item?) -> Item?) -> KeyedOutcome<Item>,
}
```

### `roblox.social-records.IndexDependencies`

```luau
export type IndexDependencies<Entry> = {
	store: Store,
	keyFor: (number) -> string,
	read: (unknown) -> Entry?,
	idOf: (Entry) -> string,
	owns: (Entry, number) -> boolean,
	same: (Entry, Entry) -> boolean,
	limit: number,
}
```

### `roblox.social-records.IndexListing`

```luau
export type IndexListing<Entry> = { ok: boolean, entries: { [string]: Entry }?, reason: string? }
```

### `roblox.social-records.Index`

```luau
export type Index<Entry> = {
	read add: (number, Entry) -> (boolean, string?),
	read remove: (number, Entry) -> boolean,
	read list: (number) -> IndexListing<Entry>,
}
```

### `roblox.social-records.Service`

```luau
export type Service = {
	read readWarband: (string) -> Warband.Result,
	read foundWarband: (string, string, Warband.Party, number) -> Warband.Result,
	read applyWarband: (string, Warband.Event, Warband.Parties) -> Warband.Result,
	read readWarbandMembership: (string) -> WarbandMembershipResult,
	read claimWarbandMembership: (string, string) -> WarbandMembershipResult,
	read confirmWarbandMembership: (string, WarbandMembership) -> WarbandMembershipResult,
	read releaseWarbandMembership: (string, WarbandMembership) -> WarbandMembershipResult,
	read read: (string) -> Result,
	read found: (Fellowship.FoundRequest) -> Result,
	read apply: (string, unknown) -> Result,
	read readFormation: (string) -> FormationResult,
	read startFormation: (Formation.StartRequest) -> FormationResult,
	read applyFormation: (string, unknown) -> FormationResult,
	read foundFromFormation: (Formation.State) -> Result,
	read readProposerFormation: (number) -> ProposerResult,
	read setProposerFormation: (number, string) -> Status,
	read clearProposerFormation: (number, string) -> Status,
	read readMembership: (number) -> MembershipResult,
	read claimMembership: (number, string) -> MembershipResult,
	read confirmMembership: (number, string) -> MembershipResult,
	read releaseMembership: (number, Membership) -> MembershipResult,
}
```

### `roblox.social-records.create`

```luau
function SocialRecords.create(dependencies: Dependencies): (Service?, string?)
```

### `roblox.social-records.inbox`

```luau
function SocialRecords.inbox(dependencies: InboxDependencies): (Inbox?, string?)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
inbox = function inbox(userId: number): InboxResult
deliver = function deliver(fromUserId: number, fromName: string, toUserId: number, phraseId: string): InboxResult
markRead = function markRead(userId: number, noteId: string): InboxResult
```

### `roblox.social-records.index`

```luau
function SocialRecords.index<Entry>(dependencies: IndexDependencies<Entry>): (Index<Entry>?, string?)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
add = function(userId: number, entry: Entry): (boolean, string?)
remove = function(userId: number, entry: Entry): boolean
list = function list(userId: number): IndexListing<Entry>
```

### `roblox.social-records.keyed`

```luau
function SocialRecords.keyed<Item>(dependencies: KeyedDependencies<Item>): (Keyed<Item>?, string?)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
getOutcome = function getOutcome(id: string): KeyedOutcome<Item>
updateOutcome = function updateOutcome(id: string, transform: (Item?) -> Item?): KeyedOutcome<Item>
```

### `roblox.social-records.ledger`

```luau
function SocialRecords.ledger<Subject, State, Receipt>(
	dependencies: LedgerDependencies<Subject, State, Receipt>
): (Ledger<Subject, State, Receipt>?, string?)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
read = function read(subject: Subject): Settled<State, Receipt>
apply = function apply(subject: Subject, command: unknown): Settled<State, Receipt>
```

## `roblox.social-warband`

[Source](../src/roblox/social-warband.luau)

```luau
local Core = require("../core/social/warband")
```

```luau
local PartyTypes = require("../core/social/membership")
```

```luau
local RecordTypes = require("./social-records")
```

### `roblox.social-warband.PartyResult`

```luau
export type PartyResult = { read ok: boolean, read found: boolean?, read party: Party?, read reason: string? }
```

### `roblox.social-warband.Dependencies`

```luau
export type Dependencies = {
	records: Records?,
	membership: (string) -> unknown,
	readParty: (string) -> PartyResult,
	clock: () -> number,
	nameFor: (number) -> string?,
	objectiveAllowed: (number, string, string) -> boolean,
	inviteAllowed: (number, number) -> boolean,
}
```

### `roblox.social-warband.Summary`

```luau
export type Summary = {
	partyId: string,
	leaderUserId: number,
	leaderName: string,
	connected: boolean,
	members: number,
	commander: boolean,
	assistant: boolean,
}
```

### `roblox.social-warband.Projection`

```luau
export type Projection = {
	rallyHosts: { { leaderUserId: number, leaderName: string, objectiveId: string } },
	requests: { { leaderUserId: number, leaderName: string, objectiveId: string } },
	available: boolean,
	revision: number,
	warbandId: string?,
	units: { Summary },
	isLeader: boolean,
	isCommander: boolean,
	canCommand: boolean,
	canAccept: boolean,
	canAcceptTransfer: boolean,
	order: Core.Order?,
	rallyObjectiveId: string?,
	targetObjectiveId: string?,
	rallyByActorId: string?,
	targetByActorId: string?,
	refusal: string?,
}
```

### `roblox.social-warband.Result`

```luau
export type Result = { ok: boolean, reason: string?, audience: { number } }
```

### `roblox.social-warband.Handle`

```luau
export type Handle = {
	read act: (number, string, number, number, string, string) -> Result,
	read project: (number, boolean?) -> Projection,
	read refresh: () -> { number },
}
```

### `roblox.social-warband.Config`

```luau
export type Config = {
	read unitOf: (State, string) -> Core.Unit?,
	read command: (State, string) -> boolean,
	read maxParties: number,
	read requestTtlSec: number,
	read rallyZone: string,
	read warbandId: (string, number, number) -> string,
	read memberFallback: (number) -> string,
}
```

### `roblox.social-warband.API`

```luau
export type API = { read create: (Dependencies) -> Handle }
```

### `roblox.social-warband.configure`

```luau
function configure(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function WarbandSocial.create(deps: Dependencies): Handle
```

## `roblox.social-whispers`

[Source](../src/roblox/social-whispers.luau)

### `roblox.social-whispers.Response`

```luau
export type Response = { ok: boolean, reason: string?, channelName: string? }
```

### `roblox.social-whispers.View`

```luau
export type View = { read userId: number, read displayName: string, read channelName: string }
```

### `roblox.social-whispers.Dependencies`

```luau
export type Dependencies = {
	read openWhisper: ((number, number) -> (string?, string?))?,
	read closeWhisper: ((string) -> ())?,
	read realmFor: (number) -> string?,
}
```

### `roblox.social-whispers.Service`

```luau
export type Service = {
	read open: (number, number) -> Response,
	read projection: (number) -> { View },
	read close: (number) -> { number },
}
```

### `roblox.social-whispers.Config`

```luau
export type Config = {
	read pairName: (number, number) -> string,
	read memberFallback: (number) -> string,
}
```

### `roblox.social-whispers.API`

```luau
export type API = { read create: (Dependencies, (number) -> string?) -> Service }
```

### `roblox.social-whispers.configure`

```luau
function configure(config: Config): API
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function create(deps: Dependencies, memberNameFor: (number) -> string?): Service
```

## `roblox.target-selection`

[Source](../src/roblox/target-selection.luau)

### `roblox.target-selection.Candidate`

```luau
export type Candidate<P> = { npcId: string, screenPos: P }
```

### `roblox.target-selection.Release`

```luau
export type Release = typeof(Selection.release(1, 1))
```

### `roblox.target-selection.create`

```luau
function Selection.create<P>(coordinates: (P) -> (number, number))
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
pickNearestToTap = function Projected.pickNearestToTap(tap: P, candidates: { Candidate<P> }, radius: number): string?
tapSelection = function Projected.tapSelection(resolved: string?, tap: P, candidates: { Candidate<P> }, radius: number): string?
```

### `roblox.target-selection.pickNext`

```luau
function Selection.pickNext(candidates: { string }, current: string?): string?
```

### `roblox.target-selection.release`

```luau
function Selection.release(range: number, seconds: number)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
observe = function(distance: number?, now: number): boolean
reset = function()
```

## `roblox.thumbstick`

[Source](../src/roblox/thumbstick.luau)

### `roblox.thumbstick.Vec2`

```luau
export type Vec2 = { x: number, y: number }
```

### `roblox.thumbstick.Stick`

```luau
export type Stick = {
	anchor: Vec2,
	knob: Vec2,
	vector: Vec2,
}
```

### `roblox.thumbstick.create`

```luau
function Module.create(options: { radiusPx: number, deadZone: number, zoneWidth: number, zoneHeight: number })
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
DEAD_ZONE = options.deadZone
RADIUS_PX = options.radiusPx
ZONE_WIDTH_SCALE = options.zoneWidth
ZONE_HEIGHT_SCALE = options.zoneHeight
anchorAt = function anchorAt(point: Vec2): Stick
drag = function drag(stick: Stick, point: Vec2, radiusPx: number?, deadZone: number?): Stick
release = function release(): Vec2
vectorFor = function vectorFor(offset: Vec2, radiusPx: number, deadZone: number): Vec2
knobFor = function knobFor(offset: Vec2, radiusPx: number): Vec2
```

## `roblox.trade`

[Source](../src/roblox/trade.luau)

```luau
local Exchange = require("../core/trade/exchange")
```

```luau
local ReceiptTypes = require("../core/trade/receipt")
```

```luau
local Transfer = require("./profile-transfer")
```

```luau
local Value = require("../kernel/value")
```

### `roblox.trade.Subject`

```luau
export type Subject = { read UserId: number }
```

### `roblox.trade.Location`

```luau
export type Location = { read x: number, read y: number, read z: number }
```

### `roblox.trade.Context`

```luau
export type Context = Transfer.Identity
```

### `roblox.trade.Account`

```luau
export type Account = {
	coin: number,
	inventory: { [string]: number },
	pending: { [string]: ReceiptTypes.Pointer }?,
}
```

### `roblox.trade.State`

```luau
export type State = Exchange.State & { sessions: { [number]: Context }?, characters: { [number]: string }? }
```

### `roblox.trade.ReceiptOutcome`

```luau
export type ReceiptOutcome = { read ok: boolean, read value: unknown, read reason: string? }
```

### `roblox.trade.Dependencies`

```luau
export type Dependencies<P, Surface> = {
	read profiles: Surface,
	read receipts: {
		read getOutcome: (string) -> ReceiptOutcome,
		read updateOutcome: (string, (ReceiptTypes.Projected?) -> ReceiptTypes.Projected?) -> ReceiptOutcome,
	},
	read contextFor: (number) -> Context?,
	read playerFor: (number) -> Subject?,
	read positionFor: (number) -> Location?,
	read allowed: (number) -> boolean,
	read tradeable: (number, P, string, number) -> boolean,
	read newId: () -> string,
	read clock: () -> number,
	read identity: ((Subject) -> unknown)?,
	read schedule: ((number, () -> ()) -> ())?,
}
```

### `roblox.trade.Result`

```luau
export type Result = {
	ok: boolean,
	reason: string?,
	pending: boolean?,
	tradeId: string?,
	state: State?,
	outcomes: { [string]: Result }?,
}
```

### `roblox.trade.Service`

```luau
export type Service = {
	read intent: (Subject, unknown) -> Result,
	read recover: (string, number?) -> Result,
	read admit: (number) -> Result,
	read playerRemoving: (Subject) -> Result,
	read sweepExpired: () -> number,
	read state: (string) -> State?,
	read stateFor: (number) -> State?,
}
```

### `roblox.trade.ExchangeOps`

```luau
export type ExchangeOps = {
	read offer: (unknown) -> Exchange.Offer?,
	read empty: (string, number, number) -> Exchange.State?,
	read step: (Exchange.State, number, unknown) -> (Exchange.State?, string?),
	read settled: (Exchange.State) -> Exchange.State?,
}
```

### `roblox.trade.ReceiptOps`

```luau
export type ReceiptOps = {
	read project: (unknown) -> ReceiptTypes.Projected?,
	read wire: (unknown) -> ReceiptTypes.Wire?,
}
```

### `roblox.trade.Effect`

```luau
export type Effect<P> = (P) -> (P?, string?)
```

### `roblox.trade.Config`

```luau
export type Config<P, Surface> = {
	read exchange: ExchangeOps,
	read receipts: ReceiptOps,
	read account: (P) -> Account,
	read withAccount: (P, Account) -> P,
	read capacity: (P) -> number,
	read entries: ({ [string]: number }) -> number,
	read unboundCount: (P, string) -> number,
	read related: (P, P) -> boolean,
	read recorded: (P, string) -> boolean,
	read profileFor: (Surface, (number) -> Context?, number) -> (P?, Context?),
	read commit: (Surface, Context, string, Effect<P>) -> Transfer.Result,
	read receiptKey: (string) -> string,
	read transactionId: (string, string, number) -> string,
	read maxCoin: number,
	read maxUserId: number,
	read maxStack: number,
	read maxDistance: number,
	read idLimit: number,
	read maxRecoverySlots: number,
	read maxCompleted: number,
	read rateWindowSec: number,
	read rateLimit: number,
	read tradeTtlSec: number,
}
```

### `roblox.trade.Host`

```luau
export type Host<P, Surface> = {
	read create: (Dependencies<P, Surface>) -> (Service?, string?),
	read MAX_DISTANCE: number,
	read RATE_LIMIT: number,
	read TRADE_TTL_SEC: number,
}
```

### `roblox.trade.configure`

```luau
function configure<P, Surface>(config: Config<P, Surface>): Host<P, Surface>
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
create = function TradeService.create(depsValue: Deps): (Service?, string?)
```

## `roblox.travel-placement`

[Source](../src/roblox/travel-placement.luau)

### `roblox.travel-placement.PlacementHost`

```luau
export type PlacementHost<Frame, Floor> = {
	count: number,
	candidate: (number) -> Frame,
	clear: (Frame) -> boolean,
	ground: () -> Floor?,
	floor: (Frame) -> Floor?,
	safe: (Floor, Floor) -> boolean,
	commit: (Frame) -> (),
}
```

### `roblox.travel-placement.EntranceHost`

```luau
export type EntranceHost<Frame, Point, Floor> = {
	count: number,
	point: (number) -> Point,
	clear: (Point) -> boolean,
	near: (Point) -> Floor?,
	far: (Point) -> Floor?,
	safe: (Floor) -> boolean,
	frame: (Floor) -> Frame,
}
```

### `roblox.travel-placement.entrance`

```luau
function Travel.entrance<Frame, Point, Floor>(host: EntranceHost<Frame, Point, Floor>): Frame?
```

### `roblox.travel-placement.place`

```luau
function Travel.place<Frame, Floor>(host: PlacementHost<Frame, Floor>): Frame?
```

## `test-scene.cast`

[Source](../src/test-scene/cast.luau)

```luau
local Clock = require("./clock")
```

```luau
local Queue = require("../core/cast/queue")
```

### `test-scene.cast.new`

```luau
function Scene.new(config: Queue.Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
clock = clock
law = law
enqueue = function enqueue(
		payload: string,
		requeues: number,
		reason: string?,
		remainingSec: number?
	): Queue.Entry<string>?
cancel = function(token: number?)
snapshot = function(): Queue.State<string>
fired = fired
```

## `test-scene.character-leases`

[Source](../src/test-scene/character-leases.luau)

```luau
local Clock = require("./clock")
```

```luau
local Lease = require("../core/identity/character-lease")
```

```luau
local Leases = require("../core/identity/character-lease-store")
```

```luau
local StoreScene = require("./persistence/store")
```

### `test-scene.character-leases.Config`

```luau
export type Config = Lease.Config
```

### `test-scene.character-leases.Options`

```luau
export type Options = StoreScene.Options
```

### `test-scene.character-leases.new`

```luau
function new(config: Config, options: Options?)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
record = record
repository = repository
store = storage.store
seed = storage.seed
clock = clock
writes = storage.writes
```

## `test-scene.clock`

[Source](../src/test-scene/clock.luau)

### `test-scene.clock.Task`

```luau
export type Task = { due: number, active: boolean, callback: () -> () }
```

### `test-scene.clock.new`

```luau
function Clock.new()
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
clock = function(): number
schedule = function schedule(delay: number, callback: () -> ()): () -> ()
advance = function advance(seconds: number)
```

## `test-scene.combat`

[Source](../src/test-scene/combat.luau)

```luau
local Contact = require("../core/combat/contact")
```

```luau
local Value = require("../kernel/value")
```

### `test-scene.combat.Payload`

```luau
export type Payload = { read impact: number, read tags: { [string]: number } }
```

### `test-scene.combat.new`

```luau
function new()
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
rules = rules
admission = function admission()
source = function source()
observation = function observation()
```

## `test-scene.diminishing`

[Source](../src/test-scene/diminishing.luau)

```luau
local Clock = require("./clock")
```

```luau
local Diminishing = require("../core/control/diminishing")
```

### `test-scene.diminishing.new`

```luau
function Scene.new(config: Diminishing.Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
clock = clock
apply = function(category: string, durationSec: number): Diminishing.Result
snapshot = function(): Diminishing.State
```

## `test-scene.effects`

[Source](../src/test-scene/effects.luau)

```luau
local Clock = require("./clock")
```

```luau
local Timed = require("../core/effects/timed")
```

### `test-scene.effects.Host`

```luau
export type Host = {
	clock: () -> number,
	apply: (string, Timed.Application) -> (),
	advance: (number) -> (),
	snapshot: () -> { [string]: Timed.Entry },
}
```

### `test-scene.effects.new`

```luau
function Scene.new(epsilon: number): Host
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
clock = clock.clock
apply = function apply(id: string, application: Timed.Application)
advance = function advance(dt: number)
snapshot = function(): { [string]: Timed.Entry }
```

## `test-scene.identity`

[Source](../src/test-scene/identity.luau)

```luau
local Policy = require("../core/identity/policy")
```

### `test-scene.identity.accountLimit`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.maxLevel`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.minLevel`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.peoples`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.profilePartitionKey`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.realmLimit`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.realms`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.registryKey`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.validDestination`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.validRegistryKey`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

### `test-scene.identity.validateName`

Exported value; see its declaration in [source](../src/test-scene/identity.luau).

## `test-scene.owner`

[Source](../src/test-scene/owner.luau)

```luau
local Sessions = require("../roblox/profile-sessions")
```

### `test-scene.owner.new`

```luau
function Owner.new(): Sessions.Owner
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
own = function own(cleanup: () -> ()): () -> ()
createChild = function(): Sessions.Owner
dispose = function()
size = function(): number
```

## `test-scene.persistence.store`

[Source](../src/test-scene/persistence/store.luau)

```luau
local Atomic = require("../../roblox/persistence/store")
```

```luau
local Host = require("../../core/persistence/store-host")
```

```luau
local Kernel = require("../../kernel/store")
```

```luau
local Retry = require("../../roblox/data-store")
```

### `test-scene.persistence.store.Options`

```luau
export type Options = Host.TestOptions
```

### `test-scene.persistence.store.Scene`

```luau
export type Scene = {
	read store: Kernel.Port,
	read seed: (string, unknown) -> (),
	read writes: () -> number,
	read updates: () -> number,
	read values: { [string]: unknown },
}
```

### `test-scene.persistence.store.API`

```luau
export type API = { read new: typeof(new) }
```

### `test-scene.persistence.store.new`

```luau
function new(clock: () -> number, options: Options?, initial: { [string]: unknown }?): Scene
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
store = Atomic.new(backend)
seed = function(key: string, value: unknown)
writes = function(): number
updates = function(): number
values = values
```

## `test-scene.signal`

[Source](../src/test-scene/signal.luau)

### `test-scene.signal.new`

```luau
function Signal.new<T>()
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
connect = function(callback: (T) -> ()): () -> ()
fire = function(value: T)
count = function(): number
```

## `test-scene.social`

[Source](../src/test-scene/social.luau)

```luau
local Fellowship = require("../core/social/fellowship")
```

```luau
local Formation = require("../core/social/formation")
```

```luau
local Records = require("../roblox/social-records")
```

```luau
local Warband = require("../core/social/warband")
```

### `test-scene.social.Counters`

```luau
export type Counters = { writes: number, clock: number }
```

### `test-scene.social.Options`

```luau
export type Options = { requiredFounders: number?, fee: number?, store: Records.Store? }
```

### `test-scene.social.rig`

```luau
function Social.rig(
	readback: ((unknown) -> unknown)?,
	options: Options?
): (Records.Service, { [string]: unknown }, Counters)
```

## `test-scene.threat`

[Source](../src/test-scene/threat.luau)

```luau
local Clock = require("./clock")
```

```luau
local Threat = require("../core/threat/table")
```

### `test-scene.threat.new`

```luau
function Scene.new(config: Threat.Config)
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
clock = clock
add = function(actorId: string, amount: number, inMelee: boolean)
taunt = function(actorId: string)
remove = function(actorId: string)
prune = function(candidates: { [string]: Threat.Candidate }): Threat.Pruned
reset = function()
snapshot = function(): Threat.State
refreshes = function(): number
```

## `test-scene.vendor`

[Source](../src/test-scene/vendor.luau)

```luau
local Clock = require("./clock")
```

```luau
local Exchange = require("../core/vendors/exchange")
```

### `test-scene.vendor.new`

```luau
function Scene.new()
```

Returned operations and values (declarations; unannotated results are inferred):

```luau
law = law
clock = clock
vendor = vendor
prices = prices
```


</details>
