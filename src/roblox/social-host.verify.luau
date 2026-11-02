--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Host = require("./social-host")
local Social = require("../test-scene/social")
local Verify = require("../../.lute/dependencies/verify/src/core")

local CHARTER = {
	fellowshipId = "f1",
	nameId = "ash_vigil",
	realmId = "dawnmoor",
	homeSlotId = "lightwood.guild_banner.village_courtyard",
	stewardUserId = 1,
	stewardName = "Alden",
}

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("social host", function()
		it("confirms a claimed membership once the record commits and serves it from cache", function()
			local records, _values, counters = Social.rig()
			local host = Host.fellowships(records)
			local result = host.claimThenCommit(1, "f1", function()
				return records.found(CHARTER)
			end)
			expect(result.ok):toBe(true)
			local cached = assert(host.cachedMembership(1))
			expect(cached.pending):toBe(false)
			local writes = counters.writes
			expect(host.membershipOf(1, false)):toBe(cached)
			expect(host.loadRecord("f1", false).ok):toBe(true)
			expect(counters.writes):toBe(writes)
			expect(host.settle(1)):toBe("f1")
		end)

		it("releases a claim whose commit was refused", function()
			local records = Social.rig()
			local host = Host.fellowships(records)
			records.found(CHARTER)
			local result = host.claimThenCommit(2, "f1", function()
				return records.found(CHARTER)
			end)
			expect(result.ok):toBe(false)
			expect(host.membershipOf(2, true)):toBeNil()
			expect(records.readMembership(2).membership):toBeNil()
		end)

		it("refuses a second claim while another fellowship holds the membership", function()
			local records = Social.rig()
			local host = Host.fellowships(records)
			host.claimThenCommit(1, "f1", function()
				return records.found(CHARTER)
			end)
			local again = host.claimThenCommit(1, "f2", function()
				return records.found(CHARTER)
			end)
			expect(again.ok):toBe(false)
			expect(again.reason):toBe("membership_held")
		end)

		it("settles a membership whose record never existed", function()
			local records = Social.rig()
			local host = Host.fellowships(records)
			records.claimMembership(5, "ghost")
			expect(host.settle(5)):toBeNil()
			expect(records.readMembership(5).membership):toBeNil()
		end)

		it("serializes one actor and skips settling while busy", function()
			local records = Social.rig()
			local host = Host.fellowships(records)
			local inner: unknown = nil
			local outer = host.serially(9, function()
				inner = host.serially(9, function()
					return "ran"
				end)
				return "outer"
			end)
			expect(outer):toBe("outer")
			expect(inner):toEqual({ ok = false, state = nil, replayed = false, reason = "social_busy" })
			expect(host.serially(9, function()
				return "again"
			end)):toBe("again")
		end)

		it("commits events through the record and refreshes its cache", function()
			local records = Social.rig()
			local host = Host.fellowships(records)
			records.found(CHARTER)
			local result = host.commitRecord("f1", {
				kind = "invite",
				eventId = "e1",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "dawnmoor",
			})
			expect(result.ok):toBe(true)
			expect(assert(host.cachedRecord("f1")).revision):toBe(1)
		end)

		it("reports unavailable records when none are configured", function()
			local host = Host.fellowships(nil)
			expect(host.loadRecord("f1", true).reason):toBe("fellowship_unavailable")
			expect(host.membershipOf(1, true)):toBeNil()
			expect(host.settle(1)):toBeNil()
		end)
	end)
end
