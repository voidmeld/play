--!strict
local Index = require("./index")
local Objectives = require("./objectives")
local Verify = require("../../../.lute/dependencies/verify/src/core")
return function(suite: Verify.Harness)
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
	suite:case("collects supplied bindings in quest and objective order", function(t)
		local rows = index.objectiveBindings()
		t:expect(#rows):toBe(3)
		t:expect(rows[1].questId):toBe("a")
		t:expect(rows[2].objectiveId):toBe("collect")
		t:expect(rows[3].questId):toBe("b")
		rows[1].targets.enemy = "changed"
		t:expect(index.objectiveBindings()[1].targets.enemy):toBe("wolf")
	end)
	suite:case("matches scopes and aliases using the shared objective catalog", function(t)
		t:expect(#index.bindingsForEvent({ kind = "defeated", targets = { enemy = "hound" } })):toBe(2)
		local rows = index.bindingsForEvent({
			kind = "defeated",
			questId = "b",
			objectiveId = "kill",
			targets = {
				enemy = "wolf",
			},
		})
		t:expect(#rows):toBe(1)
		t:expect(rows[1].questId):toBe("b")
		t:expect(#index.bindingsForEvent({ kind = "unknown", targets = {} })):toBe(0)
	end)
	suite:case("groups any supplied event and target field without embedding a kill catalog", function(t)
		t:expect(index.byTarget("defeated", "enemy")):toEqual({
			wolf = {
				{ questId = "a", objectiveId = "kill", targetId = "wolf" },
				{
					questId = "b",
					objectiveId = "kill",
					targetId = "wolf",
				},
			},
		})
		t:expect(index.byTarget("gathered", "item"))
			:toEqual({ herb = { { questId = "a", objectiveId = "collect", targetId = "herb" } } })
		t:expect(index.byTarget("defeated", "missing")):toEqual({})
		t:expect(Index.index({ catalog = catalog, quests = {} }).objectiveBindings()):toEqual({})
	end)
end
