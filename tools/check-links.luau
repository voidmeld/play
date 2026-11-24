--!strict

local fs = require("@std/fs")
local process = require("@std/process")

local function fail(message: string): never
	error("play links: " .. message, 0)
end

local function run(arguments: { string }): string
	local result = process.run(arguments)
	if not result.ok then
		fail(("command failed: %s\n%s"):format(table.concat(arguments, " "), result.stderr))
	end
	return result.stdout
end

local function trackedFiles(): { string }
	local files: { string } = {}
	for path in string.gmatch(run({ "git", "ls-files", "--cached", "--others", "--exclude-standard" }), "[^\r\n]+") do
		if fs.exists(path) then
			table.insert(files, path)
		end
	end
	table.sort(files)
	return files
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			if #parts == 0 then
				fail("relative link escapes the repository: " .. path)
			end
			table.remove(parts)
		elseif part ~= "." and part ~= "" then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function decodeFragment(fragment: string): string
	return (
		string.gsub(fragment, "%%(%x%x)", function(hex: string): string
			return string.char(assert(tonumber(hex, 16)))
		end)
	)
end

local function slug(text: string): string
	text = string.lower(text)
	text = string.gsub(text, "<[^>]*>", "")
	text = string.gsub(text, "[`*_~]", "")
	text = string.gsub(text, "[^%w%s%-_]", "")
	return (string.gsub(text, "%s", "-"))
end

local function anchors(path: string, cache: { [string]: { [string]: boolean } }): { [string]: boolean }
	if cache[path] ~= nil then
		return cache[path]
	end
	local found: { [string]: boolean } = {}
	local used: { [string]: number } = {}
	local fenced = false
	for line in string.gmatch(fs.readFileToString(path) .. "\n", "([^\r\n]*)\r?\n") do
		if string.match(line, "^%s*```") or string.match(line, "^%s*~~~") then
			fenced = not fenced
		elseif not fenced then
			local heading = string.match(line, "^%s*#+%s+(.+)%s*$")
			if heading ~= nil then
				heading = string.gsub(heading, "%s+#+%s*$", "")
				local base = slug(heading)
				local count = used[base] or 0
				used[base] = count + 1
				found[if count == 0 then base else base .. "-" .. tostring(count)] = true
			end
		end
	end
	cache[path] = found
	return found
end

local function checkDestination(source: string, raw: string, cache: { [string]: { [string]: boolean } })
	local target = string.gsub(raw, "^%s*<([^>]+)>%s*$", "%1")
	target = string.match(target, "^([^%s]+)") or target
	if target == "" or string.match(target, "^[%a][%w+.-]*:") or string.sub(target, 1, 2) == "//" then
		return
	end
	local filePart, fragment = string.match(target, "^([^#]*)#?(.*)$")
	filePart = filePart or ""
	fragment = fragment or ""
	local destination = source
	if filePart ~= "" then
		destination = normalize((if dirname(source) == "" then "" else dirname(source) .. "/") .. (assert(filePart)))
		if fs.exists(destination) and fs.type(destination) == "dir" then
			if fragment == "" then
				return
			end
			destination ..= "/README.md"
		end
		if not fs.exists(destination) or fs.type(destination) ~= "file" then
			fail(("%s links to missing path %q"):format(source, assert(target)))
		end
	end
	if fragment ~= "" then
		if not string.match(destination, "%.md$") then
			fail(("%s links to an anchor in non-Markdown file %q"):format(source, assert(target)))
		end
		local wanted = string.lower(decodeFragment(assert(fragment)))
		if not anchors(destination, cache)[wanted] then
			fail(("%s links to missing anchor %q in %s"):format(source, assert(fragment), destination))
		end
	end
end

local function checkLinks(files: { string })
	local cache: { [string]: { [string]: boolean } } = {}
	for _, path in files do
		if string.match(path, "%.md$") then
			local fenced = false
			for line in string.gmatch(fs.readFileToString(path) .. "\n", "([^\r\n]*)\r?\n") do
				if string.match(line, "^%s*```") or string.match(line, "^%s*~~~") then
					fenced = not fenced
				elseif not fenced then
					for target in string.gmatch(line, "%b[]%(([^%)]+)%)") do
						checkDestination(path, target, cache)
					end
					local reference = string.match(line, "^%s*%[[^]]+%]:%s*(%S+)")
					if reference ~= nil then
						checkDestination(path, reference, cache)
					end
				end
			end
		end
	end
	print("links: tracked Markdown relative links and anchors resolve")
end

checkLinks(trackedFiles())
