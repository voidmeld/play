--!strict

local fs = require("@std/fs")
local process = require("@std/process")

local Lock = require("../dependencies.lock")

local CACHE = ".lute/dependencies/verify"
assert(
	#process.args == 1 or (#process.args == 2 and process.args[2] == "--check"),
	"usage: sync-dependencies.luau [--check]"
)

local function git(path: string, arguments: { string }): (boolean, string)
	local argv = { "git", "-C", path }
	for _, argument in arguments do
		table.insert(argv, argument)
	end
	local result = process.run(argv)
	return result.ok, string.match(result.stdout, "^%s*(.-)%s*$") or ""
end

local function matches(path: string): boolean
	if not fs.exists(path) then
		return false
	end
	local commitOk, commit = git(path, { "rev-parse", "HEAD" })
	local treeOk, tree = git(path, { "rev-parse", "HEAD^{tree}" })
	local statusOk, status = git(path, { "status", "--porcelain" })
	return commitOk
		and treeOk
		and statusOk
		and commit == Lock.verify.commit
		and tree == Lock.verify.tree
		and status == ""
end

local function source(): string
	local override = process.env["VERIFY_SOURCE"]
	if override ~= nil and override ~= "" then
		return override
	end
	if fs.exists("../verify") then
		return "../verify"
	end
	return Lock.verify.repository
end

local function sync()
	if matches(CACHE) then
		return
	end
	if fs.exists(CACHE) then
		fs.removeDirectory(CACHE, { recursive = true })
	end
	fs.createDirectory(".lute/dependencies", { makeParents = true })
	local cloned = process.run({ "git", "clone", "--quiet", "--no-checkout", source(), CACHE })
	assert(cloned.ok, "sync-dependencies: clone failed: " .. cloned.stderr)
	local checkedOut = process.run({ "git", "-C", CACHE, "checkout", "--quiet", "--detach", Lock.verify.commit })
	assert(checkedOut.ok, "sync-dependencies: the pinned commit is not available: " .. checkedOut.stderr)
	process.run({ "git", "-C", CACHE, "remote", "set-url", "origin", Lock.verify.repository })
	assert(matches(CACHE), "sync-dependencies: the checkout does not match the pinned commit and tree")
end

if process.args[2] == "--check" then
	assert(matches(CACHE), "sync-dependencies: the dependency cache does not match the pinned commit and tree")
else
	sync()
end
print("sync-dependencies: verify at " .. Lock.verify.commit)
