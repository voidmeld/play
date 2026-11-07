--!strict

local Config = require("./checks-config")
local Reference = require("./lib/api-reference")
local fs = require("@std/fs")
local process = require("@std/process")

assert(
	#process.args == 1 or (#process.args == 2 and process.args[2] == "--write"),
	"usage: generate-api.luau [--write]"
)
local path = Config.publicSurface.docs
for _, entry in fs.listDirectory("src/core") do
	if entry.type == "dir" and entry.name ~= "internal" then
		local system = "src/core/" .. entry.name .. ".luau"
		assert(fs.exists(system), "missing system entry: " .. system)
		assert(
			string.find(fs.readFileToString(system), "export type API =", 1, true) ~= nil,
			system .. " must export API"
		)
	end
end
local current = fs.readFileToString(path)
local boundary = string.find(current, "## Signature appendix\n", 1, true)
assert(boundary ~= nil, "API reference requires a hand-written guide and a signature appendix")
local expected = string.sub(current, 1, assert(boundary) - 1) .. Reference.render(Config.publicSurface.packages)
if process.args[2] == "--write" then
	fs.writeStringToFile(path, expected)
else
	assert(
		fs.exists(path) and string.gsub(fs.readFileToString(path), "\r\n", "\n") == expected,
		"API reference is stale; run lute run tools/generate-api.luau --write"
	)
end
print("API reference: current")
