--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
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
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("objectives", function()
		it("lists kinds in authored order and events once", function()
			expect(catalog.kinds()):toEqual({ "kill", "collect", "train" })
			expect(catalog.events()):toEqual({ "mob_killed", "item_collected", "ability_trained" })
			expect(catalog.known("kill")):toBe(true)
			expect(catalog.known("dance")):toBe(false)
		end)

		it("binds an objective to its event and targets", function()
			local found = catalog.binding("q1", objective("o1", "kill", { mobId = "wolf" }))
			expect(found):toEqual({
				questId = "q1",
				objectiveId = "o1",
				objectiveKind = "kill",
				event = "mob_killed",
				targets = { mobId = "wolf" },
			})
		end)

		it("routes a targetId alias to the kind's target field", function()
			local collect: Objectives.Objective = { id = "o2", kind = "collect", targetId = "herb", targets = {} }
			expect(catalog.targetsOf(collect)):toEqual({ itemId = "herb" })
			local train: Objectives.Objective = { id = "o3", kind = "train", targetId = "lesson", targets = {} }
			expect(catalog.targetsOf(train)):toEqual({ targetId = "lesson" })
		end)

		it("reports unknown kinds and missing required targets", function()
			expect(#catalog.validate(objective("o1", "kill", { mobId = "wolf" }))):toBe(0)
			expect(catalog.validate(objective("o1", "dance", {}))[1].field):toBe("kind")
			expect(catalog.validate(objective("o1", "kill", {}))[1].field):toBe("mobId")
		end)

		it("matches events by kind, quest, objective and targets", function()
			local bound = assert(catalog.binding("q1", objective("o1", "kill", { mobId = "wolf" })))
			expect(catalog.matches({ kind = "mob_killed", targets = { mobId = "wolf" } }, bound)):toBe(true)
			expect(catalog.matches({ kind = "mob_killed", targets = { mobId = "boar" } }, bound)):toBe(false)
			expect(catalog.matches({ kind = "item_collected", targets = { mobId = "wolf" } }, bound)):toBe(false)
			expect(catalog.matches({ kind = "mob_killed", questId = "q2", targets = { mobId = "wolf" } }, bound)):toBe(
				false
			)
		end)

		it("accepts configured aliases for a target", function()
			local quest: Objectives.Quest = {
				id = "q1",
				objectives = { { id = "o1", kind = "train", targetId = "lesson", targets = {} } },
			}
			local hits = catalog.bindingsFor({ quest }, { kind = "ability_trained", targets = { targetId = "charge" } })
			expect(#hits):toBe(1)
			local misses = catalog.bindingsFor({ quest }, { kind = "ability_trained", targets = { targetId = "rest" } })
			expect(#misses):toBe(0)
		end)

		it("summarizes the target contract of an event", function()
			local contract = assert(catalog.contract("ability_trained"))
			expect(contract.required):toEqual({ "targetId" })
			expect(contract.allowed):toEqual({ targetId = true, trainerId = true })
			expect(catalog.contract("unknown")):toBeNil()
		end)
	end)
end
