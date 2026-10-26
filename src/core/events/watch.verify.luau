--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Shape = require("../social/shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local Watch = require("./watch")
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("watch", function()
		local config: Watch.Config = {
			realms = { realm = true },
			workPointCount = 2,
			minProtectionPlacements = 1,
			protectionTarget = 2,
			ticketPrefix = "watch",
			ordinaryTiers = { ordinary = true },
		}
		local law = Watch.watch(config)
		local function event(): Watch.Event
			return {
				workPoints = {
					{ id = "work-a", actionText = "Work", position = { x = 0, y = 0, z = 0 } },
					{ id = "work-b", actionText = "Work", position = { x = 1, y = 1, z = 1 } },
				},
				protectionPlacementIds = { "placement" },
				id = "event",
				realmId = "realm",
				zoneKey = "zone",
				surfacePoiId = "site",
				surfaceName = "Site",
				questId = "quest",
				mobId = "mob",
				arrivalText = "Arrival",
				activeText = "Active",
				successText = "Success",
				failureText = "Failure",
				rewardId = "reward",
				durationSec = 20,
				recoverySec = 5,
				maxParticipants = 2,
			}
		end
		it("validates configured realms, work and protection bindings", function()
			local e = event()
			expect(law.projectEvent(e) ~= nil):toBe(true)
			expect(law.projectEvent(false)):toBeNil()
			local raw = assert(Shape.raw(e))
			raw.extra = true
			expect(law.projectEvent(raw)):toBeNil()
			e = event()
			e.realmId = "other"
			expect(law.projectEvent(e)):toBeNil()
			e = event()
			e.workPoints[2].id = "work-a"
			expect(law.projectEvent(e)):toBeNil()
			e = event()
			e.workPoints[1].position.x = math.huge
			expect(law.projectEvent(e)):toBeNil()
			e = event()
			e.protectionPlacementIds = {}
			expect(law.projectEvent(e)):toBeNil()
			e = event()
			e.durationSec = 0
			expect(law.projectEvent(e)):toBeNil()
			e = event()
			expect(
				law.protectionBindingsValid(e, { placement = { mobId = "mob" } }, { { id = "mob", tier = "ordinary" } })
			):toBe(true)
			expect(law.protectionBindingsValid(e, { placement = { mobId = "mob" } }, { { id = "mob", tier = "boss" } })):toBe(
				false
			)
			expect(law.protectionBindingsValid(e, {}, {})):toBe(false)
			expect(law.protectionBindingsValid(e, false, {})):toBe(false)
		end)
		it("starts cycles, admits only the realm, bounds participants and replays joins", function()
			local e = event()
			local empty = law.emptyState()
			expect(law.join(empty, e, "a", "other", 1).reason):toBe("participant_refused")
			local first = law.join(empty, e, "a", "realm", 1)
			expect(empty.cycle):toBe(0)
			expect(first.state.target):toBe(4)
			expect(law.join(first.state, e, "a", "realm", 1).replayed):toBe(true)
			local second = law.join(first.state, e, "b", "realm", 2)
			expect(law.join(second.state, e, "c", "realm", 2).reason):toBe("watch_full")
			local left = law.leave(second.state, e, "b", 3)
			expect(left.state.participantCount):toBe(1)
			expect(law.leave(left.state, e, "b", 3).replayed):toBe(true)
			expect(law.sync(left.state, e, 2).reason):toBe("sync_refused")
			expect(law.sync(left.state, e, math.huge).ok):toBe(false)
		end)
		it("deduplicates work and protection, succeeds, and claims one stable ticket per contributor", function()
			local e = event()
			local s = law.join(law.emptyState(), e, "a", "realm", 1).state
			s = law.join(s, e, "b", "realm", 2).state
			expect(law.work(s, e, "outsider", "realm", "work-a", 3).reason):toBe("contributor_refused")
			expect(law.work(s, e, "a", "realm", "missing", 3).reason):toBe("work_refused")
			s = law.work(s, e, "a", "realm", "work-a", 3).state
			expect(law.work(s, e, "a", "realm", "work-a", 3).replayed):toBe(true)
			s = law.work(s, e, "a", "realm", "work-b", 4).state
			expect(law.protect(s, e, "", { "a" }, 4).reason):toBe("contributor_refused")
			s = law.protect(s, e, "p1", { "a", "a", "outsider" }, 4).state
			expect(law.protect(s, e, "p1", { "a" }, 4).replayed):toBe(true)
			s = law.protect(s, e, "p2", { "a" }, 5).state
			expect(s.phase):toBe("succeeded")
			expect(s.contributions.a):toBe(4)
			expect(law.protect(s, e, "p3", { "a" }, 5).reason):toBe("protection_complete")
			expect(law.claim(s, e, "b", "realm", 5).reason):toBe("no_eligible_contribution")
			local first = law.claim(s, e, "a", "realm", 5)
			expect(first.rewardTicket):toBe("watch:event:1:a")
			expect(first.rewardId):toBe("reward")
			local replay = law.claim(first.state, e, "a", "realm", 6)
			expect(replay.replayed):toBe(true)
			expect(replay.rewardTicket):toBe(first.rewardTicket)
			expect(law.join(s, e, "c", "realm", 6).reason):toBe("event_not_active")
			local nextCycle = law.join(first.state, e, "a", "realm", 10)
			expect(nextCycle.state.cycle):toBe(2)
			expect(nextCycle.state.claims):toEqual({})
		end)
		it("fails at the deadline and clears the cycle after recovery", function()
			local e = event()
			local s = law.join(law.emptyState(), e, "a", "realm", 1).state
			expect(law.claim(s, e, "a", "realm", 2).reason):toBe("claim_unavailable")
			local failed = law.sync(s, e, 21)
			expect(failed.state.phase):toBe("failed")
			expect(failed.state.recoversAtSec):toBe(26)
			expect(law.sync(failed.state, e, 26).state):toEqual({
				workDone = {},
				protectionCount = 0,
				lastClockSec = 26,
				cycle = 1,
				phase = "dormant",
				target = 0,
				progress = 0,
				participantCount = 0,
				participants = {},
				contributions = {},
				contributionEvents = {},
				claims = {},
			})
		end)
	end)
end
