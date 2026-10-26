--!strict

export type Host<T> = {
	available: () -> boolean,
	spawn: (() -> ()) -> (),
	publish: (string, T) -> (),
	subscribe: (string, (unknown) -> ()) -> () -> (),
	warn: (string, string) -> (),
}

local Messaging = {}

function Messaging.bind<T>(host: Host<T>, topic: string, decode: (unknown) -> T?)
	local function publish(payload: T)
		if not host.available() then
			return
		end
		host.spawn(function()
			local ok, failure = pcall(host.publish, topic, payload)
			if not ok then
				host.warn("publish", tostring(failure))
			end
		end)
	end
	local function subscribe(onNotice: (T) -> ()): (() -> ())?
		if not host.available() then
			return nil
		end
		local ok, disconnect = pcall(host.subscribe, topic, function(message: unknown)
			local notice = decode(message)
			if notice ~= nil then
				onNotice(notice)
			end
		end)
		if not ok then
			host.warn("subscribe", tostring(disconnect))
			return nil
		end
		return function()
			local disconnected, failure = pcall(disconnect)
			if not disconnected then
				host.warn("unsubscribe", tostring(failure))
			end
		end
	end
	return table.freeze({ publish = publish, subscribe = subscribe })
end

return table.freeze(Messaging)
