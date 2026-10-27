--!strict
local Value = require("../internal/value")

export type Sustain = {
	resource: "hp" | "mana" | "none",
	verb: string,
	durationSec: number,
	fractionPerSec: number,
	combat: boolean?,
	buff: { slot: "food" | "elixir", durationSec: number, stats: { [string]: number } }?,
}
export type Reagent = { itemId: string, quantity: number }
export type QuestInput = { questId: string, objectiveId: string, itemId: string, quantity: number }
export type Thresholds = { orange: number, yellow: number, green: number, grey: number }
export type Source = "trainer" | "vendor" | "world_drop" | "boss_drop" | "frontier"

export type Descriptor = {
	kind: "gear" | "consumable" | "material",
	name: string,
	lore: string,
	rarity: string,
	slot: string?,
	armorFamily: string?,
	weaponFamily: string?,
	handTopology: string?,
	levelReq: number,
	ladderSource: string?,
	stack: number?,
	sustain: Sustain?,
}

export type Recipe = {
	id: string,
	realmId: string?,
	profession: string,
	slug: string,
	name: string,
	requiredSkill: number,
	thresholds: Thresholds,
	reagents: { Reagent },
	output: Reagent,
	source: Source,
	rung: "pve" | "rvr",
	station: string?,
	recipeItemId: string?,
	trainerCost: number?,
	vendor: { price: number, stock: number }?,
	dropBosses: { string }?,
	dropChance: number?,
	item: Descriptor,
	questInputs: { QuestInput }?,
}

export type Extra = { itemId: string, chance: number, quantity: number }

export type NodeKind = {
	id: string,
	profession: string,
	name: string,
	itemId: string,
	requiredSkill: number,
	thresholds: Thresholds,
	minYield: number,
	maxYield: number,
	gatherSec: number,
	respawnSec: number,
	extras: { Extra },
}

export type SkinRow = {
	mobId: string,
	itemId: string,
	requiredSkill: number,
	thresholds: Thresholds,
	minYield: number,
	maxYield: number,
	skinSec: number,
	extras: { Extra },
}

export type FishRow = {
	itemId: string,
	weight: number,
	requiredSkill: number,
	thresholds: Thresholds,
}

return Value.freezeDeep({})
