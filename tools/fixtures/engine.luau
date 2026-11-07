--!strict

local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Sessions = require("../../src/roblox/profile-sessions")

local function clock(environment: Roblox.Environment?)
	local engine = environment or Roblox.testEnvironment({ handlerErrors = "raise" })
	return {
		clock = engine.now,
		advance = engine.step,
		schedule = function(seconds: number, callback: () -> ()): () -> ()
			local pending = engine.task.delay(seconds, callback)
			return function()
				engine.task.cancel(pending)
			end
		end,
	}
end

local function owner(environment: Roblox.Environment?, parent: Roblox.Instance?): Sessions.Owner
	local engine = environment or Roblox.testEnvironment({ handlerErrors = "raise" })
	local root = engine.createInstance("Folder", { Parent = parent })
	return {
		own = function(cleanup: () -> ()): () -> ()
			if not engine.isAlive(root) then
				cleanup()
				return function() end
			end
			local connection: Roblox.Connection? = nil
			local function detach()
				local current = connection
				if current ~= nil then
					connection = nil
					current:Disconnect()
					cleanup()
				end
			end
			connection = root.Destroying:Connect(detach)
			return detach
		end,
		createChild = function(): Sessions.Owner
			local child = owner(engine, if engine.isAlive(root) then root else nil)
			if not engine.isAlive(root) then
				child.dispose()
			end
			return child
		end,
		dispose = function()
			root:Destroy()
		end,
		size = function(): number
			return engine.connectionsOf(root.Destroying)
		end,
	}
end

return table.freeze({ clock = clock, owner = owner })
