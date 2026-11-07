--!strict

local fs = require("@std/fs")
local process = require("@std/process")

local LintBatches = require("./lib/lint-batches")

local listed = process.run({ "git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.luau" })
assert(listed.ok, listed.stderr)
local files: { string } = {}
for path in string.gmatch(listed.stdout, "[^\r\n]+") do
	if fs.exists(path) then
		table.insert(files, path)
	end
end
table.sort(files)

local ok, report = LintBatches.run({ "lute", "lint", "--verbose", "-c", "lint.config.luau" }, files, function(argv)
	local result = process.run(argv)
	return { ok = result.ok, stdout = result.stdout, stderr = result.stderr }
end)

if report ~= "" then
	print(report)
end
if not ok then
	process.exit(1)
end
