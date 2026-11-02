--!strict

local Clock = require("./clock")
local Lease = require("../core/identity/character-lease")
local Leases = require("../core/identity/character-lease-store")
local Retry = require("../roblox/data-store")
local StoreHost = require("../core/persistence/store-host")

export type Config = Lease.Config
export type Options = StoreHost.TestOptions

local function new(config: Config, options: Options?)
	local clock = Clock.new()
	local retry = Retry.retryPolicy({ attempts = 1, baseDelay = 0, maxDelay = 0 })
	local host = StoreHost.create({
		clock = clock.clock,
		maxKeyBytes = 256,
		maxAttempts = 1,
		backoff = retry.delay,
		retry = retry.run,
		warning = function() end,
	})
	local values: { [string]: unknown } = {}
	local writes = 0
	local store = host.memory(
		{
			name = "character-leases",
			get = function(key)
				return values[key]
			end,
			set = function(key, value)
				values[key] = value
				writes += 1
			end,
			update = function(key, transform)
				local nextValue = transform(values[key])
				if nextValue ~= nil then
					values[key] = nextValue
					writes += 1
				end
				return nextValue
			end,
		},
		options,
		function()
			return nil
		end
	)
	local record = Lease.create(config)
	local repository = Leases.create({
		record = record,
		identityLimit = math.min(config.characterIdLimit, config.sessionIdLimit, config.acquisitionIdLimit),
		zoneIdLimit = config.zoneIdLimit,
	})
	return {
		record = record,
		repository = repository,
		store = store,
		clock = clock,
		writes = function(): number
			return writes
		end,
	}
end

return table.freeze({ new = new })
