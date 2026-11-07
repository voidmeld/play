--!strict

return table.freeze({
	verify = table.freeze({
		repository = "https://github.com/voidmeld/verify.git",
		commit = "4d6fe22a7b5261c4925889b3449fcf9e60d36f28",
		tree = "ee0a7007acbf7b4942eb785d3a2d703946848674",
		role = "verification",
		surfaces = table.freeze({ "src" }),
	}),
	compose = table.freeze({
		repository = "https://github.com/voidmeld/compose.git",
		commit = "9b7c21792d974bc02a6733f5235072584440fc1b",
		tree = "41cebb3a6e999f3cfcab29e70d5485c776e18696",
		role = "example",
		surfaces = table.freeze({ "src/core", "src/roblox" }),
	}),
	facet = table.freeze({
		repository = "https://github.com/josha/Facet.git",
		commit = "a75bd3e877f6752fc5a1260d7f7a4cefe71fef46",
		tree = "edce9f60fb18cfc20d7c66e059c19d31645242ef",
		role = "example",
		surfaces = table.freeze({ "src" }),
	}),
})
