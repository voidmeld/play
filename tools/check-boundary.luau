--!strict
local Checks = require("../.lute/dependencies/verify/src/checks")
local Config = require("./checks-config")
local Finish = require("./lib/check-result")
Finish("check-boundary", Checks.boundary(Config.boundary))
local kernel = table.clone(Config.boundary)
kernel.root = "src/kernel"
kernel.allowMissing = false
kernel.rules = table.clone(kernel.rules)
for _, layer in { "core", "roblox", "client", "test%-scene" } do
	table.insert(
		kernel.rules,
		{ pattern = "[/@]" .. layer .. "[/\"']", why = "kernel must not import domain or host layers" }
	)
end
Finish("check-kernel-boundary", Checks.boundary(kernel))
