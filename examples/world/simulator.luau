--!strict

local Lute = require("../../.lute/dependencies/verify/src/lute")
local Native = require("../../.lute/dependencies/compose/src/roblox")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Scene = require("./scene")
local UI = require("./ui")
local Value = require("../../src/kernel/value")

local function new(saved: { [string]: unknown }?, startTime: number?)
	local network = Roblox.network.create({
		clients = { "11", "22", "33" },
		environment = function()
			return { handlerErrors = "raise" }
		end,
	})
	local scene = Scene.new(saved, startTime, network)
	local function createClient(userId: number)
		local client = scene.connect(userId)
		local roots: { Roblox.Instance } = {}
		local place: Roblox.PlaceRuntime? = nil
		local bridge = Lute.fixture.bridge(nil, {
			handlerErrors = "raise",
			layout = {
				roots = function()
					return roots
				end,
				viewport = function()
					return { X = 1280, Y = 900 }
				end,
				screenArea = function(screen)
					return if place ~= nil
						then place.screenArea(screen)
						else { x = 0, y = 0, width = 1280, height = 900 }
				end,
			},
		})
		local engine = bridge.placeEngine()
		local layout = assert(bridge.layout)
		place = Roblox.createPlaceRuntime(engine, { root = engine.game, scripts = {}, sources = {} }, {
			aliases = {},
			cache = Roblox.createPlaceCache(Lute.fixture.host),
			host = Lute.fixture.host,
			client = { name = "Traveler" .. tostring(userId), userId = userId, viewport = { x = 1280, y = 900 } },
			beforeRender = layout.step,
		})
		local player = assert(place.localPlayer)
		local playerGui = assert(player:FindFirstChildOfClass("PlayerGui"))
		table.insert(roots, playerGui)
		local runtime = Native.createRuntime(bridge.engine)
		local read = assert(Native.createHost(bridge.engine).observation).readProperty
		local function numberMember(value: unknown, key: string): number
			assert(type(value) == "table" or type(value) == "userdata", "geometry_value_required")
			local member = read(value, key)
			assert(type(member) == "number", "geometry_number_required")
			return member
		end
		local loader = Lute.loader.new({ globals = place.globals })
		local facet = loader.require(".lute/dependencies/facet/src")
		local types = assert(Value.raw(engine.datatypes))
		types.typeof = Roblox.typeName
		local ui = UI.mount(facet, runtime, types, playerGui, client)
		local input = Roblox.inputHost.simulated(bridge.environment, {
			playerGui = playerGui,
			inputService = engine.service("UserInputService"),
			layout = layout,
			library = engine.datatypes,
			inset = function()
				return { X = 0, Y = 0 }
			end,
			activationWindowSeconds = 0.5,
			read = assert(bridge.ui).styled,
		})
		local function settle()
			runtime:settle()
			layout.step()
		end
		local function control(name: string): Roblox.Instance
			return assert(ui.screen:FindFirstChild(name, true), "control_missing:" .. name)
		end
		return {
			client = client,
			ui = ui,
			bridge = bridge,
			player = player,
			game = engine.game,
			input = input,
			settle = settle,
			step = function(seconds: number)
				assert(place).step(seconds)
				settle()
			end,
			control = control,
			text = function(name: string): string
				settle()
				local value = bridge.environment.propertyOf(control(name), "Text")
				assert(type(value) == "string", "text_required")
				return value
			end,
			tap = function(name: string)
				settle()
				local target = control(name)
				local position = target.AbsolutePosition
				local size = target.AbsoluteSize
				local x = numberMember(position, "X") + numberMember(size, "X") / 2
				local y = numberMember(position, "Y") + numberMember(size, "Y") / 2
				assert(numberMember(size, "X") > 0 and numberMember(size, "Y") > 0, "control_has_no_area:" .. name)
				input.pointer({ x = x, y = y, button = "left", down = true })
				input.pointer({ x = x, y = y, button = "left", down = false })
			end,
			dispose = function()
				input.close()
				ui.dispose()
				client.dispose()
				runtime:dispose()
				for _, close in assert(place).closeHandlers do
					close()
				end
				bridge.close()
				engine.game:Destroy()
				bridge.environment.root:Destroy()
			end,
		}
	end
	local clients: { [number]: typeof(createClient(11)) } = {}
	for _, userId in { 11, 22, 33 } do
		clients[userId] = createClient(userId)
	end
	local function flush()
		for _ = 1, 16 do
			if network.pending() == 0 then
				break
			end
			assert(network.advance(0).ok)
		end
		assert(network.pending() == 0, "network_did_not_settle")
		for _, actor in clients do
			actor.settle()
		end
	end
	flush()
	local disposed = false
	return {
		scene = scene,
		clients = clients,
		network = network,
		flush = flush,
		step = function(seconds: number)
			assert(network.advance(seconds).ok)
			scene.clock.advance(seconds)
			for _, actor in clients do
				actor.step(seconds)
			end
			flush()
		end,
		tap = function(userId: number, name: string)
			clients[userId].tap(name)
			flush()
		end,
		dispose = function(): boolean
			if disposed then
				return true
			end
			local ok = scene.mount.shutdown()
			if not ok then
				return false
			end
			for userId, actor in clients do
				actor.dispose()
				assert(network.disconnect(tostring(userId)).ok)
			end
			scene.dispose()
			disposed = true
			return true
		end,
	}
end

return table.freeze({ new = new })
