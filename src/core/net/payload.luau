--!strict

local Result = require("../../kernel/result")
local Value = require("../../kernel/value")

export type Bounds = { maxArguments: number, maxEntries: number, maxDepth: number, maxString: number, maxKey: number }
export type Arguments = { n: number, [number]: unknown }
export type Config = { bounds: Bounds, atom: ((unknown) -> boolean)? }

local function create(config: Config)
	local bounds = table.clone(config.bounds)
	for _, limit in { bounds.maxArguments, bounds.maxEntries, bounds.maxString, bounds.maxKey } do
		assert(Value.whole(limit, 0, 1000000) ~= nil, "invalid payload bound")
	end
	assert(Value.whole(bounds.maxDepth, 0, 128) ~= nil, "invalid depth bound")
	local function decode(...: unknown): Result.Result<Arguments>
		local count = select("#", ...)
		if count > bounds.maxArguments then
			return Result.fail("arguments_exceeded")
		end
		local entries = 0
		local active: { [unknown]: boolean } = {}
		local copies: { [unknown]: Value.Raw } = {}
		local function copy(value: unknown, depth: number): Result.Result<unknown>
			if value == nil or type(value) == "boolean" then
				return Result.ok(value)
			elseif type(value) == "string" then
				return if #value <= bounds.maxString then Result.ok(value) else Result.fail("string_exceeded")
			elseif type(value) == "number" then
				return if Value.finite(value) then Result.ok(value) else Result.fail("number_invalid")
			elseif type(value) == "function" or type(value) == "thread" then
				return Result.fail("value_invalid")
			elseif type(value) ~= "table" then
				return if config.atom ~= nil and config.atom(value)
					then Result.ok(value)
					else Result.fail("value_invalid")
			end
			if active[value] or getmetatable(value) ~= nil then
				return Result.fail("table_invalid")
			end
			if depth >= bounds.maxDepth then
				return Result.fail("depth_exceeded")
			end
			local prior = copies[value]
			if prior ~= nil then
				return Result.ok(prior)
			end
			local owned: Value.Raw = {}
			copies[value], active[value] = owned, true
			for key, child in value do
				entries += 1
				if entries > bounds.maxEntries then
					return Result.fail("entries_exceeded")
				end
				if
					(type(key) ~= "string" and type(key) ~= "number")
					or (type(key) == "string" and #key > bounds.maxKey)
					or (type(key) == "number" and not Value.finite(key))
				then
					return Result.fail("key_invalid")
				end
				local result = copy(child, depth + 1)
				if not result.ok then
					return result
				end
				owned[key] = result.value
			end
			active[value] = nil
			return Result.ok(owned)
		end
		local result: Arguments = { n = count }
		for index = 1, count do
			local decoded = copy(select(index, ...), 0)
			if not decoded.ok then
				return Result.fail(decoded.reason)
			end
			result[index] = decoded.value
		end
		return Result.ok(result)
	end
	return table.freeze({ decode = decode })
end

return table.freeze({ create = create })
