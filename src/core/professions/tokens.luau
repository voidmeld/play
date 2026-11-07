--!strict

local Value = require("../../kernel/value")

export type Tokens = { [string]: string }
export type Config = { names: { string }, maxLength: number }

local Tokens = {}

function Tokens.create(config: Config)
	assert(Value.whole(config.maxLength, 1, 9007199254740991) ~= nil, "invalid token length")
	assert(#config.names > 0, "token names required")
	local fields: { [string]: boolean } = {}
	for _, name in config.names do
		assert(Value.identifier(name, 128) ~= nil and not fields[name], "invalid token name")
		fields[name] = true
	end
	local limit = config.maxLength
	local function normalize(raw: unknown, allowEmpty: boolean?): Tokens?
		local record = Value.record(raw, fields, true)
		if record == nil then
			return nil
		end
		local result: Tokens = {}
		local used: { [string]: boolean } = {}
		for name, value in record do
			if type(name) ~= "string" or type(value) ~= "string" or #value > limit then
				return nil
			end
			if value == "" then
				if allowEmpty ~= true then
					return nil
				end
			elseif string.match(value, "^[%w%-_:]+$") == nil or used[value] then
				return nil
			end
			used[value] = true
			result[name] = value
		end
		return result
	end
	local function matches(raw: unknown, name: string, supplied: unknown): boolean
		local current = normalize(raw, true)
		return current ~= nil and type(supplied) == "string" and supplied ~= "" and current[name] == supplied
	end
	return table.freeze({ normalize = normalize, matches = matches })
end

return table.freeze(Tokens)
