--!strict

local Host = require("../../core/persistence/store-host")
local Result = require("../../kernel/result")
local Store = require("../../kernel/store")
local Value = require("../../kernel/value")

export type Port = Store.Port
export type Backend = {
	read getUncachedOutcome: (string) -> Host.Outcome,
	read updateOutcome: (string, Store.Transform) -> Host.Outcome,
}

local function new(host: Backend): Port
	local function result(outcome: unknown, fallback: string): Result.Result<Store.Readback>
		local fields = Value.record(outcome, { ok = true, value = true, reason = true })
		if fields == nil then
			return Result.fail(fallback)
		end
		if fields.ok == true then
			return Result.ok(fields.value)
		end
		return Result.fail(if fields.ok == false then Value.opaque(fields.reason, 128) or fallback else fallback)
	end
	local function read(key: string): Result.Result<Store.Readback>
		return result(host.getUncachedOutcome(key), "read_failed")
	end
	local function update(key: string, transform: Store.Transform): Result.Result<Store.Readback>
		return result(host.updateOutcome(key, transform), "store_failure")
	end
	return table.freeze({ read = read, update = update })
end

export type API = { read new: typeof(new) }
local api: API = { new = new }
return table.freeze(api)
