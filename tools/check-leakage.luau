--!strict

local fs = require("@std/fs")
local process = require("@lute/process")

local denylist = require("./lib/denylist")
local walk = require("./lib/walk")

local FILE_TYPES = { ".luau", ".lua", ".md", ".json", ".toml", ".txt", ".yml", ".yaml" }

local function main(): number
	local rules = denylist.leakage
	local violations: { string } = {}
	local scanned = 0

	local listed = process.run({ "git", "ls-files", "--cached", "--others", "--exclude-standard", "-z" })
	if not listed.ok then
		print("check-leakage: could not enumerate tracked source")
		return 1
	end
	for path in string.gmatch(listed.stdout, "[^%z]+") do
		if path == denylist.selfPath or path == "LICENSE" or not fs.exists(path) then
			continue
		end
		local textFile = false
		for _, suffix in FILE_TYPES do
			if string.sub(path, -#suffix) == suffix then
				textFile = true
				break
			end
		end
		if not textFile then
			continue
		end
		local contents = fs.readFileToString(path)
		scanned += 1
		for _, rule in rules do
			local offset = string.find(contents, rule.pattern)
			if offset ~= nil then
				table.insert(
					violations,
					("%s:%d: leakage (%s): %s"):format(
						path,
						walk.lineOf(contents, offset),
						rule.why,
						string.match(string.sub(contents, offset, offset + 40), "^[^\n]*") :: string
					)
				)
			end
		end
	end

	if #violations > 0 then
		print(("check-leakage: %d finding(s)"):format(#violations))
		for _, violation in violations do
			print("  " .. violation)
		end
		return 1
	end

	print(("check-leakage: ok (%d files, %d rules)"):format(scanned, #rules))
	return 0
end

local code = main()
if code ~= 0 then
	process.exit(code)
end
return nil
