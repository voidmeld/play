--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Lease = require("./account-lease")
local Value = require("../value")

local Verify = require("../../../.lute/dependencies/verify/src/core")

type Record = Lease.Lease
type Raw = { [unknown]: unknown }

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("CharacterAccountLeaseRecord", function()
		it("acquires one fenced account lease and permits exact-expiry takeover", function()
			local empty = Lease.empty(101)
			expect(empty).never:toBeNil()
			assert(empty ~= nil, "empty lease missing")
			expect(table.isfrozen(empty)):toBe(true)
			expect(empty.revision):toBe(0)
			expect(empty.fence):toBe(0)
			local first, status = Lease.acquire(empty, 101, "session.a", "acquisition.a", 100, 180)
			expect(status):toBe("acquired")
			assert(first ~= nil, "first lease missing")
			expect(first.revision):toBe(1)
			expect(first.fence):toBe(1)
			expect(first.expiresAtUnix):toBe(280)
			expect(select(2, Lease.acquire(first, 101, "session.a", "acquisition.a", 101, 180))):toBe("owned")
			expect(select(2, Lease.acquire(first, 101, "session.b", "acquisition.b", 279, 180))):toBe("held")
			local takeover, takeoverStatus = Lease.acquire(first, 101, "session.b", "acquisition.b", 280, 180)
			expect(takeoverStatus):toBe("acquired")
			assert(takeover ~= nil, "takeover lease missing")
			expect(takeover.revision):toBe(2)
			expect(takeover.fence):toBe(2)
			expect(takeover.sessionId):toBe("session.b")
		end)

		it("renews without changing its fence and releases only exact ownership", function()
			local acquired = (Lease.acquire(nil, 101, "session", "acquisition", 100, 180))
			local renewed, renewStatus = Lease.renew(acquired, 101, "session", "acquisition", 1, 1, 120, 180)
			expect(renewStatus):toBe("renewed")
			assert(renewed ~= nil, "renewed lease missing")
			expect(renewed.revision):toBe(2)
			expect(renewed.fence):toBe(1)
			expect(renewed.expiresAtUnix):toBe(300)
			expect(select(2, Lease.renew(renewed, 101, "foreign", "acquisition", 2, 1, 130, 180))):toBe("not_owned")
			local released, releaseStatus = Lease.release(renewed, 101, "session", "acquisition", 2, 1)
			expect(releaseStatus):toBe("released")
			assert(released ~= nil, "released lease missing")
			expect(released.revision):toBe(3)
			expect(released.fence):toBe(1)
			expect(released.sessionId):toBe(false)
			expect(released.acquisitionId):toBe(false)
			expect(released.expiresAtUnix):toBe(0)
			expect(select(2, Lease.release(released, 101, "session", "acquisition", 2, 1))):toBe("absent")
		end)

		it("classifies stale, expired, foreign, absent, and exhausted records without mutation", function()
			local active = (Lease.acquire(nil, 101, "session", "acquisition", 100, 20))
			local before = Lease.copy(active)
			expect(select(2, Lease.renew(active, 101, "session", "acquisition", 0, 1, 101, 20))):toBe("stale")
			expect(select(2, Lease.renew(active, 101, "session", "acquisition", 1, 1, 120, 20))):toBe("expired")
			expect(select(2, Lease.release(active, 202, "session", "acquisition", 1, 1))):toBe("identity_mismatch")
			expect(select(2, Lease.renew(nil, 101, "session", "acquisition", 1, 1, 100, 20))):toBe("absent")
			expect(Lease.equal(active, before)):toBe(true)
			local maximum = assert(Value.raw(active))
			maximum.revision = Lease.MAX_REVISION
			maximum.fence = Lease.MAX_FENCE
			maximum.expiresAtUnix = 100
			expect(select(2, Lease.acquire(maximum, 101, "next", "next", 100, 20))):toBe("exhausted")
			expect(
				select(2, Lease.release(maximum, 101, "session", "acquisition", Lease.MAX_REVISION, Lease.MAX_FENCE))
			):toBe("exhausted")
		end)

		it(
			"refuses a release or renewal that does not name the exact session, acquisition, fence, and revision",
			function()
				local acquired = (Lease.acquire(nil, 101, "session", "acquisition", 100, 180))
				expect(select(2, Lease.release(acquired, 101, "foreign", "acquisition", 1, 1))):toBe("not_owned")
				expect(select(2, Lease.release(acquired, 101, "session", "foreign", 1, 1))):toBe("not_owned")
				expect(select(2, Lease.release(acquired, 101, "session", "acquisition", 1, 2))):toBe("not_owned")
				expect(select(2, Lease.release(acquired, 101, "session", "acquisition", 0, 1))):toBe("stale")
				expect(select(2, Lease.renew(acquired, 101, "session", "foreign", 1, 1, 120, 180))):toBe("not_owned")
				expect(select(2, Lease.renew(acquired, 101, "session", "acquisition", 1, 2, 120, 180))):toBe(
					"not_owned"
				)
			end
		)

		it("exhausts an acquisition on a spent fence and on a spent revision independently", function()
			local active = (Lease.acquire(nil, 101, "session", "acquisition", 100, 20))
			local spentFence = assert(Value.raw(active))
			spentFence.fence = Lease.MAX_FENCE
			spentFence.expiresAtUnix = 100
			expect(select(2, Lease.acquire(spentFence, 101, "next", "next", 100, 20))):toBe("exhausted")
			local spentRevision = assert(Value.raw(active))
			spentRevision.revision = Lease.MAX_REVISION
			spentRevision.expiresAtUnix = 100
			expect(select(2, Lease.acquire(spentRevision, 101, "next", "next", 100, 20))):toBe("exhausted")
		end)

		it("rejects sparse, extra, unsafe, nonfinite, and contradictory carriers", function()
			local valid = (Lease.empty(101))
			for _, edit in
				{
					function(value: Raw)
						value.schemaVersion = 2
					end,
					function(value: Raw)
						value.userId = 9007199254740992
					end,
					function(value: Raw)
						value.revision = math.nan
					end,
					function(value: Raw)
						value.fence = math.huge
					end,
					function(value: Raw)
						value.sessionId = "session"
					end,
					function(value: Raw)
						value.extra = true
					end,
				}
			do
				local changed = assert(Value.raw(valid))
				edit(changed)
				expect(Lease.validate(changed)):toBeNil()
			end
			local sparse = assert(Value.raw(valid))
			sparse.acquisitionId = nil
			expect(Lease.validate(sparse)):toBeNil()
			local meta = assert(Value.raw(valid))
			setmetatable(meta, {})
			expect(Lease.validate(meta)):toBeNil()
		end)

		it("fails invalid requests before transitions and preserves detached immutable outputs", function()
			local current = (Lease.acquire(nil, 101, "session", "acquisition", 100, 20))
			for _, value in { math.nan, math.huge, -1, 9007199254740992 } do
				expect(select(2, Lease.acquire(current, 101, "session", "acquisition", value, 20))):toBe("invalid")
			end
			expect(select(2, Lease.acquire(current, 101, "", "acquisition", 100, 20))):toBe("invalid")
			local copy = assert(Lease.copy(current))
			expect(copy).never:toBe(current)
			expect(Lease.equal(copy, current)):toBe(true)
			expect(function()
				(copy).revision = 5
			end):toThrow()
		end)
	end)
end
