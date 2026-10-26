--!strict

local fs = require("@std/fs")
local process = require("@lute/process")

local denylist = require("./lib/denylist")
local walk = require("./lib/walk")

local function main(): number
	if not fs.exists("src/core") then
		print("check-boundary: skipped (src/core does not exist yet)")
		return 0
	end

	local violations: { string } = {}
	local scanned = 0

	for _, file in walk.files("src/core", { ".luau" }) do
		if string.match(file.path, "%.verify%.luau$") then
			continue
		end
		scanned += 1
		for _, rule in denylist.boundary do
			local exemption = if rule.exempt ~= nil then rule.exempt[file.path] else nil
			if exemption ~= nil then
				continue
			end
			local offset = string.find(file.contents, rule.pattern)
			if offset ~= nil then
				local excerpt = string.match(string.sub(file.contents, offset, offset + 60), "^[^\n]*") :: string
				table.insert(
					violations,
					("%s:%d: host-neutrality boundary: %s\n    matched: %s"):format(
						file.path,
						walk.lineOf(file.contents, offset),
						rule.why,
						excerpt
					)
				)
			end
		end
	end

	if scanned == 0 then
		print("check-boundary: no core files found under src/core")
		return 1
	end

	if #violations > 0 then
		print(("check-boundary: %d violation(s) in src/core"):format(#violations))
		for _, violation in violations do
			print("  " .. violation)
		end
		return 1
	end

	print(("check-boundary: ok (%d core files, %d rules)"):format(scanned, #denylist.boundary))
	return 0
end

local code = main()
if code ~= 0 then
	process.exit(code)
end
return nil
