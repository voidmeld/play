--!strict

local Engine = require("./engine")
local Lease = require("../../src/core/identity/character-lease")
local Leases = require("../../src/core/identity/character-lease-store")
local StoreScene = require("./persistence/store")

export type Config = Lease.Config
export type Options = StoreScene.Options

local function new(config: Config, options: Options?)
	local clock = Engine.clock()
	local storage = StoreScene.new(clock.clock, options)
	local record = Lease.create(config)
	local repository = Leases.create({
		record = record,
		identityLimit = math.min(config.characterIdLimit, config.sessionIdLimit, config.acquisitionIdLimit),
		zoneIdLimit = config.zoneIdLimit,
	})
	return {
		record = record,
		repository = repository,
		store = storage.store,
		seed = storage.seed,
		clock = clock,
		writes = storage.writes,
	}
end

return table.freeze({ new = new })
