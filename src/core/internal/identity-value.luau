--!strict
local Value = require("./value")
local function hasMetatable(value: unknown): boolean
	return type(value) == "table" and getmetatable(value) ~= nil
end
return table.freeze({ fields = Value.raw, check = hasMetatable })
