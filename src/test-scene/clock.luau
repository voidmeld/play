--!strict

export type Task = { due: number, active: boolean, callback: () -> () }

local Clock = {}

function Clock.new()
	local now = 0
	local tasks: { Task } = {}
	local function schedule(delay: number, callback: () -> ()): () -> ()
		local task = { due = now + delay, active = true, callback = callback }
		table.insert(tasks, task)
		return function()
			task.active = false
		end
	end
	local function advance(seconds: number)
		local target = now + seconds
		while true do
			local nextTask: Task? = nil
			for _, task in tasks do
				if task.active and task.due <= target and (nextTask == nil or task.due < nextTask.due) then
					nextTask = task
				end
			end
			if nextTask == nil then
				break
			end
			now = nextTask.due
			nextTask.active = false
			nextTask.callback()
		end
		now = target
	end
	return {
		clock = function(): number
			return now
		end,
		schedule = schedule,
		advance = advance,
	}
end

return table.freeze(Clock)
