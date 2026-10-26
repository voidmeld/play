--!strict
local Module = require("./markers")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local QuestMarkerState = Module.markers({
	aliases = { ReplayInProgress = "InProgress", ReplayCompleted = "Completed", ReplayTurnedIn = "TurnedIn" },
	completedStatus = "Completed",
	inProgressStatus = "InProgress",
	unstartedStatus = "None",
})
local Palette = { questTurnIn = "gold", questAvailable = "green", questInProgress = "blue", questLocked = "gray" }
return function(suite: Verify.Harness)
	local current: Verify.Context? = nil
	local function expect(value: unknown): Verify.Expectation
		return assert(current):expect(value)
	end
	local function it(name: string, body: () -> ())
		suite:case(name, function(t)
			current = t
			body()
		end)
	end
	local function describe(_name: string, body: () -> ())
		body()
	end

	describe("Quests.QuestMarkerState", function()
		describe("stateForEntry", function()
			it("reads a completed quest as turn-in", function()
				expect(QuestMarkerState.stateForEntry({ status = "Completed", available = false })):toBe("turnIn")
			end)

			it("reads an in-progress quest as inProgress regardless of availability", function()
				expect(QuestMarkerState.stateForEntry({ status = "InProgress", available = true })):toBe("inProgress")
				expect(QuestMarkerState.stateForEntry({ status = "InProgress", available = false })):toBe("inProgress")
			end)

			it("reads an unstarted, acceptable quest as available", function()
				expect(QuestMarkerState.stateForEntry({ status = "None", available = true })):toBe("available")
			end)

			it("reads an unstarted, unacceptable quest as notCurrentlyAcceptable", function()
				expect(QuestMarkerState.stateForEntry({ status = "None", available = false })):toBe(
					"notCurrentlyAcceptable"
				)
			end)

			it("reads a fully turned-in quest as nil -- it contributes no marker state", function()
				expect(QuestMarkerState.stateForEntry({ status = "TurnedIn", available = false })):toBeNil()
			end)

			it("normalizes every replay status the same as its base status", function()
				expect(QuestMarkerState.stateForEntry({ status = "ReplayInProgress", available = true })):toBe(
					"inProgress"
				)
				expect(QuestMarkerState.stateForEntry({ status = "ReplayCompleted", available = false })):toBe("turnIn")
				expect(QuestMarkerState.stateForEntry({ status = "ReplayTurnedIn", available = false })):toBeNil()
			end)
		end)

		describe("stateForGiver -- state priority resolver over synthetic quest sets", function()
			it("returns nil for an NPC with no quests", function()
				expect(QuestMarkerState.stateForGiver({})):toBeNil()
			end)

			it("returns nil when every quest from this giver is already turned in", function()
				local state = QuestMarkerState.stateForGiver({
					{ status = "TurnedIn", available = false },
					{ status = "TurnedIn", available = false },
				})
				expect(state):toBeNil()
			end)

			it("makes a giver holding an available quest marker-eligible -- the Owner's missing-marker case", function()
				local state = QuestMarkerState.stateForGiver({
					{ status = "None", available = true },
				})
				expect(state):toBe("available")
				expect(state ~= nil):toBe(true)
			end)

			it("ranks turn-in above every other state", function()
				local state = QuestMarkerState.stateForGiver({
					{ status = "None", available = true },
					{ status = "InProgress", available = false },
					{ status = "Completed", available = false },
					{ status = "None", available = false },
				})
				expect(state):toBe("turnIn")
			end)

			it("ranks available above accepted-incomplete and locked", function()
				local state = QuestMarkerState.stateForGiver({
					{ status = "InProgress", available = false },
					{ status = "None", available = true },
					{ status = "None", available = false },
				})
				expect(state):toBe("available")
			end)

			it("ranks accepted-incomplete above locked", function()
				local state = QuestMarkerState.stateForGiver({
					{ status = "InProgress", available = false },
					{ status = "None", available = false },
				})
				expect(state):toBe("inProgress")
			end)

			it("falls back to notCurrentlyAcceptable when nothing else qualifies", function()
				local state = QuestMarkerState.stateForGiver({
					{ status = "None", available = false },
					{ status = "TurnedIn", available = false },
				})
				expect(state):toBe("notCurrentlyAcceptable")
			end)

			it("is order-independent -- the highest rank always wins regardless of list order", function()
				local ascending = QuestMarkerState.stateForGiver({
					{ status = "None", available = false },
					{ status = "InProgress", available = false },
					{ status = "None", available = true },
					{ status = "Completed", available = false },
				})
				local descending = QuestMarkerState.stateForGiver({
					{ status = "Completed", available = false },
					{ status = "None", available = true },
					{ status = "InProgress", available = false },
					{ status = "None", available = false },
				})
				expect(ascending):toBe("turnIn")
				expect(descending):toBe("turnIn")
			end)
		end)

		describe("palette token law", function()
			it("resolves a color from a palette-shaped table via the pinned token", function()
				expect(QuestMarkerState.colorForState(Palette, "turnIn")):toBe(Palette.questTurnIn)
				expect(QuestMarkerState.colorForState(Palette, "available")):toBe(Palette.questAvailable)
				expect(QuestMarkerState.colorForState(Palette, "inProgress")):toBe(Palette.questInProgress)
				expect(QuestMarkerState.colorForState(Palette, "notCurrentlyAcceptable")):toBe(Palette.questLocked)
				expect(QuestMarkerState.colorForState(Palette, nil)):toBe(Palette.questLocked)
			end)
		end)

		describe("restraint law", function()
			it("reserves actionable priority for available quests and turn-ins", function()
				expect(QuestMarkerState.isActionable("available")):toBe(true)
				expect(QuestMarkerState.isActionable("turnIn")):toBe(true)
				expect(QuestMarkerState.isActionable("inProgress")):toBe(false)
				expect(QuestMarkerState.isActionable("notCurrentlyAcceptable")):toBe(false)
				expect(QuestMarkerState.isActionable(nil)):toBe(false)
			end)

			it("shows quest markers in range with clear sight, independently of the nameplate layout", function()
				expect(QuestMarkerState.shownState("available", false, true)):toBe("available")
				expect(QuestMarkerState.shownState("turnIn", false, true)):toBe("turnIn")
				expect(QuestMarkerState.shownState("available", true, true)):toBeNil()
				expect(QuestMarkerState.shownState("available", false, false)):toBeNil()
				expect(QuestMarkerState.shownState("notCurrentlyAcceptable", false, true)):toBe(
					"notCurrentlyAcceptable"
				)
				expect(QuestMarkerState.shownState(nil, false, true)):toBeNil()
			end)
		end)
	end)
	it("uses supplied statuses and replay aliases with arbitrary palette values", function()
		local law = Module.markers({
			aliases = { again = "running" },
			completedStatus = "done",
			inProgressStatus = "running",
			unstartedStatus = "new",
		})
		expect(law.stateForEntry({ status = "again", available = false })):toBe("inProgress")
		expect(law.stateForEntry({ status = "done", available = false })):toBe("turnIn")
		expect(law.stateForEntry({ status = "new", available = true })):toBe("available")
		expect(law.stateForEntry({ status = "Completed", available = false })):toBeNil()
		local palette = { questTurnIn = 4, questAvailable = 3, questInProgress = 2, questLocked = 1 }
		expect(law.colorForState(palette, "turnIn")):toBe(4)
		expect(law.colorForState(palette, nil)):toBe(1)
	end)
end
