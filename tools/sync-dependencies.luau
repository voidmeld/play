--!strict

local fs = require("@std/fs")
local process = require("@std/process")

local Lock = require("../dependencies.lock")

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

type Dependency = {
	read repository: string,
	read commit: string,
	read tree: string,
	read role: string,
	read surfaces: { string },
}

local function matches(path: string, dependency: Dependency): boolean
	if not fs.exists(path) then
		return false
	end
	local commitOk, commit = git(path, { "rev-parse", "HEAD" })
	local treeOk, tree = git(path, { "rev-parse", "HEAD^{tree}" })
	local statusOk, status = git(path, { "status", "--porcelain" })
	return commitOk and treeOk and statusOk and commit == dependency.commit and tree == dependency.tree and status == ""
end

local function source(name: string, dependency: Dependency): string
	local override = process.env[string.upper(name) .. "_SOURCE"]
	if override ~= nil and override ~= "" then
		return override
	end
	if fs.exists("../" .. name) then
		return "../" .. name
	end
	return dependency.repository
end

local function sync(name: string, dependency: Dependency)
	local cache = ".lute/dependencies/" .. name
	if matches(cache, dependency) then
		return
	end
	if fs.exists(cache) then
		fs.removeDirectory(cache, { recursive = true })
	end
	fs.createDirectory(".lute/dependencies", { makeParents = true })
	local cloned = process.run({ "git", "clone", "--quiet", "--no-checkout", source(name, dependency), cache })
	assert(cloned.ok, "sync-dependencies: clone failed: " .. cloned.stderr)
	local checkedOut = process.run({ "git", "-C", cache, "checkout", "--quiet", "--detach", dependency.commit })
	assert(checkedOut.ok, "sync-dependencies: the pinned commit is not available: " .. checkedOut.stderr)
	process.run({ "git", "-C", cache, "remote", "set-url", "origin", dependency.repository })
	assert(matches(cache, dependency), "sync-dependencies: the checkout does not match the pinned commit and tree")
end

local dependencies: { [string]: Dependency } = { verify = Lock.verify, compose = Lock.compose, facet = Lock.facet }
for name, dependency in dependencies do
	assert(dependency.role == "example" or dependency.role == "verification", "development dependency role required")
	if process.args[2] == "--check" then
		assert(matches(".lute/dependencies/" .. name, dependency), "sync-dependencies: cache mismatch: " .. name)
	else
		sync(name, dependency)
	end
	for _, surface in dependency.surfaces do
		assert(fs.exists(".lute/dependencies/" .. name .. "/" .. surface), "dependency surface missing: " .. surface)
	end
	print("sync-dependencies: " .. name .. " (" .. dependency.role .. ") at " .. dependency.commit)
end
