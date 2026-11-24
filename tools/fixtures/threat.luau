--!strict

local Engine = require("./engine")
local Threat = require("../../src/core/threat/table")

local Scene = {}

function Scene.new(config: Threat.Config)
	local clock = Engine.clock()
	local law = Threat.rules(config)
	local state = Threat.empty()
	local pursuitRefreshes = 0
	return {
		clock = clock,
		add = function(actorId: string, amount: number, inMelee: boolean)
			local updated, refresh = law.add(state, actorId, amount, inMelee)
			state = updated
			if refresh then
				pursuitRefreshes += 1
			end
		end,
		taunt = function(actorId: string)
			state = law.taunt(state, actorId)
		end,
		remove = function(actorId: string)
			state = Threat.remove(state, actorId)
		end,
		prune = function(candidates: { [string]: Threat.Candidate }): Threat.Pruned
			local updated, result = Threat.prune(state, candidates)
			state = updated
			return result
		end,
		reset = function()
			state = Threat.empty()
		end,
		snapshot = function(): Threat.State
			return state
		end,
		refreshes = function(): number
			return pursuitRefreshes
		end,
	}
end

return table.freeze(Scene)
