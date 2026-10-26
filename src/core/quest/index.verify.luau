--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Index = require("./index")
local Objectives = require("./objectives")
local Verify = require("../../../.lute/dependencies/verify/src/core")
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("index", function()
		local catalog = Objectives.catalog({
			order = { "defeat", "gather", "custom" },
			kinds = {
				defeat = { event = "defeated", required = { "enemy" } },
				gather = { event = "gathered", required = { "item" } },
				custom = { event = "custom", required = {} },
			},
			aliases = { defeated = { enemy = { wolf = { hound = true } } } },
		})
		local quests: { Objectives.Quest } = {
			{
				id = "a",
				objectives = {
					{ id = "kill", kind = "defeat", targets = { enemy = "wolf" } },
					{ id = "collect", kind = "gather", targets = { item = "herb" } },
				},
			},
			{
				id = "b",
				objectives = {
					{ id = "kill", kind = "defeat", targets = { enemy = "wolf" } },
					{ id = "unknown", kind = "absent", targets = {} },
				},
			},
		}
		local index = Index.index({ catalog = catalog, quests = quests })
		it("collects supplied bindings in quest and objective order", function()
			local rows = index.objectiveBindings()
			expect(#rows):toBe(3)
			expect(rows[1].questId):toBe("a")
			expect(rows[2].objectiveId):toBe("collect")
			expect(rows[3].questId):toBe("b")
			rows[1].targets.enemy = "changed"
			expect(index.objectiveBindings()[1].targets.enemy):toBe("wolf")
		end)
		it("matches scopes and aliases using the shared objective catalog", function()
			expect(#index.bindingsForEvent({ kind = "defeated", targets = { enemy = "hound" } })):toBe(2)
			local rows = index.bindingsForEvent({
				kind = "defeated",
				questId = "b",
				objectiveId = "kill",
				targets = {
					enemy = "wolf",
				},
			})
			expect(#rows):toBe(1)
			expect(rows[1].questId):toBe("b")
			expect(#index.bindingsForEvent({ kind = "unknown", targets = {} })):toBe(0)
		end)
		it("groups any supplied event and target field without embedding a kill catalog", function()
			expect(index.byTarget("defeated", "enemy")):toEqual({
				wolf = {
					{ questId = "a", objectiveId = "kill", targetId = "wolf" },
					{
						questId = "b",
						objectiveId = "kill",
						targetId = "wolf",
					},
				},
			})
			expect(index.byTarget("gathered", "item")):toEqual({
				herb = { { questId = "a", objectiveId = "collect", targetId = "herb" } },
			})
			expect(index.byTarget("defeated", "missing")):toEqual({})
			expect(Index.index({ catalog = catalog, quests = {} }).objectiveBindings()):toEqual({})
		end)
	end)
end
