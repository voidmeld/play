--!strict

local Lock = require("./session-lock")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	suite:case("acquisition, renewal, expiry takeover and release preserve exclusive ownership", function(t)
		local acquired = Lock.tryAcquire({ sessionId = nil, lockExpiry = 0 }, "one", 1, 10)
		t:expect(acquired.granted):toBe(true)
		local state = assert(acquired.newState)
		t:expect(Lock.tryAcquire(state, "two", 2, 10).granted):toBe(false)
		t:expect(Lock.release(state, "two")):toBeNil()
		t:expect(Lock.isLocked(state, "one", 10)):toBe(true)
		t:expect(Lock.isLocked(state, "one", 11)):toBe(false)
		local renewed = Lock.tryAcquire(state, "one", 10, 10)
		t:expect(assert(renewed.newState).lockExpiry):toBe(20)
		local takeover = Lock.tryAcquire(state, "two", 11, 10)
		t:expect(takeover.reason):toBe("steal")
		t:expect(Lock.release(assert(takeover.newState), "two")):toEqual({ sessionId = nil, lockExpiry = 0 })
	end)
end
