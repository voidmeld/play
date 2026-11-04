--!strict

local Codec = require("./codec")
local Result = require("./result")

export type Readback = unknown
export type Transform = (unknown) -> unknown
export type Reader = { read read: (string) -> Result.Result<Readback> }
export type Writer = { read update: (string, Transform) -> Result.Result<Readback> }
export type Port = Reader & Writer
export type Codec<T> = Codec.Record<T>

local function compareAndSwap<T>(found: boolean, expected: T, desired: T, codec: Codec<T>): Transform
	return function(current: unknown): unknown
		if found then
			local prior = codec.copy(current)
			if prior == nil or not codec.equal(prior, expected) then
				return nil
			end
		elseif current ~= nil then
			return nil
		end
		return (codec.copy(desired))
	end
end

local function committed<T>(readback: Readback, expected: T, codec: Codec<T>): Result.Result<T>
	local value = codec.copy(readback)
	if value == nil or not codec.equal(value, expected) then
		return Result.fail("readback_conflict")
	end
	return Result.ok(value)
end

local function confirm(reader: Reader, key: string, expected: Result.Result<unknown>): Result.Result<Readback>
	if not expected.ok then
		return expected
	end
	local observed = reader.read(key)
	if not observed.ok then
		return observed
	end
	return if Codec.equalData(observed.value, expected.value) then observed else Result.fail("readback_mismatch")
end

export type API = {
	read compareAndSwap: typeof(compareAndSwap),
	read committed: typeof(committed),
	read confirm: typeof(confirm),
}
local api: API = { compareAndSwap = compareAndSwap, committed = committed, confirm = confirm }
return table.freeze(api)
