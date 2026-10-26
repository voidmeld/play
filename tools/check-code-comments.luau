--!strict

local fs = require "@std/fs"
local process = require "@lute/process"

local walk = require "./lib/walk"

local ROOTS = { "src", "tools" }
local FILES = { "dependencies.lock.luau", "lint.config.luau" }
local CONFIG_FILES = { ".styluaignore", "rokit.toml", "stylua.toml" }

local function longBracket(source: string, index: number): (number?, string?)
	if string.byte(source, index) ~= string.byte "[" then
		return nil, nil
	end
	local cursor = index + 1
	while string.byte(source, cursor) == string.byte "=" do
		cursor += 1
	end
	if string.byte(source, cursor) ~= string.byte "[" then
		return nil, nil
	end
	return cursor + 1, "]" .. string.rep("=", cursor - index - 1) .. "]"
end

local function lineEnd(source: string, index: number): number
	local ending = string.find(source, "\n", index, true)
	return if ending == nil then #source + 1 else ending
end

local function isDirective(source: string, index: number): boolean
	local start = index
	while start > 1 and string.byte(source, start - 1) ~= string.byte "\n" do
		start -= 1
	end
	if string.match(string.sub(source, start, index - 1), "^[ \t]*$") == nil then
		return false
	end
	local line = string.sub(source, index, lineEnd(source, index) - 1)
	return string.match(line, "^%-%-![A-Za-z]+") ~= nil or string.match(line, "^%-%-# selene") ~= nil
end

local function comments(source: string): { number }
	local found: { number } = {}
	local index = 1
	while index <= #source do
		local byte = string.byte(source, index)
		if byte == string.byte "'" or byte == string.byte '"' or byte == string.byte "`" then
			local quote = byte
			index += 1
			while index <= #source do
				local current = string.byte(source, index)
				if current == string.byte "\\" then
					index += 2
				elseif current == quote then
					index += 1
					break
				else
					index += 1
				end
			end
		elseif byte == string.byte "[" then
			local body, close = longBracket(source, index)
			if body == nil or close == nil then
				index += 1
			else
				local ending = string.find(source, close, body, true)
				index = if ending == nil then #source + 1 else ending + #close
			end
		elseif byte == string.byte "-" and string.byte(source, index + 1) == string.byte "-" then
			if not isDirective(source, index) then
				table.insert(found, index)
			end
			local body, close = longBracket(source, index + 2)
			if body == nil or close == nil then
				index = lineEnd(source, index)
			else
				local ending = string.find(source, close, body, true)
				index = if ending == nil then #source + 1 else ending + #close
			end
		else
			index += 1
		end
	end
	return found
end

local function hashComments(source: string): { number }
	local found: { number } = {}
	local index = 1
	while index <= #source do
		local byte = string.byte(source, index)
		if byte == string.byte "'" or byte == string.byte '"' then
			local quote = byte
			index += 1
			while index <= #source do
				local current = string.byte(source, index)
				if current == string.byte "\\" then
					index += 2
				elseif current == quote then
					index += 1
					break
				elseif current == string.byte "\n" then
					break
				else
					index += 1
				end
			end
		elseif byte == string.byte "#" then
			if index ~= 1 or string.byte(source, index + 1) ~= string.byte "!" then
				table.insert(found, index)
			end
			index = lineEnd(source, index)
		else
			index += 1
		end
	end
	return found
end

local function withoutHashComments(source: string, starts: { number }): string
	local drop: { [number]: boolean } = {}
	for _, start in starts do
		drop[start] = true
	end
	local pieces: { string } = {}
	local cursor = 1
	for _, start in starts do
		local lineStart = start
		while lineStart > 1 and string.byte(source, lineStart - 1) ~= string.byte "\n" do
			lineStart -= 1
		end
		local prefix = string.sub(source, lineStart, start - 1)
		local finish = lineEnd(source, start)
		if string.match(prefix, "^[ \t]*$") ~= nil then
			table.insert(pieces, string.sub(source, cursor, lineStart - 1))
			cursor = math.min(finish + 1, #source + 1)
		else
			table.insert(pieces, string.sub(source, cursor, lineStart - 1) .. (string.gsub(prefix, "%s+$", "")))
			cursor = finish
		end
	end
	table.insert(pieces, string.sub(source, cursor))
	return table.concat(pieces)
end

local function withoutComments(source: string, starts: { number }): string
	local pieces: { string } = {}
	local cursor = 1
	for _, start in starts do
		table.insert(pieces, string.sub(source, cursor, start - 1))
		local body, close = longBracket(source, start + 2)
		local finish = lineEnd(source, start)
		if body ~= nil and close ~= nil then
			local ending = string.find(source, close, body, true)
			finish = if ending == nil then #source + 1 else ending + #close
		end
		local removed = string.sub(source, start, finish - 1)
		local blank = string.gsub(removed, "[^\n]", " ")
		table.insert(pieces, blank)
		cursor = finish
	end
	table.insert(pieces, string.sub(source, cursor))
	return table.concat(pieces)
end

local function parse(): boolean
	if #process.args == 1 then
		return false
	end
	if #process.args == 2 and process.args[2] == "--write" then
		return true
	end
	error "check-code-comments: expected no argument or --write"
end

local function main(): number
	local write = parse()
	local violations: { string } = {}
	local scanned = 0
	local function check(path: string, contents: string)
		scanned += 1
		local starts = comments(contents)
		if #starts == 0 then
			return
		end
		if write then
			fs.writeStringToFile(path, withoutComments(contents, starts))
		end
		for _, start in starts do
			table.insert(violations, ("%s:%d"):format(path, walk.lineOf(contents, start)))
		end
	end
	local function checkConfig(path: string, contents: string)
		scanned += 1
		local starts = hashComments(contents)
		if #starts == 0 then
			return
		end
		if write then
			fs.writeStringToFile(path, withoutHashComments(contents, starts))
		end
		for _, start in starts do
			table.insert(violations, ("%s:%d"):format(path, walk.lineOf(contents, start)))
		end
	end
	for _, path in FILES do
		if fs.exists(path) then
			check(path, fs.readFileToString(path))
		end
	end
	for _, path in CONFIG_FILES do
		if fs.exists(path) then
			checkConfig(path, fs.readFileToString(path))
		end
	end
	for _, root in ROOTS do
		for _, file in walk.files(root, { ".luau" }) do
			check(file.path, file.contents)
		end
	end
	if write then
		print(("check-code-comments: removed %d comment(s) from %d source file(s)"):format(#violations, scanned))
		return 0
	end
	if #violations > 0 then
		print(("check-code-comments: %d prohibited comment(s)"):format(#violations))
		for _, violation in violations do
			print("  " .. violation)
		end
		return 1
	end
	print(("check-code-comments: ok (%d source files)"):format(scanned))
	return 0
end

local code = main()
if code ~= 0 then
	process.exit(code)
end
return nil
