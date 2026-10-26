--!strict

local Value = require("../internal/value")

export type MaterialStack = { materialId: string, source: string, quantity: number }
export type Recipe = { id: string, rung: string, outputItemId: string, inputs: { MaterialStack } }
export type SourceRule = { min: number?, max: number? }
export type Config = { sources: { [string]: boolean }, rungs: { [string]: { [string]: SourceRule } } }
export type Catalog = { projectRecipe: (unknown) -> Recipe? }

local Recipes = {}

function Recipes.catalog(config: Config): Catalog
	local function projectStack(value: unknown): MaterialStack?
		local raw = Value.record(value, { materialId = true, source = true, quantity = true }, false, false)
		if raw == nil then
			return nil
		end
		local materialId = Value.opaque(raw.materialId, math.huge)
		local source = raw.source
		local quantity = Value.whole(raw.quantity, 1, math.huge)
		if materialId == nil or type(source) ~= "string" or not config.sources[source] or quantity == nil then
			return nil
		end
		return Value.freezeDeep({ materialId = materialId, source = source, quantity = quantity })
	end

	return {
		projectRecipe = function(value: unknown): Recipe?
			local raw =
				Value.record(value, { id = true, rung = true, outputItemId = true, inputs = true }, false, false)
			if raw == nil then
				return nil
			end
			local id = Value.opaque(raw.id, math.huge)
			local outputItemId = Value.opaque(raw.outputItemId, math.huge)
			local rung = raw.rung
			if id == nil or outputItemId == nil or type(rung) ~= "string" then
				return nil
			end
			local rules = config.rungs[rung]
			local inputs = Value.dense(raw.inputs, math.huge, false)
			if rules == nil or inputs == nil or #inputs == 0 then
				return nil
			end
			local rows: { MaterialStack } = {}
			local seen: { [string]: boolean } = {}
			local counts: { [string]: number } = {}
			for _, value in inputs do
				local stack = projectStack(value)
				if stack == nil then
					return nil
				end
				local key = stack.materialId .. "\0" .. stack.source
				if seen[key] then
					return nil
				end
				seen[key] = true
				counts[stack.source] = (counts[stack.source] or 0) + 1
				table.insert(rows, stack)
			end
			for source, rule in rules do
				local count = counts[source] or 0
				if count < (rule.min or 0) or (rule.max ~= nil and count > rule.max) then
					return nil
				end
			end
			return Value.freezeDeep({ id = id, rung = rung, outputItemId = outputItemId, inputs = rows })
		end,
	}
end

return Recipes
