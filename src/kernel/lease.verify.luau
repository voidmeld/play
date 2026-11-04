--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Lease = require("./lease")
local Result = require("./result")
local Verify = require("../../.lute/dependencies/verify/src/core")

local rules = Lease.configure({
	maxRevision = 10,
	maxTime = 100,
	sessionIdLimit = 16,
	acquisitionIdLimit = 16,
	integerTime = false,
})

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("lease generations", function()
		it(
			"retains acquisition identity through replay, renewal and release without mutating the prior state",
			function()
				local initial: Lease.State = { revision = 0, expiresAt = 0 }
				local request = { sessionId = "owner", acquisitionId = "first", now = 1.5, ttl = 10 }
				local acquired = Result.unwrap(rules.acquire(initial, request))
				expect(acquired.kind):toBe("acquired")
				expect(Result.unwrap(rules.acquire(acquired.state, request)).kind):toBe("owned")
				local expected = { sessionId = "owner", acquisitionId = "first", revision = 1, now = 2, ttl = 10 }
				local renewed = Result.unwrap(rules.renew(acquired.state, expected)).state
				expect(renewed.revision):toBe(2)
				expect(renewed.expiresAt):toBe(12)
				expect(rules.release(renewed, expected).ok):toBe(false)
				local released = Result.unwrap(
					rules.release(renewed, { sessionId = "owner", acquisitionId = "first", revision = 2 })
				)
				expect(released.state.revision):toBe(3)
				expect(released.state.sessionId):toBeNil()
				expect(initial.revision):toBe(0)
				expect(acquired.state.expiresAt):toBe(11.5)
			end
		)

		it("keeps uncertain ownership closed and rejects invalid state and time", function()
			local held: Lease.State = { revision = 1, sessionId = "other", acquisitionId = "prior", expiresAt = 10 }
			local request: {
				sessionId: string,
				acquisitionId: string,
				now: number,
				ttl: number,
				liveness: Lease.Liveness?,
			} =
				{ sessionId = "owner", acquisitionId = "next", now = 9, ttl = 10 }
			expect(rules.acquire(held, request).ok):toBe(false)
			request.liveness = "dead"
			expect(Result.unwrap(rules.acquire(held, request)).state.revision):toBe(2)
			request.now, request.liveness = 11, "alive"
			expect(rules.acquire(held, request).ok):toBe(false)
			request.liveness = "unknown"
			expect(rules.acquire(held, request).ok):toBe(true)
			request.ttl = math.huge
			expect(rules.acquire(held, request).ok):toBe(false)
			for _, value in
				{
					setmetatable({ revision = 0, expiresAt = 0 }, {}),
					{ revision = 0, expiresAt = 1 },
					{ revision = 0, expiresAt = 0, sessionId = "partial" },
				}
			do
				expect(rules.copy(value).ok):toBe(false)
			end
		end)
	end)
end
