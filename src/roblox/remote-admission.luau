--!strict

local Events = require("./remote-events")
local Payload = require("../core/net/payload")
local RateLimit = require("../core/net/rate-limit")
local Result = require("../kernel/result")
local Value = require("../kernel/value")

export type Handler<P> = (P, Payload.Arguments) -> ()
export type InvokeHandler<P> = (P, ...unknown) -> ...unknown
export type Refusal<P> = {
	read player: P,
	read handler: Handler<P> | InvokeHandler<P>,
	read handlerId: number,
	read channel: string,
	read reason: string,
	read payloadSize: number,
}
export type Options<P> = {
	lane: RateLimit.Config?,
	refused: ((P, string) -> ())?,
	refusedRecord: ((Refusal<P>) -> ())?,
	refusedArgs: InvokeHandler<P>?,
}
export type Invoker<P> = { read call: (P, ...unknown) -> ...unknown, read remove: () -> () }
export type Lane<P> = { read admit: (P, ...unknown) -> boolean, read remove: () -> () }
export type Dispatch = { accepted: number, refused: number, reason: string? }
export type Dependencies<E, P> = {
	clock: () -> number,
	keyFor: (P) -> string,
	budget: (string) -> RateLimit.Config,
	payload: Payload.Config?,
	decode: ((...unknown) -> Result.Result<Payload.Arguments>)?,
	maxChannels: number?,
	maxHandlers: number?,
	maxKeys: number?,
	maxText: number?,
	refusalWindow: number?,
	noticePolicy: ("window" | "streak")?,
	retainBudgets: boolean?,
	spawn: ((() -> ()) -> ())?,
	connect: (E, (P, ...unknown) -> ()) -> () -> (),
	own: (() -> ()) -> (),
	notify: (string, P, string) -> (),
}
type Entry<P> = {
	id: number,
	handler: Handler<P>,
	original: Handler<P> | InvokeHandler<P>,
	invoke: InvokeHandler<P>?,
	options: Options<P>,
	active: boolean,
}
type Sender = {
	bucket: RateLimit.Bucket,
	lanes: { [number]: RateLimit.Bucket },
	notices: { [string]: number? },
	refusing: boolean,
}
type Channel<P> = {
	budget: RateLimit.Config,
	references: number,
	entries: { Entry<P> },
	senders: { [string]: Sender },
	busy: { [string]: boolean },
	notices: { [string]: number? },
	refusing: boolean,
}

local function validBudget(config: RateLimit.Config): boolean
	return Value.finite(config.capacity)
		and config.capacity >= 1
		and Value.finite(config.refillPerSec)
		and config.refillPerSec >= 0
end

local function new<E, P>(deps: Dependencies<E, P>)
	local maxChannels, maxHandlers = deps.maxChannels or math.huge, deps.maxHandlers or math.huge
	local maxKeys, maxText = deps.maxKeys or math.huge, deps.maxText or math.huge
	for _, limit in { deps.maxChannels, deps.maxHandlers, deps.maxKeys, deps.maxText } do
		assert(Value.whole(limit, 1, 1000000) ~= nil, "invalid admission bound")
	end
	local refusalWindow = deps.refusalWindow or 1
	assert(Value.finite(refusalWindow) and refusalWindow > 0, "invalid refusal window")
	assert(
		deps.noticePolicy == nil or deps.noticePolicy == "window" or deps.noticePolicy == "streak",
		"invalid notice policy"
	)
	local payload = if deps.payload ~= nil then Payload.create(deps.payload) else nil
	local maxArguments = if deps.payload ~= nil and deps.decode == nil
		then deps.payload.bounds.maxArguments
		else math.huge
	local function decode(...: unknown): Result.Result<Payload.Arguments>
		if deps.decode ~= nil then
			return deps.decode(...)
		end
		assert(payload ~= nil, "payload decoder required")
		return payload.decode(...)
	end
	assert(payload ~= nil or deps.decode ~= nil, "payload decoder required")
	local channels: { [string]: Channel<P> } = {}
	local releases: { [() -> ()]: boolean } = {}
	local nextId = 0
	local invokers: { [string]: boolean } = {}
	local disposed = false
	local function own(release: () -> ())
		releases[release] = true
		local ok, problem = pcall(deps.own, function()
			releases[release] = nil
			release()
		end)
		if not ok then
			releases[release] = nil
			release()
			error(problem, 0)
		end
	end
	local function served(name: string): number
		local channel = channels[name]
		return if channel ~= nil then #channel.entries else 0
	end
	local function add(
		name: string,
		handler: Handler<P>,
		supplied: Options<P>?,
		invoke: InvokeHandler<P>?,
		standalone: boolean?
	): (() -> (), Entry<P>, Channel<P>)
		assert(not disposed and Value.opaque(name, maxText) ~= nil, "channel_invalid")
		assert(standalone or not invokers[name], "invoke_already_registered")
		local channel = channels[name]
		assert(invoke == nil or channel == nil or #channel.entries == 0, "channel_already_registered")
		if channel == nil then
			local count = 0
			for _ in channels do
				count += 1
			end
			assert(count < maxChannels, "channels_full")
			local budget = table.clone(deps.budget(name))
			assert(validBudget(budget), "budget_invalid")
			channel = {
				budget = budget,
				references = 0,
				entries = {},
				senders = {},
				busy = {},
				notices = {},
				refusing = false,
			}
		end
		assert(channel.references < maxHandlers, "handlers_full")
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
		local entry: Entry<P> =
			{ id = nextId, handler = handler, original = handler, invoke = invoke, options = options, active = true }
		if invoke ~= nil then
			entry.original = invoke
		end
		if invoke ~= nil then
			invokers[name] = true
		end
		channels[name] = channel
		channel.references += 1
		if not standalone then
			table.insert(channel.entries, entry)
		end
		local function remove(): ()
			if not entry.active then
				return
			end
			entry.active = false
			channel.references -= 1
			if entry.invoke ~= nil then
				invokers[name] = nil
			end
			local index = table.find(channel.entries, entry)
			if index ~= nil then
				table.remove(channel.entries, index)
			end
			for _, sender in channel.senders do
				sender.lanes[entry.id] = nil
			end
			if channel.references == 0 and channels[name] == channel and not deps.retainBudgets then
				channels[name] = nil
			end
		end
		return remove, entry, channel
	end
	local function register(name: string, handler: Handler<P>, supplied: Options<P>?): () -> ()
		local remove = add(name, handler, supplied, nil, nil)
		return remove
	end
	local function registerRaw(name: string, handler: InvokeHandler<P>, options: Options<P>?): () -> ()
		local function run(player: P, args: Payload.Arguments)
			handler(player, table.unpack(args, 1, args.n))
		end
		local remove, entry = add(name, run, options, nil, nil)
		entry.original = handler
		return remove
	end
	local function refuseAt(
		name: string,
		player: P,
		entries: { Entry<P> },
		reason: string,
		args: Payload.Arguments,
		now: number,
		notices: { notices: { [string]: number? }, refusing: boolean }
	): Payload.Arguments?
		if notices.refusing then
			return nil
		end
		notices.refusing = true
		local response: Payload.Arguments? = nil
		for _, entry in entries do
			if entry.options.refused ~= nil then
				pcall(entry.options.refused, player, reason)
			end
			if entry.options.refusedRecord ~= nil then
				pcall(
					entry.options.refusedRecord,
					table.freeze({
						player = player,
						handler = entry.original,
						handlerId = entry.id,
						channel = name,
						reason = reason,
						payloadSize = args.n,
					})
				)
			end
			local refusedArgs = entry.options.refusedArgs
			if refusedArgs ~= nil then
				local ok, returned = pcall(function(): Payload.Arguments?
					local function run(): Payload.Arguments
						return table.pack(refusedArgs(player, table.unpack(args, 1, args.n)))
					end
					if deps.spawn ~= nil and entry.invoke == nil then
						deps.spawn(function()
							run()
						end)
						return nil
					end
					return run()
				end)
				if ok then
					response = returned
				end
			end
		end
		local noticeKey = if deps.noticePolicy == "streak"
				and reason == "lane_limited"
				and #entries == 1
			then "lane:" .. entries[1].id
			else reason
		local last = notices.notices[noticeKey]
		if last == nil or (deps.noticePolicy ~= "streak" and now - last >= refusalWindow) then
			notices.notices[noticeKey] = now
			pcall(deps.notify, name, player, reason)
		end
		notices.refusing = false
		return response
	end
	local function senderFor(channel: Channel<P>, key: string, now: number): Sender?
		local sender = channel.senders[key]
		if sender ~= nil then
			return sender
		end
		local count = 0
		for _ in channel.senders do
			count += 1
		end
		if count >= maxKeys then
			return nil
		end
		local created: Sender =
			{ bucket = RateLimit.newBucket(channel.budget, now), lanes = {}, notices = {}, refusing = false }
		channel.senders[key] = created
		return created
	end
	local function lane(name: string, options: Options<P>?): Lane<P>
		local function identity(_player: P, _args: Payload.Arguments) end
		local remove, entry, channel = add(name, identity, options, nil, true)
		local function admit(player: P, ...: unknown): boolean
			if disposed or not entry.active then
				return false
			end
			local key, now = deps.keyFor(player), deps.clock()
			local args = table.pack(...)
			if Value.opaque(key, maxText) == nil or not Value.finite(now) then
				refuseAt(
					name,
					player,
					{ entry },
					if not Value.finite(now) then "clock_invalid" else "key_invalid",
					args,
					if Value.finite(now) then now else 0,
					channel
				)
				return false
			end
			local sender = senderFor(channel, key, now)
			if sender == nil then
				refuseAt(name, player, { entry }, "senders_full", args, now, channel)
				return false
			end
			local budget = entry.options.lane
			if budget == nil then
				return true
			end
			local current = sender.lanes[entry.id] or RateLimit.newBucket(budget, now)
			if now < current.lastRefill then
				refuseAt(name, player, { entry }, "clock_invalid", args, now, sender)
				return false
			end
			local accepted, bucket = RateLimit.tryConsume(current, budget, now)
			sender.lanes[entry.id] = bucket
			if not accepted then
				refuseAt(name, player, { entry }, "lane_limited", args, now, sender)
			elseif deps.noticePolicy == "streak" then
				sender.notices["lane:" .. entry.id] = nil
			end
			return accepted
		end
		own(remove)
		return table.freeze({ admit = admit, remove = remove })
	end
	local function dispatch(name: string, player: P, ...: unknown): (Dispatch, Payload.Arguments?, boolean)
		local channel = channels[name]
		if disposed or channel == nil then
			return { accepted = 0, refused = 0, reason = "channel_missing" }, nil, false
		end
		local args = table.pack(...)
		local response: Payload.Arguments? = nil
		local snapshot = table.clone(channel.entries)
		local now = deps.clock()
		local function untracked(reason: string): Dispatch
			response = refuseAt(name, player, snapshot, reason, args, if Value.finite(now) then now else 0, channel)
			return { accepted = 0, refused = #snapshot, reason = reason }
		end
		local key = deps.keyFor(player)
		if Value.opaque(key, maxText) == nil then
			return untracked("key_invalid"), response, false
		end
		if not Value.finite(now) then
			return untracked("clock_invalid"), response, false
		end
		local sender = senderFor(channel, key, now)
		if sender == nil then
			return untracked("senders_full"), response, false
		end
		local function refuse(entries: { Entry<P> }, reason: string)
			response = refuseAt(name, player, entries, reason, args, now, sender) or response
		end
		local function reject(reason: string): Dispatch
			refuse(snapshot, reason)
			return { accepted = 0, refused = #snapshot, reason = reason }
		end
		if channel.busy[key] then
			return reject("invocation_busy"), response, false
		end
		if now < sender.bucket.lastRefill then
			return reject("clock_invalid"), response, false
		end
		local admitted, bucket = RateLimit.tryConsume(sender.bucket, channel.budget, now)
		sender.bucket = bucket
		if not admitted then
			return reject("channel_limited"), response, false
		end
		if deps.noticePolicy == "streak" then
			sender.notices.channel_limited = nil
		end
		channel.busy[key] = true
		if select("#", ...) > maxArguments then
			local rejected = reject("payload_invalid")
			channel.busy[key] = nil
			return rejected, response, true
		end
		local ran, result = pcall(function(): Dispatch
			local decoded = decode(table.unpack(args, 1, args.n))
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
					if deps.noticePolicy == "streak" then
						sender.notices["lane:" .. entry.id] = nil
					end
				end
				local handled = pcall(function()
					local invoke = entry.invoke
					if invoke ~= nil then
						response = table.pack(invoke(player, table.unpack(decoded.value, 1, decoded.value.n)))
					else
						local function run()
							entry.handler(player, decoded.value)
						end
						if deps.spawn ~= nil then
							deps.spawn(run)
						else
							run()
						end
					end
				end)
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
		if not ran then
			return reject("dispatch_failed"), response, true
		end
		return result, response, true
	end
	local function receive(name: string, player: P, ...: unknown): Dispatch
		local result = dispatch(name, player, ...)
		return result
	end
	local function dispatchAdmitted(name: string, player: P, ...: unknown): boolean
		local _, _, admitted = dispatch(name, player, ...)
		return admitted
	end
	local function serveInvoke(name: string, handler: InvokeHandler<P>, options: Options<P>?): Invoker<P>
		local function identity(_player: P, _args: Payload.Arguments) end
		local remove = add(name, identity, options, handler, nil)
		local active = true
		local function release(): ()
			if not active then
				return
			end
			active = false
			remove()
		end
		local function call(player: P, ...: unknown): ...unknown
			if not active or disposed then
				return nil
			end
			local _, response = dispatch(name, player, ...)
			if response == nil then
				return nil
			end
			return table.unpack(response, 1, response.n)
		end
		own(release)
		return table.freeze({ call = call, remove = release })
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
		table.clear(invokers)
	end
	return table.freeze({
		serve = serve,
		register = register,
		registerRaw = registerRaw,
		serveInvoke = serveInvoke,
		lane = lane,
		dispatch = dispatchAdmitted,
		receive = receive,
		forget = forget,
		served = served,
		dispose = dispose,
	})
end

return table.freeze({ new = new })
