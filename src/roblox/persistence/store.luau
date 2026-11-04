--!strict

local Host = require("../../core/persistence/store-host")
local Result = require("../../kernel/result")
local Store = require("../../kernel/store")

export type Port = Store.Port
export type Backend = {
	read getUncachedOutcome: (string) -> Host.Outcome,
	read updateOutcome: (string, Store.Transform) -> Host.Outcome,
}

local function new(host: Backend): Port
	local function read(key: string): Result.Result<Store.Readback>
		local outcome = host.getUncachedOutcome(key)
		return if outcome.ok then Result.ok(outcome.value) else Result.fail(outcome.reason or "read_failed")
	end
	local function update(key: string, transform: Store.Transform): Result.Result<Store.Readback>
		local outcome = host.updateOutcome(key, transform)
		return if outcome.ok then Result.ok(outcome.value) else Result.fail(outcome.reason or "store_failure")
	end
	return table.freeze({ read = read, update = update })
end

export type API = { read new: typeof(new) }
local api: API = { new = new }
return table.freeze(api)
