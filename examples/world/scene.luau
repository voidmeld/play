--!strict

local Client = require("./roblox-client")
local Clock = require("../../src/test-scene/clock")
local Codec = require("../../src/kernel/codec")
local Mount = require("./roblox-server")
local Owner = require("../../src/test-scene/owner")
local Protocol = require("./protocol")
local Signal = require("../../src/test-scene/signal")
local Stores = require("../../src/core/persistence/store-host")
local sceneSerial = 0
local fixtureUniverse = 101
local fixtureDestination = 202
local fixtureSource = 303

type ResponseSignal = {
	connect: ((Protocol.Response) -> ()) -> () -> (),
	fire: (Protocol.Response) -> (),
	count: () -> number,
}
local responseSignal: () -> ResponseSignal = Signal.new
local playerSignal: () -> { connect: ((Mount.Subject) -> ()) -> () -> (), fire: (Mount.Subject) -> (), count: () -> number } =
	Signal.new
local function copy(value: unknown): unknown
	local result = Codec.copyData(value)
	assert(result.ok, "fixture_copy_failed")
	return result.value
end

local function new(saved: { [string]: unknown }?, startTime: number?)
	sceneSerial += 1
	local serverId = "fixture-server-" .. tostring(sceneSerial)
	local clock = Clock.new()
	clock.advance(startTime or 0)
	local values: { [string]: unknown } = saved or {}
	local players: { [number]: Mount.Subject } = {}
	local removing: { [(Mount.Subject) -> boolean]: boolean } = {}
	local added = playerSignal()
	local responses: { [number]: ResponseSignal } = {}
	local requestHandler: ((Mount.Subject, ...unknown) -> ())? = nil
	local serial = 0
	local updates = 0
	local reports: { string } = {}
	local control: { failWrite: boolean, loseReply: boolean, denyBody: boolean, onUpdate: (() -> ())? } =
		{ failWrite = false, loseReply = false, denyBody = false, onUpdate = nil }
	local queue: { Stores.QueuedWrite } = {}
	local circuitSerial = 0
	local circuit: Stores.Circuit = {
		success = function() end,
		failure = function() end,
		canAttempt = function()
			return true
		end,
		begin = function() end,
		enqueue = function(request, now)
			circuitSerial += 1
			local row =
				{ id = tostring(circuitSerial), storeName = request.storeName, key = request.key, nextAttemptAt = now }
			table.insert(queue, row)
			return true, nil, row
		end,
		markFailure = function(id, now)
			for _, row in queue do
				if row.id == id then
					row.nextAttemptAt = now + 1
				end
			end
		end,
		markSuccess = function(id)
			for index, row in queue do
				if row.id == id then
					table.remove(queue, index)
					return
				end
			end
		end,
		hasQueued = function(name, key)
			for _, row in queue do
				if row.storeName == name and row.key == key then
					return true
				end
			end
			return false
		end,
		isReadOnly = function()
			return false
		end,
		list = function()
			return table.clone(queue)
		end,
	}
	local raw: Stores.RawStore = {
		GetAsync = function(_self, key)
			return copy(values[key])
		end,
		SetAsync = function(_self, _key, _value)
			error("use_atomic_updates")
		end,
		UpdateAsync = function(_self, key, transform)
			updates += 1
			local callback = control.onUpdate
			control.onUpdate = nil
			if callback ~= nil then
				callback()
			end
			if control.failWrite then
				error("storage_unavailable")
			end
			local nextValue = transform(copy(values[key]))
			if nextValue ~= nil then
				values[key] = copy(nextValue)
			end
			if control.loseReply then
				error("reply_lost")
			end
			return copy(nextValue)
		end,
	}
	local mount = Mount.start({
		serverId = serverId,
		universeId = fixtureUniverse,
		placeId = fixtureDestination,
		sourcePlaceId = fixtureSource,
		storeName = "fixture-world",
		storage = {
			raw = raw,
			sleep = function() end,
			jitter = function()
				return 0
			end,
			now = clock.clock,
			clock = clock.clock,
			requestBudget = function()
				return 100
			end,
			uncachedOptions = function()
				return "uncached"
			end,
			validUncachedOptions = function(value)
				return value == "uncached"
			end,
		},
		circuit = circuit,
		owner = Owner.new(),
		clock = clock.clock,
		schedule = clock.schedule,
		newId = function(): string
			serial += 1
			return serverId .. "-" .. tostring(serial)
		end,
		report = function(reason)
			table.insert(reports, reason)
		end,
		filter = function(_sender, _text, _listener)
			return "Hello Harbor"
		end,
		remote = {
			connectRequest = function(callback)
				requestHandler = callback
				return function()
					requestHandler = nil
				end
			end,
			sendResponse = function(player, response)
				local signal = responses[player.UserId]
				if signal ~= nil then
					signal.fire(response)
				end
			end,
		},
		players = {
			present = function(player)
				return players[player.UserId] == player
			end,
			getJoinData = function()
				return {}
			end,
			getPlayers = function()
				local result: { Mount.Subject } = {}
				for _, player in players do
					table.insert(result, player)
				end
				return result
			end,
			connectRemoving = function(callback)
				removing[callback] = true
				return function()
					removing[callback] = nil
				end
			end,
			connectAdded = added.connect,
		},
		clear = function()
			return true
		end,
		refuse = function(_player, reason)
			table.insert(reports, reason)
			return true
		end,
		actor = {
			admitPlayer = function()
				return true, nil
			end,
			removePlayer = function()
				return true
			end,
		},
		body = {
			admitPlayer = function()
				return not control.denyBody, "body_unavailable"
			end,
			removePlayer = function()
				return true
			end,
		},
		movement = {
			admitPlayer = function()
				return true, nil
			end,
			removePlayer = function()
				return true
			end,
		},
	})
	local function connect(userId: number)
		local signal = responseSignal()
		responses[userId] = signal
		local player: Mount.Subject = { UserId = userId, Name = "Traveler" .. tostring(userId), Character = false }
		local client = Client.start({
			fireRequest = function(request)
				local handler = assert(requestHandler)
				handler(player, request)
			end,
			connectResponse = signal.connect,
		})
		players[userId] = player
		added.fire(player)
		return client, player
	end
	local function disconnect(userId: number): boolean
		local player = assert(players[userId])
		local ok = true
		for callback in removing do
			ok = callback(player) and ok
		end
		if ok then
			players[userId] = nil
		end
		return ok
	end
	return table.freeze({
		connect = connect,
		disconnect = disconnect,
		mount = mount,
		clock = clock,
		values = values,
		control = control,
		updates = function()
			return updates
		end,
		reports = function()
			return table.clone(reports)
		end,
		rawRequest = function(player: Mount.Subject, request: unknown)
			assert(requestHandler)(player, request)
		end,
	})
end

return table.freeze({ new = new })
