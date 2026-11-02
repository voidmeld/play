--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Social = require("../test-scene/social")
local Value = require("../core/value")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	local CHARTER = {
		fellowshipId = "f1",
		nameId = "ash_vigil",
		realmId = "dawnmoor",
		homeSlotId = "lightwood.guild_banner.village_courtyard",
		stewardUserId = 1,
		stewardName = "Alden",
	}

	local FORMATION_REQUEST = {
		formationId = "g1",
		nameId = "ash_vigil",
		realmId = "dawnmoor",
		homeSlotId = "lightwood.guild_banner.village_courtyard",
		initiatorId = 1,
		initiatorName = "Alden",
	}

	describe("social records durable guild record", function()
		it(
			"refuses missing and malformed write results while preserving committed guild and formation records",
			function()
				local corruptors = {
					function(_value: unknown): unknown
						return nil
					end,
					function(_value: unknown): unknown
						return false
					end,
					function(_value: unknown): unknown
						return { invalid = true }
					end,
				}
				for _, corrupt in corruptors do
					local service, _values, counters = Social.rig(corrupt)
					local founded = service.found(CHARTER)
					expect(founded.ok):toBe(false)
					expect(founded.state):toBeNil()
					expect(founded.reason):toBe("readback_mismatch")
					expect(service.read("f1").ok):toBe(true)
					local formation = service.startFormation(FORMATION_REQUEST)
					expect(formation.ok):toBe(false)
					expect(formation.state):toBeNil()
					expect(formation.reason):toBe("readback_mismatch")
					expect(service.readFormation("g1").ok):toBe(true)
					expect(counters.writes):toBe(2)
				end
			end
		)

		it("refuses foreign guild and formation identities before applying events", function()
			local invitation = {
				kind = "invite",
				eventId = "i1",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "dawnmoor",
			}
			local service, values, counters = Social.rig()
			assert(service.found(CHARTER).ok)
			local guild = table.clone(assert(service.read("f1").state))
			guild.fellowshipId = "other"
			values["fellowship/f1"] = guild
			local before = counters.writes
			expect(service.read("f1").ok):toBe(false)
			expect(service.apply("f1", invitation).ok):toBe(false)
			expect(counters.writes):toBe(before)
			expect(values["fellowship/f1"]):toBe(guild)
			local formed = service.startFormation(FORMATION_REQUEST)
			local formation = table.clone(assert(formed.state))
			formation.formationId = "other"
			values["fellowship/formation:g1"] = formation
			before = counters.writes
			expect(service.readFormation("g1").ok):toBe(false)
			expect(service.applyFormation("g1", invitation).ok):toBe(false)
			expect(counters.writes):toBe(before)
			expect(values["fellowship/formation:g1"]):toBe(formation)
		end)

		it("founds a record once and refuses a second charter under the same id", function()
			local service = Social.rig()
			expect(service.found(CHARTER).ok):toBe(true)
			local again = service.found(CHARTER)
			expect(again.ok):toBe(false)
			expect(again.reason):toBe("fellowship_exists")
			expect(assert(service.read("f1").state).members[1].name):toBe("Alden")
			expect(service.read("missing").reason):toBe("fellowship_unknown")
		end)

		it("applies an event on a server whose clock trails the record's last write", function()
			local service, _values, counters = Social.rig()
			service.found(CHARTER)
			counters.clock = 90
			local invited = service.apply("f1", {
				kind = "invite",
				eventId = "e1",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "dawnmoor",
			})
			expect(invited.ok):toBe(true)
			expect(assert(invited.state).revision):toBe(1)
		end)

		it("refuses old schemas without rewriting their stored records", function()
			for _, version in { 2, 3 } do
				local service, values, counters = Social.rig()
				service.found(CHARTER)
				local previous = assert(Value.raw(values["fellowship/f1"]))
				previous.schemaVersion = version
				previous.creed = nil
				if version == 2 then
					previous.officers, previous.stewardSeenAtSec, previous.audit = nil, nil, nil
				end
				values["fellowship/f1"] = previous
				local before = counters.writes
				expect(service.read("f1").ok):toBe(false)
				local event = {
					kind = "invite",
					eventId = "e1",
					expectedRevision = 0,
					actorUserId = 1,
					targetUserId = 2,
					targetRealmId = "dawnmoor",
				}
				local refused = service.apply("f1", event)
				expect(refused.ok):toBe(false)
				expect(refused.reason):toBe("record_invalid")
				expect(counters.writes):toBe(before)
				expect(values["fellowship/f1"]):toBe(previous)
				expect(previous.schemaVersion):toBe(version)
			end
		end)

		it("lets only one of a returning steward and a claiming officer win the same revision", function()
			local service, _values, counters = Social.rig()
			service.found(CHARTER)
			local function step(event: unknown)
				return service.apply("f1", event)
			end
			expect(step({
				kind = "invite",
				eventId = "i2",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "dawnmoor",
			}).ok):toBe(true)
			expect(step({
				kind = "accept",
				eventId = "a2",
				expectedRevision = 1,
				actorUserId = 2,
				actorRealmId = "dawnmoor",
				actorName = "Bryn",
			}).ok):toBe(true)
			expect(
				step({ kind = "promote", eventId = "p2", expectedRevision = 2, actorUserId = 1, targetUserId = 2 }).ok
			):toBe(true)
			counters.clock += 31 * 24 * 60 * 60
			local claim = { kind = "claim", eventId = "claim", expectedRevision = 3, actorUserId = 2 }
			local returning = { kind = "seen", eventId = "seen", expectedRevision = 3, actorUserId = 1 }
			expect(step(returning).ok):toBe(true)
			local late = step(claim)
			expect(late.ok):toBe(false)
			expect(late.reason):toBe("revision_conflict")
			local retried = step({ kind = "claim", eventId = "claim2", expectedRevision = 4, actorUserId = 2 })
			expect(retried.reason):toBe("steward_present")
			expect(assert(service.read("f1").state).stewardUserId):toBe(1)
		end)

		it("forms a guild once from five consenting founders even when two servers complete together", function()
			local service = Social.rig()
			local formed = service.startFormation(FORMATION_REQUEST)
			expect(formed.ok):toBe(true)
			expect(service.startFormation(FORMATION_REQUEST).reason):toBe("formation_exists")
			local revision = 0
			local function apply(event: { [string]: unknown })
				event.expectedRevision = revision
				local result = service.applyFormation("g1", event)
				if result.ok and not result.replayed then
					revision = assert(result.state).revision
				end
				return result
			end
			for id = 2, 5 do
				expect(apply({
					kind = "invite",
					eventId = "i" .. id,
					actorUserId = 1,
					targetUserId = id,
					targetRealmId = "dawnmoor",
				}).ok):toBe(true)
				expect(apply({
					kind = "consent",
					eventId = "c" .. id,
					actorUserId = id,
					actorRealmId = "dawnmoor",
					actorName = "M" .. id,
				}).ok):toBe(true)
			end
			expect(apply({ kind = "fee_held", eventId = "fee", actorUserId = 1 }).ok):toBe(true)
			local before = revision
			local first = apply({ kind = "complete", eventId = "done-a", actorUserId = 1 })
			revision = before
			local second = apply({ kind = "complete", eventId = "done-b", actorUserId = 1 })
			expect(first.ok):toBe(true)
			expect(second.ok):toBe(false)
			expect(second.reason):toBe("revision_conflict")
			local state = assert(service.readFormation("g1").state)
			local founded = service.foundFromFormation(state)
			expect(founded.ok):toBe(true)
			expect(#assert(founded.state).members):toBe(5)
			expect(service.foundFromFormation(state).reason):toBe("fellowship_exists")
			local corrupt = Social.rig(function(_value: unknown): unknown
				return nil
			end)
			local uncertain = corrupt.foundFromFormation(state)
			expect(uncertain.ok):toBe(false)
			expect(uncertain.state):toBeNil()
			expect(uncertain.reason):toBe("readback_mismatch")
			expect(#assert(corrupt.read(state.fellowshipId).state).members):toBe(5)
		end)

		it("answers an exact replay from the record without writing again", function()
			local service, _values, counters = Social.rig()
			service.found(CHARTER)
			local event = {
				kind = "invite",
				eventId = "e1",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "dawnmoor",
			}
			service.apply("f1", event)
			local writes = counters.writes
			local replay = service.apply("f1", event)
			expect(replay.ok):toBe(true)
			expect(replay.replayed):toBe(true)
			expect(counters.writes):toBe(writes)
		end)

		it("refuses a stale revision and a corrupt record without writing", function()
			local service, values, counters = Social.rig()
			service.found(CHARTER)
			local writes = counters.writes
			local stale = service.apply("f1", { kind = "leave", eventId = "e2", expectedRevision = 7, actorUserId = 1 })
			expect(stale.reason):toBe("revision_conflict")
			values["fellowship/f1"] = { schemaVersion = 1 }
			expect(
				service.apply("f1", { kind = "leave", eventId = "e3", expectedRevision = 0, actorUserId = 1 }).reason
			):toBe("record_invalid")
			expect(counters.writes):toBe(writes)
		end)
	end)

	describe("social records durable membership index", function()
		it("claims a pending membership, confirms it, and releases only its own guild", function()
			local service = Social.rig()
			local claimed = service.claimMembership(7, "f1")
			expect(claimed.ok):toBe(true)
			expect(assert(claimed.membership).pending):toBe(true)
			expect(assert(service.confirmMembership(7, "f1").membership).pending):toBe(false)
			local seen = assert(service.readMembership(7).membership)
			expect(
				assert(
					service.releaseMembership(7, { fellowshipId = "other", pending = false, revision = seen.revision }).membership
				).fellowshipId
			):toBe("f1")
			expect(service.releaseMembership(7, seen).membership):toBeNil()
			expect(service.readMembership(7).membership):toBeNil()
		end)

		it("refuses a second guild while one claim is held, even a pending one from another server", function()
			local service = Social.rig()
			service.claimMembership(7, "f1")
			local second = service.claimMembership(7, "f2")
			expect(second.ok):toBe(false)
			expect(second.reason):toBe("membership_held")
			expect(service.claimMembership(7, "f1").ok):toBe(true)
		end)

		it("refuses to confirm a claim that moved elsewhere", function()
			local service = Social.rig()
			service.claimMembership(7, "f1")
			expect(service.confirmMembership(7, "f2").reason):toBe("membership_moved")
		end)
	end)

	describe("social records membership release is compare-and-swap", function()
		it("keeps a claim that was rewritten after the releaser read it", function()
			local service = Social.rig()
			service.claimMembership(7, "f1")
			local stale = assert(service.readMembership(7).membership)
			service.confirmMembership(7, "f1")
			local kept = service.releaseMembership(7, stale)
			expect(kept.ok):toBe(true)
			expect(assert(kept.membership).fellowshipId):toBe("f1")
			expect(assert(kept.membership).pending):toBe(false)
			expect(assert(service.readMembership(7).membership).fellowshipId):toBe("f1")
		end)

		it("keeps a fresh claim of the same guild made after an earlier release", function()
			local service = Social.rig()
			service.claimMembership(7, "f1")
			local first = assert(service.readMembership(7).membership)
			service.releaseMembership(7, first)
			service.claimMembership(7, "f1")
			expect(assert(service.releaseMembership(7, first).membership).fellowshipId):toBe("f1")
			expect(assert(service.readMembership(7).membership).revision > first.revision):toBe(true)
		end)
	end)
end
