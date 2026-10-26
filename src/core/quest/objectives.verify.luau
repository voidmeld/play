--!strict

local Objectives = require("./objectives")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local catalog = Objectives.catalog({
	order = { "kill", "collect", "train" },
	kinds = {
		kill = { event = "mob_killed", required = { "mobId" } },
		collect = { event = "item_collected", required = { "itemId" }, targetIdField = "itemId" },
		train = { event = "ability_trained", required = { "targetId" }, optional = { "trainerId" } },
	},
	aliases = { ability_trained = { targetId = { lesson = { charge = true } } } },
})

local function objective(id: string, kind: string, targets: Objectives.Targets): Objectives.Objective
	return { id = id, kind = kind, targets = targets }
end

return function(suite: Verify.Harness)
	suite:case("lists kinds in authored order and events once", function(context)
		context:expect(catalog.kinds()):toEqual({ "kill", "collect", "train" })
		context:expect(catalog.events()):toEqual({ "mob_killed", "item_collected", "ability_trained" })
		context:expect(catalog.known("kill")):toBe(true)
		context:expect(catalog.known("dance")):toBe(false)
	end)

	suite:case("binds an objective to its event and targets", function(context)
		local found = catalog.binding("q1", objective("o1", "kill", { mobId = "wolf" }))
		context:expect(found):toEqual({
			questId = "q1",
			objectiveId = "o1",
			objectiveKind = "kill",
			event = "mob_killed",
			targets = { mobId = "wolf" },
		})
	end)

	suite:case("routes a targetId alias to the kind's target field", function(context)
		local collect: Objectives.Objective = { id = "o2", kind = "collect", targetId = "herb", targets = {} }
		context:expect(catalog.targetsOf(collect)):toEqual({ itemId = "herb" })
		local train: Objectives.Objective = { id = "o3", kind = "train", targetId = "lesson", targets = {} }
		context:expect(catalog.targetsOf(train)):toEqual({ targetId = "lesson" })
	end)

	suite:case("reports unknown kinds and missing required targets", function(context)
		context:expect(#catalog.validate(objective("o1", "kill", { mobId = "wolf" }))):toBe(0)
		context:expect(catalog.validate(objective("o1", "dance", {}))[1].field):toBe("kind")
		context:expect(catalog.validate(objective("o1", "kill", {}))[1].field):toBe("mobId")
	end)

	suite:case("matches events by kind, quest, objective and targets", function(context)
		local bound = assert(catalog.binding("q1", objective("o1", "kill", { mobId = "wolf" })))
		context:expect(catalog.matches({ kind = "mob_killed", targets = { mobId = "wolf" } }, bound)):toBe(true)
		context:expect(catalog.matches({ kind = "mob_killed", targets = { mobId = "boar" } }, bound)):toBe(false)
		context:expect(catalog.matches({ kind = "item_collected", targets = { mobId = "wolf" } }, bound)):toBe(false)
		context
			:expect(catalog.matches({ kind = "mob_killed", questId = "q2", targets = { mobId = "wolf" } }, bound))
			:toBe(false)
	end)

	suite:case("accepts configured aliases for a target", function(context)
		local quest: Objectives.Quest = {
			id = "q1",
			objectives = { { id = "o1", kind = "train", targetId = "lesson", targets = {} } },
		}
		local hits = catalog.bindingsFor({ quest }, { kind = "ability_trained", targets = { targetId = "charge" } })
		context:expect(#hits):toBe(1)
		local misses = catalog.bindingsFor({ quest }, { kind = "ability_trained", targets = { targetId = "rest" } })
		context:expect(#misses):toBe(0)
	end)

	suite:case("summarizes the target contract of an event", function(context)
		local contract = assert(catalog.contract("ability_trained"))
		context:expect(contract.required):toEqual({ "targetId" })
		context:expect(contract.allowed):toEqual({ targetId = true, trainerId = true })
		context:expect(catalog.contract("unknown")):toBeNil()
	end)
end
