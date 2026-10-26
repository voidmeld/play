--!strict

export type Raw = { [unknown]: unknown }

local Value = {}

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

return Value
