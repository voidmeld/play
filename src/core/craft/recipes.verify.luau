--!strict

local Recipes = require("./recipes")
local settings: Recipes.Config = {
	sources = { common = true, contested = true, rare = true },
	rungs = {
		basic = { contested = { max = 0 }, rare = { max = 0 } },
		advanced = { contested = { min = 1 }, rare = { max = 0 } },
		master = { contested = { min = 1 }, rare = { min = 1 } },
	},
}
local Crafting = Recipes.catalog(settings)
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type StackFixture = { materialId: string, source: string, quantity: number }
type RecipeFixture = { id: string, rung: string, outputItemId: string, inputs: { StackFixture }, extra: boolean? }

local function basicRecipe(): RecipeFixture
	return {
		id = "recipe.copper_blade",
		rung = "basic",
		outputItemId = "item.copper_blade",
		inputs = {
			{ materialId = "material.copper_ore", source = "common", quantity = 2 },
		},
	}
end

local function advancedRecipe(): RecipeFixture
	return {
		id = "recipe.contested_blade",
		rung = "advanced",
		outputItemId = "item.contested_blade",
		inputs = {
			{ materialId = "material.copper_ore", source = "common", quantity = 2 },
			{ materialId = "material.contested_iron", source = "contested", quantity = 1 },
		},
	}
end

local function masterRecipe(): RecipeFixture
	return {
		id = "recipe.rare_blade",
		rung = "master",
		outputItemId = "item.rare_blade",
		inputs = {
			{ materialId = "material.contested_iron", source = "contested", quantity = 1 },
			{ materialId = "material.rare_shard", source = "rare", quantity = 1 },
		},
	}
end

local function stack(materialId: string, source: string, quantity: number): StackFixture
	return { materialId = materialId, source = source, quantity = quantity }
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("recipes", function()
		do
			it("projects a frozen recipe and rejects malformed authored rows", function(own)
				local recipe = Crafting.projectRecipe(basicRecipe())
				expect((recipe ~= nil)):toBe(true)
				assert(recipe ~= nil)
				expect((table.isfrozen(recipe))):toBe(true)
				expect((table.isfrozen(recipe.inputs))):toBe(true)
				expect(recipe.rung):toBe("basic")

				local bad = basicRecipe()
				bad.rung = "raid"
				expect((Crafting.projectRecipe(bad))):toBeNil()

				bad = basicRecipe()
				bad.outputItemId = ""
				expect((Crafting.projectRecipe(bad))):toBeNil()

				bad = basicRecipe()
				bad.inputs = {}
				expect((Crafting.projectRecipe(bad))):toBeNil()

				bad = basicRecipe()
				bad.inputs[1].source = "moon"
				expect((Crafting.projectRecipe(bad))):toBeNil()

				bad = basicRecipe()
				bad.inputs[1].quantity = 0
				expect((Crafting.projectRecipe(bad))):toBeNil()

				bad = basicRecipe()
				bad.extra = true
				expect((Crafting.projectRecipe(bad))):toBeNil()
			end)
		end

		do
			it("encodes basic baseline as contested-material-free", function(own)
				expect((Crafting.projectRecipe(basicRecipe()) ~= nil)):toBe(true)

				local bad = basicRecipe()
				bad.inputs[2] = stack("material.contested_iron", "contested", 1)
				expect((Crafting.projectRecipe(bad))):toBeNil()
			end)

			it("requires an advanced recipe to declare a contested material and forbids rare", function(own)
				expect((Crafting.projectRecipe(advancedRecipe()) ~= nil)):toBe(true)

				local noFrontier = advancedRecipe()
				noFrontier.inputs = { stack("material.copper_ore", "common", 2) }
				expect((Crafting.projectRecipe(noFrontier))):toBeNil()

				local withFalls = advancedRecipe()
				withFalls.inputs[3] = stack("material.rare_shard", "rare", 1)
				expect((Crafting.projectRecipe(withFalls))):toBeNil()
			end)

			it("requires an master recipe to declare BOTH contested and rare materials", function(own)
				expect((Crafting.projectRecipe(masterRecipe()) ~= nil)):toBe(true)

				local contestedOnly = masterRecipe()
				contestedOnly.inputs = { stack("material.contested_iron", "contested", 1) }
				expect((Crafting.projectRecipe(contestedOnly))):toBeNil()

				local rareOnly = masterRecipe()
				rareOnly.inputs = { stack("material.rare_shard", "rare", 1) }
				expect((Crafting.projectRecipe(rareOnly))):toBeNil()
			end)
		end

		it("uses authored source sets, rung names and source row bounds", function(own)
			local catalog = Recipes.catalog({
				sources = { garden = true, mine = true },
				rungs = { novice = { garden = { min = 1, max = 2 }, mine = { max = 0 } } },
			})
			local recipe: Recipes.Recipe = {
				id = "r",
				rung = "novice",
				outputItemId = "o",
				inputs = { { materialId = "a", source = "garden", quantity = 5 } },
			}
			expect(catalog.projectRecipe(recipe) ~= nil):toBe(true)
			recipe.inputs[2] = { materialId = "b", source = "garden", quantity = 1 }
			expect(catalog.projectRecipe(recipe) ~= nil):toBe(true)
			recipe.inputs[3] = { materialId = "c", source = "garden", quantity = 1 }
			expect(catalog.projectRecipe(recipe)):toBeNil()
			recipe.inputs = { { materialId = "a", source = "mine", quantity = 1 } }
			expect(catalog.projectRecipe(recipe)):toBeNil()
			recipe.inputs[1].source = "unknown"
			expect(catalog.projectRecipe(recipe)):toBeNil()
			recipe.inputs[1].source = "garden"
			recipe.rung = "basic"
			expect(catalog.projectRecipe(recipe)):toBeNil()
		end)

		it("rejects duplicate material-source pairs, sparse inputs and nonfinite quantities", function()
			local recipe = basicRecipe()
			recipe.inputs[2] = table.clone(recipe.inputs[1])
			expect(Crafting.projectRecipe(recipe)):toBeNil()
			recipe.inputs = { [2] = recipe.inputs[1] }
			expect(Crafting.projectRecipe(recipe)):toBeNil()
			recipe = basicRecipe()
			recipe.inputs[1].quantity = math.huge
			expect(Crafting.projectRecipe(recipe)):toBeNil()
			recipe.inputs[1].quantity = 1.5
			expect(Crafting.projectRecipe(recipe)):toBeNil()
		end)
	end)
end
