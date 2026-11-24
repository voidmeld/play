--!strict

local Allies = require("./social/allies")
local Chronicle = require("./social/chronicle")
local Fellowship = require("./social/fellowship")
local Formation = require("./social/formation")
local Group = require("./social/group")
local Guildbank = require("./social/guildbank")
local Guildhome = require("./social/guildhome")
local Guildledger = require("./social/guildledger")
local Membership = require("./social/membership")
local Notes = require("./social/notes")
local Profile = require("./social/profile")
local Rally = require("./social/rally")
local Roster = require("./social/roster")
local Warband = require("./social/warband")

export type AlliesQualificationKind = Allies.QualificationKind
export type AlliesEntry = Allies.Entry
export type AlliesState = Allies.State
export type AlliesPolicy = Allies.Policy
export type AlliesResult = Allies.Result
export type AlliesQualifyEvent = Allies.QualifyEvent
export type AlliesReconcileEvent = Allies.ReconcileEvent
export type AlliesEvent = Allies.Event
export type AlliesAuthority = Allies.Authority
export type AlliesConfig = Allies.Config
export type ChronicleActiveStatus = Chronicle.ActiveStatus
export type ChronicleTerminalStatus = Chronicle.TerminalStatus
export type ChronicleDefinition = Chronicle.Definition
export type ChronicleActiveVow = Chronicle.ActiveVow
export type ChronicleDeed = Chronicle.Deed
export type ChronicleState = Chronicle.State
export type ChronicleApplied = Chronicle.Applied
export type ChronicleRejected = Chronicle.Rejected
export type ChronicleResult = Chronicle.Result
export type ChronicleAccessPolicy = Chronicle.AccessPolicy
export type ChronicleContributionAuthority = Chronicle.ContributionAuthority
export type ChronicleEvent = Chronicle.Event
export type ChronicleConfig = Chronicle.Config
export type FellowshipMember = Fellowship.Member
export type FellowshipInvite = Fellowship.Invite
export type FellowshipCreed = Fellowship.Creed
export type FellowshipCreedDraft = Fellowship.CreedDraft
export type FellowshipFormationRequest = Fellowship.FormationRequest
export type FellowshipEvent = Fellowship.Event
export type FellowshipEventDraft = Fellowship.EventDraft
export type FellowshipAudit = Fellowship.Audit
export type FellowshipState = Fellowship.State
export type FellowshipFoundRequest = Fellowship.FoundRequest
export type FellowshipResult = Fellowship.Result
export type FellowshipConfig = Fellowship.Config
export type FormationFounder = Formation.Founder
export type FormationState = Formation.State
export type FormationEventDraft = Formation.EventDraft
export type FormationEvent = Formation.Event
export type FormationStartRequest = Formation.StartRequest
export type FormationResult = Formation.Result
export type FormationConfig = Formation.Config
export type GroupRelations = Group.Relations
export type GroupAdmission = Group.Admission
export type GroupTicket = Group.Ticket
export type GroupState = Group.State
export type GroupResult = Group.Result
export type GroupDecision = Group.Decision
export type GroupRequest = Group.Request
export type GroupAuthority = Group.Authority
export type GroupMemberEvent = Group.MemberEvent
export type GroupReconcileEvent = Group.ReconcileEvent
export type GroupEvent = Group.Event
export type GroupConfig = Group.Config
export type GuildbankReceipt = Guildbank.Receipt
export type GuildbankOperation = Guildbank.Operation
export type GuildbankEntry = Guildbank.Entry
export type GuildbankWithdrawal = Guildbank.Withdrawal
export type GuildbankCommand = Guildbank.Command
export type GuildbankState = Guildbank.State
export type GuildbankResult = Guildbank.Result
export type GuildbankConfig = Guildbank.Config
export type GuildhomeSlot = Guildhome.Slot
export type GuildhomeConfig = Guildhome.Config
export type GuildledgerPending = Guildledger.Pending
export type GuildledgerLedger = Guildledger.Ledger
export type GuildledgerLimits = Guildledger.Limits
export type GuildledgerReceipt = Guildledger.Receipt
export type GuildledgerProfileInput = Guildledger.ProfileInput
export type GuildledgerConfig<T> = Guildledger.Config<T>
export type MembershipLootMode = Membership.LootMode
export type MembershipMember = Membership.Member
export type MembershipInvite = Membership.Invite
export type MembershipLeaderTransfer = Membership.LeaderTransfer
export type MembershipState = Membership.State
export type MembershipResult = Membership.Result
export type MembershipConfig = Membership.Config
export type MembershipCore = Membership.Core
export type NotesNote = Notes.Note
export type NotesState = Notes.State
export type NotesResult = Notes.Result
export type NotesPhrase = Notes.Phrase
export type NotesCatalog = Notes.Catalog
export type NotesDelivery = Notes.Delivery
export type NotesConfig = Notes.Config
export type ProfileFellowshipIdentity = Profile.FellowshipIdentity
export type ProfileState = Profile.State
export type ProfileConfig = Profile.Config
export type RallyRow = Rally.Row
export type RallyConfig = Rally.Config
export type RosterMember = Roster.Member
export type RosterParty = Roster.Party
export type RosterActor = Roster.Actor
export type RosterRuntime<S> = Roster.Runtime<S>
export type RosterResult<S, A> = Roster.Result<S, A>
export type RosterConfig<S, A> = Roster.Config<S, A>
export type WarbandParty = Warband.Party
export type WarbandUnit = Warband.Unit
export type WarbandInvite = Warband.Invite
export type WarbandTransfer = Warband.Transfer
export type WarbandOrder = Warband.Order
export type WarbandState = Warband.State
export type WarbandEvent = Warband.Event
export type WarbandParties = Warband.Parties
export type WarbandResult = Warband.Result
export type WarbandConfig = Warband.Config

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

local api: API = {
	allies = Allies,
	chronicle = Chronicle,
	fellowship = Fellowship,
	formation = Formation,
	group = Group,
	guildbank = Guildbank,
	guildhome = Guildhome,
	guildledger = Guildledger,
	membership = Membership,
	notes = Notes,
	profile = Profile,
	rally = Rally,
	roster = Roster,
	warband = Warband,
}

return table.freeze(api)
