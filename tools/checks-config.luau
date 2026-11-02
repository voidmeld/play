--!strict

local Clone = require("../.lute/dependencies/verify/src/checks/clean-clone")
local Comments = require("../.lute/dependencies/verify/src/checks/comments")
local Manifest = require("../.lute/dependencies/verify/src/checks/manifest")
local Policy = require("./checks-policy")
local Provenance = require("../.lute/dependencies/verify/src/checks/provenance")
local Repository = require("../.lute/dependencies/verify/src/checks/repository")
local Surface = require("../.lute/dependencies/verify/src/checks/surface")
local process = require("@std/process")

local Walk = require("../.lute/dependencies/verify/src/checks/walk")

local function writeRequested(): boolean
	local write = false
	for index = 2, #process.args do
		assert(process.args[index] == "--write", "expected no arguments or --write")
		write = true
	end
	return write
end

local function comments(): Comments.Config
	return {
		roots = { "src", "tools" },
		files = { "dependencies.lock.luau", "lint.config.luau" },
		configFiles = { ".styluaignore", "rokit.toml", "stylua.toml" },
		allowed = { "^%-%-![A-Za-z]+", "^%-%-# selene" },
		lineDirectives = true,
		write = writeRequested(),
	}
end

local function manifest(): Manifest.Config
	local write = writeRequested()
	return {
		path = "tools/test-manifest.luau",
		rules = {
			{ root = "src", pattern = "%.verify%.luau$" },
			{ root = "tools", pattern = "%.verify%.luau$" },
		},
		write = write,
		entries = if write then nil else require("./test-manifest"),
		format = function(path)
			local result = process.run({ "stylua", path })
			assert(result.ok, result.stderr)
		end,
	}
end

local packages: { Surface.Package } = {}
for _, file in Walk.paths("src", { ".luau" }) do
	if string.match(file, "%.verify%.luau$") == nil and string.find(file, "/internal/", 1, true) == nil then
		local module = string.sub(file, 1, -6)
		table.insert(packages, {
			prefix = string.gsub(string.sub(module, 5), "/", "."),
			entry = file,
			load = function(): unknown
				local ok, value = pcall(require, "../" .. module)
				assert(ok, tostring(value))
				return value
			end,
		})
	end
end

local config: {
	boundary: Repository.Boundary,
	leakage: Repository.Scan,
	provenance: Provenance.Config,
	comments: () -> Comments.Config,
	manifest: () -> Manifest.Config,
	publicSurface: Surface.Config,
	cleanClone: Clone.Config,
	noAny: Repository.Selection,
	specStyle: Repository.Selection,
} =
	{
		boundary = {
			root = "src/core",
			allowMissing = true,
			exclude = "%.verify%.luau$",
			rules = Policy.boundary,
		},
		leakage = {
			untracked = true,
			suffixes = { ".luau", ".lua", ".md", ".json", ".toml", ".txt", ".yml", ".yaml" },
			exclude = { [Policy.selfPath] = true, LICENSE = true },
			rules = Policy.leakage,
			allowedLiterals = {},
		},
		provenance = {
			forbiddenPaths = {
				"vendor",
				"third_party",
				"third-party",
				"node_modules",
				"Packages",
				"DevPackages",
				"bench/frameworks",
			},
			license = "LICENSE",
			licensePrefix = "MIT License\n",
			licenseFragments = {
				"Copyright (c) 2026 voidmeld",
				"Permission is hereby granted, free of charge, to any person obtaining a copy",
			},
			lock = "dependencies.lock.luau",
			dependencyCommand = { "lute", "run", "tools/sync-dependencies.luau", "--check" },
			root = ".",
			skip = { ".git/", "build/", "bench/results/", ".lute/" },
			suffixes = { ".luau", ".lua", ".md", ".toml", ".json", ".yml", ".yaml", ".sh", ".py" },
			descriptors = {
				"manifest.json",
				"package.json",
				"package-lock.json",
				"wally.toml",
				"wally.lock",
				"rotriever.toml",
			},
			noticeNames = { "LICENSE", "LICENCE", "LICENSE.md", "LICENCE.md", "COPYING", "NOTICE", "NOTICE.md" },
			expectedNotices = { LICENSE = "Play's MIT license grant" },
			scriptExceptions = {},
			forbiddenSuffixes = { ".py" },
			justifiedSuffixes = { ".sh" },
		},
		comments = comments,
		manifest = manifest,
		publicSurface = { docs = "docs/api.md", packages = packages, includeTypes = true },
		cleanClone = {
			prefix = "play-clean-clone",
			command = { "lute", "run", "tools/gate.luau", "--tier", "fast" },
			env = { VERIFY_SOURCE = tostring(process.cwd()) .. "/.lute/dependencies/verify" },
			requiredPaths = { ".lute/dependencies" },
		},
		noAny = { untracked = true },
		specStyle = { untracked = true },
	}

return config
