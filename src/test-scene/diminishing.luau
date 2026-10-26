--!strict

local Clock = require("./clock")
local Diminishing = require("../core/control/diminishing")

local Scene = {}

function Scene.new(config: Diminishing.Config)
	local clock = Clock.new()
	local law = Diminishing.rules(config)
	local state = Diminishing.empty()
	return {
		clock = clock,
		apply = function(category: string, durationSec: number): Diminishing.Result
			local result = law.apply(state, category, durationSec, clock.clock())
			state = result.dr
			return result
		end,
		snapshot = function(): Diminishing.State
			return Diminishing.clone(state)
		end,
	}
end

return table.freeze(Scene)
