--!strict

type Stamp = { id: string?, at: number? }
type Waiter = { id: string, at: number, present: () -> (), cancel: () -> () }
type Watch<T> = {
	count: number,
	id: string?,
	at: number?,
	confirmedId: string?,
	confirmedAt: number?,
	waiters: { [Waiter]: boolean },
	releases: { () -> () },
	tracks: { [T]: Stamp },
}

local Module = {}

export type Host<C, T> = {
	stamp: (C) -> (string?, number?),
	listen: (C, (T) -> ()) -> () -> (),
	marker: (T, () -> ()) -> () -> (),
	admit: (C, T, string, number) -> boolean,
}

function Module.create<C, T>(host: Host<C, T>)
	local watches: { [C]: Watch<T> } = setmetatable({}, { __mode = "k" })
	local Contacts = {}
	function Contacts.watch(character: C): () -> ()
		local watch = watches[character]
		if watch == nil then
			local current: Watch<T> = { count = 0, waiters = {}, releases = {}, tracks = {} }
			watch = current
			watches[character] = current
			local function started(track: T)
				local id, at = host.stamp(character)
				local accepted = current.tracks[track]
				if accepted ~= nil then
					accepted.id, accepted.at = id, at
					return
				end
				local playing: Stamp = { id = id, at = at }
				current.tracks[track] = playing
				table.insert(
					current.releases,
					host.marker(track, function()
						local id, at = host.stamp(character)
						if
							id == nil
							or at == nil
							or playing.id ~= id
							or playing.at ~= at
							or not host.admit(character, track, id, at)
							or (current.id == id and current.at == at)
						then
							return
						end
						current.id, current.at = id, at
						for waiter in current.waiters do
							if waiter.at <= at then
								if waiter.id == id and waiter.at == at then
									waiter.present()
								else
									waiter.cancel()
								end
							end
						end
					end)
				)
			end
			table.insert(current.releases, host.listen(character, started))
		end
		watch.count += 1
		local held = watch
		local released = false
		return function()
			if released then
				return
			end
			released = true
			held.count -= 1
			if held.count == 0 then
				for _, release in held.releases do
					release()
				end
				table.clear(held.waiters)
				watches[character] = nil
			end
		end
	end
	function Contacts.onContact(character: C, id: string, at: number, present: () -> (), confirmed: boolean?): () -> ()
		local release = Contacts.watch(character)
		local watch = assert(watches[character])
		if confirmed == true and (watch.confirmedAt == nil or watch.confirmedAt <= at) then
			watch.confirmedId, watch.confirmedAt = id, at
		end
		local done = false
		local waiter: Waiter
		local function cancel()
			if done then
				return
			end
			done = true
			watch.waiters[waiter] = nil
			release()
		end
		waiter = {
			id = id,
			at = at,
			cancel = cancel,
			present = function()
				cancel()
				present()
			end,
		}
		local currentId, currentAt = host.stamp(character)
		if currentAt ~= nil and currentAt > at then
			cancel()
		elseif watch.id == id and watch.at == at and currentId == id and currentAt == at then
			waiter.present()
		elseif watch.at == nil or watch.at < at then
			watch.waiters[waiter] = true
		else
			cancel()
		end
		return cancel
	end
	function Contacts.confirmed(character: C, id: string, at: number?): boolean
		local watch = watches[character]
		return watch ~= nil and watch.confirmedId == id and watch.confirmedAt == at
	end
	function Contacts.retrigger(character: C, track: T, id: string?, at: number?)
		local watch = watches[character]
		local playing = if watch ~= nil then watch.tracks[track] else nil
		if playing ~= nil then
			playing.id, playing.at = id, at
		end
	end
	return table.freeze(Contacts)
end

return table.freeze(Module)
