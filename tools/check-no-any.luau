--!strict

do
	local fs = require "@std/fs"
	local process = require "@std/process"
	local parser = require "@std/syntax/parser"
	local visitor = require "@std/syntax/visitor"
	local listed =
		process.run { "git", "ls-files", "--cached", "--others", "--exclude-standard", "-z", "--", "*.luau", "*.lua" }
	assert(listed.ok, listed.stderr)
	local failures = 0
	local seen: { [string]: boolean } = {}
	for path in string.gmatch(listed.stdout, "[^%z]+") do
		if seen[path] or not fs.exists(path) then
			continue
		end
		seen[path] = true
		local parsed = parser.parse(fs.readFileToString(path))
		local walk = visitor.create()
		walk.visitExprTypeAssertion = function(node)
			print(
				("%s:%d: type casts are forbidden; fix the contract or narrow the value"):format(
					path,
					node.operator.location.beginLine
				)
			)
			failures += 1
			return true
		end
		visitor.visit(parsed.root, walk)
	end
	assert(failures == 0, ("type policy: %d forbidden casts"):format(failures))
end
local Checks = require("../.lute/dependencies/verify/src/checks")
local Config = require("./checks-config")
local Finish = require("./lib/check-result")
Finish("check-no-any", Checks.noAny(Config.noAny))
