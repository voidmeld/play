--!strict

local Client = require("./roblox-client")
local Codec = require("../../src/kernel/codec")
local Engine = require("../../tools/fixtures/engine")
local Lute = require("../../.lute/dependencies/verify/src/lute")
local Mount = require("./roblox-server")
local Protocol = require("./protocol")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Stores = require("../../src/core/persistence/store-host")
local Value = require("../../src/kernel/value")
local sceneSerial = 0
local fixtureUniverse = 101
local fixtureDestination = 202
local fixtureSource = 303

type ResponseSignal = Roblox.Signal<Protocol.Response>
type Payload = boolean | number | string | { Payload } | { [string]: Payload }
local function wire(raw: unknown): Payload
	if type(raw) == "boolean" or type(raw) == "number" or type(raw) == "string" then
		return raw
	end
	local fields = assert(Value.raw(raw), "wire_record_required")
	local list: { Payload } = {}
	local record: { [string]: Payload } = {}
	local array = false
	for key, value in fields do
		if type(key) == "number" then
			array = true
			list[key] = wire(value)
		else
			assert(type(key) == "string", "wire_key_invalid")
			record[key] = wire(value)
		end
	end
	return if array then list else record
end
local function copy(value: unknown): unknown
	local result = Codec.copyData(value)
	assert(result.ok, "fixture_copy_failed")
	return result.value
end

local function separation(first: Roblox.DatatypeVector3, second: Roblox.DatatypeVector3): number
	return (first - second).Magnitude
end

local function new(saved: { [string]: unknown }?, startTime: number?, network: Roblox.Network?)
	sceneSerial += 1
	local serverId = "fixture-server-" .. tostring(sceneSerial)
	local bridge = Lute.fixture.bridge(nil, { handlerErrors = "raise" })
	local engine = bridge.environment
	local native = bridge.placeEngine()
	local runtime = Roblox.createPlaceRuntime(native, { root = native.game, scripts = {}, sources = {} }, {
		aliases = {},
		cache = Roblox.createPlaceCache(Lute.fixture.host),
		host = Lute.fixture.host,
	})
	local stage = engine.createInstance("Model", { Name = "World", Parent = native.service("Workspace") })
	local enemy = engine.createInstance("Model", { Name = "Enemy", Parent = stage })
	local enemyRoot = engine.createInstance(
		"Part",
		{ Name = "Root", Parent = enemy, Anchored = true, Position = native.datatypes.Vector3.new(3, 0, 0) }
	)
	local enemyBody = engine.createInstance("Humanoid", { Parent = enemy, Health = 30 })
	local instances: { [number]: Roblox.Instance } = {}
	local bodies: { [number]: Roblox.Instance } = {}
	local clock = Engine.clock(engine)
	clock.advance(startTime or 0)
	local values: { [string]: unknown } = saved or {}
	local players: { [number]: Mount.Subject } = {}
	local removing: { [(Mount.Subject) -> boolean]: boolean } = {}
	local added: Roblox.Signal<Mount.Subject> = engine.newSignal()
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
		owner = Engine.owner(engine),
		clock = function()
			return math.floor(clock.clock())
		end,
		elapsed = clock.clock,
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
		contact = function(userId)
			local body = bodies[userId]
			local root = if body ~= nil then body:FindFirstChild("Root") else nil
			if root == nil then
				return nil
			end
			local first, second = root.Position, enemyRoot.Position
			assert(Roblox.typeName(first) == "Vector3" and Roblox.typeName(second) == "Vector3", "position_required")
			local distance = Roblox.value.invoke(Roblox.value.value(separation), first, second)
			assert(type(distance) == "number", "distance_required")
			return { distance = distance, clear = body ~= nil and body:GetAttribute("Blocked") ~= true }
		end,
		remote = {
			connectRequest = function(callback)
				if network ~= nil then
					local connection = network.server.onMessage(function(sender, message)
						local userId = tonumber(sender)
						local player = if userId ~= nil then players[userId] else nil
						if player ~= nil and message.channel == "world" then
							callback(player, message.payload)
						end
					end)
					return function()
						connection:Disconnect()
					end
				end
				requestHandler = callback
				return function()
					requestHandler = nil
				end
			end,
			sendResponse = function(player, response)
				if response.activity ~= nil then
					enemyBody.Health = response.activity.health
				end
				if network ~= nil then
					assert(
						network.server.send(tostring(player.UserId), { channel = "world", payload = wire(response) }).ok
					)
					return
				end
				local signal = responses[player.UserId]
				if signal ~= nil then
					signal:Fire(response)
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
			connectAdded = function(callback)
				local connection = added:Connect(callback)
				return function()
					connection:Disconnect()
				end
			end,
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
		local signal: ResponseSignal = engine.newSignal()
		responses[userId] = signal
		local name = "Traveler" .. tostring(userId)
		local instance = engine.createEngineInstance("Player", { Name = name, Parent = native.service("Players") })
		engine.poke(instance, "UserId", userId)
		local body = engine.createInstance("Model", { Name = "Character" .. tostring(userId), Parent = stage })
		engine.createInstance(
			"Part",
			{ Name = "Root", Parent = body, Anchored = true, Position = native.datatypes.Vector3.zero }
		)
		engine.createInstance("Humanoid", { Parent = body })
		engine.poke(instance, "Character", body)
		instances[userId] = instance
		bodies[userId] = body
		local player: Mount.Subject = { UserId = userId, Name = name, Character = body }
		local client = Client.start({
			fireRequest = function(request)
				if network ~= nil then
					assert(network.clients[tostring(userId)].send({ channel = "world", payload = wire(request) }).ok)
					return
				end
				local handler = assert(requestHandler)
				handler(player, request)
			end,
			connectResponse = function(callback)
				if network ~= nil then
					local connection = network.clients[tostring(userId)].onMessage(function(message)
						if message.channel == "world" then
							callback(message.payload)
						end
					end)
					return function()
						connection:Disconnect()
					end
				end
				local connection = signal:Connect(callback)
				return function()
					connection:Disconnect()
				end
			end,
		})
		players[userId] = player
		added:Fire(player)
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
			instances[userId]:Destroy()
			instances[userId] = nil
			bodies[userId]:Destroy()
			bodies[userId] = nil
			if network ~= nil then
				assert(network.disconnect(tostring(userId)).ok)
			end
		end
		return ok
	end
	return table.freeze({
		connect = connect,
		disconnect = disconnect,
		mount = mount,
		clock = clock,
		engine = engine,
		instances = instances,
		bodies = bodies,
		enemy = enemy,
		dispose = function()
			for _, close in runtime.closeHandlers do
				close()
			end
			bridge.close()
			native.game:Destroy()
			engine.root:Destroy()
		end,
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
