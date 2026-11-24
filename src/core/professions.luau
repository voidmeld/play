--!strict

local Crafting = require("./professions/crafting")
local Fishing = require("./professions/fishing")
local Gathering = require("./professions/gathering")
local Harvest = require("./professions/harvest")
local Milestones = require("./professions/milestones")
local Progression = require("./professions/progression")
local Session = require("./professions/session")
local Skills = require("./professions/skills")
local Tokens = require("./professions/tokens")
local Types = require("./professions/types")
local WorkOrders = require("./orders/work")

export type CraftingPlan = Crafting.Plan
export type CraftingOutcome = Crafting.Outcome
export type CraftingConfig = Crafting.Config
export type FishingPhase = Fishing.Phase
export type FishingLine = Fishing.Line
export type FishingCatch = Fishing.Catch
export type FishingConfig = Fishing.Config
export type GatheringRealmId = Gathering.RealmId
export type GatheringSpaceKind = Gathering.SpaceKind
export type GatheringPhase = Gathering.Phase
export type GatheringNode = Gathering.Node
export type GatheringState = Gathering.State
export type GatheringCommandKind = Gathering.CommandKind
export type GatheringCommand = Gathering.Command
export type GatheringResult = Gathering.Result
export type HarvestYield = Harvest.Yield
export type HarvestOutcome = Harvest.Outcome
export type HarvestConfig = Harvest.Config
export type MilestonesReceipt = Milestones.Receipt
export type MilestonesDefinition = Milestones.Definition
export type MilestonesConfig = Milestones.Config
export type MilestonesState = Milestones.State
export type ProgressionTokens = Progression.Tokens
export type ProgressionWorkOrder = Progression.WorkOrder
export type ProgressionState = Progression.State
export type ProgressionConfig = Progression.Config
export type TokensTokens = Tokens.Tokens
export type TokensConfig = Tokens.Config
export type WorkOrdersPhase = WorkOrders.Phase
export type WorkOrdersWorkOrderStep = WorkOrders.WorkOrderStep
export type WorkOrdersWorkOrder = WorkOrders.WorkOrder
export type WorkOrdersState = WorkOrders.State
export type WorkOrdersCommandKind = WorkOrders.CommandKind
export type WorkOrdersCommand = WorkOrders.Command
export type WorkOrdersResult = WorkOrders.Result
export type SessionKind = Session.Kind
export type SessionSession = Session.Session
export type SessionSample = Session.Sample
export type SkillsKind = Skills.Kind
export type SkillsProfession = Skills.Profession
export type SkillsState = Skills.State
export type SkillsColor = Skills.Color
export type SkillsConfig = Skills.Config
export type TypesSustain = Types.Sustain
export type TypesReagent = Types.Reagent
export type TypesQuestInput = Types.QuestInput
export type TypesThresholds = Types.Thresholds
export type TypesSource = Types.Source
export type TypesDescriptor = Types.Descriptor
export type TypesRecipe = Types.Recipe
export type TypesExtra = Types.Extra
export type TypesNodeKind = Types.NodeKind
export type TypesSkinRow = Types.SkinRow
export type TypesFishRow = Types.FishRow

export type API = {
	read crafting: typeof(Crafting),
	read fishing: typeof(Fishing),
	read gathering: typeof(Gathering),
	read harvest: typeof(Harvest),
	read milestones: typeof(Milestones),
	read progression: typeof(Progression),
	read session: typeof(Session),
	read skills: typeof(Skills),
	read tokens: typeof(Tokens),
	read types: typeof(Types),
	read workOrders: typeof(WorkOrders),
}

local api: API = {
	crafting = Crafting,
	fishing = Fishing,
	gathering = Gathering,
	harvest = Harvest,
	milestones = Milestones,
	progression = Progression,
	session = Session,
	skills = Skills,
	tokens = Tokens,
	types = Types,
	workOrders = WorkOrders,
}

return table.freeze(api)
