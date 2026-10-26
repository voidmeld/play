--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Rate = require("./rate-limit")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("rate limit", function()
		it("keyed budgets isolate senders and preserve the input state", function()
			local budget = { capacity = 2, refillPerSec = 1 }
			local initial: Rate.KeyedState = {}
			local allowed, first = Rate.consume(initial, "one", budget, 0, 2)
			expect(allowed):toBe(true)
			expect(initial.one):toBeNil()
			local denied, exhausted = Rate.consume(first, "one", budget, 0)
			expect(denied):toBe(false)
			local other = Rate.consume(exhausted, "two", budget, 0)
			expect(other):toBe(true)
			local refilled = Rate.consume(exhausted, "one", budget, 1)
			expect(refilled):toBe(true)
		end)
	end)
end
