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
	do
		suite:case("projects a frozen recipe and rejects malformed authored rows", function(context)
			local recipe = Crafting.projectRecipe(basicRecipe())
			context:expect((recipe ~= nil)):toBe(true)
			assert(recipe ~= nil)
			context:expect((table.isfrozen(recipe))):toBe(true)
			context:expect((table.isfrozen(recipe.inputs))):toBe(true)
			context:expect(recipe.rung):toBe("basic")

			local bad = basicRecipe()
			bad.rung = "raid"
			context:expect((Crafting.projectRecipe(bad))):toBeNil()

			bad = basicRecipe()
			bad.outputItemId = ""
			context:expect((Crafting.projectRecipe(bad))):toBeNil()

			bad = basicRecipe()
			bad.inputs = {}
			context:expect((Crafting.projectRecipe(bad))):toBeNil()

			bad = basicRecipe()
			bad.inputs[1].source = "moon"
			context:expect((Crafting.projectRecipe(bad))):toBeNil()

			bad = basicRecipe()
			bad.inputs[1].quantity = 0
			context:expect((Crafting.projectRecipe(bad))):toBeNil()

			bad = basicRecipe()
			bad.extra = true
			context:expect((Crafting.projectRecipe(bad))):toBeNil()
		end)
	end

	do
		suite:case("encodes basic baseline as contested-material-free", function(context)
			context:expect((Crafting.projectRecipe(basicRecipe()) ~= nil)):toBe(true)

			local bad = basicRecipe()
			bad.inputs[2] = stack("material.contested_iron", "contested", 1)
			context:expect((Crafting.projectRecipe(bad))):toBeNil()
		end)

		suite:case("requires an advanced recipe to declare a contested material and forbids rare", function(context)
			context:expect((Crafting.projectRecipe(advancedRecipe()) ~= nil)):toBe(true)

			local noFrontier = advancedRecipe()
			noFrontier.inputs = { stack("material.copper_ore", "common", 2) }
			context:expect((Crafting.projectRecipe(noFrontier))):toBeNil()

			local withFalls = advancedRecipe()
			withFalls.inputs[3] = stack("material.rare_shard", "rare", 1)
			context:expect((Crafting.projectRecipe(withFalls))):toBeNil()
		end)

		suite:case("requires an master recipe to declare BOTH contested and rare materials", function(context)
			context:expect((Crafting.projectRecipe(masterRecipe()) ~= nil)):toBe(true)

			local contestedOnly = masterRecipe()
			contestedOnly.inputs = { stack("material.contested_iron", "contested", 1) }
			context:expect((Crafting.projectRecipe(contestedOnly))):toBeNil()

			local rareOnly = masterRecipe()
			rareOnly.inputs = { stack("material.rare_shard", "rare", 1) }
			context:expect((Crafting.projectRecipe(rareOnly))):toBeNil()
		end)
	end

	suite:case("uses authored source sets, rung names and source row bounds", function(context)
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
		context:expect(catalog.projectRecipe(recipe) ~= nil):toBe(true)
		recipe.inputs[2] = { materialId = "b", source = "garden", quantity = 1 }
		context:expect(catalog.projectRecipe(recipe) ~= nil):toBe(true)
		recipe.inputs[3] = { materialId = "c", source = "garden", quantity = 1 }
		context:expect(catalog.projectRecipe(recipe)):toBeNil()
		recipe.inputs = { { materialId = "a", source = "mine", quantity = 1 } }
		context:expect(catalog.projectRecipe(recipe)):toBeNil()
		recipe.inputs[1].source = "unknown"
		context:expect(catalog.projectRecipe(recipe)):toBeNil()
		recipe.inputs[1].source = "garden"
		recipe.rung = "basic"
		context:expect(catalog.projectRecipe(recipe)):toBeNil()
	end)

	suite:case("rejects duplicate material-source pairs, sparse inputs and nonfinite quantities", function(context)
		local recipe = basicRecipe()
		recipe.inputs[2] = table.clone(recipe.inputs[1])
		context:expect(Crafting.projectRecipe(recipe)):toBeNil()
		recipe.inputs = { [2] = recipe.inputs[1] }
		context:expect(Crafting.projectRecipe(recipe)):toBeNil()
		recipe = basicRecipe()
		recipe.inputs[1].quantity = math.huge
		context:expect(Crafting.projectRecipe(recipe)):toBeNil()
		recipe.inputs[1].quantity = 1.5
		context:expect(Crafting.projectRecipe(recipe)):toBeNil()
	end)
end
