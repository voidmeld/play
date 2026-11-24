--!strict

local Clone = require("@verify/src/checks/clean-clone")
local Comments = require("@verify/src/checks/comments")
local Manifest = require("@verify/src/checks/manifest")
local Policy = require("./checks-policy")
local Provenance = require("@verify/src/checks/provenance")
local Repository = require("@verify/src/checks/repository")
local Surface = require("@verify/src/checks/surface")
local process = require("@std/process")

local Walk = require("@verify/src/checks/walk")

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
		roots = { "src", "tools", "examples" },
		files = { "pkg.luau", "lint.config.luau", ".config.luau" },
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
			{ root = "examples", pattern = "%.verify%.luau$" },
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
	canon: Repository.Boundary,
	canonExamples: Repository.Boundary,
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
		canon = { root = "src", rules = Policy.canon },
		canonExamples = { root = "examples/world", rules = Policy.canon },
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
			lock = "pkg.lock.luau",
			dependencyCommand = { "lute", "pkg", "install", "--locked" },
			root = ".",
			skip = { ".git/", "build/", "bench/results/", ".lute/", ".lpm/" },
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
			requiredPaths = { "pkg.lock.luau" },
		},
		noAny = { untracked = true, exclude = { ["pkg.lock.luau"] = true } },
		specStyle = { untracked = true },
	}

return config
