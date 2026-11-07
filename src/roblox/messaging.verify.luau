--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Engine = require("../../tools/fixtures/engine")
local Messaging = require("./messaging")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("messaging", function()
		it("fanout decodes notices, isolates unavailable service and disconnects", function()
			local clock = Engine.clock()
			local engine = Roblox.testEnvironment({ handlerErrors = "raise" })
			local signal: Roblox.Signal<unknown> = engine.newSignal()
			local available = true
			local failPublish = false
			local warnings: { string } = {}
			local received: { string } = {}
			local transport = Messaging.bind(
				{
					available = function(): boolean
						return available
					end,
					spawn = function(callback: () -> ())
						clock.schedule(0, callback)
					end,
					publish = function(topic: string, value: string)
						expect(topic):toBe("topic")
						if failPublish then
							error("offline", 0)
						end
						signal:Fire(value)
					end,
					subscribe = function(_topic: string, callback: (unknown) -> ()): () -> ()
						local connection = signal:Connect(callback)
						return function()
							connection:Disconnect()
						end
					end,
					warn = function(operation: string, _failure: string)
						table.insert(warnings, operation)
					end,
				},
				"topic",
				function(raw: unknown): string?
					return if type(raw) == "string" then raw else nil
				end
			)
			local stop = assert(transport.subscribe(function(value: string)
				table.insert(received, value)
			end))
			transport.publish("notice")
			expect(received):toEqual({})
			clock.advance(0)
			expect(received):toEqual({ "notice" })
			signal:Fire(false)
			expect(#received):toBe(1)
			failPublish = true
			transport.publish("fails")
			clock.advance(0)
			expect(warnings):toEqual({ "publish" })
			stop()
			expect(engine.connectionsOf(signal)):toBe(0)
			available = false
			expect(transport.subscribe(function(_value: string) end)):toBeNil()
			transport.publish("ignored")
			clock.advance(0)
			expect(#warnings):toBe(1)
		end)
		it("subscription and unsubscribe errors remain contained", function()
			local warnings: { string } = {}
			local failSubscribe = true
			local transport = Messaging.bind(
				{
					available = function(): boolean
						return true
					end,
					spawn = function(callback: () -> ())
						callback()
					end,
					publish = function(_topic: string, _value: string) end,
					subscribe = function(_topic: string, _callback: (unknown) -> ()): () -> ()
						if failSubscribe then
							error("offline", 0)
						end
						return function()
							error("disconnect", 0)
						end
					end,
					warn = function(operation: string, _failure: string)
						table.insert(warnings, operation)
					end,
				},
				"topic",
				function(raw: unknown): string?
					return if type(raw) == "string" then raw else nil
				end
			)
			expect(transport.subscribe(function(_value: string) end)):toBeNil()
			failSubscribe = false
			assert(transport.subscribe(function(_value: string) end))()
			expect(warnings):toEqual({ "subscribe", "unsubscribe" })
		end)
	end)
end
