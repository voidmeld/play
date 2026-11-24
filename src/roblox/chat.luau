--!strict

local Chat = {}

export type DirectQuery = (number, { number }) -> { number }

function Chat.directAllowed(query: DirectQuery, requester: number, target: number): boolean
	local ran, allowed = pcall(query, requester, { target })
	return ran and type(allowed) == "table" and table.find(allowed, target) ~= nil
end

function Chat.permission(
	query: () -> boolean,
	waitFor: (number) -> (),
	studio: boolean,
	userId: number,
	attempts: number,
	retry: number
): string
	for attempt = 1, attempts do
		local checked, allowed = pcall(query)
		if checked then
			return if allowed then "allowed" else "denied"
		end
		if studio and userId <= 0 then
			return "allowed"
		end
		if attempt < attempts then
			waitFor(retry * 2 ^ (attempt - 1))
		end
	end
	return "unavailable"
end

function Chat.seat<Channel>(
	channels: { Channel },
	userId: number,
	nameOf: (Channel) -> string,
	addUser: (Channel, number) -> boolean
): { string }
	local refusals: { string } = {}
	for _, channel in channels do
		local ran, source = pcall(addUser, channel, userId)
		if not ran then
			table.insert(refusals, ("%s:%s"):format(nameOf(channel), tostring(source)))
		elseif not source then
			table.insert(refusals, nameOf(channel) .. ":chat_off_or_absent")
		end
	end
	return refusals
end

function Chat.removeForeign<Channel>(
	children: { Channel },
	nameOf: (Channel) -> string,
	isChannel: (Channel) -> boolean,
	keep: (string) -> boolean,
	destroy: (Channel) -> ()
): { string }
	local removed: { string } = {}
	for _, child in children do
		if isChannel(child) and not keep(nameOf(child)) then
			table.insert(removed, nameOf(child))
			destroy(child)
		end
	end
	table.sort(removed)
	return removed
end

return table.freeze(Chat)
