--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Claims = require("./claims")
local Run = require("./run")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local destination = 1

local package: Run.Package = {
	id = "route",
	entryId = "entry",
	returnId = "return",
	recoveryWindowSec = 10,
	group = { minPlayers = 2, maxPlayers = 2 },
	phases = {
		{ id = "first", kind = "checkpoint", contentId = "rest" },
		{ id = "last", kind = "boss", contentId = "opponent" },
	},
}
local Core = Run.run({
	describe = function(value: Run.Package): Run.Package
		return value
	end,
	readPackage = function(value: unknown): Run.Package?
		return if value == package then package else nil
	end,
	validCheckpoint = function(_, state)
		return state.checkpointId == (if state.phaseIndex == 1 then nil else "rest")
	end,
	wipePhase = function(_, state)
		return state.phaseIndex
	end,
	replacementAllowed = function(_, state)
		return state.status == "active" and state.checkpointId ~= nil
	end,
	maxMembers = 2,
})
local Claim = Claims.claims({
	recordTtlSec = 100,
	claimLeaseSec = 10,
	carrierContract = "test.carrier",
	memberCount = 2,
	maxText = 256,
	retryDelaysSec = { 1 },
})
local function start(): Run.RunState
	local result = Core.transition(package, nil, {
		kind = "start",
		eventId = "start",
		runId = "run",
		leaderId = "a",
		memberIds = { "b", "a" },
	}, 0)
	assert(result.ok)
	return result.state
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("run progress and claims", function()
		it("replays accepted phases and refuses conflicts without progressing the caller", function()
			local state = start()
			local event = { kind = "complete_phase", eventId = "phase", expectedRevision = 1, phaseId = "first" }
			local next = Core.transition(package, state, event, 1)
			assert(next.ok)
			expect(next.state.checkpointId):toBe("rest")
			expect(state.phaseIndex):toBe(1)
			local replay = Core.transition(package, next.state, event, 2)
			assert(replay.ok)
			expect(replay.replayed):toBe(true)
			expect(replay.state.revision):toBe(2)
			event.phaseId = "last"
			local conflict = Core.transition(package, next.state, event, 2)
			assert(not conflict.ok)
			expect(conflict.reason):toBe("receipt_conflict")
			local complete = Core.transition(package, next.state, {
				kind = "complete_phase",
				eventId = "end",
				expectedRevision = 2,
				phaseId = "last",
			}, 3)
			assert(complete.ok)
			expect(complete.state.status):toBe("completed")
		end)
		it("keeps a disconnected seat through its recovery window and admits replacement after expiry", function()
			local state = start()
			local phase = Core.transition(package, state, {
				kind = "complete_phase",
				eventId = "phase",
				expectedRevision = 1,
				phaseId = "first",
			}, 1)
			assert(phase.ok)
			local disconnected = Core.transition(package, phase.state, {
				kind = "disconnect",
				eventId = "lost",
				expectedRevision = 2,
				memberId = "b",
			}, 2)
			assert(disconnected.ok)
			local request =
				{ kind = "replace", eventId = "replace", expectedRevision = 3, memberId = "b", replacementId = "c" }
			local held = Core.transition(package, disconnected.state, request, 12)
			assert(not held.ok)
			expect(held.reason):toBe("replacement_seat_reserved")
			local replaced = Core.transition(package, disconnected.state, request, 13)
			assert(replaced.ok)
			expect(replaced.state.members[2].id):toBe("c")
		end)
		it("fences old jobs and stale revisions after claim takeover", function()
			local record = assert(Claim.newRecord({
				runId = "run",
				packageId = "route",
				placeId = destination,
				accessCode = "access",
				privateServerId = "server",
				partyId = "party",
				leaderUserId = 1,
				request = {},
				rows = {},
				runState = start(),
				members = { { userId = 1, characterId = "a" }, { userId = 2, characterId = "b" } },
			}, 0))
			local held = assert(Claim.claimTransform("server", "job-a", 0)(record))
			expect(Claim.claimTransform("server", "job-b", 10)(held)):toBeNil()
			local taken = assert(Claim.claimTransform("server", "job-b", 11)(held))
			expect(Claim.renewTransform("run", "job-a", 11)(taken)):toBeNil()
			expect(Claim.writeThroughTransform("run", start(), "job-b", 11)(taken)):toBeNil()
			local advanced = table.clone(start())
			advanced.revision = 2
			local written = assert(Claim.writeThroughTransform("run", advanced, "job-b", 12)(taken))
			expect(written.stateRevision):toBe(2)
			expect(taken.stateRevision):toBe(1)
			expect(Claim.claimTransform("other", "job-b", 12)(written)):toBeNil()
		end)
	end)
end
