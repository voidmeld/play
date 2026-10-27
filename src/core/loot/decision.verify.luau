--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./decision")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local LootDecision = Module.decision({ windowSeconds = 30 })
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	local SEATS = {
		{ userId = "1", needLegal = true },
		{ userId = "2", needLegal = false },
		{ userId = "3", needLegal = true },
	}

	local function opened(cursor: number?)
		return assert(LootDecision.open("drop:1", "helm", SEATS, 100, cursor or 0))
	end

	local function declared(decision, userId, choice, now)
		local next, refusal = LootDecision.declare(decision, userId, choice, now)
		expect(refusal):toBeNil()
		return assert(next)
	end

	describe("LootDecision", function()
		it("closes thirty seconds after it opens", function()
			local decision = opened()
			expect(decision.deadline):toBe(130)
			expect(LootDecision.due(decision, 129)):toBe(false)
			expect(LootDecision.due(decision, 130)):toBe(true)
			local _, refusal = LootDecision.declare(decision, "1", "need", 130)
			expect(refusal):toBe("closed")
		end)

		it("refuses need from a player for whom the item is not an upgrade", function()
			local _, refusal = LootDecision.declare(opened(), "2", "need", 101)
			expect(refusal):toBe("need_not_legal")
		end)

		it("refuses outsiders, unknown choices and a second declaration", function()
			local decision = opened()
			expect(select(2, LootDecision.declare(decision, "9", "greed", 101))):toBe("not_eligible")
			expect(select(2, LootDecision.declare(decision, "1", "steal", 101))):toBe("bad_choice")
			local once = declared(decision, "1", "greed", 101)
			expect(select(2, LootDecision.declare(once, "1", "need", 102))):toBe("already_declared")
		end)

		it("settles early once every seat has declared", function()
			local decision =
				declared(declared(declared(opened(), "1", "pass", 101), "2", "pass", 101), "3", "pass", 101)
			expect(LootDecision.due(decision, 101)):toBe(true)
			expect(select(2, LootDecision.settle(opened(), 101))):toBe("not_due")
		end)

		it("gives need priority over greed", function()
			local decision = declared(declared(opened(), "1", "need", 101), "2", "greed", 102)
			local settled = assert((LootDecision.settle(decision, 130)))
			local result = assert(settled.result)
			expect(result.winner):toBe("1")
			expect(result.by):toBe("need")
		end)

		it("treats a silent seat as a pass when the window closes", function()
			local decision = declared(opened(), "2", "greed", 101)
			local result = assert(assert((LootDecision.settle(decision, 130))).result)
			expect(result.winner):toBe("2")
			expect(result.by):toBe("greed")
		end)

		it("rolls once among tied choices and keeps that one result", function()
			local decision = declared(declared(opened(), "1", "need", 101), "3", "need", 101)
			local settled = assert((LootDecision.settle(decision, 130)))
			local result = assert(settled.result)
			expect(result.rolls["1"] ~= nil and result.rolls["3"] ~= nil):toBe(true)
			local again = assert(assert((LootDecision.settle(decision, 130))).result)
			expect(again.winner):toBe(result.winner)
			expect(select(2, LootDecision.settle(settled, 131))):toBe("settled")
			expect(select(2, LootDecision.declare(settled, "2", "greed", 102))):toBe("settled")
		end)

		it("hands an all-pass item to the next seat in turn and advances the cursor", function()
			local result = assert(assert((LootDecision.settle(opened(4), 130))).result)
			expect(result.by):toBe("round_robin")
			expect(result.winner):toBe("2")
			expect(result.cursorAfter):toBe(5)
		end)

		it("keeps the seats it opened with when membership later changes", function()
			local seats = table.clone(SEATS)
			local decision = assert(LootDecision.open("drop:2", "helm", seats, 100, 0))
			table.remove(seats, 1)
			expect(#decision.seats):toBe(3)
			expect(decision.seats[1].userId):toBe("1")
		end)

		it("refuses an empty or duplicated seating", function()
			expect(LootDecision.open("drop:3", "helm", {}, 100, 0)):toBeNil()
			local twice = { { userId = "1", needLegal = true }, { userId = "1", needLegal = true } }
			expect(LootDecision.open("drop:3", "helm", twice, 100, 0)):toBeNil()
		end)
	end)
end
