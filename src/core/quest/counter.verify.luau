--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./counter")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local QuestCompletionCounter =
	Module.counter({ markerPrefix = "Quest_", completedStatus = "TurnedIn", labelFormat = "%d of %d at your level" })
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("QuestCompletionCounter", function()
		local bands = {
			{ questId = "a", minLevel = 1 },
			{ questId = "b", minLevel = 2 },
			{ questId = "c", minLevel = 2 },
			{ questId = "d", minLevel = 5 },
		}

		it("counts level-eligible quests and turned-in completions", function()
			local counts = QuestCompletionCounter.count(bands, { a = "TurnedIn", b = "InProgress" }, 2)
			assert(counts ~= nil, "counts")
			expect(counts.eligible):toBe(3)
			expect(counts.completed):toBe(1)
		end)

		it("grows the eligible pool at the level-up boundary — the reveal moment", function()
			local before = QuestCompletionCounter.count(bands, {}, 1)
			local after = QuestCompletionCounter.count(bands, {}, 5)
			assert(before ~= nil and after ~= nil, "counts")
			expect(before.eligible):toBe(1)
			expect(after.eligible):toBe(4)
		end)

		it("counts only TurnedIn as complete, and unknown quests as incomplete", function()
			local counts = QuestCompletionCounter.count(bands, { a = "Completed", b = "None", zz = "TurnedIn" }, 10)
			assert(counts ~= nil, "counts")
			expect(counts.completed):toBe(0)
		end)

		it("returns nil without bands so the counter hides rather than lies", function()
			expect(QuestCompletionCounter.count(nil, {}, 3)):toBeNil()
			expect(QuestCompletionCounter.count({}, {}, 3)):toBeNil()
		end)

		it("formats the header label and hides at zero", function()
			expect(QuestCompletionCounter.label({ eligible = 7, completed = 2 })):toBe("2 of 7 at your level")
			expect(QuestCompletionCounter.label(nil)):toBe("")
			expect(QuestCompletionCounter.label({ eligible = 0, completed = 0 })):toBe("")
		end)

		it("extracts quest ids from log marker names", function()
			expect(QuestCompletionCounter.questIdFromMarkerName("Quest_example")):toBe("example")
			expect(QuestCompletionCounter.questIdFromMarkerName("Objective_1")):toBeNil()
			expect(QuestCompletionCounter.questIdFromMarkerName("Quest_")):toBeNil()
		end)

		it("covers every supplied chain band at the level cap", function()
			local counts = QuestCompletionCounter.count(bands, {}, 10)
			assert(counts ~= nil, "counts")
			expect(counts.eligible):toBe(#bands)
			expect(counts.completed):toBe(0)
		end)
	end)
	it("configures marker names, completion status and label copy", function()
		local law = Module.counter({ markerPrefix = "Q:", completedStatus = "done", labelFormat = "%d / %d" })
		expect(law.questIdFromMarkerName("Q:first")):toBe("first")
		expect(law.questIdFromMarkerName("Quest_first")):toBeNil()
		local counts = law.count(
			{ { questId = "a", minLevel = 1 }, { questId = "b", minLevel = 2 } },
			{ a = "done", b = "TurnedIn" },
			2
		)
		expect(law.label(counts)):toBe("1 / 2")
	end)
end
