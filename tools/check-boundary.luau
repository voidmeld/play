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
for _, root in { "src/core", "src/kernel", "src/roblox", "src/world" } do
	Finish(
		"check-ui-boundary",
		Checks.boundary({
			root = root,
			allowMissing = true,
			rules = {
				{ pattern = "%f[%w_]Compose%f[^%w_]", why = "UI dependencies belong in examples" },
				{ pattern = "%f[%w_]Facet%f[^%w_]", why = "UI dependencies belong in examples" },
				{ pattern = "[/\"']compose[/\"']", why = "UI dependencies belong in examples" },
				{ pattern = "[/\"']facet[/\"']", why = "UI dependencies belong in examples" },
			},
		})
	)
end
