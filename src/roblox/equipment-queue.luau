--!strict

export type Deps<P, C> = {
	spawn: (() -> ()) -> (),
	active: () -> boolean,
	current: (P, C) -> boolean,
	perform: (P, C, () -> boolean) -> (),
	warn: (string) -> (),
}

export type Queue<P, C> = {
	request: (P, C) -> (),
	invalidate: (P) -> (),
	forget: (P) -> (),
	generation: (P) -> number?,
	running: (P) -> boolean,
	dispose: () -> (),
}

type Request<C> = {
	character: C,
	generation: number,
}

local EquipmentApplyQueue = {}

function EquipmentApplyQueue.create<P, C>(deps: Deps<P, C>): Queue<P, C>
	local generations: { [P]: number } = {}
	local pending: { [P]: Request<C> } = {}
	local running: { [P]: boolean } = {}

	local function nextGeneration(player: P): number
		local generation = (generations[player] or 0) + 1
		generations[player] = generation
		return generation
	end

	local function drain(player: P)
		while deps.active() do
			local request = pending[player]
			if request == nil then
				break
			end
			pending[player] = nil
			local character = request.character
			local generation = request.generation
			local function fence(): boolean
				return deps.active() and generations[player] == generation and deps.current(player, character)
			end
			local outcome = table.pack(pcall(deps.perform, player, character, fence))
			if outcome[1] ~= true then
				deps.warn("[EquipmentApplyQueue] apply drain failed: " .. tostring(outcome[2]))
			end
		end
		running[player] = nil
	end

	local queue = {}

	function queue.request(player: P, character: C)
		pending[player] = { character = character, generation = nextGeneration(player) }
		if running[player] == true then
			return
		end
		running[player] = true
		deps.spawn(function()
			drain(player)
		end)
	end

	function queue.invalidate(player: P)
		nextGeneration(player)
		pending[player] = nil
	end

	function queue.forget(player: P)
		generations[player] = nil
		pending[player] = nil
		running[player] = nil
	end

	function queue.generation(player: P): number?
		return generations[player]
	end

	function queue.running(player: P): boolean
		return running[player] == true
	end

	function queue.dispose()
		table.clear(generations)
		table.clear(pending)
		table.clear(running)
	end

	return queue
end

return EquipmentApplyQueue
