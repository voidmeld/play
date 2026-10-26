--!strict
local Lifecycle = require("./lifecycle")
local Objectives = require("./objectives")
local Verify = require("../../../.lute/dependencies/verify/src/core")
return function(suite: Verify.Harness)
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
	suite:case("keeps waypoint metadata out of objective event targets", function(t)
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
		t:expect(#bindings):toBe(1)
		t:expect(bindings[1].targets.poiId):toBe("hall")
		t:expect(bindings[1].targets.waypointPoiId):toBeNil()
		t:expect(objective.waypointPoiId):toBe("approach")
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
		suite:case("binds " .. row[1] .. " objectives to supplied events", function(t)
			local objective = { id = "objective", kind = row[1], target = 1, targetId = row[2] }
			local binding = assert(law.bindingForObjective("quest", objective))
			t:expect(binding.event):toBe(row[3])
			t:expect(binding.targets.targetId):toBe(row[2])
			t:expect(catalog.matches({ kind = row[3], targets = { targetId = row[2] } }, binding)):toBe(true)
		end)
	end
	suite:case("overlays tracked fields, preserves explicit targets and resolves target aliases", function(t)
		local objective = {
			id = "o",
			kind = "collect",
			targetId = "fallback",
			itemId = "tracked",
			eventKind = "override",
			eventTargets = { itemId = "explicit", extra = "kept" },
		}
		local binding = assert(law.bindingForObjective("q", objective))
		t:expect(binding.event):toBe("override")
		t:expect(binding.targets):toEqual({ itemId = "tracked", extra = "kept" })
		binding.targets.itemId = "changed"
		t:expect(objective.eventTargets.itemId):toBe("explicit")
		t:expect(
			assert(law.bindingForObjective("q", { id = "o", kind = "collect", targetId = "fallback" })).targets.itemId
		):toBe("fallback")
	end)
	suite:case("validates malformed explicit targets, group sizes and prohibited script fields", function(t)
		t:expect(#law.validateObjective({ id = "o", kind = "unknown" })):toBe(1)
		t:expect(law.validateObjective({ id = "o", kind = "collect" })[1].field):toBe("itemId")
		for _, targets in { false, { itemId = "" }, { [1] = "item" }, { itemId = 2 } } do
			local problems =
				law.validateObjective({ id = "o", kind = "collect", itemId = "item", eventTargets = targets })
			t:expect(problems[1].field):toBe("eventTargets")
		end
		for _, size in { 1, -1, 1.5, math.nan } do
			t:expect(law.validateObjective({ id = "o", kind = "collect", itemId = "item", groupSize = size })[1].field)
				:toBe("groupSize")
		end
		t:expect(#law.validateObjective({ id = "o", kind = "collect", itemId = "item", groupSize = 2 })):toBe(0)
		for _, field in settings.bespokeFields do
			local objective: { [string]: unknown } = { id = "o", kind = "collect", itemId = "item" }
			objective[field] = true
			t:expect(law.validateObjective(objective)[1].kind):toBe("bespoke_script")
		end
	end)
	suite:case("checks finite stillness constraints against the supplied objective kinds", function(t)
		local valid = { durationSec = 2, radiusStuds = 4, maxDriftStuds = 3, position = { x = 0, y = 1, z = -2 } }
		t:expect(#law.validateObjective({ id = "o", kind = "examine", target = 1, poiId = "site", stillness = valid }))
			:toBe(0)
		t
			:expect(
				law.validateObjective({ id = "o", kind = "explore", target = 1, poiId = "site", stillness = valid })[1].field
			)
			:toBe("stillness")
		t
			:expect(
				law.validateObjective({ id = "o", kind = "examine", target = 2, poiId = "site", stillness = valid })[1].field
			)
			:toBe("stillness")
		for _, bad in { 0, -1, math.huge, math.nan } do
			local policy = table.clone(valid)
			policy.durationSec = bad
			t
				:expect(
					law.validateObjective({ id = "o", kind = "examine", target = 1, poiId = "site", stillness = policy })[1].field
				)
				:toBe("stillness")
		end
		local tooFar = table.clone(valid)
		tooFar.maxDriftStuds = 5
		t
			:expect(
				law.validateObjective({ id = "o", kind = "examine", target = 1, poiId = "site", stillness = tooFar })[1].field
			)
			:toBe("stillness")
		local infinite = table.clone(valid)
		infinite.position = { x = math.huge, y = 0, z = 0 }
		t
			:expect(
				law.validateObjective({ id = "o", kind = "examine", target = 1, poiId = "site", stillness = infinite })[1].field
			)
			:toBe("stillness")
	end)
	suite:case("uses configured fields and stillness kinds without changing the shared catalog", function(t)
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
		t:expect(binding.event):toBe("custom")
		t:expect(binding.targets):toEqual({ itemId = "item", extra = "target" })
		t:expect(custom.validateObjective({ id = "o", kind = "collect", itemId = "item", code = true })[1].field)
			:toBe("code")
		t:expect(#custom.validateObjective({ id = "o", kind = "collect", itemId = "item", script = true })):toBe(0)
		t:expect(#custom.validateObjective({
			id = "o",
			kind = "explore",
			target = 1,
			targetId = "site",
			stillness = { durationSec = 1, radiusStuds = 1, maxDriftStuds = 1, position = { x = 0, y = 0, z = 0 } },
		})):toBe(0)
		t:expect(custom.projectObjective(false)):toBeNil()
		t:expect(custom.bindingForObjective("q", {})):toBeNil()
	end)
end
