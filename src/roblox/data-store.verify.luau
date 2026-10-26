--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Clock = require("../test-scene/clock")
local DataStore = require("./data-store")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("data store", function()
		it("retries transient failures on the fake host clock and returns the committed result", function()
			local clock = Clock.new()
			local retry = DataStore.retryPolicy({ attempts = 4, baseDelay = 0.5, maxDelay = 8 })
			local calls = 0
			local ok, result = retry.run(
				function(): (boolean, string)
					calls += 1
					return calls == 3, if calls == 3 then "committed" else "offline"
				end,
				clock.advance,
				function(): number
					return 1
				end
			)
			expect(ok):toBe(true)
			expect(result):toBe("committed")
			expect(calls):toBe(3)
			expect(clock.clock()):toBe(1.5)
			expect(retry.delay(10, 0.5)):toBe(4)
		end)
		it("exhausted attempts preserve failure instead of claiming a save", function()
			local clock = Clock.new()
			local retry = DataStore.retryPolicy({ attempts = 4, baseDelay = 0.5, maxDelay = 8 })
			local calls = 0
			local ok, result = retry.run(
				function(): (boolean, string)
					calls += 1
					return false, "offline"
				end,
				clock.advance,
				function(): number
					return 1
				end
			)
			expect(ok):toBe(false)
			expect(result):toBe("offline")
			expect(calls):toBe(4)
			expect(clock.clock()):toBe(3.5)
		end)
	end)
end
