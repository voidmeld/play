--!strict

local Actionbar = require("./progression/actionbar")
local Consumables = require("./progression/consumables")
local FingerprintedTransactions = require("./progression/fingerprinted-transactions")
local Grants = require("./progression/grants")
local Hearth = require("./progression/hearth")
local Levels = require("./progression/levels")
local Recovery = require("./progression/recovery")
local Reputation = require("./progression/reputation")
local Season = require("./progression/season")
local Settlement = require("./progression/settlement")
local StandingCredit = require("./progression/standing-credit")
local TalentRanks = require("./progression/talent-ranks")
local Talents = require("./progression/talents")
local Tracking = require("./progression/tracking")
local Transactions = require("./progression/transactions")

export type ActionbarState = Actionbar.State
export type ActionbarContext = Actionbar.Context
export type ActionbarLayout = Actionbar.Layout
export type ActionbarIntent = Actionbar.Intent
export type ActionbarConfig = Actionbar.Config
export type ConsumablesBuff = Consumables.Buff
export type ConsumablesItem = Consumables.Item
export type ConsumablesChannel = Consumables.Channel
export type ConsumablesActiveBuff = Consumables.ActiveBuff
export type ConsumablesState = Consumables.State
export type ConsumablesActor = Consumables.Actor
export type ConsumablesActorView = Consumables.ActorView
export type ConsumablesMob = Consumables.Mob
export type ConsumablesConfig = Consumables.Config
export type GrantsGrant = Grants.Grant
export type GrantsGrantIndex = Grants.GrantIndex
export type GrantsProductionRegistry = Grants.ProductionRegistry
export type GrantsProductionRegistryResult = Grants.ProductionRegistryResult
export type GrantsConfig = Grants.Config
export type FingerprintedTransactionsBounds = FingerprintedTransactions.Bounds
export type FingerprintedTransactionsReceipts = FingerprintedTransactions.Receipts
export type FingerprintedTransactionsResult<T> = FingerprintedTransactions.Result<T>
export type FingerprintedTransactionsConfig<T> = FingerprintedTransactions.Config<T>
export type HearthDestination = Hearth.Destination
export type HearthBind = Hearth.Bind
export type HearthState = Hearth.State
export type HearthBoundState = Hearth.BoundState
export type HearthConfig = Hearth.Config
export type LevelsCurveRow = Levels.CurveRow
export type LevelsCurve = Levels.Curve
export type LevelsConfig = Levels.Config
export type LevelsProgression = Levels.Progression
export type LevelsSnapshot = Levels.Snapshot
export type LevelsRewardProjection = Levels.RewardProjection
export type RecoveryPoint = Recovery.Point
export type RecoveryCost = Recovery.Cost
export type RecoveryDeath = Recovery.Death
export type RecoveryPosition<Travel> = Recovery.Position<Travel>
export type RecoveryAnchoredPosition = Recovery.AnchoredPosition
export type RecoveryConfig = Recovery.Config
export type ReputationEventKind = Reputation.EventKind
export type ReputationEvent = Reputation.Event
export type ReputationState = Reputation.State
export type ReputationApplyResult = Reputation.ApplyResult
export type ReputationLadder = Reputation.Ladder
export type ReputationStanding = Reputation.Standing
export type ReputationConfig = Reputation.Config
export type SeasonEvent = Season.Event
export type SeasonState = Season.State
export type SeasonResult = Season.Result
export type SeasonPlaySource = Season.PlaySource
export type SeasonObjective = Season.Objective
export type SeasonReward = Season.Reward
export type SeasonAuthoredDefinition = Season.AuthoredDefinition
export type SeasonDefinition = Season.Definition
export type SeasonProjectionObjective = Season.ProjectionObjective
export type SeasonProjection = Season.Projection
export type SeasonConfig = Season.Config
export type SettlementRewardReceipt<Q> = Settlement.RewardReceipt<Q>
export type SettlementRewardHistory<Q> = Settlement.RewardHistory<Q>
export type SettlementRewardRequest = Settlement.RewardRequest
export type SettlementRewardGrant<Q> = Settlement.RewardGrant<Q>
export type SettlementRewardApplied<S, Q> = Settlement.RewardApplied<S, Q>
export type SettlementRewardRejected<S, Q> = Settlement.RewardRejected<S, Q>
export type SettlementRewardResult<S, Q> = Settlement.RewardResult<S, Q>
export type SettlementGrantResult<S> = Settlement.GrantResult<S>
export type SettlementConfig<P, S, C, Q> = Settlement.Config<P, S, C, Q>
export type StandingCreditOutcome = StandingCredit.Outcome
export type StandingCreditConfig = StandingCredit.Config
export type TalentRanksLoadout = TalentRanks.Loadout
export type TalentRanksResult = TalentRanks.Result
export type TalentRanksNode = TalentRanks.Node
export type TalentRanksTier = TalentRanks.Tier
export type TalentRanksLine = TalentRanks.Line
export type TalentRanksSpec = TalentRanks.Spec
export type TalentRanksBucket = TalentRanks.Bucket
export type TalentsState = Talents.State
export type TalentsLoadout = Talents.Loadout
export type TalentsIntent = Talents.Intent
export type TalentsResult = Talents.Result
export type TrackingConfig = Tracking.Config
export type TransactionsCollectionSet = Transactions.CollectionSet
export type TransactionsOutcome = Transactions.Outcome
export type TransactionsResult<T> = Transactions.Result<T>
export type TransactionsConfig<T> = Transactions.Config<T>

export type API = {
	read actionbar: typeof(Actionbar),
	read consumables: typeof(Consumables),
	read grants: typeof(Grants),
	read fingerprinted_transactions: typeof(FingerprintedTransactions),
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

local api: API = {
	actionbar = Actionbar,
	consumables = Consumables,
	grants = Grants,
	fingerprinted_transactions = FingerprintedTransactions,
	hearth = Hearth,
	levels = Levels,
	recovery = Recovery,
	reputation = Reputation,
	season = Season,
	settlement = Settlement,
	standing_credit = StandingCredit,
	talent_ranks = TalentRanks,
	talents = Talents,
	tracking = Tracking,
	transactions = Transactions,
}

return table.freeze(api)
