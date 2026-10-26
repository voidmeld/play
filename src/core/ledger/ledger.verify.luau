--!strict

local Ledger = require("./ledger")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local settings: Ledger.Config =
	{ maxText = 256, maxCount = 1000000000, maxAt = 1000000000000, minGroupSize = 2, maxGroupSize = 32 }
local Core = Ledger.ledger(settings)

type Event = Ledger.Event
type EventKind = Ledger.EventKind
type State = Ledger.State
type ApplyResult = Ledger.ApplyResult
type TornGroup = Ledger.TornGroup
type Balances = { [string]: { [string]: number } }

local function grant(eventId: string, materialId: string, count: number, at: number, actorId: string?): Event
	return {
		eventId = eventId,
		kind = "grant",
		materialId = materialId,
		count = count,
		actorId = actorId or "actor-a",
		at = at,
	}
end

local function member(
	eventId: string,
	kind: EventKind,
	materialId: string,
	count: number,
	at: number,
	groupId: string,
	groupSize: number,
	actorId: string?
): Event
	return {
		eventId = eventId,
		kind = kind,
		materialId = materialId,
		count = count,
		actorId = actorId or "actor-a",
		at = at,
		groupId = groupId,
		groupSize = groupSize,
	}
end

local function applyAll(events: { Event }): State
	local state: State = Core.emptyState()
	for _, event in events do
		local result, reason = Core.apply(state, event)
		assert(reason == nil, reason)
		state = assert(result).state
	end
	return state
end

return function(suite: Verify.Harness)
	suite:case("settles grants immediately and derives balances", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 5, 1),
			grant("g2", "material.ore", 2, 2),
			grant("g3", "material.wood", 4, 3, "actor-b"),
		})
		local balances: Balances? = Core.balances(state)
		context:expect(assert(balances)["actor-a"]["material.ore"]):toBe(7)
		context:expect(assert(balances)["actor-b"]["material.wood"]):toBe(4)
		context:expect(#state.events):toBe(3)
	end)

	suite:case("returns the same state marked as replay for a replayed grant", function(context)
		local state = applyAll({ grant("g1", "material.ore", 5, 1) })
		local result: ApplyResult?, reason = Core.apply(state, grant("g1", "material.ore", 5, 1))
		context:expect(reason):toBe(nil)
		context:expect(assert(result).replayed):toBe(true)
		context:expect(assert(result).settled):toBe(true)
		context:expect(#assert(result).state.events):toBe(1)
		context:expect(assert(result).state):toEqual(state)
		local balances: Balances? = Core.balances(assert(result).state)
		context:expect(assert(balances)["actor-a"]["material.ore"]):toBe(5)
	end)

	suite:case("refuses a reused eventId carrying different content", function(context)
		local state = applyAll({ grant("g1", "material.ore", 5, 1) })
		local result, reason = Core.apply(state, grant("g1", "material.ore", 6, 1))
		context:expect(result):toBe(nil)
		context:expect(reason):toBe("event_id_conflict")
	end)

	suite:case("settles a craft atomically only when its group completes", function(context)
		local state = applyAll({ grant("g1", "material.ore", 5, 1) })
		local consumed: ApplyResult? =
			Core.apply(state, member("c1", "craft_consume", "material.ore", 3, 2, "craft-1", 2))
		context:expect(assert(consumed).settled):toBe(false)
		local balancesBefore: Balances? = Core.balances(assert(consumed).state)
		context:expect(assert(balancesBefore)["actor-a"]["material.ore"]):toBe(5)
		context:expect((Core.available(assert(consumed).state, "actor-a", "material.ore"))):toBe(2)
		local yielded: ApplyResult? =
			Core.apply(assert(consumed).state, member("y1", "craft_yield", "item.blade", 1, 3, "craft-1", 2))
		context:expect(assert(yielded).settled):toBe(true)
		context:expect(assert(yielded).groupId):toBe("craft-1")
		local balancesAfter: Balances? = Core.balances(assert(yielded).state)
		context:expect(assert(balancesAfter)["actor-a"]["material.ore"]):toBe(2)
		context:expect(assert(balancesAfter)["actor-a"]["item.blade"]):toBe(1)
	end)

	suite:case("never double-applies a replayed craft member", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 5, 1),
			member("c1", "craft_consume", "material.ore", 3, 2, "craft-1", 2),
			member("y1", "craft_yield", "item.blade", 1, 3, "craft-1", 2),
		})
		local consumeReplay: ApplyResult? =
			Core.apply(state, member("c1", "craft_consume", "material.ore", 3, 2, "craft-1", 2))
		context:expect(assert(consumeReplay).replayed):toBe(true)
		context:expect(assert(consumeReplay).settled):toBe(true)
		local yieldReplay: ApplyResult? =
			Core.apply(assert(consumeReplay).state, member("y1", "craft_yield", "item.blade", 1, 3, "craft-1", 2))
		context:expect(assert(yieldReplay).replayed):toBe(true)
		context:expect(#assert(yieldReplay).state.events):toBe(3)
		local balances: Balances? = Core.balances(assert(yieldReplay).state)
		context:expect(assert(balances)["actor-a"]["material.ore"]):toBe(2)
		context:expect(assert(balances)["actor-a"]["item.blade"]):toBe(1)
	end)

	suite:case("keeps a torn craft group detectable and out of balances", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 5, 1),
			member("c1", "craft_consume", "material.ore", 3, 2, "craft-1", 2),
		})
		local balances: Balances? = Core.balances(state)
		context:expect(assert(balances)["actor-a"]["material.ore"]):toBe(5)
		local torn: { TornGroup }? = Core.tornGroups(state)
		context:expect(#assert(torn)):toBe(1)
		context:expect(assert(torn)[1].groupId):toBe("craft-1")
		context:expect(assert(torn)[1].groupSize):toBe(2)
		context:expect(assert(torn)[1].memberCount):toBe(1)
	end)

	suite:case("reserves pending consumption so it cannot be spent twice", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 5, 1),
			member("c1", "craft_consume", "material.ore", 4, 2, "craft-1", 2),
		})
		local result, reason = Core.apply(state, member("c2", "craft_consume", "material.ore", 4, 3, "craft-2", 2))
		context:expect(result):toBe(nil)
		context:expect(reason):toBe("balance_insufficient")
	end)

	suite:case("refuses any overdraw", function(context)
		local state = applyAll({ grant("g1", "material.ore", 5, 1) })
		local craft, craftReason = Core.apply(state, member("c1", "craft_consume", "material.ore", 6, 2, "craft-1", 2))
		context:expect(craft):toBe(nil)
		context:expect(craftReason):toBe("balance_insufficient")
		local trade, tradeReason = Core.apply(state, member("t1", "trade_out", "material.ore", 6, 2, "trade-1", 2))
		context:expect(trade):toBe(nil)
		context:expect(tradeReason):toBe("balance_insufficient")
	end)

	suite:case("keeps a torn trade detectable, unmoved, and completable exactly once", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 5, 1),
			member("t1", "trade_out", "material.ore", 3, 2, "trade-1", 2),
		})
		local balancesTorn: Balances? = Core.balances(state)
		context:expect(assert(balancesTorn)["actor-a"]["material.ore"]):toBe(5)
		context:expect(assert(balancesTorn)["actor-b"]):toBe(nil)
		local torn: { TornGroup }? = Core.tornGroups(state)
		context:expect(assert(torn)[1].groupId):toBe("trade-1")
		local completed: ApplyResult? =
			Core.apply(state, member("t2", "trade_in", "material.ore", 3, 3, "trade-1", 2, "actor-b"))
		context:expect(assert(completed).settled):toBe(true)
		local balances: Balances? = Core.balances(assert(completed).state)
		context:expect(assert(balances)["actor-a"]["material.ore"]):toBe(2)
		context:expect(assert(balances)["actor-b"]["material.ore"]):toBe(3)
		local replay: ApplyResult? =
			Core.apply(assert(completed).state, member("t2", "trade_in", "material.ore", 3, 3, "trade-1", 2, "actor-b"))
		context:expect(assert(replay).replayed):toBe(true)
		context:expect((Core.balances(assert(replay).state))):toEqual(balances)
	end)

	suite:case("refuses an unbalanced trade at completion and stays recoverable", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 5, 1),
			member("t1", "trade_out", "material.ore", 3, 2, "trade-1", 2),
		})
		local short, shortReason =
			Core.apply(state, member("t2", "trade_in", "material.ore", 2, 3, "trade-1", 2, "actor-b"))
		context:expect(short):toBe(nil)
		context:expect(shortReason):toBe("trade_unbalanced")
		local other, otherReason =
			Core.apply(state, member("t3", "trade_in", "material.wood", 3, 3, "trade-1", 2, "actor-b"))
		context:expect(other):toBe(nil)
		context:expect(otherReason):toBe("trade_unbalanced")
		local balanced: ApplyResult? =
			Core.apply(state, member("t4", "trade_in", "material.ore", 3, 3, "trade-1", 2, "actor-b"))
		context:expect(assert(balanced).settled):toBe(true)
	end)

	suite:case("enforces group discipline exactly", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 9, 1),
			member("c1", "craft_consume", "material.ore", 3, 2, "craft-1", 3),
		})
		local mixed, mixedReason = Core.apply(state, member("t1", "trade_out", "material.ore", 3, 3, "craft-1", 3))
		context:expect(mixed):toBe(nil)
		context:expect(mixedReason):toBe("group_kind_mismatch")
		local resized, resizedReason =
			Core.apply(state, member("c2", "craft_consume", "material.ore", 3, 3, "craft-1", 2))
		context:expect(resized):toBe(nil)
		context:expect(resizedReason):toBe("group_size_mismatch")
		local foreign, foreignReason =
			Core.apply(state, member("c3", "craft_consume", "material.ore", 3, 3, "craft-1", 3, "actor-b"))
		context:expect(foreign):toBe(nil)
		context:expect(foreignReason):toBe("group_actor_mismatch")
		local sealedState = applyAll({
			grant("g1", "material.ore", 9, 1),
			member("c1", "craft_consume", "material.ore", 3, 2, "craft-1", 2),
			member("y1", "craft_yield", "item.blade", 1, 3, "craft-1", 2),
		})
		local sealed, sealedReason =
			Core.apply(sealedState, member("c9", "craft_consume", "material.ore", 1, 4, "craft-1", 2))
		context:expect(sealed):toBe(nil)
		context:expect(sealedReason):toBe("group_sealed")
	end)

	suite:case("refuses an incoherent completing composition", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 9, 1),
			member("c1", "craft_consume", "material.ore", 3, 2, "craft-1", 2),
		})
		local doubleConsume, doubleConsumeReason =
			Core.apply(state, member("c2", "craft_consume", "material.ore", 3, 3, "craft-1", 2))
		context:expect(doubleConsume):toBe(nil)
		context:expect(doubleConsumeReason):toBe("group_composition_invalid")
		local tradeState = applyAll({
			grant("g1", "material.ore", 9, 1),
			member("t1", "trade_out", "material.ore", 3, 2, "trade-1", 2),
		})
		local doubleOut, doubleOutReason =
			Core.apply(tradeState, member("t2", "trade_out", "material.ore", 3, 3, "trade-1", 2))
		context:expect(doubleOut):toBe(nil)
		context:expect(doubleOutReason):toBe("group_composition_invalid")
	end)

	suite:case("refuses fresh time regression while still satisfying old replays", function(context)
		local state = applyAll({
			grant("g1", "material.ore", 5, 10),
			grant("g2", "material.ore", 5, 20),
		})
		local regressed, regressedReason = Core.apply(state, grant("g3", "material.ore", 1, 5))
		context:expect(regressed):toBe(nil)
		context:expect(regressedReason):toBe("time_regressed")
		local replay: ApplyResult? = Core.apply(state, grant("g1", "material.ore", 5, 10))
		context:expect(assert(replay).replayed):toBe(true)
	end)

	suite:case("refuses each malformed event with its exact reason", function(context)
		local state = Core.emptyState()
		local cases: { { unknown } } = {
			{
				{ eventId = "e", kind = "grant", materialId = "m", count = 1, actorId = "a", at = 1, extra = true },
				"event_shape_invalid",
			},
			{ grant("", "m", 1, 1), "event_id_invalid" },
			{
				{ eventId = "e", kind = "steal", materialId = "m", count = 1, actorId = "a", at = 1 },
				"event_kind_invalid",
			},
			{ grant("e", "", 1, 1), "material_invalid" },
			{ grant("e", "m", 0, 1), "count_invalid" },
			{ grant("e", "m", 1.5, 1), "count_invalid" },
			{ grant("e", "m", settings.maxCount + 1, 1), "count_invalid" },
			{ grant("e", "m", 1, 1, ""), "actor_invalid" },
			{ grant("e", "m", 1, -1), "time_invalid" },
			{ grant("e", "m", 1, settings.maxAt + 1), "time_invalid" },
			{ grant("e", "m", 1, math.huge - math.huge), "time_invalid" },
			{ member("e", "craft_consume", "m", 1, 1, "", 2), "group_id_invalid" },
			{ member("e", "craft_consume", "m", 1, 1, "g", 1), "group_size_invalid" },
			{ member("e", "craft_consume", "m", 1, 1, "g", settings.maxGroupSize + 1), "group_size_invalid" },
		}
		for _, case in cases do
			local result, reason = Core.apply(state, case[1])
			context:expect(result):toBe(nil)
			context:expect(reason):toBe(case[2])
		end
		local granted = grant("e", "m", 1, 1)
		granted.groupId = "g"
		local forbidden, forbiddenReason = Core.apply(state, granted)
		context:expect(forbidden):toBe(nil)
		context:expect(forbiddenReason):toBe("group_forbidden")
	end)

	suite:case("distinguishes state corruption from valid state", function(context)
		local invalid, invalidReason = Core.apply({ garbage = true }, grant("e", "m", 1, 1))
		context:expect(invalid):toBe(nil)
		context:expect(invalidReason):toBe("state_invalid")
		local duplicated, duplicatedReason = Core.projectState({
			events = { grant("g1", "m", 1, 1), grant("g1", "m", 1, 1) },
		})
		context:expect(duplicated):toBe(nil)
		context:expect(duplicatedReason):toBe("state_invalid")
		local overdrawn, overdrawnReason = Core.projectState({
			events = { member("c1", "craft_consume", "m", 5, 1, "craft-1", 2) },
		})
		context:expect(overdrawn):toBe(nil)
		context:expect(overdrawnReason):toBe("state_invalid")
		local state = applyAll({
			grant("g1", "material.ore", 5, 1),
			member("c1", "craft_consume", "material.ore", 3, 2, "craft-1", 2),
		})
		local reprojected: State? = Core.projectState(state)
		context:expect(reprojected):toEqual(state)
	end)

	suite:case("never mutates its inputs and freezes its outputs", function(context)
		local rawEvent = grant("g1", "material.ore", 5, 1)
		local rawState = { events = { grant("g0", "material.ore", 1, 0) } }
		local result: ApplyResult?, reason = Core.apply(rawState, rawEvent)
		context:expect(reason):toBe(nil)
		context:expect(#rawState.events):toBe(1)
		context:expect(rawEvent.count):toBe(5)
		context:expect(table.isfrozen(assert(result))):toBe(true)
		context:expect(table.isfrozen(assert(result).state)):toBe(true)
		context:expect(table.isfrozen(assert(result).state.events)):toBe(true)
		context:expect(table.isfrozen(assert(result).state.events[2])):toBe(true)
	end)

	suite:case("names its exact refusal surface", function(context)
		context:expect(table.isfrozen(Core.REASONS)):toBe(true)
		context:expect(Core.REASONS):toEqual({
			"state_invalid",
			"event_shape_invalid",
			"event_id_invalid",
			"event_kind_invalid",
			"material_invalid",
			"count_invalid",
			"actor_invalid",
			"time_invalid",
			"group_forbidden",
			"group_id_invalid",
			"group_size_invalid",
			"event_id_conflict",
			"time_regressed",
			"group_sealed",
			"group_kind_mismatch",
			"group_size_mismatch",
			"group_actor_mismatch",
			"group_composition_invalid",
			"trade_unbalanced",
			"balance_insufficient",
		})
	end)

	suite:case("uses configured text limits for every identity field", function(context)
		local small = Ledger.ledger({
			maxText = 2,
			maxCount = settings.maxCount,
			maxAt = settings.maxAt,
			minGroupSize = 2,
			maxGroupSize = 32,
		})
		local valid = grant("ab", "cd", 1, 0, "ef")
		context:expect((small.projectEvent(valid))):toEqual(valid)
		local cases: { { value: Event, reason: string } } = {
			{ value = grant("abc", "cd", 1, 0, "ef"), reason = "event_id_invalid" },
			{ value = grant("ab", "cde", 1, 0, "ef"), reason = "material_invalid" },
			{ value = grant("ab", "cd", 1, 0, "efg"), reason = "actor_invalid" },
			{ value = member("ab", "trade_in", "cd", 1, 0, "ghi", 2, "ef"), reason = "group_id_invalid" },
		}
		for _, case in cases do
			local event, reason = small.projectEvent(case.value)
			context:expect(event):toBeNil()
			context:expect(reason):toBe(case.reason)
		end
		local _, actorReason = small.available(small.emptyState(), "abc", "cd")
		local _, materialReason = small.available(small.emptyState(), "ab", "cde")
		context:expect(actorReason):toBe("actor_invalid")
		context:expect(materialReason):toBe("material_invalid")
	end)

	suite:case("uses configured count, time and group size limits in projection and application", function(context)
		local small = Ledger.ledger({ maxText = 256, maxCount = 3, maxAt = 5, minGroupSize = 3, maxGroupSize = 4 })
		local first = grant("g", "m", 3, 5)
		local state = assert(small.apply(small.emptyState(), first)).state
		context:expect((small.projectState(state))):toEqual(state)
		local cases: { { value: Event, reason: string } } = {
			{ value = grant("g2", "m", 4, 5), reason = "count_invalid" },
			{ value = grant("g2", "m", 1, 6), reason = "time_invalid" },
			{ value = member("c", "craft_consume", "m", 1, 5, "cg", 2), reason = "group_size_invalid" },
			{ value = member("c", "craft_consume", "m", 1, 5, "cg", 5), reason = "group_size_invalid" },
		}
		for _, case in cases do
			local result, reason = small.apply(state, case.value)
			context:expect(result):toBeNil()
			context:expect(reason):toBe(case.reason)
		end
		local torn = assert(small.apply(state, member("c", "craft_consume", "m", 1, 5, "cg", 3)))
		context:expect(torn.settled):toBe(false)
		local pending = assert(small.apply(torn.state, member("y", "craft_yield", "n", 1, 5, "cg", 3)))
		context:expect(pending.settled):toBe(false)
		context
			:expect(assert(small.apply(pending.state, member("z", "craft_yield", "n", 1, 5, "cg", 3))).settled)
			:toBe(true)
		context:expect(small.projectEvent(member("max", "craft_yield", "n", 1, 0.5, "other", 4)) ~= nil):toBe(true)
		local projected, reason = small.projectState({ events = { grant("too-large", "m", 4, 0) } })
		context:expect(projected):toBeNil()
		context:expect(reason):toBe("state_invalid")
	end)

	suite:case("rejects sparse event histories and reports pending replay without settling it", function(context)
		local projected, reason = Core.projectState({ events = { [2] = grant("g", "m", 1, 0) } })
		context:expect(projected):toBeNil()
		context:expect(reason):toBe("state_invalid")
		local pending = member("c", "craft_yield", "n", 1, 1, "cg", 2)
		local state = assert(Core.apply(Core.emptyState(), pending)).state
		local replay = assert(Core.apply(state, pending))
		context:expect(replay.replayed):toBe(true)
		context:expect(replay.settled):toBe(false)
		context:expect((Core.balances(state))):toEqual({})
		context:expect((Core.available(state, "actor-a", "n"))):toBe(0)
	end)
end
