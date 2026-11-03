--!strict

export type Raw = { [unknown]: unknown }
export type MetatableProbe = typeof(setmetatable({}, {}))

local Value = {}

function Value.hasMetatable(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) ~= nil
end

function Value.raw(value: unknown): Raw?
	if type(value) ~= "table" then
		return nil
	end
	local out: Raw = {}
	for key, entry in value do
		out[key] = entry
	end
	return out
end

function Value.record(value: unknown, fields: { [string]: boolean }, required: boolean?, plain: boolean?): Raw?
	if type(value) ~= "table" or (plain ~= false and getmetatable(value) ~= nil) then
		return nil
	end
	local out: Raw = {}
	for key, entry in value do
		if type(key) ~= "string" or fields[key] ~= true then
			return nil
		end
		out[key] = entry
	end
	if required then
		for key in fields do
			if out[key] == nil then
				return nil
			end
		end
	end
	return out
end

function Value.finite(value: unknown): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function Value.nonempty(value: unknown): boolean
	return type(value) == "string" and #value > 0
end

function Value.whole(value: unknown, low: number, high: number): number?
	return if type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value == math.floor(value)
			and value >= low
			and value <= high
		then value
		else nil
end

function Value.opaque(value: unknown, limit: number): string?
	return if type(value) == "string" and #value > 0 and #value <= limit then value else nil
end

function Value.identifier(value: unknown, limit: number): string?
	local text = Value.opaque(value, limit)
	return if text ~= nil and string.match(text, "^[%w%.%-_:]+$") ~= nil then text else nil
end

function Value.dense(value: unknown, maximum: number, plain: boolean?): { unknown }?
	if type(value) ~= "table" or (plain ~= false and getmetatable(value) ~= nil) then
		return nil
	end
	local found = Value.raw(value)
	if found == nil then
		return nil
	end
	local count = 0
	for key in found do
		if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
			return nil
		end
		count += 1
	end
	if count > maximum then
		return nil
	end
	local out: { unknown } = {}
	for index = 1, count do
		if found[index] == nil then
			return nil
		end
		out[index] = found[index]
	end
	return out
end

function Value.freezeDeep<T>(value: T): T
	local probe: unknown = value
	if type(probe) ~= "table" or table.isfrozen(probe) then
		return value
	end
	for _, child in probe do
		Value.freezeDeep(child)
	end
	table.freeze(probe)
	return value
end

export type API = {
	read raw: typeof(Value.raw),
	read record: typeof(Value.record),
	read finite: typeof(Value.finite),
	read nonempty: typeof(Value.nonempty),
	read whole: typeof(Value.whole),
	read opaque: typeof(Value.opaque),
	read identifier: typeof(Value.identifier),
	read dense: typeof(Value.dense),
	read freezeDeep: typeof(Value.freezeDeep),
	read hasMetatable: typeof(Value.hasMetatable),
}
local api: API = Value
return table.freeze(api)
