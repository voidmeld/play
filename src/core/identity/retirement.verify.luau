--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Retirement = require("./retirement")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("retirement planning", function()
		local retiring = { withdrawing = true, draining = true }
		local restoring = { compensating = true }
		local plan = Retirement.create({
			maxFence = 100,
			characterIdLimit = 32,
			operationIdLimit = 32,
			fingerprintLimit = 64,
			phaseLimit = 32,
			retiringPhases = retiring,
			restoringPhases = restoring,
		})
		local function view(phase: string?, roster: boolean, retired: boolean): Retirement.View
			return {
				characterId = "character",
				rosterHolds = roster,
				deletion = if phase == nil then false else { characterId = "character", phase = phase, fence = 3 },
				retirement = if retired
					then { operationId = "operation", fingerprint = "identity", fence = 3 }
					else false,
			}
		end
		it("uses caller phases and snapshots their policy", function()
			retiring.withdrawing = false
			restoring.compensating = false
			for _, phase in { "withdrawing", "draining" } do
				local decision = plan.decide(view(phase, true, false))
				expect(decision.action):toBe("retire")
				expect(decision.reason):toBe("deletion_in_progress")
			end
			expect(plan.decide(view("compensating", false, true)).action):toBe("restore")
			expect(plan.decide(view("unknown", true, false)).reason):toBe("phase_unknown")
		end)
		it("reconciles orphaned tombstones and refuses malformed views", function()
			expect(plan.decide(view(nil, true, true)).reason):toBe("retirement_orphaned")
			expect(plan.decide(view(nil, false, false)).action):toBe("orphan")
			expect(plan.decide(view(nil, false, true)).reason):toBe("character_retired")
			expect(plan.decide(view(nil, true, false)).reason):toBe("character_live")
			for _, value in { false, 0, "view", {}, { characterId = "character" } } do
				expect(plan.decide(value).action):toBe("invalid")
			end
			local observed = assert((plan.view(view(nil, true, true))))
			expect(table.isfrozen(observed)):toBe(true)
			expect(table.isfrozen(plan.decide(observed))):toBe(true)
		end)
		it("leaves foreign deletion identity separate from the subject", function()
			local observed = view("withdrawing", true, false)
			observed.deletion = { characterId = "foreign", phase = "withdrawing", fence = 3 }
			expect(plan.decide(observed).reason):toBe("character_live")
		end)
	end)
end
