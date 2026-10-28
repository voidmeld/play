--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Cargo = require("./cargo")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local claims = Cargo.create({
	maxText = 256,
	maxCount = 1000,
	maxAt = 10000,
	ledgerEventKind = "deposit",
	intentPrefix = "delivery",
	intentSeparator = "/",
})
local function step(state: Cargo.State, command: Cargo.Command, at: number): Cargo.Result
	local result, reason = claims.step(state, command, at)
	assert(result, reason)
	return result
end
local function carry(): Cargo.State
	return step(claims.emptyState(), {
		kind = "carry",
		claimId = "claim-a",
		actorId = "carrier-a",
		materialId = "ore",
		count = 7,
	}, 1).state
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("Cargo claim custody", function()
		it("hands off a dropped claim once and deposits it with replay-safe credit", function()
			local initial = carry()
			local dropped = step(initial, {
				kind = "release",
				dropId = "drop-a",
				actorId = "carrier-a",
				cause = "death",
				expiresAtSec = 20,
			}, 2)
			expect(initial.claims[1].status):toBe("carried")
			expect(dropped.droppedCount):toBe(7)
			local recovered = step(dropped.state, { kind = "recover", dropId = "drop-a", actorId = "carrier-b" }, 3)
			expect(recovered.recoveredCount):toBe(7)
			local refused, reason =
				claims.step(recovered.state, { kind = "recover", dropId = "drop-a", actorId = "carrier-c" }, 4)
			expect(refused):toBeNil()
			expect(reason):toBe("drop_taken")
			local command: Cargo.Command =
				{ kind = "extract", extractionId = "delivery-a", actorId = "carrier-b", campId = "depot-a" }
			local delivered = step(recovered.state, command, 4)
			expect(delivered.bankedCount):toBe(7)
			expect(delivered.intents[1].eventId):toBe("delivery/delivery-a/ore")
			expect(delivered.intents[1].kind):toBe("deposit")
			local replay = step(delivered.state, command, 5)
			expect(replay.replayed):toBe(true)
			expect(replay.intents):toContain(delivered.intents[1])
			expect(#replay.state.extractions):toBe(1)
			local totals = claims.census(replay.state)
			assert(totals)
			expect(totals[1].banked):toBe(7)
		end)
		it("expires cargo at the deadline without permitting recovery or duplicating loss", function()
			local dropped = step(
				carry(),
				{ kind = "release", dropId = "drop-a", actorId = "carrier-a", cause = "disconnect", expiresAtSec = 10 },
				2
			)
			local recovered, reason =
				claims.step(dropped.state, { kind = "recover", dropId = "drop-a", actorId = "carrier-b" }, 10)
			expect(recovered):toBeNil()
			expect(reason):toBe("drop_expired")
			local lost = step(dropped.state, { kind = "expire", dropId = "drop-a" }, 10)
			expect(lost.expiredCount):toBe(7)
			local replay = step(lost.state, { kind = "expire", dropId = "drop-a" }, 11)
			expect(replay.expiredCount):toBe(0)
			expect(replay.replayed):toBe(true)
			local retired = claims.retireTransient(replay.state)
			assert(retired)
			expect(#retired.claims):toBe(0)
		end)
		it("refuses conflicting claims, regressed clocks and inconsistent saved custody", function()
			local initial = carry()
			local result, reason = claims.step(
				initial,
				{ kind = "carry", claimId = "claim-a", actorId = "carrier-b", materialId = "ore", count = 7 },
				2
			)
			expect(result):toBeNil()
			expect(reason):toBe("claim_conflict")
			local regressed, clockReason = claims.step(initial, { kind = "expire", dropId = "unknown" }, 0)
			expect(regressed):toBeNil()
			expect(clockReason):toBe("clock_regressed")
			local corrupt = {
				lastClockSec = 1,
				claims = {
					{
						claimId = "claim-a",
						actorId = "carrier-a",
						materialId = "ore",
						count = 7,
						status = "banked",
						holderId = "missing",
					},
				},
				drops = {},
				extractions = {},
			}
			local saved, savedReason = claims.projectState(corrupt)
			expect(saved):toBeNil()
			expect(savedReason):toBe("state_invalid")
		end)
	end)
end
