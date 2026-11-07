# Adoption

[Play](../README.md) · [Architecture](architecture.md) · [System catalog](api.md#task-table) · [API reference](api.md)

Games supply content, policy, saved schemas and native authority. Play supplies reusable rules,
validation and coordination over explicit host ports. Keep an adopter's source comparison, file
inventory, migration receipts and acceptance evidence in that adopter's repository.

## Choose the boundary

| Area | Play owns | The game supplies |
| --- | --- | --- |
| Identity and admission | Claims, creation/retirement transitions, lease coordination, routing checks and staged cleanup. | Identity and record codecs, destinations, native carrier authority, ownership ports and labels. |
| Persistence | Atomic readback confirmation, fencing, record coordination and session recovery. | Store scope, saved schema/migration, payload projections, timing policy and resource lifetime. |
| Combat and rewards | Threat, effects, contribution and loot rules. | Class kits, enemy mechanics, actor schema, random samples and grant installation. |
| Items | Stack/equipment transitions, wear, repair plans and exchanges. | Item definitions, eligibility, capacity, proficiency and currency projection. |
| Quests and progression | Objective/journal transitions, validation, ordering and replay admission. | Catalog, status vocabulary, spatial facts, experience curve, rewards and caps. |
| Economy | Configured bank, trade, mail and market coordination and recovery. | Profile/ledger projections, transaction authority, item policy, namespaces and native lifetime. |
| Social | Group admission, membership, formation, messaging and guild-bank coordination. | Platform observations, communication permission, phrases, labels, fees, catalogs and limits. |
| Cargo | Pure claim custody, drops, extraction receipts and conservation. | Camp geometry, safe radii, realm bindings, intent installation and persistence integration. |

Use the selected [API area](api.md#task-table) for its current public entry, required ports, runnable
example and invariants. The API owns signatures, returns, failures and import paths.

## Cut over one consumer

1. Pin a merged library commit and its exact tree through the game's dependency tooling. CI and
   documentation changes do not require a runtime repin.
2. Supply one configured binding for game policy, schema and host operations. Preserve fail-closed
   admission, uncertainty, cleanup, lease fencing and receipt identity at every boundary.
3. Run the game's actual service and persistence regressions against the binding. Library fixtures
   prove their configured fake hosts; they do not establish live storage or native player behavior.
4. Remove the displaced implementation, its copied generic tests and stale callers together.
   Retain tests of authored content, configured policy and game wiring. Record the deletion in the game.
5. Complete the game's required native and durability proof before calling its cutover accepted.
   A source gate or successful module load does not substitute for consumer evidence.

The [host-operation contract](api.md#host-operations) and
[compatibility policy](../README.md#compatibility) apply throughout the cutover.

Keep private deployment identities and cutover status outside this library. Shared guides describe
the current reusable contract; adopter-specific plans and historical line counts do not define it.
