--!strict

local Events = require("../../src/roblox/remote-events")
local Protocol = require("./protocol")

local function start(ports: Protocol.ClientPorts)
	local latest: Protocol.Response? = nil
	local lines: { Protocol.Line } = {}
	local function receive(response: Protocol.Response)
		latest = response
		if response.line ~= nil then
			table.insert(lines, response.line)
			if #lines > 20 then
				table.remove(lines, 1)
			end
		end
	end
	local handler: ((Protocol.Response) -> ())? = nil
	local transport = Events.transport({
		register = function(_name: string, callback: (Protocol.Response) -> (), _options: boolean?)
			handler = callback
			return function()
				handler = nil
			end
		end,
		served = function(_name: string)
			return if handler ~= nil then 1 else 0
		end,
		connect = function(_event: string, callback: (boolean, ...unknown) -> ())
			return ports.connectResponse(function(raw)
				callback(false, raw)
			end)
		end,
		receive = function(_name: string, _player: boolean, ...: unknown)
			if select("#", ...) ~= 1 then
				return
			end
			local response = Protocol.decodeResponse((...))
			local callback = handler
			if response ~= nil and callback ~= nil then
				callback(response)
			end
		end,
		own = function(_cleanup) end,
	})
	local detach = transport.serve("world", "world", receive, nil)
	return table.freeze({
		request = function(intent: Protocol.Request)
			ports.fireRequest(intent)
		end,
		latest = function(): Protocol.Response?
			return latest
		end,
		lines = function(): { Protocol.Line }
			return table.clone(lines)
		end,
		dispose = detach,
	})
end

return table.freeze({ start = start })
