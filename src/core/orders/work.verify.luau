--!strict

local Module = require("./work")
local WorkOrderCore = Module
local Shape = require("../social/shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local current: Verify.Context? = nil
	local function expect(value: unknown): Verify.Expectation
		return assert(current):expect(value)
	end
	local function it(name: string, body: () -> ())
		suite:case(name, function(context)
			current = context
			body()
		end)
	end
	local function describe(_name: string, body: () -> ())
		body()
	end

	local function singleStepOrder<T>(overrides: T?)
		local order: { [string]: unknown } = {
			id = "wo.mend_the_fences",
			rewardId = "reward.mender_token",
			repeatable = true,
			steps = {
				{ id = "step.mend", tag = "mend.fence_post", targetCount = 3 },
			},
		}
		if overrides ~= nil then
			for key, value in assert(Shape.raw(overrides)) do
				assert(type(key) == "string")
				order[key] = value
			end
		end
		return order
	end

	local function twoStepOrder()
		return {
			id = "wo.clear_and_deliver",
			rewardId = "reward.provisioner_crate",
			repeatable = true,
			steps = {
				{ id = "step.clear", tag = "kill.brackenling", targetCount = 2 },
				{ id = "step.deliver", tag = "deliver.ration_crate", targetCount = 1 },
			},
		}
	end

	local function oneShotOrder()
		return {
			id = "wo.dedicate_the_shrine",
			rewardId = "reward.dedication_plaque",
			repeatable = false,
			steps = {
				{ id = "step.dedicate", tag = "interact.shrine", targetCount = 1 },
			},
		}
	end

	local function accept()
		return { kind = "accept" }
	end

	local function progress(tag: string, amount: number)
		return { kind = "progress", stepTag = tag, amount = amount }
	end

	local function complete()
		return { kind = "complete" }
	end

	local function claim(eventId: string)
		return { kind = "claim", eventId = eventId }
	end

	local function step(state: unknown, order: unknown, command: unknown, nowSec: number): Module.Result
		return assert(WorkOrderCore.step(state, order, command, nowSec))
	end

	local function reconstruct(state: Module.State)
		local rebuilt: Shape.Raw = {}
		for key, value in assert(Shape.raw(state)) do
			if type(value) == "table" then
				local copy: Shape.Raw = {}
				for innerKey, innerValue in assert(Shape.raw(value)) do
					copy[innerKey] = innerValue
				end
				rebuilt[key] = copy
			else
				rebuilt[key] = value
			end
		end
		return rebuilt
	end

	describe("WorkOrderCore order schema", function()
		it("projects a frozen order and rejects malformed authored rows", function()
			local order = WorkOrderCore.projectOrder(singleStepOrder())
			expect((order ~= nil)):toBe(true)
			expect((table.isfrozen(assert(order)))):toBe(true)
			expect((table.isfrozen((assert(order)).steps))):toBe(true)

			expect((WorkOrderCore.projectOrder(singleStepOrder({ id = "" })))):toBeNil()
			expect((WorkOrderCore.projectOrder(singleStepOrder({ rewardId = "" })))):toBeNil()
			expect((WorkOrderCore.projectOrder(singleStepOrder({ repeatable = "yes" })))):toBeNil()
			expect((WorkOrderCore.projectOrder(singleStepOrder({ steps = {} })))):toBeNil()
			expect((WorkOrderCore.projectOrder(singleStepOrder({ extra = true })))):toBeNil()

			local dupIds = twoStepOrder()
			dupIds.steps[2].id = dupIds.steps[1].id
			expect((WorkOrderCore.projectOrder(dupIds))):toBeNil()

			local dupTags = twoStepOrder()
			dupTags.steps[2].tag = dupTags.steps[1].tag
			expect((WorkOrderCore.projectOrder(dupTags))):toBeNil()

			local badTarget = singleStepOrder()
			local badSteps = { { id = "step.mend", tag = "mend.fence_post", targetCount = 0 } }
			badTarget.steps = badSteps
			badSteps[1].targetCount = 0
			expect((WorkOrderCore.projectOrder(badTarget))):toBeNil()

			local nonIntegerTarget = singleStepOrder()
			local nonIntegerSteps = { { id = "step.mend", tag = "mend.fence_post", targetCount = 1.5 } }
			nonIntegerTarget.steps = nonIntegerSteps
			nonIntegerSteps[1].targetCount = 1.5
			expect((WorkOrderCore.projectOrder(nonIntegerTarget))):toBeNil()
		end)
	end)

	describe("WorkOrderCore lifecycle", function()
		it("accepts, progresses, completes, and claims a solo work order end to end", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			expect(accepted.accepted):toBe(true)
			expect(accepted.phase):toBe("accepted")

			local first = step(accepted.state, order, progress("mend.fence_post", 1), 10)
			expect(first.progressed):toBe(true)
			expect(first.state.stepProgress["step.mend"]):toBe(1)

			local second = step(first.state, order, progress("mend.fence_post", 2), 20)
			expect(second.state.stepProgress["step.mend"]):toBe(3)

			local completed = step(second.state, order, complete(), 25)
			expect(completed.completed):toBe(true)
			expect(completed.phase):toBe("completed")

			local claimed = step(completed.state, order, claim("evt.1"), 30)
			expect(claimed.claimed):toBe(true)
			expect(claimed.replayed):toBe(false)
			expect(claimed.rewardId):toBe("reward.mender_token")
			expect(claimed.phase):toBe("unaccepted")
		end)
	end)

	describe("WorkOrderCore population-gated-spine falsifier", function()
		it("completes and claims for a solo player on a server of one with no population data anywhere", function()
			local order = twoStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local killed = step(accepted.state, order, progress("kill.brackenling", 2), 5)
			local delivered = step(killed.state, order, progress("deliver.ration_crate", 1), 8)
			local completed = step(delivered.state, order, complete(), 9)
			local claimed = step(completed.state, order, claim("solo.evt"), 10)
			expect(claimed.claimed):toBe(true)
			expect(claimed.rewardId):toBe("reward.provisioner_crate")
		end)

		it("rejects commands carrying any population-shaped field as malformed input", function()
			local badAccept = { kind = "accept", populationShares = { north = 1 } }
			expect((WorkOrderCore.step(WorkOrderCore.emptyState(), singleStepOrder(), badAccept, 0))):toBeNil()
		end)
	end)

	describe("WorkOrderCore market-dependency falsifier", function()
		it("rejects any command or order carrying market, price, or currency fields", function()
			local order = singleStepOrder()
			local pricedCommand = { kind = "claim", eventId = "e", price = 10 }
			expect((WorkOrderCore.step(WorkOrderCore.emptyState(), order, pricedCommand, 0))):toBeNil()

			local pricedOrder = singleStepOrder({ price = 10 })
			expect((WorkOrderCore.projectOrder(pricedOrder))):toBeNil()
		end)
	end)

	describe("WorkOrderCore decorative-service-credit falsifier", function()
		it("refuses to complete before every step reaches its target", function()
			local order = twoStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local partial = step(accepted.state, order, progress("kill.brackenling", 1), 5)
			expect((WorkOrderCore.step(partial.state, order, complete(), 6))):toBeNil()
		end)

		it("refuses to claim a reward that was never completed", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			expect((WorkOrderCore.step(accepted.state, order, claim("evt"), 1))):toBeNil()
			expect((WorkOrderCore.step(WorkOrderCore.emptyState(), order, claim("evt"), 1))):toBeNil()
		end)
	end)

	describe("WorkOrderCore progress-validation falsifier", function()
		it("rejects progress against an untracked step tag", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			expect((WorkOrderCore.step(accepted.state, order, progress("not.a.real.tag", 1), 1))):toBeNil()
		end)

		it("rejects progress while the order has not been accepted", function()
			local order = singleStepOrder()
			expect((WorkOrderCore.step(WorkOrderCore.emptyState(), order, progress("mend.fence_post", 1), 1))):toBeNil()
		end)

		it("clamps progress at the step target rather than overshooting", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local overshoot = step(accepted.state, order, progress("mend.fence_post", 50), 1)
			expect(overshoot.state.stepProgress["step.mend"]):toBe(3)
		end)
	end)

	describe("WorkOrderCore infinite-resource falsifier", function()
		it("pays a reward exactly once per completion and refuses a second payout under a fresh event id", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local progressed = step(accepted.state, order, progress("mend.fence_post", 3), 1)
			local completed = step(progressed.state, order, complete(), 2)
			local claimed = step(completed.state, order, claim("evt.first"), 3)
			expect(claimed.claimed):toBe(true)

			local secondAttempt = WorkOrderCore.step(claimed.state, order, claim("evt.second"), 4)
			expect(secondAttempt):toBeNil()
		end)
	end)

	describe("WorkOrderCore duplicate-claim falsifier", function()
		it("claims a completed order exactly once and replays idempotently under the same event id", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local progressed = step(accepted.state, order, progress("mend.fence_post", 3), 1)
			local completed = step(progressed.state, order, complete(), 2)
			local done = step(completed.state, order, claim("evt.dup"), 3)
			expect(done.claimed):toBe(true)
			expect(done.replayed):toBe(false)

			local replay = step(done.state, order, claim("evt.dup"), 40)
			expect(replay.claimed):toBe(true)
			expect(replay.replayed):toBe(true)
			expect(replay.rewardId):toBe(done.rewardId)
			expect(replay.state.claims):toEqual(done.state.claims)
		end)

		it("keeps replaying an old claim event id correctly even after a new cycle begins", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local progressed = step(accepted.state, order, progress("mend.fence_post", 3), 1)
			local completed = step(progressed.state, order, complete(), 2)
			local firstClaim = step(completed.state, order, claim("evt.cycle1"), 3)

			local reAccepted = step(firstClaim.state, order, accept(), 4)
			local reProgressed = step(reAccepted.state, order, progress("mend.fence_post", 3), 5)
			local reCompleted = step(reProgressed.state, order, complete(), 6)
			local secondClaim = step(reCompleted.state, order, claim("evt.cycle2"), 7)
			expect(secondClaim.claimed):toBe(true)
			expect(secondClaim.replayed):toBe(false)

			local oldReplay = step(secondClaim.state, order, claim("evt.cycle1"), 8)
			expect(oldReplay.replayed):toBe(true)
			expect(oldReplay.rewardId):toBe(firstClaim.rewardId)
		end)
	end)

	describe("WorkOrderCore unique-permanent-reward falsifier", function()
		it("re-accepts and re-claims a repeatable order for a second independent payout", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local progressed = step(accepted.state, order, progress("mend.fence_post", 3), 1)
			local completed = step(progressed.state, order, complete(), 2)
			local firstClaim = step(completed.state, order, claim("evt.a"), 3)
			expect(firstClaim.phase):toBe("unaccepted")

			local reAccepted = step(firstClaim.state, order, accept(), 4)
			expect(reAccepted.accepted):toBe(true)
			local reProgressed = step(reAccepted.state, order, progress("mend.fence_post", 3), 5)
			local reCompleted = step(reProgressed.state, order, complete(), 6)
			local secondClaim = step(reCompleted.state, order, claim("evt.b"), 7)
			expect(secondClaim.claimed):toBe(true)
			expect(secondClaim.replayed):toBe(false)
		end)

		it("keeps an explicitly one-shot order from ever being re-accepted after its single claim", function()
			local order = oneShotOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local progressed = step(accepted.state, order, progress("interact.shrine", 1), 1)
			local completed = step(progressed.state, order, complete(), 2)
			local claimed = step(completed.state, order, claim("evt.once"), 3)
			expect(claimed.phase):toBe("completed")

			expect((WorkOrderCore.step(claimed.state, order, accept(), 4))):toBeNil()
			local replay = step(claimed.state, order, claim("evt.once"), 5)
			expect(replay.replayed):toBe(true)
		end)
	end)

	describe("WorkOrderCore resume-after-disconnect", function()
		it("resumes mid-progress from a reconstructed state without losing progress", function()
			local order = twoStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local partial = step(accepted.state, order, progress("kill.brackenling", 1), 5)
			expect(partial.state.stepProgress["step.clear"]):toBe(1)

			local persisted = reconstruct(partial.state)
			local resumed = step(persisted, order, progress("kill.brackenling", 1), 20)
			expect(resumed.state.stepProgress["step.clear"]):toBe(2)

			local delivered = step(resumed.state, order, progress("deliver.ration_crate", 1), 21)
			local completed = step(delivered.state, order, complete(), 22)
			expect(completed.completed):toBe(true)

			local persistedCompleted = reconstruct(completed.state)
			local claimed = step(persistedCompleted, order, claim("evt.resume"), 23)
			expect(claimed.claimed):toBe(true)
		end)

		it("resumes a reconstructed completed-but-unclaimed state and still pays exactly once", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local progressed = step(accepted.state, order, progress("mend.fence_post", 3), 1)
			local completed = step(progressed.state, order, complete(), 2)

			local persisted = reconstruct(completed.state)
			local claimed = step(persisted, order, claim("evt.reconnect"), 10)
			expect(claimed.claimed):toBe(true)

			local persistedAgain = reconstruct(claimed.state)
			local replay = step(persistedAgain, order, claim("evt.reconnect"), 20)
			expect(replay.replayed):toBe(true)
		end)
	end)

	describe("WorkOrderCore fail-closed validation", function()
		it("rejects malformed clocks, backward clocks, and bad command shapes", function()
			local order = singleStepOrder()
			local state = WorkOrderCore.emptyState()
			for _, clock in assert({ math.huge - math.huge, math.huge, -math.huge, -1, "now" }) do
				expect((WorkOrderCore.step(state, order, accept(), clock))):toBeNil()
			end

			local advanced = step(state, order, accept(), 100).state
			expect((WorkOrderCore.step(advanced, order, progress("mend.fence_post", 1), 99.5))):toBeNil()

			expect((WorkOrderCore.step(state, order, { kind = "abandon" }, 10))):toBeNil()
			expect((WorkOrderCore.step(state, order, { kind = "progress" }, 10))):toBeNil()
			expect((WorkOrderCore.step(state, order, { kind = "claim" }, 10))):toBeNil()
			expect((WorkOrderCore.step(state, order, nil, 10))):toBeNil()
			expect((WorkOrderCore.step(state, nil, accept(), 10))):toBeNil()
		end)

		it("rejects accepting while already accepted and progressing an unknown order tag mismatch", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			expect((WorkOrderCore.step(accepted.state, order, accept(), 1))):toBeNil()
		end)

		it("rejects persisted state that no longer reconciles with the authored order shape", function()
			local order = twoStepOrder()
			local staleState = {
				lastClockSec = 0,
				phase = "accepted",
				stepProgress = { ["step.clear"] = 1 },
				claimed = false,
				claims = {},
			}
			expect((WorkOrderCore.step(staleState, order, complete(), 1))):toBeNil()
		end)

		it("rejects malformed persisted state shapes", function()
			local order = singleStepOrder()
			expect((WorkOrderCore.step({ phase = "unaccepted", claimed = false, claims = {} }, order, accept(), 10))):toBeNil()
			expect((WorkOrderCore.step({
				lastClockSec = 0,
				phase = "spent",
				stepProgress = {},
				claimed = false,
				claims = {},
			}, order, accept(), 10))):toBeNil()
			expect((WorkOrderCore.step({
				lastClockSec = 0,
				phase = "unaccepted",
				stepProgress = {},
				claimed = true,
				claims = {},
			}, order, accept(), 10))):toBeNil()
			expect((WorkOrderCore.step({
				lastClockSec = 0,
				phase = "unaccepted",
				stepProgress = {},
				claimed = false,
				claims = { [""] = "r" },
			}, order, accept(), 10))):toBeNil()
		end)
	end)

	describe("WorkOrderCore isolation", function()
		it("returns fresh state and claim ledgers that never alias the input", function()
			local order = singleStepOrder()
			local accepted = step(WorkOrderCore.emptyState(), order, accept(), 0)
			local progressed = step(accepted.state, order, progress("mend.fence_post", 3), 1)
			local completed = step(progressed.state, order, complete(), 2)
			local claimed = step(completed.state, order, claim("iso"), 3)

			expect((claimed.state == completed.state)):toBe(false)
			expect((claimed.state.claims == completed.state.claims)):toBe(false)

			claimed.state.claims["iso"] = "tampered"
			local replay = step(claimed.state, order, claim("iso"), 4)
			expect((replay.state.claims == claimed.state.claims)):toBe(false)
		end)

		it("returns fresh empty states", function()
			local first = WorkOrderCore.emptyState()
			local second = WorkOrderCore.emptyState()
			expect((first == second)):toBe(false)
			expect((first.stepProgress == second.stepProgress)):toBe(false)
			expect((first.claims == second.claims)):toBe(false)
		end)
	end)
end
