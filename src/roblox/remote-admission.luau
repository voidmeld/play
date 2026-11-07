--!strict

local Events = require("./remote-events")
local Payload = require("../core/net/payload")
local RateLimit = require("../core/net/rate-limit")
local Value = require("../kernel/value")

export type Handler<P> = (P, Payload.Arguments) -> ()
export type Options<P> = { lane: RateLimit.Config?, refused: ((P, string) -> ())? }
export type Dispatch = { accepted: number, refused: number, reason: string? }
export type Dependencies<E, P> = {
	clock: () -> number,
	keyFor: (P) -> string,
	budget: (string) -> RateLimit.Config,
	payload: Payload.Config,
	maxChannels: number,
	maxHandlers: number,
	maxKeys: number,
	maxText: number,
	refusalWindow: number,
	connect: (E, (P, ...unknown) -> ()) -> () -> (),
	own: (() -> ()) -> (),
	notify: (string, P, string) -> (),
}
type Entry<P> = { id: number, handler: Handler<P>, options: Options<P>, active: boolean }
type Sender = {
	bucket: RateLimit.Bucket,
	lanes: { [number]: RateLimit.Bucket },
	notices: { [string]: number },
	refusing: boolean,
}
type Channel<P> = {
	budget: RateLimit.Config,
	entries: { Entry<P> },
	senders: { [string]: Sender },
	busy: { [string]: boolean },
	notices: { [string]: number },
	refusing: boolean,
}

local function validBudget(config: RateLimit.Config): boolean
	return Value.finite(config.capacity)
		and config.capacity >= 1
		and Value.finite(config.refillPerSec)
		and config.refillPerSec >= 0
end

local function new<E, P>(deps: Dependencies<E, P>)
	for _, limit in { deps.maxChannels, deps.maxHandlers, deps.maxKeys, deps.maxText } do
		assert(Value.whole(limit, 1, 1000000) ~= nil, "invalid admission bound")
	end
	assert(Value.finite(deps.refusalWindow) and deps.refusalWindow > 0, "invalid refusal window")
	local payload = Payload.create(deps.payload)
	local maxArguments = deps.payload.bounds.maxArguments
	local channels: { [string]: Channel<P> } = {}
	local releases: { [() -> ()]: boolean } = {}
	local nextId = 0
	local disposed = false
	local function served(name: string): number
		local channel = channels[name]
		return if channel ~= nil then #channel.entries else 0
	end
	local function register(name: string, handler: Handler<P>, supplied: Options<P>?): () -> ()
		assert(not disposed and Value.opaque(name, deps.maxText) ~= nil, "channel_invalid")
		local channel = channels[name]
		if channel == nil then
			local count = 0
			for _ in channels do
				count += 1
			end
			assert(count < deps.maxChannels, "channels_full")
			local budget = table.clone(deps.budget(name))
			assert(validBudget(budget), "budget_invalid")
			channel = { budget = budget, entries = {}, senders = {}, busy = {}, notices = {}, refusing = false }
		end
		assert(#channel.entries < deps.maxHandlers, "handlers_full")
		local source: Options<P> = supplied or { lane = nil, refused = nil }
		local options: Options<P> = table.clone(source)
		if options.lane ~= nil then
			local lane = table.clone(options.lane)
			assert(
				validBudget(lane)
					and lane.capacity <= channel.budget.capacity
					and lane.refillPerSec <= channel.budget.refillPerSec,
				"lane_invalid"
			)
			options.lane = lane
		end
		nextId += 1
		local entry: Entry<P> = { id = nextId, handler = handler, options = options, active = true }
		channels[name] = channel
		table.insert(channel.entries, entry)
		return function()
			if not entry.active then
				return
			end
			entry.active = false
			local index = table.find(channel.entries, entry)
			if index ~= nil then
				table.remove(channel.entries, index)
			end
			for _, sender in channel.senders do
				sender.lanes[entry.id] = nil
			end
			if #channel.entries == 0 and channels[name] == channel then
				channels[name] = nil
			end
		end
	end
	local function refuseAt(
		name: string,
		player: P,
		entries: { Entry<P> },
		reason: string,
		now: number,
		notices: { notices: { [string]: number }, refusing: boolean }
	)
		if notices.refusing then
			return
		end
		notices.refusing = true
		for _, entry in entries do
			if entry.options.refused ~= nil then
				pcall(entry.options.refused, player, reason)
			end
		end
		local last = notices.notices[reason]
		if last == nil or now - last >= deps.refusalWindow then
			notices.notices[reason] = now
			pcall(deps.notify, name, player, reason)
		end
		notices.refusing = false
	end
	local function receive(name: string, player: P, ...: unknown): Dispatch
		local channel = channels[name]
		if disposed or channel == nil then
			return { accepted = 0, refused = 0, reason = "channel_missing" }
		end
		local snapshot = table.clone(channel.entries)
		local now = deps.clock()
		local function untracked(reason: string): Dispatch
			refuseAt(name, player, snapshot, reason, if Value.finite(now) then now else 0, channel)
			return { accepted = 0, refused = #snapshot, reason = reason }
		end
		local key = deps.keyFor(player)
		if Value.opaque(key, deps.maxText) == nil then
			return untracked("key_invalid")
		end
		if not Value.finite(now) then
			return untracked("clock_invalid")
		end
		local sender = channel.senders[key]
		if sender == nil then
			local count = 0
			for _ in channel.senders do
				count += 1
			end
			if count >= deps.maxKeys then
				return untracked("senders_full")
			end
			sender = { bucket = RateLimit.newBucket(channel.budget, now), lanes = {}, notices = {}, refusing = false }
			channel.senders[key] = sender
		end
		local function refuse(entries: { Entry<P> }, reason: string)
			refuseAt(name, player, entries, reason, now, sender)
		end
		local function reject(reason: string): Dispatch
			refuse(snapshot, reason)
			return { accepted = 0, refused = #snapshot, reason = reason }
		end
		if channel.busy[key] then
			return reject("invocation_busy")
		end
		if now < sender.bucket.lastRefill then
			return reject("clock_invalid")
		end
		local admitted, bucket = RateLimit.tryConsume(sender.bucket, channel.budget, now)
		sender.bucket = bucket
		if not admitted then
			return reject("channel_limited")
		end
		channel.busy[key] = true
		if select("#", ...) > maxArguments then
			local rejected = reject("payload_invalid")
			channel.busy[key] = nil
			return rejected
		end
		local args = table.pack(...)
		local ran, result = pcall(function(): Dispatch
			local decoded = payload.decode(table.unpack(args, 1, args.n))
			if not decoded.ok then
				return reject("payload_invalid")
			end
			local accepted, refused = 0, 0
			for _, entry in snapshot do
				if disposed or channels[name] ~= channel or channel.senders[key] ~= sender then
					break
				end
				if not entry.active then
					continue
				end
				local lane = entry.options.lane
				if lane ~= nil then
					local available, nextBucket =
						RateLimit.tryConsume(sender.lanes[entry.id] or RateLimit.newBucket(lane, now), lane, now)
					sender.lanes[entry.id] = nextBucket
					if not available then
						refused += 1
						refuse({ entry }, "lane_limited")
						continue
					end
				end
				local handled = pcall(entry.handler, player, decoded.value)
				if handled then
					accepted += 1
				else
					refused += 1
					refuse({ entry }, "handler_failed")
				end
			end
			return { accepted = accepted, refused = refused }
		end)
		channel.busy[key] = nil
		return if ran then result else reject("dispatch_failed")
	end
	local transport = Events.transport({
		register = register,
		served = served,
		connect = deps.connect,
		receive = function(name: string, player: P, ...: unknown)
			receive(name, player, ...)
		end,
		own = function(release: () -> ())
			releases[release] = true
			deps.own(function()
				releases[release] = nil
				release()
			end)
		end,
	})
	local function serve(name: string, event: E, handler: Handler<P>, options: Options<P>?): () -> ()
		local release = transport.serve(name, event, handler, options)
		return function()
			releases[release] = nil
			release()
		end
	end
	local function forget(key: string)
		for _, channel in channels do
			channel.senders[key] = nil
		end
	end
	local function dispose()
		if disposed then
			return
		end
		disposed = true
		for release in releases do
			release()
		end
		table.clear(releases)
		table.clear(channels)
	end
	return table.freeze({ serve = serve, receive = receive, forget = forget, served = served, dispose = dispose })
end

return table.freeze({ new = new })
