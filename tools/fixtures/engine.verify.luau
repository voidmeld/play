--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Engine = require("./engine")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("simulated host ports", function()
		it("cancels timers and releases child resources through Instance destruction", function()
			local environment = Roblox.testEnvironment({ handlerErrors = "raise" })
			local clock = Engine.clock(environment)
			local owner = Engine.owner(environment)
			local child = owner.createChild()
			local calls = 0
			child.own(clock.schedule(1, function()
				calls += 1
			end))
			expect(child.size()):toBe(1)
			owner.dispose()
			clock.advance(2)
			expect(calls):toBe(0)
			expect(child.size()):toBe(0)
			child.own(function()
				calls += 1
			end)
			expect(calls):toBe(1)
			owner.createChild().own(function()
				calls += 1
			end)
			expect(calls):toBe(2)
			expect(environment.scheduler.pending()):toBe(0)
		end)
		it("starts yielding listeners independently and preserves connection order", function()
			local environment = Roblox.testEnvironment({ handlerErrors = "raise" })
			local signal: Roblox.Signal<number> = environment.newSignal()
			local seen: { number } = {}
			signal:Connect(function(value)
				table.insert(seen, value)
				environment.scheduler.wait(1)
				table.insert(seen, value + 2)
			end)
			signal:Connect(function(value)
				table.insert(seen, value + 1)
			end)
			signal:Fire(1)
			expect(seen):toEqual({ 1, 2 })
			environment.step(1)
			expect(seen):toEqual({ 1, 2, 3 })
			expect(environment.errors):toEqual({})
			signal:DisconnectAll()
			expect(environment.liveConnections()):toBe(0)
		end)
	end)
end
