--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Lock = require("./session-lock")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("session lock", function()
		it("acquisition, renewal, expiry takeover and release preserve exclusive ownership", function()
			local acquired = Lock.tryAcquire({ sessionId = nil, lockExpiry = 0 }, "one", 1, 10)
			expect(acquired.granted):toBe(true)
			local state = assert(acquired.newState)
			expect(Lock.tryAcquire(state, "two", 2, 10).granted):toBe(false)
			expect(Lock.release(state, "two")):toBeNil()
			expect(Lock.isLocked(state, "one", 10)):toBe(true)
			expect(Lock.isLocked(state, "one", 11)):toBe(false)
			local renewed = Lock.tryAcquire(state, "one", 10, 10)
			expect(assert(renewed.newState).lockExpiry):toBe(20)
			local takeover = Lock.tryAcquire(state, "two", 11, 10)
			expect(takeover.reason):toBe("steal")
			expect(Lock.release(assert(takeover.newState), "two")):toEqual({ sessionId = nil, lockExpiry = 0 })
		end)
	end)
end
