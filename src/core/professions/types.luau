--!strict
local Value = require("../internal/value")

export type Sustain = {
	read resource: "hp" | "mana" | "none",
	read verb: string,
	read durationSec: number,
	read fractionPerSec: number,
	read combat: boolean?,
	read buff: { slot: "food" | "elixir", durationSec: number, stats: { [string]: number } }?,
}
export type Reagent = { read itemId: string, read quantity: number }
export type QuestInput = { read questId: string, read objectiveId: string, read itemId: string, read quantity: number }
export type Thresholds = { read orange: number, read yellow: number, read green: number, read grey: number }
export type Source = "trainer" | "vendor" | "world_drop" | "boss_drop" | "frontier"

export type Descriptor = {
	read kind: "gear" | "consumable" | "material",
	read name: string,
	read lore: string,
	read rarity: string,
	read slot: string?,
	read armorFamily: string?,
	read weaponFamily: string?,
	read handTopology: string?,
	read levelReq: number,
	read ladderSource: string?,
	read stack: number?,
	read sustain: Sustain?,
}

export type Recipe = {
	read id: string,
	read realmId: string?,
	read profession: string,
	read slug: string,
	read name: string,
	read requiredSkill: number,
	read thresholds: Thresholds,
	read reagents: { Reagent },
	read output: Reagent,
	read source: Source,
	read rung: "pve" | "rvr",
	read station: string?,
	read recipeItemId: string?,
	read trainerCost: number?,
	read vendor: { price: number, stock: number }?,
	read dropBosses: { string }?,
	read dropChance: number?,
	read item: Descriptor,
	read questInputs: { QuestInput }?,
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
