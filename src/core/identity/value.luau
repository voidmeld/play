--!strict

export type MetatableProbe = typeof(setmetatable({}, {}))
export type RawReadback = { [unknown]: unknown }

local HasMetatable = {}

local function tableFields(value: unknown): RawReadback?
	if type(value) == "table" then
		return value
	end
	return nil
end

HasMetatable.fields = tableFields

function HasMetatable.check(value: unknown): boolean
	return getmetatable(value) ~= nil
end

return table.freeze(HasMetatable)
