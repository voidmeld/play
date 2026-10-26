--!strict

local Sessions = require("../roblox/profile-sessions")

local Owner = {}

function Owner.new(): Sessions.Owner
	local cleanups: { [() -> ()]: boolean } = {}
	local disposed = false
	local function own(cleanup: () -> ()): () -> ()
		if disposed then
			cleanup()
			return function() end
		end
		local attached = true
		local function detach()
			if attached then
				attached = false
				cleanups[detach] = nil
				cleanup()
			end
		end
		cleanups[detach] = true
		return detach
	end
	return {
		own = own,
		createChild = function(): Sessions.Owner
			local child = Owner.new()
			own(child.dispose)
			return child
		end,
		dispose = function()
			disposed = true
			for cleanup in cleanups do
				cleanup()
			end
		end,
		size = function(): number
			local count = 0
			for _ in cleanups do
				count += 1
			end
			return count
		end,
	}
end

return table.freeze(Owner)
