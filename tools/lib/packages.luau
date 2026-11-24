--!strict

local fs = require("@std/fs")

local function directory(alias: string): string
	local lock = fs.readFileToString("pkg.lock.luau")
	local roots = string.match(lock, "^(.-)\n%s*packages%s*=") or lock
	local key = string.match(roots, '[%s{,]%[?"?' .. alias .. '"?%]?%s*=%s*"([^"]+)"')
	assert(key ~= nil, "pkg.lock.luau does not lock " .. alias .. "; run lute pkg install --vendor")
	local encoded = string.gsub(key, "[^%w%-_%.@]", function(character: string): string
		return string.format("%%%02X", string.byte(character))
	end)
	return ".lpm/" .. encoded
end

return table.freeze({ directory = directory })
