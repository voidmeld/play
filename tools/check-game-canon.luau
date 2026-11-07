--!strict

local Checks = require("../.lute/dependencies/verify/src/checks")
local Config = require("./checks-config")
local Finish = require("./lib/check-result")
local findings = Checks.boundary(Config.canon)
for _, finding in Checks.boundary(Config.canonExamples) do
	table.insert(findings, finding)
end
Finish("check-game-canon", findings)
