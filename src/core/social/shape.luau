--!strict

local Value = require("../internal/value")

export type Raw = Value.Raw

local Shape = {}

Shape.raw = Value.raw
Shape.freezeDeep = Value.freezeDeep

function Shape.whole(value: unknown, minimum: number, maximum: number): boolean
	return Value.whole(value, minimum, maximum) ~= nil
end

function Shape.opaque(value: unknown, maximum: number): boolean
	return Value.opaque(value, maximum) ~= nil
end

function Shape.onlyFields(value: unknown, fields: { [string]: boolean }): boolean
	return Value.record(value, fields, false, false) ~= nil
end

function Shape.exact(value: unknown, fields: { [string]: boolean }): boolean
	return Value.record(value, fields, true) ~= nil
end

function Shape.denseLength(value: unknown): number?
	if type(value) ~= "table" then
		return nil
	end
	local raw: Raw = {}
	local meta = getmetatable(value)
	if type(meta) == "table" then
		setmetatable(raw, meta)
	end
	local count = 0
	for key, entry in value do
		raw[key] = entry
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return nil
		end
		count += 1
	end
	for index = 1, count do
		if raw[index] == nil then
			return nil
		end
	end
	return count
end

function Shape.dense(value: unknown, maximum: number): number?
	local rows = Value.dense(value, maximum)
	return if rows ~= nil then #rows else nil
end

function Shape.freezeDeepWithKeys<T>(value: T): T
	local probe: unknown = value
	if type(probe) ~= "table" or table.isfrozen(probe) then
		return value
	end
	for key, child in probe do
		Shape.freezeDeepWithKeys(key)
		Shape.freezeDeepWithKeys(child)
	end
	table.freeze(probe)
	return value
end

function Shape.number(value: unknown): number?
	return if type(value) == "number" then value else nil
end

function Shape.string(value: unknown): string?
	return if type(value) == "string" then value else nil
end

function Shape.boolean(value: unknown): boolean?
	return if type(value) == "boolean" then value else nil
end

function Shape.array<T>(value: unknown, project: (unknown) -> T?): { T }?
	local rows = Value.dense(value, math.huge, false)
	if rows == nil then
		return nil
	end
	local out: { T } = {}
	for _, row in rows do
		local entry = project(row)
		if entry == nil then
			return nil
		end
		table.insert(out, entry)
	end
	return out
end

function Shape.map<K, V>(value: unknown, keyOf: (unknown) -> K?, valueOf: (unknown) -> V?): { [K]: V }?
	local rows = Value.raw(value)
	if rows == nil then
		return nil
	end
	local out: { [K]: V } = {}
	for key, value in rows do
		local projectedKey, projectedValue = keyOf(key), valueOf(value)
		if projectedKey == nil or projectedValue == nil then
			return nil
		end
		out[projectedKey] = projectedValue
	end
	return out
end

return Shape
