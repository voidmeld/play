--!strict

return {
	package = {
		name = "voidmeld/play",
		version = "0.1.0",
		files = {
			"/src/**",
			"/tools/fixtures/**",
			"/docs/**",
			"/.agents/skills/play/**",
			"/README.md",
			"/CHANGELOG.md",
			"/LICENSE",
			"!*.verify.luau",
		},
		metadata = {
			description = "Reusable persistent-world game systems for Roblox, written in strict Luau.",
			license = "MIT",
			repository = "https://github.com/voidmeld/play",
			exports = {
				kernel = "src/kernel",
				core = "src/core/<family>",
				roblox = "src/roblox/<adapter>",
			},
		},
		dev_dependencies = {
			verify = {
				sourceKind = "github",
				source = "https://github.com/voidmeld/verify",
				rev = "2e8cedeb260dd61d29b6f4be51a5fc250254e80b",
			},
			compose = {
				sourceKind = "github",
				source = "https://github.com/voidmeld/compose",
				rev = "206648c0becb496919ca7af3855fc775bb96d900",
			},
			facet = {
				sourceKind = "github",
				source = "https://github.com/josha/Facet",
				rev = "b8352269efcf76a51951557997d9c151e30c8afa",
			},
		},
	},
}
