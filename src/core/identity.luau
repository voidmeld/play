--!strict

local Account = require("./identity/account")
local AccountLease = require("./identity/account-lease")
local Creation = require("./identity/creation")
local CreationRecord = require("./identity/creation-record")
local Deletion = require("./identity/deletion")
local NameClaims = require("./identity/name-claims")
local NameRecord = require("./identity/name-record")
local Policy = require("./identity/policy")
local Roster = require("./identity/roster")

export type AccountLeaseLease = AccountLease.Lease
export type AccountDeletionState = Account.DeletionState
export type AccountBase = Account.Base
export type AccountCreationReceipt = Account.CreationReceipt
export type AccountAccount<E> = Account.Account<E>
export type AccountExtension<E> = Account.Extension<E>
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
export type RosterCharacterIdentity = Roster.CharacterIdentity
export type RosterRoster = Roster.Roster

export type API = {
	read account_lease: typeof(AccountLease),
	read account: typeof(Account),
	read creation_record: typeof(CreationRecord),
	read creation: typeof(Creation),
	read deletion: typeof(Deletion),
	read name_claims: typeof(NameClaims),
	read name_record: typeof(NameRecord),
	read policy: typeof(Policy),
	read roster: typeof(Roster),
}

local api: API = {
	account_lease = AccountLease,
	account = Account,
	creation_record = CreationRecord,
	creation = Creation,
	deletion = Deletion,
	name_claims = NameClaims,
	name_record = NameRecord,
	policy = Policy,
	roster = Roster,
}

return table.freeze(api)
