--!strict

local fs = require("@std/fs")
local process = require("@lute/process")

local Lute = require("../.lute/dependencies/verify/src/lute")

local MANIFEST_PATH = "tools/test-manifest.luau"

local function discover(): { string }
	return Lute.corpus.discover({
		listDir = fs.listDirectory,
		rules = {
			{ root = "src", pattern = "%.verify%.luau$" },
			{ root = "tools", pattern = "%.verify%.luau$" },
		},
		order = "walk",
	})
end

local function render(sources: { string }): string
	local lines: { string } = { "--!strict", "", "return table.freeze {" }
	for _, source in sources do
		table.insert(lines, ("\t%q,"):format(source))
	end
	table.insert(lines, "}")
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

local function main(): number
	local write = false
	for index = 2, #process.args do
		local argument = process.args[index]
		if argument == "--write" then
			write = true
		else
			error(("check-test-manifest: unrecognised argument %q"):format(tostring(argument)), 0)
		end
	end

	local found = discover()
	if write then
		fs.writeStringToFile(MANIFEST_PATH, render(found))
		process.run({ "stylua", MANIFEST_PATH })
		print(("check-test-manifest: wrote %s (%d sources)"):format(MANIFEST_PATH, #found))
		return 0
	end

	local committed = (require("./test-manifest") :: unknown) :: { string }
	local findings: { string } = {}
	local named: { [string]: boolean } = {}
	local onDisk: { [string]: boolean } = {}
	for _, source in found do
		onDisk[source] = true
	end
	for index, source in committed do
		named[source] = true
		if not onDisk[source] then
			table.insert(findings, ("manifest names %s, which is not on disk"):format(source))
		elseif found[index] ~= source then
			table.insert(
				findings,
				("%s is entry %d in the manifest and %s is entry %d on disk; order is part of a reproducible run"):format(
					source,
					index,
					tostring(found[index]),
					index
				)
			)
		end
	end
	for _, source in found do
		if not named[source] then
			table.insert(findings, ("%s is on disk and not in the manifest"):format(source))
		end
	end

	if #findings > 0 then
		print(("check-test-manifest: %d finding(s); regenerate with --write"):format(#findings))
		for _, finding in findings do
			print("  " .. finding)
		end
		return 1
	end

	print(("check-test-manifest: %s matches disk (%d sources)"):format(MANIFEST_PATH, #committed))
	return 0
end

local code = main()
if code ~= 0 then
	process.exit(code)
end
return nil
