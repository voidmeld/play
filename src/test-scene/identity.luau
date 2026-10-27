--!strict

local Policy = require("../core/identity/policy")

local function validate(raw: unknown): (boolean, string?, string?)
	if type(raw) ~= "string" then
		return false, nil, "invalid"
	end
	local normalized = string.match(raw, "^%s*(.-)%s*$") :: string
	if
		normalized == "Reserved"
		or #normalized < 2
		or #normalized > 32
		or string.match(normalized, "^[%w '-]+$") == nil
	then
		return false, nil, "invalid"
	end
	return true, normalized, nil
end

local function key(raw: unknown): (string?, string?)
	local ok, name = validate(raw)
	return if ok and name ~= nil then "claim/" .. string.lower(name) else nil, nil
end

local policy: Policy.Policy = {
	validateName = validate,
	registryKey = key,
	validRegistryKey = function(raw: unknown): boolean
		return type(raw) == "string" and string.sub(raw, 1, 6) == "claim/" and key(string.sub(raw, 7)) == raw
	end,
	validDestination = function(raw: unknown): boolean
		return type(raw) == "string"
			and #raw <= 128
			and string.match(raw, "^[a-z][a-z0-9_-]*%.[a-z][a-z0-9_-]*$") ~= nil
	end,
	profilePartitionKey = function(userId: unknown, characterId: unknown): string
		return "profile/" .. tostring(userId) .. "/" .. tostring(characterId)
	end,
	realms = { red = true, green = true, blue = true },
	peoples = { first = true, second = true, third = true },
	accountLimit = 12,
	realmLimit = 4,
	minLevel = 1,
	maxLevel = 50,
}

return table.freeze(policy) :: Policy.Policy
