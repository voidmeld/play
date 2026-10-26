--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Lifecycle = require("./lifecycle")
local Objectives = require("./objectives")
local Verify = require("../../../.lute/dependencies/verify/src/core")
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("lifecycle", function()
		local catalog = Objectives.catalog({
			order = { "chat", "emote", "inspect", "explore", "examine", "collect" },
			kinds = {
				chat = { event = "chat_sent", required = { "targetId" } },
				emote = { event = "emote_performed", required = { "targetId" } },
				inspect = { event = "player_inspected", required = { "targetId" } },
				explore = { event = "poi_explored", required = { "poiId" }, targetIdField = "poiId" },
				examine = { event = "poi_explored", required = { "poiId" }, targetIdField = "poiId" },
				collect = { event = "item_collected", required = { "itemId" }, targetIdField = "itemId" },
			},
		})
		local settings: Lifecycle.Config = {
			catalog = catalog,
			targetFields = { "poiId", "itemId" },
			eventField = "eventKind",
			targetsField = "eventTargets",
			bespokeFields = { "script", "module", "handler", "callback", "reducer", "serverScript" },
			stillnessKinds = { examine = true },
		}
		local law = Lifecycle.lifecycle(settings)
		it("keeps waypoint metadata out of objective event targets", function()
			local objective = {
				id = "visit",
				description = "Visit",
				target = 1,
				kind = "explore",
				poiId = "hall",
				waypointPoiId = "approach",
			}
			local projected = assert(law.projectObjective(objective))
			local bindings = catalog.bindings({ id = "journey", objectives = { projected } })
			expect(#bindings):toBe(1)
			expect(bindings[1].targets.poiId):toBe("hall")
			expect(bindings[1].targets.waypointPoiId):toBeNil()
			expect(objective.waypointPoiId):toBe("approach")
		end)
		for _, row in
			{
				{ "chat", "local", "chat_sent" },
				{ "emote", "beckon", "emote_performed" },
				{
					"inspect",
					"player",
					"player_inspected",
				},
			}
		do
			it("binds " .. row[1] .. " objectives to supplied events", function(own)
				local objective = { id = "objective", kind = row[1], target = 1, targetId = row[2] }
				local binding = assert(law.bindingForObjective("quest", objective))
				expect(binding.event):toBe(row[3])
				expect(binding.targets.targetId):toBe(row[2])
				expect(catalog.matches({ kind = row[3], targets = { targetId = row[2] } }, binding)):toBe(true)
			end)
		end
		it("overlays tracked fields, preserves explicit targets and resolves target aliases", function(own)
			local objective = {
				id = "o",
				kind = "collect",
				targetId = "fallback",
				itemId = "tracked",
				eventKind = "override",
				eventTargets = { itemId = "explicit", extra = "kept" },
			}
			local binding = assert(law.bindingForObjective("q", objective))
			expect(binding.event):toBe("override")
			expect(binding.targets):toEqual({ itemId = "tracked", extra = "kept" })
			binding.targets.itemId = "changed"
			expect(objective.eventTargets.itemId):toBe("explicit")
			expect(
				assert(law.bindingForObjective("q", { id = "o", kind = "collect", targetId = "fallback" })).targets.itemId
			):toBe("fallback")
		end)
		it("validates malformed explicit targets, group sizes and prohibited script fields", function()
			expect(#law.validateObjective({ id = "o", kind = "unknown" })):toBe(1)
			expect(law.validateObjective({ id = "o", kind = "collect" })[1].field):toBe("itemId")
			for _, targets in { false, { itemId = "" }, { [1] = "item" }, { itemId = 2 } } do
				local problems =
					law.validateObjective({ id = "o", kind = "collect", itemId = "item", eventTargets = targets })
				expect(problems[1].field):toBe("eventTargets")
			end
			for _, size in { 1, -1, 1.5, math.nan } do
				expect(
					law.validateObjective({ id = "o", kind = "collect", itemId = "item", groupSize = size })[1].field
				):toBe("groupSize")
			end
			expect(#law.validateObjective({ id = "o", kind = "collect", itemId = "item", groupSize = 2 })):toBe(0)
			for _, field in settings.bespokeFields do
				local objective: { [string]: unknown } = { id = "o", kind = "collect", itemId = "item" }
				objective[field] = true
				expect(law.validateObjective(objective)[1].kind):toBe("bespoke_script")
			end
		end)
		it("checks finite stillness constraints against the supplied objective kinds", function()
			local valid = { durationSec = 2, radiusStuds = 4, maxDriftStuds = 3, position = { x = 0, y = 1, z = -2 } }
			expect(
				#law.validateObjective({ id = "o", kind = "examine", target = 1, poiId = "site", stillness = valid })
			):toBe(0)
			expect(
				law.validateObjective({ id = "o", kind = "explore", target = 1, poiId = "site", stillness = valid })[1].field
			):toBe("stillness")
			expect(
				law.validateObjective({ id = "o", kind = "examine", target = 2, poiId = "site", stillness = valid })[1].field
			):toBe("stillness")
			for _, bad in { 0, -1, math.huge, math.nan } do
				local policy = table.clone(valid)
				policy.durationSec = bad
				expect(
					law.validateObjective({ id = "o", kind = "examine", target = 1, poiId = "site", stillness = policy })[1].field
				):toBe("stillness")
			end
			local tooFar = table.clone(valid)
			tooFar.maxDriftStuds = 5
			expect(
				law.validateObjective({ id = "o", kind = "examine", target = 1, poiId = "site", stillness = tooFar })[1].field
			):toBe("stillness")
			local infinite = table.clone(valid)
			infinite.position = { x = math.huge, y = 0, z = 0 }
			expect(
				law.validateObjective({ id = "o", kind = "examine", target = 1, poiId = "site", stillness = infinite })[1].field
			):toBe("stillness")
		end)
		it("uses configured fields and stillness kinds without changing the shared catalog", function()
			local config = table.clone(settings)
			config.targetFields = { "itemId" }
			config.eventField = "signal"
			config.targetsField = "selectors"
			config.bespokeFields = { "code" }
			config.stillnessKinds = { explore = true }
			local custom = Lifecycle.lifecycle(config)
			local binding = assert(
				custom.bindingForObjective(
					"q",
					{ id = "o", kind = "collect", itemId = "item", signal = "custom", selectors = { extra = "target" } }
				)
			)
			expect(binding.event):toBe("custom")
			expect(binding.targets):toEqual({ itemId = "item", extra = "target" })
			expect(custom.validateObjective({ id = "o", kind = "collect", itemId = "item", code = true })[1].field):toBe(
				"code"
			)
			expect(#custom.validateObjective({ id = "o", kind = "collect", itemId = "item", script = true })):toBe(0)
			expect(#custom.validateObjective({
				id = "o",
				kind = "explore",
				target = 1,
				targetId = "site",
				stillness = { durationSec = 1, radiusStuds = 1, maxDriftStuds = 1, position = { x = 0, y = 0, z = 0 } },
			})):toBe(0)
			expect(custom.projectObjective(false)):toBeNil()
			expect(custom.bindingForObjective("q", {})):toBeNil()
		end)
	end)
end
