--!strict

local Denylist = require("../.lute/dependencies/verify/src/checks/denylist")
export type Rule = Denylist.Rule

local function identifier(name: string): string
	return "%f[%w_]" .. name .. "%f[^%w_]"
end

local function rulesFor(names: { string }, why: string): { Rule }
	local rules: { Rule } = {}
	for _, name in names do
		table.insert(rules, { pattern = identifier(name), why = why })
	end
	return rules
end

local function concat(...: { Rule }): { Rule }
	local all: { Rule } = {}
	for index = 1, select("#", ...) do
		for _, rule in select(index, ...) :: { Rule } do
			table.insert(all, rule)
		end
	end
	return all
end

local boundary: { Rule } = concat(
	{
		{ pattern = "@std/", why = "modules take host operations by injection" },
		{ pattern = "@lute/", why = "modules take host operations by injection" },
	},
	rulesFor({
		"game",
		"workspace",
		"Instance",
		"RBXScriptSignal",
		"RBXScriptConnection",
		"Enum",
		"DataModel",
	}, "core must not name a Roblox global"),
	rulesFor({
		"Vector2",
		"Vector3",
		"CFrame",
		"UDim",
		"UDim2",
		"Color3",
		"BrickColor",
		"TweenInfo",
		"NumberSequence",
		"ColorSequence",
		"NumberRange",
		"Rect",
		"Region3",
		"PhysicalProperties",
	}, "core must not name a Roblox datatype"),
	rulesFor({
		"GetService",
		"ReplicatedStorage",
		"ReplicatedFirst",
		"RunService",
		"UserInputService",
		"TweenService",
		"Players",
		"StarterGui",
		"StarterPlayer",
		"SoundService",
		"ContextActionService",
		"CollectionService",
		"HttpService",
		"MarketplaceService",
		"GuiService",
	}, "core must not name a Roblox service"),
	{
		{ pattern = "%.Parent%f[^%w_]", why = "core must reparent through host.insertChild/removeChild" },
		{ pattern = identifier("Destroy"), why = "core must release nodes through host.destroyNode" },
		{ pattern = ":Connect%s*%(", why = "core must subscribe through host.connectEvent" },
		{ pattern = "%f[%w_]Connect%s*%(", why = "core must subscribe through host.connectEvent" },
		{ pattern = "%f[%w_]Disconnect%f[^%w_]", why = "core must unsubscribe through the returned unsubscribe" },
		{
			pattern = identifier("GetPropertyChangedSignal"),
			why = "core must observe through the host observation capability",
		},
		{ pattern = identifier("WaitForChild"), why = "core must not traverse a host tree by name" },
		{ pattern = identifier("FindFirstChild"), why = "core must not traverse a host tree by name" },
		{ pattern = identifier("IsA"), why = "core must not interrogate host node classes" },
	},
	{
		{ pattern = "%f[%w_]tick%s*%(", why = "core must take time from an injected driver" },
		{ pattern = "os%.clock", why = "core must take time from an injected driver" },
		{ pattern = "os%.time", why = "core must take time from an injected driver" },
		{ pattern = "os%.date", why = "core must take time from an injected driver" },
		{ pattern = "task%.wait", why = "core must not schedule on an ambient scheduler" },
		{ pattern = "task%.spawn", why = "core must not schedule on an ambient scheduler" },
		{ pattern = "task%.defer", why = "core must not schedule on an ambient scheduler" },
		{ pattern = "task%.delay", why = "core must not schedule on an ambient scheduler" },
		{ pattern = "%f[%w_]wait%s*%(", why = "core must never yield on an ambient scheduler" },
	},
	{
		{ pattern = identifier("script"), why = "core must not assume a Roblox script instance" },
	}
)

local productMaterial: { Rule } = {
	{ pattern = "rbxassetid://", why = "product asset identifier" },
	{ pattern = "rbxthumb://", why = "product asset identifier" },

	{ pattern = "%f[%w_]placeId%s*=%s*[1-9]", why = "product place identifier" },
	{ pattern = "%f[%w_]universeId%s*=%s*[1-9]", why = "product universe identifier" },
}

return {
	boundary = boundary,
	leakage = productMaterial,
	selfPath = "tools/checks-policy.luau",
}
