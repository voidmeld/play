--!strict

local Events = {}

function Events.transport<Event, Player, Handler, Options>(host: {
	register: (string, Handler, Options?) -> () -> (),
	served: (string) -> number,
	connect: (Event, (Player, ...unknown) -> ()) -> () -> (),
	receive: (string, Player, ...unknown) -> (),
	own: (() -> ()) -> (),
})
	local dispatchers: { [string]: () -> () } = {}
	local function serve(name: string, event: Event, handler: Handler, options: Options?): () -> ()
		local remove = host.register(name, handler, options)
		if dispatchers[name] == nil then
			dispatchers[name] = host.connect(event, function(player: Player, ...: unknown)
				host.receive(name, player, ...)
			end)
		end
		local released = false
		local function release()
			if released then
				return
			end
			released = true
			remove()
			local disconnect = dispatchers[name]
			if host.served(name) == 0 and disconnect ~= nil then
				dispatchers[name] = nil
				disconnect()
			end
		end
		host.own(release)
		return release
	end
	return table.freeze({ serve = serve })
end

return table.freeze(Events)
