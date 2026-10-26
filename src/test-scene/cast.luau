--!strict

local Clock = require("./clock")
local Queue = require("../core/cast/queue")

local Scene = {}

function Scene.new(config: Queue.Config)
	local clock = Clock.new()
	local law = Queue.rules(config)
	local state: Queue.State<string> = { nextToken = 1 }
	local fired: { Queue.Entry<string> } = {}
	local function enqueue(
		payload: string,
		requeues: number,
		reason: string?,
		remainingSec: number?
	): Queue.Entry<string>?
		local updated, entry = law.enqueue(state, payload, requeues, reason, remainingSec, clock.clock())
		state = updated
		if entry ~= nil then
			local pending = entry
			clock.schedule(pending.dueAt - clock.clock(), function()
				local nextState, taken = Queue.take(state, pending.token, clock.clock())
				state = nextState
				if taken ~= nil then
					table.insert(fired, taken)
				end
			end)
		end
		return entry
	end
	return {
		clock = clock,
		law = law,
		enqueue = enqueue,
		cancel = function(token: number?)
			state = Queue.cancel(state, token)
		end,
		snapshot = function(): Queue.State<string>
			return state
		end,
		fired = fired,
	}
end

return table.freeze(Scene)
