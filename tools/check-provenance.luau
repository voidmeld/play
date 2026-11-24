--!strict
local Checks = require("@verify/src/checks")
local Config = require("./checks-config")
local Finish = require("./lib/check-result")
Finish("check-provenance", Checks.provenance(Config.provenance))
