--!strict

local Events = require("../../src/roblox/remote-events")
local Protocol = require("./protocol")

export type Handle = {
	read request: (Protocol.Request) -> (),
	read latest: () -> Protocol.Response?,
	read lines: () -> { Protocol.Line },
	read subscribe: ((Protocol.Response) -> ()) -> () -> (),
	read dispose: () -> (),
}

local function start(ports: Protocol.ClientPorts): Handle
	local latest: Protocol.Response? = nil
	local lines: { Protocol.Line } = {}
	local listeners: { [(Protocol.Response) -> ()]: boolean } = {}
	local disposed = false
	local function receive(response: Protocol.Response)
		latest = response
		if response.line ~= nil then
			table.insert(lines, response.line)
			if #lines > 20 then
				table.remove(lines, 1)
			end
		end
		for listener in listeners do
			listener(response)
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
		subscribe = function(listener: (Protocol.Response) -> ()): () -> ()
			assert(not disposed, "client_disposed")
			listeners[listener] = true
			if latest ~= nil then
				listener(latest)
			end
			return function()
				listeners[listener] = nil
			end
		end,
		dispose = function()
			disposed = true
			table.clear(listeners)
			detach()
		end,
	})
end

return table.freeze({ start = start })
