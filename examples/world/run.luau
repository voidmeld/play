--!strict

local fs = require("@std/fs")
local process = require("@std/process")

local synced = process.run({ "lute", "run", "tools/sync-dependencies.luau" })
assert(synced.ok, synced.stdout .. synced.stderr)

local Lock = require("../../dependencies.lock")
local Lute = require("../../.lute/dependencies/verify/src/lute")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Simulator = require("./simulator")
local Tour = require("./tour")

local directory = ".lute/tmp/world-demo"
fs.createDirectory(directory, { makeParents = true })
local demo = Simulator.new()
local ran, failure = pcall(function()
	local result = Tour.run(demo)
	for userId, actor in demo.clients do
		actor.settle()
		local dump = Roblox.uiAudit.collect({
			game = actor.game,
			roots = { actor.ui.screen },
			device = "simulator",
			input = { "pointer" },
		})
		assert(#dump.roots == 1 and #dump.elements > 0, "client_ui_tree_missing")
		fs.writeStringToFile(directory .. "/client-" .. tostring(userId) .. ".json", Lute.encode(dump))
		print(actor.text("Character") .. " · " .. actor.text("Coin"))
	end
	fs.writeStringToFile(
		directory .. "/result.json",
		Lute.encode({
			dependencies = Lock,
			economy = result,
			world = demo.scene.values,
			capabilities = { "simulated-instances", "virtual-scheduler", "isolated-clients", "simulated-pointer" },
		})
	)
end)
local closed = demo.dispose()
assert(ran, tostring(failure))
assert(closed, "world_shutdown_failed")
print("World demo passed: server, three clients, quests, combat, crafting and market")
print("Headless UI trees and committed world: " .. directory)
