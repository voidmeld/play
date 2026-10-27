--!strict
local Value = require("../internal/value")

local Skills = require("./skills")
local Stacks = require("../inventory/stacks")
local Types = require("./types")

type State = Skills.State
type Recipe = Types.Recipe
type Inventory = { [string]: number }

export type Plan = {
	ok: boolean,
	reason: string?,
	recipe: Recipe?,
	color: string?,
}

export type Outcome = {
	ok: boolean,
	reason: string?,
	state: State,
	inventory: Inventory,
	skillUp: boolean,
	color: string?,
	skill: number,
	quality: string?,
	produced: { itemId: string, quantity: number }?,
}

export type Config = {
	core: {
		read knows: (State, string) -> boolean,
		read skillOf: (State, string) -> number,
		read colorFor: (number, Types.Thresholds) -> string?,
		read rollSkillUp: (State, string, Types.Thresholds, number) -> (State, boolean, string?),
	},
	maxStack: number,
	recipes: {
		get: (unknown) -> Recipe?,
		isGear: (Recipe) -> boolean,
		rollQuality: (string?, number?) -> string,
		qualityItemId: (string, string) -> string,
	},
}

local System = {}

function System.create(config: Config)
	local Core, Recipes = config.core, config.recipes
	local Inventory =
		Stacks.stacks({ maxStack = config.maxStack, baseCapacity = math.huge, permanentItems = {}, bagBonus = {} })
	local Crafting = {}

	Crafting.MAX_STACK = config.maxStack

	local function refuse(state: State, inventory: Inventory, reason: string?): Outcome
		return {
			ok = false,
			reason = reason,
			state = state,
			inventory = inventory,
			skillUp = false,
			color = nil,
			skill = 0,
			quality = nil,
			produced = nil,
		}
	end

	function Crafting.plan(state: State, recipeId: unknown, inventory: Inventory, stations: { [string]: boolean }): Plan
		local recipe = Recipes.get(recipeId)
		if recipe == nil then
			return { ok = false, reason = "unknown_recipe", recipe = nil, color = nil }
		end
		if not Core.knows(state, recipe.profession) then
			return { ok = false, reason = "profession_not_known", recipe = recipe, color = nil }
		end
		if state.recipes[recipe.id] ~= true then
			return { ok = false, reason = "recipe_not_known", recipe = recipe, color = nil }
		end
		local skill = Core.skillOf(state, recipe.profession)
		if skill < recipe.requiredSkill then
			return { ok = false, reason = "skill_too_low", recipe = recipe, color = nil }
		end
		if recipe.station ~= nil and stations[recipe.station] ~= true then
			return { ok = false, reason = "needs_" .. recipe.station, recipe = recipe, color = nil }
		end
		for _, reagent in recipe.reagents do
			if (inventory[reagent.itemId] or 0) < reagent.quantity then
				return { ok = false, reason = "missing_reagents", recipe = recipe, color = nil }
			end
		end
		local after = inventory[recipe.output.itemId] or 0
		for _, reagent in recipe.reagents do
			if reagent.itemId == recipe.output.itemId then
				after -= reagent.quantity
			end
		end
		if after + recipe.output.quantity > math.min(Crafting.MAX_STACK, recipe.item.stack or Crafting.MAX_STACK) then
			return { ok = false, reason = "inventory_full", recipe = recipe, color = nil }
		end
		return { ok = true, reason = nil, recipe = recipe, color = Core.colorFor(skill, recipe.thresholds) }
	end

	function Crafting.craft(
		state: State,
		recipeId: unknown,
		inventory: Inventory,
		stations: { [string]: boolean },
		roll: number,
		qualityRoll: number?,
		maxInventoryEntries: number?
	): Outcome
		local plan = Crafting.plan(state, recipeId, inventory, stations)
		if not plan.ok or plan.recipe == nil then
			return refuse(state, inventory, plan.reason)
		end
		local recipe = plan.recipe
		local nextInventory = table.clone(inventory)
		for _, reagent in recipe.reagents do
			local after, removed = Inventory.removeFromBag(nextInventory, reagent.itemId, reagent.quantity)
			if not removed then
				return refuse(state, inventory, "missing_reagents")
			end
			nextInventory = after
		end
		local skillColor = plan.color
		local quality = if Recipes.isGear(recipe) then Recipes.rollQuality(skillColor, qualityRoll) else "normal"
		local producedId = Recipes.qualityItemId(recipe.output.itemId, quality)
		if
			(nextInventory[producedId] or 0) + recipe.output.quantity
			> math.min(Crafting.MAX_STACK, recipe.item.stack or Crafting.MAX_STACK)
		then
			return refuse(state, inventory, "inventory_full")
		end
		nextInventory = Inventory.addToBag(nextInventory, producedId, recipe.output.quantity)
		if maxInventoryEntries ~= nil then
			local entries = 0
			for _ in nextInventory do
				entries += 1
			end
			if entries > maxInventoryEntries then
				return refuse(state, inventory, "inventory_full")
			end
		end
		local nextState, gained, color = Core.rollSkillUp(state, recipe.profession, recipe.thresholds, roll)
		return {
			ok = true,
			reason = nil,
			state = nextState,
			inventory = nextInventory,
			skillUp = gained,
			color = color,
			skill = Core.skillOf(nextState, recipe.profession),
			quality = quality,
			produced = { itemId = producedId, quantity = recipe.output.quantity },
		}
	end

	return Value.freezeDeep(Crafting)
end

return Value.freezeDeep(System)
