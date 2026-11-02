--!strict

local Crafting = require("./professions/crafting")
local Fishing = require("./professions/fishing")
local Gathering = require("./professions/gathering")
local Harvest = require("./professions/harvest")
local Session = require("./professions/session")
local Skills = require("./professions/skills")
local Types = require("./professions/types")

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
	read session: typeof(Session),
	read skills: typeof(Skills),
	read types: typeof(Types),
}

local api: API = {
	crafting = Crafting,
	fishing = Fishing,
	gathering = Gathering,
	harvest = Harvest,
	session = Session,
	skills = Skills,
	types = Types,
}

return table.freeze(api)
