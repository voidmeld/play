--!strict

local Result = require("./result")
local Value = require("./value")

export type Decoder<T> = (unknown) -> (T?, string?)
export type Record<T> = { read copy: Decoder<T>, read equal: (T, T) -> boolean }
export type Versioned<T> = {
	read version: number,
	read fields: { [string]: boolean },
	read required: boolean?,
	read migrate: ((unknown) -> unknown)?,
	read decode: (Value.Raw) -> (T?, string?),
}

local function versioned<T>(config: Versioned<T>): Decoder<T>
	config = table.freeze(table.clone(config))
	assert(Value.whole(config.version, 1, 9007199254740991) ~= nil, "invalid codec version")
	local fields = table.freeze(table.clone(config.fields))
	return function(raw: unknown): (T?, string?)
		local migrated = if config.migrate then config.migrate(raw) else raw
		local source = Value.record(migrated, fields, config.required)
		if source == nil then
			return nil, "record_invalid"
		end
		if source.schemaVersion ~= config.version then
			return nil, "schema_unsupported"
		end
		return config.decode(source)
	end
end

local function clone(value: unknown, copies: Value.Raw, active: { [unknown]: boolean }): Result.Result<unknown>
	local kind = type(value)
	if value == nil or kind == "boolean" or kind == "string" then
		return Result.ok(value)
	end
	if type(value) == "number" then
		return if Value.finite(value) then Result.ok(value) else Result.fail("value_invalid")
	end
	if type(value) ~= "table" or getmetatable(value) ~= nil or active[value] then
		return Result.fail("value_invalid")
	end
	if copies[value] ~= nil then
		return Result.ok(copies[value])
	end
	local result: Value.Raw = {}
	copies[value] = result
	active[value] = true
	for key, child in value do
		local keyType = type(key)
		if (keyType ~= "string" and keyType ~= "number") or (type(key) == "number" and not Value.finite(key)) then
			return Result.fail("value_invalid")
		end
		local copied = clone(child, copies, active)
		if not copied.ok then
			return copied
		end
		result[key] = copied.value
	end
	active[value] = nil
	return Result.ok(result)
end

local function copyData(value: unknown): Result.Result<unknown>
	return clone(value, {}, {})
end

local function equal(left: unknown, right: unknown): boolean
	local a, b = Value.raw(left), Value.raw(right)
	if a == nil or b == nil then
		return left == right
	end
	for key, value in a do
		if not equal(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local function equalData(left: unknown, right: unknown): boolean
	local a, b = copyData(left), copyData(right)
	return a.ok and b.ok and equal(a.value, b.value)
end

export type API = {
	read versioned: typeof(versioned),
	read copyData: typeof(copyData),
	read equalData: typeof(equalData),
}
local api: API = { versioned = versioned, copyData = copyData, equalData = equalData }
return table.freeze(api)
