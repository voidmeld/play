--!strict

local Atomic = require("../../roblox/persistence/store")
local Host = require("../../core/persistence/store-host")
local Kernel = require("../../kernel/store")
local Retry = require("../../roblox/data-store")

export type Options = Host.TestOptions
export type Scene = { read store: Kernel.Port, read seed: (string, unknown) -> (), read writes: () -> number }

local function new(clock: () -> number, options: Options?): Scene
	local retry = Retry.retryPolicy({ attempts = 1, baseDelay = 0, maxDelay = 0 })
	local host = Host.create({
		clock = clock,
		maxKeyBytes = 256,
		maxAttempts = 1,
		backoff = retry.delay,
		retry = retry.run,
		warning = function() end,
	})
	local values: { [string]: unknown } = {}
	local writes = 0
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
	local backend = host.memory(memory, options, function()
		return nil
	end)
	return table.freeze({
		store = Atomic.new(backend),
		seed = backend.set,
		writes = function(): number
			return writes
		end,
	})
end

export type API = { read new: typeof(new) }
local api: API = { new = new }
return table.freeze(api)
