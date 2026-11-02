# Realms adoption

[Return to Play](../README.md) · [Character lease system](systems/character-leases.md)

The comparison used Realms source at `ead38db43d31cb66e28f0298fc0189491e566251`.
This is a library extraction and cutover guide. The game owner updates the consumer pin and lands
the game changes; this library change does not claim a completed production cutover.

## Comparison

| Realms owner | Existing Play implementation | Remaining responsibility |
| --- | --- | --- |
| `shared/world/ZoneStoreCombat.luau` and `ZoneStoreTick.luau` | Threat tables, timed effects, contribution, progression and loot are already imported. | World orchestration, class kits, authored enemy mechanics and authoritative actor schema still compose game policy. |
| `shared/world/ZoneStoreRules.luau` | `threat.table.rules` | Configured takeover values, class rules, combat tuning and random samples. |
| `shared/world/MobLootRoll.luau` and `ZonePartyLoot.luau` | `loot.roll`, `loot.decision` | Receipt namespace, actor identity and world grant integration. |
| `roblox/shared/services/InventoryRules.luau` | `inventory.stacks` | Item definitions, permanent items, bag sizes and stack limits. |
| `roblox/shared/quests/QuestFramework.luau` | `quest.objectives`, `quest.lifecycle` | Game objective shape/metadata. `ZoneStoreQuest.luau` still combines actor progress with realm admission and content-row lookup (367 lines). |
| `shared/progression/ProfileProgression.luau` | `progression.levels` | Authored XP curve, level cap, rewards and early-level death policy. `DerivedStats.luau` retains class/equipment formulas (415 lines). |
| `shared/economy/trade/TradeCore.luau` and `TradeReceipt.luau` | `trade.exchange`, `trade.receipt` | Numeric bounds and durable account wiring. |
| `shared/economy/mail/MailCore.luau` | `mail.mailbox` | Profile schema, inventory conversion and game limits. |

The already-delegating modules above are game bindings rather than duplicated rule implementations.
The character lease block is the largest self-contained remaining extraction selected in this pass:
1,157 lines spanning record rules, atomic coordination and recovery planning. It exceeds the complete
1,039-line combat helper while avoiding that helper's class, world and content dependencies.
The larger world tick and frontier files contain mixed orchestration and game mechanics; moving them
wholesale would move canon and game schemas into the library.

## Implementations made deletable

| Exact Realms path | Lines displaced | Play replacement |
| --- | ---: | --- |
| `shared/progression/CharacterLeaseRecord.luau` | 556 | `Identity.character_lease.create(recordPolicy)` |
| `roblox/shared/services/CharacterLeaseRepository.luau` | 430 | `Identity.character_lease_store.create(storePolicy)` |
| `shared/progression/CharacterRetirementPlan.luau` | 171 | `Identity.retirement.create(retirementPolicy)` |

`Identity` is the value returned by `src/core/identity`. Its exported component-prefixed aliases
cover every record, witness, claim, outcome, view and configuration type. Factories return the
operation names and result shapes used by the displaced implementations. Their constants come
from the game's policy. The game can delete these three implementations after routing imports to
one thin game-owned configured binding; it need not retain forwarding implementations at those paths.

## Cutover

1. Pin the merged Play commit and exact tree in Realms' `dependencies.lock.luau` and sync through
   its dependency tooling. Keep the three surface roles described in the [README](../README.md#pin-and-consume).
2. Keep current schema/version bounds, identifier lengths, timestamp limits, retirement phase sets
   and the old `lifted` migration policy in a game-owned policy module. Pass them to the factories.
   No default policy or historical game schema is embedded in Play. `migrate` must return detached
   data and preserve the current migration admission/refusal behavior; use an identity projector
   only when intentionally refusing old schemas. Keep numeric identity/zone limits consistent
   between the record and store coordinator.
3. Configure the three APIs once in a thin game-owned binding. The atomic store port matches
   `DataStoreResource`/Play's `store-host` outcome contract. Keep `PersistenceScope` keys, session
   heartbeat observations, native services and lifecycle scheduling in Realms.
4. Route the record/repository/planner imports and type references to that binding, then delete
   the three displaced implementations. Reconcile project generation and native module-import
   tests when removing paths. Do not remove host durability or admission tests.
5. Run the original record, repository and retirement-plan specifications against the binding.
   Run affected deletion, admission, profile session and quest durability specifications and
   whole-tree analysis because these exported contracts reach distant consumers. Follow Realms'
   source-delivery procedure; durability in a deployed place remains the game owner's check.

Production consumers requiring the import cutover include:

- `roblox/shared/services/CharacterDeletionPersistence.luau`
- `roblox/shared/services/CharacterProfileAdmission.luau`
- `roblox/shared/services/ProfilePersistenceSession.luau`
- `roblox/shared/services/ZoneCharacterAdmission.luau`
- `roblox/shared/services/ZoneQuestDurability.luau`
- `roblox/places/development/frontdoor/FrontdoorRosterAdmission.luau`
- `roblox/places/development/frontdoor/FrontdoorRosterAdmissionEntry.server.luau`
- `roblox/places/zone-return/server/ZoneCharacterAdmissionMount.luau`
- `lute/shared/projectgen.luau`

The persistence-test probes, fault harness and corresponding specifications also reference these
paths. Enumerate them with `git grep -n -E 'CharacterLeaseRecord|CharacterLeaseRepository|CharacterRetirementPlan' -- '*.luau'`
in the consumer before deleting files.

## Validation boundary

The extraction replayed all 79 original Realms record, repository and retirement-plan case bodies
through Verify against the Play factories. Only imports, game policy construction and the existing
Play memory-store binding changed in that replay. Current record slots, exact-expiry ownership,
foreign identity, schema refusal, receipt replay, callback retries, transport failure and recovery
decisions matched the original expectations. The game checkout and its pin were unchanged.

Maintained library specifications additionally exercise a different schema, smaller bounds,
caller-defined recovery phases and caller-owned migration. The gate runs these specifications and
the [standalone fake-host example](../tools/examples/character-leases.luau). These checks establish
the reusable rule/port contract; they do not establish native deployment or a repinned game build.
