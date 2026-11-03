--!strict
local Value = require("./value")
local function equal(left: unknown, right: unknown): boolean
	local a = Value.raw(left)
	local b = Value.raw(right)
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
return equal
