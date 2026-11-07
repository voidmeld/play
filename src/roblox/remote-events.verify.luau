--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Events = require("./remote-events")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("remote events", function()
		it("one dispatcher per channel survives partial release and disconnects the last", function(own)
			local engine = Roblox.testEnvironment({ handlerErrors = "raise" })
			local signal: Roblox.Signal<unknown> = engine.newSignal()
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
					local connection = signal:Connect(function(value: unknown)
						if type(value) == "number" then
							callback(value)
						end
					end)
					return function()
						connection:Disconnect()
					end
				end,
				receive = function(_name: string, player: number, ...: unknown)
					for handler in handlers do
						handler(player)
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
			expect(engine.connectionsOf(signal)):toBe(1)
			signal:Fire(1)
			expect(count):toBe(11)
			signal:Fire(2)
			expect(count):toBe(22)
			first()
			first()
			expect(engine.connectionsOf(signal)):toBe(1)
			signal:Fire(1)
			expect(count):toBe(32)
			signal:Fire(1)
			expect(count):toBe(42)
			for _, release in owned do
				release()
			end
			expect(engine.connectionsOf(signal)):toBe(0)
		end)
	end)
end
