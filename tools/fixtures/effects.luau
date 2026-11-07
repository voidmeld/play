--!strict

local Engine = require("./engine")
local Timed = require("../../src/core/effects/timed")

local Scene = {}

export type Host = {
	clock: () -> number,
	apply: (string, Timed.Application) -> (),
	advance: (number) -> (),
	snapshot: () -> { [string]: Timed.Entry },
}

function Scene.new(epsilon: number): Host
	local clock = Engine.clock()
	local effects: { [string]: Timed.Entry } = {}
	local function apply(id: string, application: Timed.Application)
		local updated = table.clone(effects)
		updated[id] = Timed.application(effects[id], application)
		effects = updated
	end
	local function advance(dt: number)
		clock.advance(dt)
		local updated: { [string]: Timed.Entry } = {}
		for id, effect in effects do
			local nextEffect = Timed.advance(effect, dt)
			if not Timed.expired(nextEffect, epsilon) then
				updated[id] = nextEffect
			end
		end
		effects = updated
	end
	return {
		clock = clock.clock,
		apply = apply,
		advance = advance,
		snapshot = function(): { [string]: Timed.Entry }
			return effects
		end,
	}
end

return table.freeze(Scene)
