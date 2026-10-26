--!strict

local Rate = require("./rate-limit")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	suite:case("keyed budgets isolate senders and preserve the input state", function(t)
		local budget = { capacity = 2, refillPerSec = 1 }
		local initial: Rate.KeyedState = {}
		local allowed, first = Rate.consume(initial, "one", budget, 0, 2)
		t:expect(allowed):toBe(true)
		t:expect(initial.one):toBeNil()
		local denied, exhausted = Rate.consume(first, "one", budget, 0)
		t:expect(denied):toBe(false)
		local other = Rate.consume(exhausted, "two", budget, 0)
		t:expect(other):toBe(true)
		local refilled = Rate.consume(exhausted, "one", budget, 1)
		t:expect(refilled):toBe(true)
	end)
end
