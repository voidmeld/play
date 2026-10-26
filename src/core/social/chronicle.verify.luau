--!strict

local Chronicle = require("./chronicle")
local Shape = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local settings: Chronicle.Config = {
	offerTtlSec = 2,
	swornTtlSec = 5,
	chronicleLimit = 1,
	maxRevision = 100,
	maxTime = 100,
	maxId = 30,
	maxCharacterId = 4,
	maxFingerprint = 200,
}
local core = Chronicle.chronicle(settings)
local definitions: { Chronicle.Definition } = {
	{
		id = "vow",
		witnessedOutcomeId = "vow.seen",
		contestedOutcomeId = "vow.disputed",
		fulfilledOutcomeId = "vow.done",
		expiredOutcomeId = "vow.expired",
		abandonedOutcomeId = "vow.left",
	},
}
local policy: Chronicle.AccessPolicy = {
	allows = function(
		_action: string,
		_actor: string?,
		_holder: string,
		_counterpart: string,
		_witness: string?
	): unknown
		return true
	end,
}
local authority: Chronicle.ContributionAuthority = {
	validate = function(
		_receipt: string,
		_definition: string,
		_holder: string,
		_counterpart: string,
		_witness: string?,
		_outcome: string
	): unknown
		return true
	end,
}

local function stateOf(result: Chronicle.Result): Chronicle.State
	assert(result.ok, if not result.ok then result.reason else "")
	return result.state
end

local function step(state: Chronicle.State, event: Shape.Raw, now: number): Chronicle.Result
	event.expectedRevision = state.revision
	return core.transition(state, definitions, event, now, policy, authority)
end

local function sworn(): Chronicle.State
	local empty = assert(core.emptyState("self"))
	local offered = stateOf(
		step(
			empty,
			{ kind = "offer", eventId = "offer", vowInstanceId = "i", definitionId = "vow", actorCharacterId = "peer" },
			0
		)
	)
	return stateOf(step(offered, { kind = "swear", eventId = "swear", actorCharacterId = "self" }, 1))
end

return function(suite: Verify.Harness)
	suite:case(
		"offers, swears, witnesses and fulfills once with authority checks and immutable state",
		function(context)
			local initial = sworn()
			context:expect(assert(initial.active).expiresAtSec):toBe(6)
			local witnessed = stateOf(
				step(
					initial,
					{ kind = "witness", eventId = "seen", actorCharacterId = "ally", verdict = "witnessed" },
					2
				)
			)
			context:expect(assert(witnessed.active).outcomeId):toBe("vow.seen")
			context:expect(assert(initial.active).status):toBe("Sworn")
			local event = {
				kind = "fulfill",
				eventId = "finish",
				actorCharacterId = "self",
				contributionReceiptId = "proof",
				expectedRevision = witnessed.revision,
			}
			local completed = core.transition(witnessed, definitions, event, 3, policy, authority)
			local state = stateOf(completed)
			context:expect(state.active):toBeNil()
			context:expect(state.chronicle[1].terminalStatus):toBe("Fulfilled")
			assert(completed.ok)
			context:expect(assert(completed.fulfillment).contributionReceiptId):toBe("proof")
			local replay = core.transition(state, definitions, event, 3, policy, authority)
			assert(replay.ok)
			context:expect(replay.replayed):toBe(true)
			context:expect(replay.fulfillment):toEqual(completed.fulfillment)
			context:expect(core.projectState(state, definitions)):toEqual(state)
			context:expect(core.projectChronicle(state, definitions, "peer")):toBeNil()
			context:expect(#assert(core.projectChronicle(state, definitions, "self"))):toBe(1)
			context:expect(table.isfrozen(state.chronicle[1])):toBe(true)
		end
	)

	suite:case("preserves contested outcomes, abandons and bounds terminal history", function(context)
		local disputed = stateOf(
			step(sworn(), { kind = "witness", eventId = "seen", actorCharacterId = "ally", verdict = "contested" }, 2)
		)
		context:expect(assert(disputed.active).status):toBe("Contested")
		context:expect(assert(disputed.active).outcomeId):toBe("vow.disputed")
		local abandoned = stateOf(step(disputed, { kind = "abandon", eventId = "leave", actorCharacterId = "self" }, 3))
		context:expect(abandoned.chronicle[1].outcomeId):toBe("vow.left")
		local second = stateOf(step(abandoned, {
			kind = "offer",
			eventId = "second",
			vowInstanceId = "ii",
			definitionId = "vow",
			actorCharacterId = "peer",
		}, 4))
		local expired = stateOf(step(second, { kind = "expire", eventId = "expire" }, 6))
		context:expect(#expired.chronicle):toBe(1)
		context:expect(expired.chronicle[1].outcomeId):toBe("vow.expired")
	end)

	suite:case("enforces configured lifetimes, bounds, revisions, definitions and authorities", function(context)
		context:expect(core.emptyState("longer")):toBeNil()
		local state = sworn()
		local due = step(state, { kind = "abandon", eventId = "late", actorCharacterId = "self" }, 6)
		assert(not due.ok)
		context:expect(due.reason):toBe("expiry_due")
		local early = step(state, { kind = "expire", eventId = "early" }, 5)
		assert(not early.ok)
		context:expect(early.reason):toBe("expiry_not_due")
		local invalid = core.transition(
			state,
			definitions,
			{ kind = "expire", eventId = "e", expectedRevision = 0 },
			6,
			policy,
			authority
		)
		assert(not invalid.ok)
		context:expect(invalid.reason):toBe("revision_conflict")
		local denied = core.transition(state, definitions, {
			kind = "witness",
			eventId = "x",
			expectedRevision = state.revision,
			actorCharacterId = "ally",
			verdict = "witnessed",
		}, 2, nil, authority)
		assert(not denied.ok)
		context:expect(denied.reason):toBe("access_denied")
		local seen = stateOf(
			step(state, { kind = "witness", eventId = "seen", actorCharacterId = "ally", verdict = "witnessed" }, 2)
		)
		denied = core.transition(seen, definitions, {
			kind = "fulfill",
			eventId = "f",
			expectedRevision = seen.revision,
			actorCharacterId = "self",
			contributionReceiptId = "proof",
		}, 3, policy, nil)
		assert(not denied.ok)
		context:expect(denied.reason):toBe("contribution_denied")
		context:expect(core.projectState(state, {})):toBeNil()
		local malformed = table.clone(definitions[1])
		malformed.id = "Bad..id"
		context:expect(core.projectState(state, { malformed })):toBeNil()
		local cfg = table.clone(settings)
		cfg.maxRevision = 1
		local bounded = Chronicle.chronicle(cfg)
		context:expect(bounded.projectState(state, definitions)):toBeNil()
		cfg = table.clone(settings)
		cfg.maxTime = 1
		context:expect(Chronicle.chronicle(cfg).projectState(state, definitions)):toBeNil()
		cfg = table.clone(settings)
		cfg.maxId = 1
		context:expect(Chronicle.chronicle(cfg).projectState(state, definitions)):toBeNil()
		cfg = table.clone(settings)
		cfg.maxFingerprint = 1
		context:expect(Chronicle.chronicle(cfg).projectState(state, definitions)):toBeNil()
	end)
end
