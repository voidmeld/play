--!strict
local Checks = require("../.lute/dependencies/verify/src/checks")
local Config = require("./checks-config")
local Finish = require("./lib/check-result")
Finish("check-leakage", Checks.leakage(Config.leakage))
