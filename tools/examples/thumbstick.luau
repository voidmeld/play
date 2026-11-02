--!strict

local Thumbstick = require("../../src/roblox/thumbstick")

local input = Thumbstick.create({ radiusPx = 100, deadZone = 0.1, zoneWidth = 0.5, zoneHeight = 0.5 })
local start = input.anchorAt({ x = 100, y = 100 })
local inside = input.drag(start, { x = 105, y = 100 })
assert(inside.vector.x == 0 and inside.vector.y == 0)
local beyond = input.drag(start, { x = 300, y = 100 })
assert(beyond.vector.x == 1 and beyond.vector.y == 0)
assert(beyond.knob.x == 100 and beyond.knob.y == 0)
assert(start.vector.x == 0 and start.knob.x == 0)
local released = input.release()
assert(released.x == 0 and released.y == 0)
print("Thumbstick: dead zone, clamping, detached state and release passed")
