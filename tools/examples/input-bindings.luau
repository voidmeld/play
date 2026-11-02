--!strict

local Bindings = require("../../src/roblox/input-bindings")

local actions: { Bindings.Action<string> } = {
	{
		id = "confirm",
		context = "dialog",
		keyboard = { "Return" },
		gamepad = "ButtonA",
		chord = "ButtonL1",
		touch = "button",
		affordance = "Confirm",
	},
}
local bindings = Bindings.create(actions, { ButtonA = "A", ButtonL1 = "LB" }, "ButtonL1")
local keys = { Return = 1, ButtonA = 2 }
assert(bindings.matchesInput("confirm", keys.Return, keys, function()
	return false
end))
assert(not bindings.matchesInput("confirm", keys.ButtonA, keys, function()
	return false
end))
assert(bindings.matchesInput("confirm", keys.ButtonA, keys, function(name)
	return name == "ButtonL1"
end))
assert(bindings.gamepadLabel("confirm") == "LB+A")
assert(#bindings.forContext("dialog") == 1)
assert(#bindings.forContext("world") == 0)
print("Input bindings: keyboard, chord admission and contexts passed")
