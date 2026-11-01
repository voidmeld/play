--!strict
local Value = require("../internal/value")

local RecipesTypes = require("./types")

export type Kind = "gathering" | "primary_craft" | "secondary"

export type Profession = {
	id: string,
	name: string,
	kind: Kind,
	primary: boolean,
	order: number,
}

export type State = {
	skills: { [string]: number },
	recipes: { [string]: boolean },
	questInputs: { [string]: boolean }?,
}

export type Color = "orange" | "yellow" | "green" | "grey"
type Thresholds = RecipesTypes.Thresholds
type Recipe = RecipesTypes.Recipe
type Raw = { [unknown]: unknown }

export type Config = {
	catalogue: { Profession },
	skillCap: number,
	primarySlots: number,
	startSkill: number,
	skillUpChance: { [string]: number },
	questInputs: (unknown) -> { [string]: boolean }?,
	recipes: {
		read get: (unknown) -> Recipe?,
		read forProfession: (string) -> { read [number]: Recipe },
		read forRecipeItem: (unknown) -> Recipe?,
	},
}

local Skills = {}

function Skills.create(config: Config)
	local SKILL_CAP, PRIMARY_SLOTS, START_SKILL = config.skillCap, config.primarySlots, config.startSkill
	local CATALOGUE, SKILL_UP_CHANCE, Recipes = config.catalogue, config.skillUpChance, config.recipes
	local byId: { [string]: Profession } = {}
	for _, row in CATALOGUE do
		byId[row.id] = row
	end
	local COLORS: { [string]: Color } = { orange = "orange", yellow = "yellow", green = "green", grey = "grey" }

	local Core = {}

	Core.SKILL_CAP = SKILL_CAP
	Core.PRIMARY_SLOTS = PRIMARY_SLOTS
	Core.START_SKILL = START_SKILL
	Core.SKILL_UP_CHANCE = Value.freezeDeep(SKILL_UP_CHANCE)
	Core.catalogue = Value.freezeDeep(CATALOGUE)
	Core.byId = Value.freezeDeep(byId)

	function Core.profession(id: unknown): Profession?
		return if type(id) == "string" then byId[id] else nil
	end

	function Core.default(): State
		return { skills = {}, recipes = {} }
	end

	local function whole(value: unknown, low: number, high: number): boolean
		return type(value) == "number"
			and value == value
			and value >= low
			and value <= high
			and value == math.floor(value)
	end

	function Core.normalize(raw: unknown): State
		local out = Core.default()
		local fields = Value.raw(raw)
		if fields == nil then
			return out
		end
		local rawSkills = Value.raw(fields.skills)
		if type(rawSkills) == "table" then
			local primaries = 0
			for _, row in CATALOGUE do
				local value = (rawSkills)[row.id]
				if
					(type(value) == "number" and whole(value, START_SKILL, SKILL_CAP))
					and (not row.primary or primaries < PRIMARY_SLOTS)
				then
					out.skills[row.id] = value
					if row.primary then
						primaries += 1
					end
				end
			end
		end
		local rawRecipes = Value.raw(fields.recipes)
		if type(rawRecipes) == "table" then
			for recipeId, flag in rawRecipes do
				local recipe = Recipes.get(recipeId)
				if
					type(recipeId) == "string"
					and flag == true
					and recipe ~= nil
					and out.skills[recipe.profession] ~= nil
				then
					out.recipes[assert(Recipes.get(recipeId)).id] = true
				end
			end
		end
		out.questInputs = config.questInputs(raw)
		return out
	end

	function Core.copy(state: State): State
		return {
			skills = table.clone(state.skills),
			recipes = table.clone(state.recipes),
			questInputs = if state.questInputs ~= nil then table.clone(state.questInputs) else nil,
		}
	end

	function Core.knows(state: State, professionId: string): boolean
		return state.skills[professionId] ~= nil
	end

	function Core.skillOf(state: State, professionId: string): number
		return state.skills[professionId] or 0
	end

	function Core.primaryCount(state: State): number
		local count = 0
		for professionId in state.skills do
			local row = byId[professionId]
			if row ~= nil and row.primary then
				count += 1
			end
		end
		return count
	end

	function Core.primarySlotsFree(state: State): number
		return PRIMARY_SLOTS - Core.primaryCount(state)
	end

	function Core.canLearn(state: State, professionId: unknown): (boolean, string?)
		local row = Core.profession(professionId)
		if row == nil then
			return false, "unknown_profession"
		end
		if state.skills[row.id] ~= nil then
			return false, "already_known"
		end
		if row.primary and Core.primaryCount(state) >= PRIMARY_SLOTS then
			return false, "primary_slots_full"
		end
		return true, nil
	end

	function Core.learn(state: State, professionId: unknown): (State?, string?)
		local ok, reason = Core.canLearn(state, professionId)
		if not ok then
			return nil, reason
		end
		local out = Core.copy(state)
		out.skills[assert(Core.profession(professionId)).id] = START_SKILL
		return out, nil
	end

	function Core.unlearn(state: State, professionId: unknown): (State?, string?)
		local row = Core.profession(professionId)
		if row == nil then
			return nil, "unknown_profession"
		end
		if state.skills[row.id] == nil then
			return nil, "not_known"
		end
		if not row.primary then
			return nil, "secondary_cannot_unlearn"
		end
		local out = Core.copy(state)
		out.skills[row.id] = nil
		for recipeId in state.recipes do
			local recipe = Recipes.get(recipeId)
			if recipe == nil or recipe.profession == row.id then
				out.recipes[recipeId] = nil
			end
		end
		return out, nil
	end

	local function colorFor(skill: number, thresholds: Thresholds): Color?
		if skill < thresholds.orange then
			return nil
		elseif skill < thresholds.yellow then
			return COLORS.orange
		elseif skill < thresholds.green then
			return COLORS.yellow
		elseif skill < thresholds.grey then
			return COLORS.green
		end
		return COLORS.grey
	end

	Core.colorFor = colorFor

	function Core.skillUpChance(color: Color?): number
		return if color ~= nil then SKILL_UP_CHANCE[color] or 0 else 0
	end

	function Core.rollSkillUp(
		state: State,
		professionId: string,
		thresholds: Thresholds,
		roll: number
	): (State, boolean, Color?)
		local skill = state.skills[professionId]
		if skill == nil then
			return state, false, nil
		end
		local color: Color? = colorFor(skill, thresholds)
		if color == nil or skill >= SKILL_CAP then
			return state, false, color
		end
		if type(roll) ~= "number" or roll ~= roll or roll < 0 or roll >= Core.skillUpChance(color) then
			return state, false, color
		end
		local out = Core.copy(state)
		out.skills[professionId] = skill + 1
		return out, true, color
	end

	function Core.knownRecipes(state: State, professionId: string): { Recipe }
		local out = {}
		for _, recipe in Recipes.forProfession(professionId) do
			if state.recipes[recipe.id] == true then
				table.insert(out, recipe)
			end
		end
		return out
	end

	function Core.canLearnRecipe(state: State, recipeId: unknown, via: "trainer" | "item"): (boolean, string?)
		local recipe = Recipes.get(recipeId)
		if recipe == nil then
			return false, "unknown_recipe"
		end
		if state.skills[recipe.profession] == nil then
			return false, "profession_not_known"
		end
		if state.recipes[recipe.id] == true then
			return false, "already_known"
		end
		if via == "trainer" and recipe.trainerCost == nil then
			return false, "not_taught_by_trainer"
		end
		if via == "item" and recipe.source == "trainer" then
			return false, "no_recipe_item"
		end
		if state.skills[recipe.profession] < recipe.requiredSkill then
			return false, "skill_too_low"
		end
		return true, nil
	end

	function Core.learnRecipe(state: State, recipeId: unknown, via: "trainer" | "item"): (State?, string?)
		local ok, reason = Core.canLearnRecipe(state, recipeId, via)
		if not ok then
			return nil, reason
		end
		local out = Core.copy(state)
		out.recipes[assert(Recipes.get(recipeId)).id] = true
		return out, nil
	end

	function Core.learnFromItem(state: State, itemId: unknown): (State?, string?, Recipe?)
		local recipe = Recipes.forRecipeItem(itemId)
		if recipe == nil then
			return nil, "not_a_recipe_item", nil
		end
		local out, reason = Core.learnRecipe(state, recipe.id, "item")
		return out, reason, recipe
	end

	function Core.trainerRoster(
		state: State,
		professionId: string
	): { { recipe: Recipe, status: string, cost: number } }
		local out: { { recipe: Recipe, status: string, cost: number } } = {}
		for _, recipe in Recipes.forProfession(professionId) do
			if recipe.trainerCost ~= nil then
				local status = if state.recipes[recipe.id] == true
					then "known"
					elseif state.skills[professionId] == nil then "profession_not_known"
					elseif state.skills[professionId] < recipe.requiredSkill then "skill_too_low"
					else "learnable"
				table.insert(out, { recipe = recipe, status = status, cost = recipe.trainerCost or 0 })
			end
		end
		return out
	end

	function Core.sameState(left: State, right: State): boolean
		for key, value in left.skills do
			if right.skills[key] ~= value then
				return false
			end
		end
		for key in right.skills do
			if left.skills[key] == nil then
				return false
			end
		end
		for key in left.recipes do
			if right.recipes[key] ~= true then
				return false
			end
		end
		for key in right.recipes do
			if left.recipes[key] ~= true then
				return false
			end
		end
		return true
	end

	function Core.freezeState(state: State): State
		local out: State = { skills = table.clone(state.skills), recipes = table.clone(state.recipes) }
		return Value.freezeDeep(out)
	end

	return Value.freezeDeep(Core)
end

return Value.freezeDeep(Skills)
