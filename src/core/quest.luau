--!strict

local Claims = require("./quest/claims")
local Counter = require("./quest/counter")
local Index = require("./quest/index")
local Journal = require("./quest/journal")
local Lifecycle = require("./quest/lifecycle")
local Markers = require("./quest/markers")
local Objectives = require("./quest/objectives")
local Progress = require("./quest/progress")
local Run = require("./quest/run")

export type ClaimsInvitation = Claims.Invitation
export type ClaimsReplacementIdentity = Claims.ReplacementIdentity
export type ClaimsMember = Claims.Member
export type ClaimsRecord = Claims.Record
export type ClaimsTarget = Claims.Target
export type ClaimsTransform = Claims.Transform
export type ClaimsConfig = Claims.Config
export type CounterBand = Counter.Band
export type CounterCounts = Counter.Counts
export type CounterConfig = Counter.Config
export type IndexConfig = Index.Config
export type IndexTargetBinding = Index.TargetBinding
export type JournalQuestProgress = Journal.QuestProgress
export type JournalRecord = Journal.Record
export type JournalConfig = Journal.Config
export type JournalAPI = Journal.API
export type LifecycleObjective = Lifecycle.Objective
export type LifecycleBinding = Lifecycle.Binding
export type LifecycleEvent = Lifecycle.Event
export type LifecycleQuest = Lifecycle.Quest
export type LifecycleProblem = Lifecycle.Problem
export type LifecycleConfig = Lifecycle.Config
export type MarkersQuestStatus = Markers.QuestStatus
export type MarkersMarkerState = Markers.MarkerState
export type MarkersQuestEntry = Markers.QuestEntry
export type MarkersConfig = Markers.Config
export type ObjectivesTargets = Objectives.Targets
export type ObjectivesKindSpec = Objectives.KindSpec
export type ObjectivesObjective = Objectives.Objective
export type ObjectivesQuest = Objectives.Quest
export type ObjectivesEvent = Objectives.Event
export type ObjectivesBinding = Objectives.Binding
export type ObjectivesProblem = Objectives.Problem
export type ObjectivesEventContract = Objectives.EventContract
export type ObjectivesAliases = Objectives.Aliases
export type ObjectivesConfig = Objectives.Config
export type ObjectivesCatalog = Objectives.Catalog
export type ProgressQuestProgress = Progress.QuestProgress
export type ProgressRule = Progress.Rule
export type ProgressBranch = Progress.Branch
export type ProgressStatuses = Progress.Statuses
export type ProgressObjectiveView = Progress.ObjectiveView
export type ProgressQuestView<O> = Progress.QuestView<O>
export type ProgressActorView = Progress.ActorView
export type ProgressContentView<Q> = Progress.ContentView<Q>
export type ProgressConfig<C, A, Q, O> = Progress.Config<C, A, Q, O>
export type ProgressAPI<C, A, Q, O> = Progress.API<C, A, Q, O>
export type RunPackage = Run.Package
export type RunRunStatus = Run.RunStatus
export type RunMember = Run.Member
export type RunRunState = Run.RunState
export type RunStartEvent = Run.StartEvent
export type RunCompletePhaseEvent = Run.CompletePhaseEvent
export type RunMemberEvent = Run.MemberEvent
export type RunWipeEvent = Run.WipeEvent
export type RunEvent = Run.Event
export type RunRecovery = Run.Recovery
export type RunTransitionApplied = Run.TransitionApplied
export type RunTransitionRejected = Run.TransitionRejected
export type RunTransitionResult = Run.TransitionResult
export type RunCore = Run.Core
export type RunConfig<P> = Run.Config<P>

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

local api: API = {
	claims = Claims,
	counter = Counter,
	index = Index,
	journal = Journal,
	lifecycle = Lifecycle,
	markers = Markers,
	objectives = Objectives,
	progress = Progress,
	run = Run,
}

return table.freeze(api)
