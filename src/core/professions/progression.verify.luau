--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Milestones = require("./milestones")
local Progression = require("./progression")
local Tokens = require("./tokens")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local orders = require("../orders/work")

local order: orders.WorkOrder = {
	id = "supply",
	rewardId = "capability",
	repeatable = false,
	steps = { { id = "collect", tag = "gather", targetCount = 2 }, { id = "supply", tag = "deliver", targetCount = 1 } },
}
local definitions = { gather = { transactionId = "first:gather", eventKind = "gathered" } }
local model = Progression.create({
	nodeIds = { ore = true },
	milestones = definitions,
	orders = { supply = order },
	maxTokenLength = 12,
})

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("profession progression", function()
		it("rejects forged, collided, absent and stale action tokens", function()
			local tokens = Tokens.create({ names = { "craft", "deliver" }, maxLength = 12 })
			local issued = { craft = "craft:1", deliver = "deliver:1" }
			expect(tokens.matches(issued, "craft", "craft:1")):toBe(true)
			expect(tokens.matches(issued, "craft", "deliver:1")):toBe(false)
			expect(tokens.matches(issued, "craft", "craft:0")):toBe(false)
			expect(tokens.matches({ craft = "", deliver = "" }, "craft", "")):toBe(false)
			expect(tokens.normalize({ craft = "same", deliver = "same" })):toBeNil()
			expect(tokens.normalize({ craft = "ok" })):toBeNil()
			expect(tokens.normalize({ craft = "ok", deliver = "too long a token" })):toBeNil()
			expect(tokens.normalize(setmetatable(issued, {}))):toBeNil()
			expect(tokens.normalize({ craft = "", deliver = "" }, true)):toEqual({ craft = "", deliver = "" })
		end)
		it("binds milestone receipts to their character and configured event", function()
			local milestones = Milestones.create(definitions)
			local receipt = milestones.receipt("actor", "gather")
			local saved = { gather = receipt }
			local projected = assert(milestones.normalize(saved, "actor"))
			expect(projected):toEqual(saved)
			expect(projected.gather == receipt):toBe(false)
			expect(milestones.normalize(saved, "other")):toBeNil()
			receipt.eventKind = "forged"
			expect(milestones.normalize(saved, "actor")):toBeNil()
			expect(milestones.normalize({ unknown = projected.gather }, "actor")):toBeNil()
		end)
		it("reconstructs an earned order and admits its reward once", function()
			local before = model.default()
			local accepted = assert(orders.step(before.workOrder.state, order, { kind = "accept" }, 1))
			expect(orders.step(accepted.state, order, { kind = "complete" }, 2)):toBeNil()
			local gathered =
				assert(orders.step(accepted.state, order, { kind = "progress", stepTag = "gather", amount = 2 }, 2))
			local delivered =
				assert(orders.step(gathered.state, order, { kind = "progress", stepTag = "deliver", amount = 1 }, 3))
			local completed = assert(orders.step(delivered.state, order, { kind = "complete" }, 4))
			local claimed = assert(orders.step(completed.state, order, { kind = "claim", eventId = "reward:1" }, 5))
			local saved = model.default()
			saved.workOrder = { orderId = order.id, capabilityRank = 1, state = claimed.state }
			saved.milestones.gather = model.milestone("actor", "gather")
			saved.gatherSlots.ore = 2
			local restored = assert(model.normalize(saved, "actor"))
			local replay =
				assert(orders.step(restored.workOrder.state, order, { kind = "claim", eventId = "reward:1" }, 6))
			expect(replay.replayed):toBe(true)
			expect(orders.step(restored.workOrder.state, order, { kind = "claim", eventId = "reward:2" }, 6)):toBeNil()
			expect(orders.step(restored.workOrder.state, order, { kind = "claim", eventId = "reward:1" }, 4)):toBeNil()
			expect(before.workOrder.state.phase):toBe("unaccepted")
			expect(restored):toEqual(saved)
			saved.workOrder.state.stepProgress.collect = 0
			expect(model.normalize(saved, "actor")):toBeNil()
			saved.workOrder.state.stepProgress.collect = 2
			saved.workOrder.state.claims["reward:1"] = "forged"
			expect(model.normalize(saved, "actor")):toBeNil()
			saved.workOrder.state.claims["reward:1"] = "capability"
			saved.workOrder.capabilityRank = 0
			expect(model.normalize(saved, "actor")):toBeNil()
		end)
		it("fails closed on corrupt saved progress without modifying its input", function()
			local saved = model.default()
			expect(model.normalize(saved, "actor")):toEqual(saved)
			saved.gatherSlots.ore = -1
			expect(model.normalize(saved, "actor")):toBeNil()
			saved.gatherSlots.ore = 1
			saved.gatherSlots.unknown = 1
			expect(model.normalize(saved, "actor")):toBeNil()
			saved.gatherSlots.unknown = nil
			saved.revision = math.huge
			expect(model.normalize(saved, "actor")):toBeNil()
			expect(saved.gatherSlots.ore):toBe(1)
			expect(model.tokens({ craft = "one", equip = "two", order = "three" })):toEqual({
				craft = "one",
				equip = "two",
				order = "three",
			})
			expect(model.tokens({ craft = "one", equip = "two", order = "one" })):toBeNil()
		end)
	end)
end
