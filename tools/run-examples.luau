--!strict

local process = require("@std/process")

for _, path in { "tools/quickstart.luau", "tools/examples/input-bindings.luau", "tools/examples/thumbstick.luau" } do
	local result = process.run({ "lute", "run", path })
	assert(result.ok, result.stdout .. result.stderr)
	print(result.stdout)
end
