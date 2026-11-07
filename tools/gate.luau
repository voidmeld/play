--!strict

local process = require("@std/process")

local fs = require("@std/fs")

local USAGE =
	"usage: lute run tools/gate.luau [--only producer]... [--tier name]... [--case id]... [--file spec]... [--name text] [--rerun] [--explain id] [--list]"
local DIRECTORY = ".lute/tmp/play-gate"
local flags: { string } = {}
for index = 2, #process.args do
	table.insert(flags, process.args[index])
end

if #flags == 0 then
	local status = process.run({ "git", "status", "--porcelain" })
	if not status.ok or string.match(status.stdout, "%S") ~= nil then
		print(
			"gate: full candidate requires a clean committed HEAD; use focused checks while editing, then commit before the full gate"
		)
		process.exit(1)
	end
end

local synced = process.run({ "lute", "run", "tools/sync-dependencies.luau" })
if not synced.ok then
	error(synced.stdout .. synced.stderr, 0)
end

local Gate = require("../.lute/dependencies/verify/src/gate")
local Lute = require("../.lute/dependencies/verify/src/lute")

local listed = process.run({ "git", "ls-files", "--cached", "--others", "--exclude-standard", "--", "*.luau" })
assert(listed.ok, listed.stderr)
local luauFiles: { string } = {}
for path in string.gmatch(listed.stdout, "[^\r\n]+") do
	if fs.exists(path) then
		table.insert(luauFiles, path)
	end
end
table.sort(luauFiles)

local specs = require("./test-manifest")
assert(#specs > 0, "test corpus is empty")

local analyze: { string } =
	{ "luau-lsp", "analyze", "--platform=standard", "--flag:LuauSolverV2=true", "--ignore=**/.lute/**" }
local format: { string } = { "stylua", "--check" }
for _, path in luauFiles do
	table.insert(analyze, path)
	table.insert(format, path)
end

local function command(id: string, argv: { string }): Gate.ProducerDraft
	return { id = id, kind = "command", argv = argv, tier = "fast" }
end

local function script(id: string, path: string): Gate.ProducerDraft
	return command(id, { "lute", "run", path })
end

local producers: { Gate.ProducerDraft } = {
	script("links", "tools/check-links.luau"),
	{
		id = "war-benchmark",
		kind = "benchmark",
		benchmark = require("./war-benchmark"),
		tier = "profile",
		why = "measured-only synthetic 200-player war tick module costs",
	},
	script("type-policy", "tools/check-no-any.luau"),
	command("types", analyze),
	script("test-manifest", "tools/check-test-manifest.luau"),
	script("spec-style", "tools/check-spec-style.luau"),
	script("boundary", "tools/check-boundary.luau"),
	script("game-canon", "tools/check-game-canon.luau"),
	script("provenance", "tools/check-provenance.luau"),
	script("leakage", "tools/check-leakage.luau"),
	script("public-surface", "tools/check-public-surface.luau"),
	script("api-reference", "tools/generate-api.luau"),
	script("examples", "tools/run-examples.luau"),
	{
		id = "specs",
		kind = "tests",
		worker = "tools/worker.luau",
		locators = specs,
		why = "the specifications of the Play systems and fake hosts",
		deadlineSeconds = 1800,
		tier = "fast",
	},
	script("comments", "tools/check-code-comments.luau"),
	command("format", format),
	script("lint", "tools/run-lint.luau"),
	command("verify-check", {
		"lute",
		"run",
		".lute/dependencies/verify/tools/verify-check.luau",
		"--ruleset",
		"generic",
		"src",
		"tools",
	}),
	{
		id = "clean-clone",
		kind = "command",
		argv = { "lute", "run", "tools/check-clean-clone.luau" },
		exclusive = true,
		tier = "slow",
		deadlineSeconds = 1800,
		why = "a fresh clone of HEAD passes the fast gate without working-tree state",
	},
}
local exitCode = Lute.gate.cli({
	id = "play-gate",
	producers = producers,
	policy = { commandDeadlineSeconds = 900, deadlineSeconds = 3600 },
}, flags, { usage = USAGE, options = { directory = DIRECTORY } })
if exitCode ~= 0 then
	process.exit(exitCode)
end
