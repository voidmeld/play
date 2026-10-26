--!strict

local fs = require("@std/fs")
local process = require("@lute/process")

local TemporaryDirectory = require("./lib/temporary-directory")

local function git(...: string): (boolean, string)
	local argv = { "git" }
	for index = 1, select("#", ...) do
		table.insert(argv, (select(index, ...)))
	end
	local result = process.run(argv)
	return result.ok, (string.gsub(result.stdout, "%s+$", ""))
end

local function main(): number
	local hasHead, head = git("rev-parse", "HEAD")
	if not hasHead then
		print("check-clean-clone: no commit at HEAD yet; nothing to clone")
		return 1
	end

	local statusOk, dirty = git("status", "--porcelain")
	if not statusOk or dirty ~= "" then
		print("check-clean-clone: working tree is not clean, so the clone would not match what you are testing:")
		for line in string.gmatch(dirty, "[^\n]+") do
			print("  " .. line)
		end
		return 1
	end

	local source = process.cwd()
	local dependencySourceRoot = source .. "/.lute/dependencies"
	if not fs.exists(dependencySourceRoot) then
		print("check-clean-clone: the verified dependency cache is absent; run lute run tools/sync-dependencies.luau")
		return 1
	end

	local outcome = TemporaryDirectory.run(TemporaryDirectory.root(), "play-clean-clone", function(temporary)
		local cloned = process.run({ "git", "clone", "--quiet", "--no-local", source, temporary })
		if not cloned.ok then
			print("check-clean-clone: clone failed:\n" .. cloned.stderr)
			return 1
		end

		local checkedOut = process.run({ "git", "-C", temporary, "checkout", "--quiet", head })
		if not checkedOut.ok then
			print("check-clean-clone: could not check out HEAD in the clone:\n" .. checkedOut.stderr)
			return 1
		end

		print(("check-clean-clone: running the fast gate in %s at %s"):format(temporary, head))
		local environment: { [string]: string } = {}
		for name, value in process.env do
			environment[name] = value
		end
		environment.VERIFY_SOURCE = dependencySourceRoot .. "/verify"
		local gate = process.run(
			{ "lute", "run", "tools/gate.luau", "--tier", "fast" },
			{ cwd = temporary, stdio = "inherit", env = environment }
		)

		if not gate.ok then
			print("check-clean-clone: the fresh clone does not pass its own gate")
			return 1
		end

		return 0
	end)
	if outcome ~= 0 then
		return outcome
	end

	print("check-clean-clone: ok")
	return 0
end

local code = main()
if code ~= 0 then
	process.exit(code)
end
return nil
