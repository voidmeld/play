--!strict

local Checks = require("../.lute/dependencies/verify/src/checks")
local Config = require("./checks-config")
local Finish = require("./lib/check-result")
local fs = require("@std/fs")

local findings = Checks.publicSurface(Config.publicSurface)
local docs = fs.readFileToString(Config.publicSurface.docs)
for _, package in Config.publicSurface.packages do
	for name in string.gmatch(fs.readFileToString(package.entry), "export%s+type%s+([%w_]+)") do
		local qualified = package.prefix .. "." .. name
		if string.find(docs, "`" .. qualified .. "`", 1, true) == nil then
			table.insert(findings, qualified .. " is an exported type but undocumented")
		end
	end
end
table.sort(findings)
Finish("check-public-surface", findings)
