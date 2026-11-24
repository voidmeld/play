--!strict

local Account = require("./identity/account")
local AccountLease = require("./identity/account-lease")
local CharacterLease = require("./identity/character-lease")
local CharacterLeaseStore = require("./identity/character-lease-store")
local Creation = require("./identity/creation")
local CreationRecord = require("./identity/creation-record")
local Deletion = require("./identity/deletion")
local NameClaims = require("./identity/name-claims")
local NameRecord = require("./identity/name-record")
local Policy = require("./identity/policy")
local Retirement = require("./identity/retirement")
local Roster = require("./identity/roster")
local Routing = require("./identity/routing")

export type AccountLeaseLease = AccountLease.Lease
export type AccountDeletionState = Account.DeletionState
export type AccountBase = Account.Base
export type AccountCreationReceipt = Account.CreationReceipt
export type AccountAccount<E> = Account.Account<E>
export type AccountExtension<E> = Account.Extension<E>
export type CharacterLeaseStoreStoreOutcome = CharacterLeaseStore.StoreOutcome
export type CharacterLeaseStoreStore = CharacterLeaseStore.Store
export type CharacterLeaseStoreAccepted = CharacterLeaseStore.Accepted
export type CharacterLeaseStoreRefused = CharacterLeaseStore.Refused
export type CharacterLeaseStoreOutcome = CharacterLeaseStore.Outcome
export type CharacterLeaseStoreConfig = CharacterLeaseStore.Config
export type CharacterLeaseStoreAPI = CharacterLeaseStore.API
export type CharacterLeaseRecord = CharacterLease.Record
export type CharacterLeaseRetirement = CharacterLease.Retirement
export type CharacterLeaseArrival = CharacterLease.Arrival
export type CharacterLeaseCharacterLeaseRecord = CharacterLease.CharacterLeaseRecord
export type CharacterLeaseWitness = CharacterLease.Witness
export type CharacterLeaseClaim = CharacterLease.Claim
export type CharacterLeaseConfig = CharacterLease.Config
export type CharacterLeaseAPI = CharacterLease.API
export type CreationRecordSeed = CreationRecord.Seed
export type CreationRecordReceipt = CreationRecord.Receipt
export type CreationCompletion = Creation.Completion
export type CreationReceipt = Creation.Receipt
export type CreationPhase = Creation.Phase
export type CreationState = Creation.State
export type CreationPrepared = Creation.Prepared
export type CreationRejected = Creation.Rejected
export type CreationAccepted = Creation.Accepted
export type CreationResult = Creation.Result
export type CreationPlan = Creation.Plan
export type DeletionPhase = Deletion.Phase
export type DeletionState = Deletion.State
export type DeletionPrepared = Deletion.Prepared
export type DeletionRejected = Deletion.Rejected
export type DeletionAccepted = Deletion.Accepted
export type DeletionResult = Deletion.Result
export type DeletionPlan = Deletion.Plan
export type NameClaimsClaim = NameClaims.Claim
export type NameClaimsClaimStatus = NameClaims.ClaimStatus
export type NameClaimsReleaseStatus = NameClaims.ReleaseStatus
export type NameClaimsAvailability = NameClaims.Availability
export type NameRecordRecord = NameRecord.Record
export type NameRecordClaim = NameRecord.Claim
export type PolicyPolicy = Policy.Policy
export type RetirementDeletion = Retirement.Deletion
export type RetirementRetirement = Retirement.Retirement
export type RetirementView = Retirement.View
export type RetirementDecision = Retirement.Decision
export type RetirementConfig = Retirement.Config
export type RetirementAPI = Retirement.API
export type RosterCharacterIdentity = Roster.CharacterIdentity
export type RosterRoster = Roster.Roster
export type RoutingDestinationProjection = Routing.DestinationProjection
export type RoutingPlaceBinding = Routing.PlaceBinding
export type RoutingBinding = Routing.Binding
export type RoutingBudget = Routing.Budget
export type RoutingRefusalRow = Routing.RefusalRow
export type RoutingHandoff = Routing.Handoff
export type RoutingPolicy = Routing.Policy
export type RoutingSession = Routing.Session
export type RoutingCharacter = Routing.Character
export type RoutingRequest = Routing.Request
export type RoutingRoute = Routing.Route
export type RoutingRefusal = Routing.Refusal
export type RoutingDecision = Routing.Decision
export type RoutingArrival = Routing.Arrival
export type RoutingConfig = Routing.Config
export type RoutingAPI = Routing.API

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

local api: API = {
	account_lease = AccountLease,
	account = Account,
	character_lease_store = CharacterLeaseStore,
	character_lease = CharacterLease,
	creation_record = CreationRecord,
	creation = Creation,
	deletion = Deletion,
	name_claims = NameClaims,
	name_record = NameRecord,
	policy = Policy,
	retirement = Retirement,
	roster = Roster,
	routing = Routing,
}

return table.freeze(api)
