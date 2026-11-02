--!strict

local Recipes = require("./craft/recipes")

export type RecipesMaterialStack = Recipes.MaterialStack
export type RecipesRecipe = Recipes.Recipe
export type RecipesSourceRule = Recipes.SourceRule
export type RecipesConfig = Recipes.Config
export type RecipesCatalog = Recipes.Catalog

export type API = {
	read recipes: typeof(Recipes),
}

local api: API = {
	recipes = Recipes,
}

return table.freeze(api)
