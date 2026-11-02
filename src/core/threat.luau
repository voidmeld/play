--!strict

local Contribution = require("./threat/contribution")
local Table = require("./threat/table")

export type ContributionPoint = Contribution.Point
export type ContributionDungeonAdmission = Contribution.DungeonAdmission
export type ContributionRelation = Contribution.Relation
export type ContributionObservation = Contribution.Observation
export type ContributionCredit = Contribution.Credit
export type ContributionActorContribution = Contribution.ActorContribution
export type ContributionEndActor = Contribution.EndActor
export type ContributionEncounter = Contribution.Encounter
export type ContributionParticipant = Contribution.Participant
export type ContributionConfig = Contribution.Config
export type TableConfig = Table.Config
export type TableState = Table.State
export type TableCandidate = Table.Candidate
export type TablePruned = Table.Pruned

export type API = {
	read contribution: typeof(Contribution),
	read table: typeof(Table),
}

local api: API = {
	contribution = Contribution,
	table = Table,
}

return table.freeze(api)
