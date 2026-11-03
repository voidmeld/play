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
| `roblox/shared/services/EquipmentRules.luau` | `inventory.equipment` | Eligibility/slot policy, class/proficiency rules, stack/capacity configuration, item definitions and profile currency installation. Wear, copy transfers, repair plans and inventory exchanges delegate to Play. |
| `roblox/shared/quests/QuestFramework.luau` | `quest.objectives`, `quest.lifecycle` | Game objective shape/metadata. `ZoneStoreQuest.luau` still combines actor progress with realm admission and content-row lookup (367 lines). |
| `shared/progression/ZoneQuestRecord.luau` | `quest.journal` | Saved version, numeric/identity bounds, status vocabulary, semantic receipt namespace and known quest catalog. Generic validation/copying and journal storage conversion delegate to Play. |
| `shared/progression/ProfileProgression.luau` | `progression.levels` | Authored XP curve, level cap, rewards and early-level death policy. `DerivedStats.luau` retains class/equipment formulas (415 lines). |
| `shared/economy/trade/TradeCore.luau` and `TradeReceipt.luau` | `trade.exchange`, `trade.receipt` | Numeric bounds and durable account wiring. |
| `roblox/shared/services/TradeService.luau` | `roblox/trade.configure` | Profile projection, transaction ledger, realm/item policy, storage namespace and native remote lifetime. The durable exchange coordinator can be removed from this service. |
| `shared/economy/mail/MailCore.luau` | `mail.mailbox` | Profile schema, inventory conversion and game limits. |
| `roblox/shared/services/MailService.luau` | `roblox/mail.configure` | Native identity decoding, recipient resolution, storage scope, profile/pointer projection and limits. The durable delivery coordinator can be removed. |
| `roblox/shared/services/MarketSettlement.luau` | `roblox/market-settlement.configure` | Configured wallet transitions, receipt projection and matching retention policy. The settlement coordinator can be removed. |
| `roblox/shared/services/MarketService.luau` | `roblox/market.configure` | Item facts/rarity, category and class matching policy, configured transitions, numeric bounds and native UI. The admission/search/projection coordinator can be removed. |
| `roblox/shared/services/MarketProfileWallet.luau` | `roblox/market-profile-wallet.configure` | Profile projections, catalog/tradeability policy, item rules and save authority. The paired-delta coordinator can be removed. |
| `roblox/shared/services/BankService.luau` | `roblox/bank.configure` | Configured vault rules, profile transaction commit, namespace, bounds and banker/item policy. The transfer admission coordinator can be removed. |
| `roblox/shared/services/SocialParty.luau` | `roblox/social-party.configure` | Configured TTL/loot/rally policy, grouping-domain and character lookup, party namespaces, labels and projection reporting. The invitation/projection coordinator can be removed. |
| `roblox/shared/services/SocialFellowship.luau` | `roblox/social-fellowship.configure` | Configured home/group policies, TTLs, refresh cadence, namespaces and labels. The guild membership/invitation/projection coordinator can be removed. |
| `roblox/shared/services/SocialFormation.luau` | `roblox/social-formation.configure` | Configured home/group policy, founder count, fee and native/profile ports. The multi-founder fee/charter coordinator can be removed. |
| `roblox/shared/services/GuildBankService.luau` | `roblox/guild-bank.configure` | Profile/ledger projection, capacity, configured rules, retention and material labels. The deposit/claim/recovery coordinator can be removed. |

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

## Durable trade cutover

Replace the coordinator in `roblox/shared/services/TradeService.luau` with
`src/roblox/trade.configure`. Keep its exported game types and `mount` binding. Supply the existing
`TradeCore`, `TradeReceipt`, `ProfileTransactionCommit` and profile ledger through the typed ports;
project gold, inventory and pending trade pointers through `account` and `withAccount`.
Preserve the current profile-copy policy, realm admission, unbound-item checks, numeric bounds,
receipt keys and transaction identifiers. Bind context lookup to the authoritative profile owner.
No saved-shape migration is required when these projections and namespaces remain unchanged.

All 15 existing Realms trade service cases were replayed against the extracted coordinator with
the original game policy, profiles and native mount. They cover durable hold/grant boundaries,
cross-server admission, uncertain receipt replies, malformed decisions, refunds, disconnect and
expiry. Keep those consumer cases and the hub/session checks during the actual pin cutover.
The neutral [library fixture](../src/roblox/trade.verify.luau) independently exercises the generic
ports. The remaining game service must retain its authentication, remote bus and lifecycle owner.

## Durable mail cutover

Replace `roblox/shared/services/MailService.luau` with a configured `src/roblox/mail` binding.
Retain `MailCore` policy and its account conversion, the exact transaction/envelope namespaces,
profile copy and pointer projections, native player decoding, recipient resolution and inbox scope.
Supply the existing profile transaction commit and update operations. Preserve session fencing
selection and current TTL/rate/pointer limits. Mail transport and hub projections remain game-owned.

All 12 existing Realms mail service cases pass through the extracted coordinator with the original
profile, mailbox and transaction policy. Neutral maintained fixtures cover uncertainty, replay,
interrupted delivery admission, character replacement and returns. Keep the consumer service,
transport, hub and profile-session cases for the actual repin cutover.

## Market settlement cutover

Bind `roblox/shared/services/MarketSettlement.luau` to `src/roblox/market-settlement.configure`
using the existing `MarketWalletCore`, `MarketBookCore.receiptsFor` and wallet heal retention.
Keep profile-wallet projection, book transport, catalog admission and UI in Realms. The original
19 consumer cases pass against this binding, including conservation, lost replies, durable void
fences, receipt batching, item room, delayed writes and aged recovery. Keep those cases on repin.

`MarketService.luau` can then bind `src/roblox/market.configure` with its existing item/category
policy and typed rarity. All 27 original market service cases pass through this adapter, including
catalog rules, paid-item permission, room admission, item search and merchant pricing. Keep those
cases and the consumer hub/profile integration checks during the actual cutover.

The profile wallet binds `src/roblox/market-profile-wallet` to existing inventory fit/unbound rules,
wallet codecs, game goods projection and profile copy/save operations. All 12 original profile-wallet
cases pass through this binding. Keep those cases with market settlement and profile-session checks.
`BankService.luau` binds `src/roblox/bank` to existing vault and profile transaction APIs. Its neutral
library fixture covers actor identity, distance, rate admission, receipt replay and uncertain saves;
retain the consumer bank-hub and vault checks during repin. Banker positions and item policy stay local.

## Social party cutover

Replace `SocialParty.luau` with a configured `roblox/social-party` binding using the existing party
and rally APIs, TTLs, loot policy, identity construction and labels. Update the single SocialService
metric reference from `partyDomain.__pendingInviteCount` to `partyDomain.pendingInviteCount` in the
same cutover. Keep the game's existing test/diagnostic surface and native subscriptions local.
All 85 original SocialService cases pass with the extracted party coordinator, including party
lifecycles, privacy admission, notices and native fake-host composition. Keep that consumer suite,
party core/host and module-import checks for the actual pin cutover.

The fellowship and formation bindings configure their existing home/group APIs, rule constants,
identifier prefixes and labels. All 85 original SocialService cases pass with all three extracted
coordinators together. Neutral maintained fixtures additionally use two founders, a seven-unit fee
and a different refresh interval. The formation host retains proposer pointers across uncertain fee
holds/refunds and failed charter responses; the consumer must preserve the fee port's explicit outcome.
Keep guild profile fees, durable transports, platform observations and native notifications in Realms.

The guild-bank binding supplies existing ledger transitions and inventory projections to
`roblox/guild-bank.configure`. All 14 consumer cases pass against the new host after making the
crowded-ledger fixture clone its frozen nested ledger before editing it. Keep that fixture repair
in the consumer cutover. Neutral cases additionally verify final-transform retry acceptance,
missing callbacks and missing bank state. Keep guild bank/ledger/transport and social integration
specifications on repin; namespaces, current role lookup and profile save authority stay in Realms.

Replace `WarbandSocial.luau` with `roblox/social-warband.configure`, supplying existing warband rules,
request bounds, location, identity construction and labels. All ten original warband-host cases pass
through the prepared binding. Keep those cases and the social/record suites during repin. Location
and objective catalogs, native notices and party loot remain game-owned; the library fixture uses
a different request lifetime and a neutral location to prove the policy seam.

`SocialNotes.luau` and `SocialWhispers.luau` become configured `roblox/social-notes` and
`roblox/social-whispers` bindings. Phrase content, label, throttle, expiry, namespace, display
fallback and native filtering/communication authority remain game-owned. All 85 original
SocialService cases pass with the party/fellowship/formation and messaging hosts together.
Whisper admission rechecks both subjects against the original realm after an asynchronous open;
a stale successful channel is disposed. Keep consumer social/platform/native fake-host tests at repin.

The `SocialService` authoritative party admission query uses `roblox/social-party.admission`.
Only the solo identifier namespace remains local. A failed membership read must remain distinguishable
from a known solo subject, and a current roster must contain its requesting subject.
