--!strict

local Atomic = require("../../../src/roblox/persistence/store")
local Host = require("../../../src/core/persistence/store-host")
local Kernel = require("../../../src/kernel/store")
local Retry = require("../../../src/roblox/data-store")

export type Options = Host.TestOptions
export type Scene = {
	read store: Kernel.Port,
	read seed: (string, unknown) -> (),
	read writes: () -> number,
	read updates: () -> number,
	read values: { [string]: unknown },
}

local function new(clock: () -> number, options: Options?, initial: { [string]: unknown }?): Scene
	local retry = Retry.retryPolicy({ attempts = 1, baseDelay = 0, maxDelay = 0 })
	local host = Host.create({
		clock = clock,
		maxKeyBytes = 256,
		maxAttempts = 1,
		backoff = retry.delay,
		retry = retry.run,
		warning = function() end,
	})
	local values: { [string]: unknown } = initial or {}
	local writes = 0
	local updates = 0
	local function set(key: string, value: unknown)
		values[key] = value
		writes += 1
	end
	local memory: Host.MemoryStore = {
		name = "atomic-store",
		get = function(key: string): unknown
			return values[key]
		end,
		set = set,
		update = function(key: string, transform: (unknown) -> unknown): unknown
			local value = transform(values[key])
			if value ~= nil then
				set(key, value)
			end
			return value
		end,
	}
	local function observe(event: Host.Observation)
		if event.operation == "Update" then
			updates += 1
		end
	end
	local backend = host.memory(memory, options, function()
		return observe
	end)
	return table.freeze({
		store = Atomic.new(backend),
		seed = function(key: string, value: unknown)
			local outcome = backend.set(key, value)
			assert(outcome.ok, outcome.reason)
		end,
		writes = function(): number
			return writes
		end,
		updates = function(): number
			return updates
		end,
		values = values,
	})
end

export type API = { read new: typeof(new) }
local api: API = { new = new }
return table.freeze(api)
