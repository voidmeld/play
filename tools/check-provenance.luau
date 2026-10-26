--!strict

local fs = require("@std/fs")
local process = require("@lute/process")

local walk = require("./lib/walk")

local FOREIGN_DIRECTORIES = {
	"vendor",
	"third_party",
	"third-party",
	"node_modules",
	"Packages",
	"DevPackages",
	"bench/frameworks",
}

local DEPENDENCY_DESCRIPTORS = {
	"manifest.json",
	"package.json",
	"package-lock.json",
	"wally.toml",
	"wally.lock",
	"rotriever.toml",
}

local EXPECTED_NOTICES: { [string]: string } = {
	LICENSE = "Play's MIT license grant",
}
local LICENCE_NAMES = { "LICENSE", "LICENCE", "LICENSE.md", "LICENCE.md", "COPYING", "NOTICE", "NOTICE.md" }
local READABLE = { ".luau", ".lua", ".md", ".toml", ".json", ".yml", ".yaml", ".sh", ".py" }
local SKIP = { ".git/", "build/", "bench/results/", ".lute/" }
local SCRIPT_EXCEPTIONS: { [string]: string } = {}

local function basename(path: string): string
	return string.match(path, "([^/]+)$") or path
end

local function isSkipped(path: string): boolean
	for _, prefix in SKIP do
		if string.sub(path, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function skipDirectory(path: string, kind: string): boolean
	return kind == "dir" and isSkipped(path .. "/")
end

local function main(): number
	local findings: { string } = {}
	local function fail(message: string)
		table.insert(findings, message)
	end

	for _, directory in FOREIGN_DIRECTORIES do
		if fs.exists(directory) then
			fail(("%s/ exists; dependencies belong in the ignored cache, not this repository"):format(directory))
		end
	end

	if not fs.exists("dependencies.lock.luau") then
		fail("dependencies.lock.luau is absent")
	else
		local dependencyCheck = process.run({ "lute", "run", "tools/sync-dependencies.luau", "--check" })
		if not dependencyCheck.ok then
			fail("the dependency cache does not match the committed lock: " .. dependencyCheck.stdout)
		end
	end

	local paths: { string } = {}
	for _, path in walk.pathsSkipping(".", READABLE, skipDirectory) do
		local normalised = string.gsub(path, "^%./", "")
		if not isSkipped(normalised) then
			table.insert(paths, normalised)
		end
	end
	for _, name in LICENCE_NAMES do
		if fs.exists(name) then
			table.insert(paths, name)
		end
	end

	local seen: { [string]: true } = {}
	local licences: { string } = {}
	local checked = 0
	for _, path in paths do
		if seen[path] then
			continue
		end
		seen[path] = true
		checked += 1

		local name = basename(path)
		if string.match(name, "%.py$") then
			fail(("%s: Python is prohibited"):format(path))
		elseif string.match(name, "%.sh$") and SCRIPT_EXCEPTIONS[path] == nil then
			fail(("%s: use Lute Luau or document why Lute cannot perform this job"):format(path))
		end
		for _, descriptor in DEPENDENCY_DESCRIPTORS do
			if name == descriptor then
				fail(("%s: ungoverned dependency descriptor; dependencies use dependencies.lock.luau"):format(path))
			end
		end
		for _, licenceName in LICENCE_NAMES do
			if name == licenceName then
				table.insert(licences, path)
				break
			end
		end
	end

	for _, path in licences do
		if EXPECTED_NOTICES[path] == nil then
			fail(
				("%s: an unaccounted license or notice; Play carries only its reviewed MIT grant and required notices"):format(
					path
				)
			)
		end
	end
	for path, why in EXPECTED_NOTICES do
		if not fs.exists(path) then
			fail(("%s is missing (%s)"):format(path, why))
		elseif #fs.readFileToString(path) < 40 then
			fail(("%s exists but is empty"):format(path))
		end
	end
	if fs.exists("LICENSE") then
		local grant = fs.readFileToString("LICENSE")
		if string.sub(grant, 1, 12) ~= "MIT License\n" then
			fail("LICENSE is not the reviewed MIT grant")
		end
		if string.find(grant, "Copyright (c) 2026 voidmeld", 1, true) == nil then
			fail("LICENSE does not name the reviewed copyright holder")
		end
		if
			string.find(grant, "Permission is hereby granted, free of charge, to any person obtaining a copy", 1, true)
			== nil
		then
			fail("LICENSE does not contain the MIT permission grant")
		end
	end
	for path, why in SCRIPT_EXCEPTIONS do
		if not fs.exists(path) then
			fail(("%s is a stale script exception (%s)"):format(path, why))
		elseif #why < 20 then
			fail(("%s has no meaningful justification for bypassing Lute Luau"):format(path))
		end
	end
	if #findings > 0 then
		print(("check-provenance: %d finding(s)"):format(#findings))
		for _, finding in findings do
			print("  " .. finding)
		end
		return 1
	end

	print(
		("check-provenance: ok (%d file(s), dependencies lock-resolved outside the repository, no foreign source tree, reviewed MIT grant, %d required license/notice file(s))"):format(
			checked,
			#licences
		)
	)
	return 0
end

local code = main()
if code ~= 0 then
	process.exit(code)
end
return nil
