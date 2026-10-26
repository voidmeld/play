--!strict

local Clock = require("../test-scene/clock")
local Messaging = require("./messaging")
local Signal = require("../test-scene/signal")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	suite:case("fanout decodes notices, isolates unavailable service and disconnects", function(t)
		local clock = Clock.new()
		local signal = Signal.new()
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
					t:expect(topic):toBe("topic")
					if failPublish then
						error("offline", 0)
					end
					signal.fire(value)
				end,
				subscribe = function(_topic: string, callback: (unknown) -> ()): () -> ()
					return signal.connect(callback)
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
		t:expect(received):toEqual({})
		clock.advance(0)
		t:expect(received):toEqual({ "notice" })
		signal.fire(false)
		t:expect(#received):toBe(1)
		failPublish = true
		transport.publish("fails")
		clock.advance(0)
		t:expect(warnings):toEqual({ "publish" })
		stop()
		t:expect(signal.count()):toBe(0)
		available = false
		t:expect(transport.subscribe(function(_value: string) end)):toBeNil()
		transport.publish("ignored")
		clock.advance(0)
		t:expect(#warnings):toBe(1)
	end)
	suite:case("subscription and unsubscribe errors remain contained", function(t)
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
		t:expect(transport.subscribe(function(_value: string) end)):toBeNil()
		failSubscribe = false
		assert(transport.subscribe(function(_value: string) end))()
		t:expect(warnings):toEqual({ "subscribe", "unsubscribe" })
	end)
end
