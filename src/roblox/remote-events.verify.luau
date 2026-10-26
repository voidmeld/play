--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Clock = require("../test-scene/clock")
local Events = require("./remote-events")
local Signal = require("../test-scene/signal")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("remote events", function()
		it("one dispatcher per channel survives partial release and disconnects the last", function(own)
			local signal = Signal.new()
			local clock = Clock.new()
			local limiter = Events.limiter({ capacity = 1, refillPerSec = 1 })
			local handlers: { [(number) -> ()]: boolean } = {}
			local owned: { () -> () } = {}
			local transport = Events.transport({
				register = function(_name: string, handler: (number) -> (), _options: boolean?): () -> ()
					handlers[handler] = true
					return function()
						handlers[handler] = nil
					end
				end,
				served = function(_name: string): number
					local count = 0
					for _ in handlers do
						count += 1
					end
					return count
				end,
				connect = function(_event: string, callback: (number, ...unknown) -> ()): () -> ()
					return signal.connect(function(value: unknown)
						if type(value) == "number" then
							callback(value)
						end
					end)
				end,
				receive = function(_name: string, player: number, ...: unknown)
					if limiter.admit(tostring(player), clock.clock()) then
						for handler in handlers do
							handler(player)
						end
					end
				end,
				own = function(release: () -> ())
					table.insert(owned, release)
				end,
			})
			local count = 0
			local first = transport.serve("event", "event", function(_player: number)
				count += 1
			end, nil)
			transport.serve("event", "event", function(_player: number)
				count += 10
			end, nil)
			expect(signal.count()):toBe(1)
			signal.fire(1)
			signal.fire(1)
			expect(count):toBe(11)
			signal.fire(2)
			expect(count):toBe(22)
			first()
			first()
			expect(signal.count()):toBe(1)
			clock.advance(1)
			signal.fire(1)
			expect(count):toBe(32)
			limiter.forget("1")
			signal.fire(1)
			expect(count):toBe(42)
			for _, release in owned do
				release()
			end
			expect(signal.count()):toBe(0)
		end)
	end)
end
