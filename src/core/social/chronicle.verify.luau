--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
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
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("chronicle", function()
		it("offers, swears, witnesses and fulfills once with authority checks and immutable state", function(own)
			local initial = sworn()
			expect(assert(initial.active).expiresAtSec):toBe(6)
			local witnessed = stateOf(
				step(
					initial,
					{ kind = "witness", eventId = "seen", actorCharacterId = "ally", verdict = "witnessed" },
					2
				)
			)
			expect(assert(witnessed.active).outcomeId):toBe("vow.seen")
			expect(assert(initial.active).status):toBe("Sworn")
			local event = {
				kind = "fulfill",
				eventId = "finish",
				actorCharacterId = "self",
				contributionReceiptId = "proof",
				expectedRevision = witnessed.revision,
			}
			local completed = core.transition(witnessed, definitions, event, 3, policy, authority)
			local state = stateOf(completed)
			expect(state.active):toBeNil()
			expect(state.chronicle[1].terminalStatus):toBe("Fulfilled")
			assert(completed.ok)
			expect(assert(completed.fulfillment).contributionReceiptId):toBe("proof")
			local replay = core.transition(state, definitions, event, 3, policy, authority)
			assert(replay.ok)
			expect(replay.replayed):toBe(true)
			expect(replay.fulfillment):toEqual(completed.fulfillment)
			expect(core.projectState(state, definitions)):toEqual(state)
			expect(core.projectChronicle(state, definitions, "peer")):toBeNil()
			expect(#assert(core.projectChronicle(state, definitions, "self"))):toBe(1)
			expect(table.isfrozen(state.chronicle[1])):toBe(true)
		end)

		it("preserves contested outcomes, abandons and bounds terminal history", function()
			local disputed = stateOf(
				step(
					sworn(),
					{ kind = "witness", eventId = "seen", actorCharacterId = "ally", verdict = "contested" },
					2
				)
			)
			expect(assert(disputed.active).status):toBe("Contested")
			expect(assert(disputed.active).outcomeId):toBe("vow.disputed")
			local abandoned =
				stateOf(step(disputed, { kind = "abandon", eventId = "leave", actorCharacterId = "self" }, 3))
			expect(abandoned.chronicle[1].outcomeId):toBe("vow.left")
			local second = stateOf(step(abandoned, {
				kind = "offer",
				eventId = "second",
				vowInstanceId = "ii",
				definitionId = "vow",
				actorCharacterId = "peer",
			}, 4))
			local expired = stateOf(step(second, { kind = "expire", eventId = "expire" }, 6))
			expect(#expired.chronicle):toBe(1)
			expect(expired.chronicle[1].outcomeId):toBe("vow.expired")
		end)

		it("enforces configured lifetimes, bounds, revisions, definitions and authorities", function()
			expect(core.emptyState("longer")):toBeNil()
			local state = sworn()
			local due = step(state, { kind = "abandon", eventId = "late", actorCharacterId = "self" }, 6)
			assert(not due.ok)
			expect(due.reason):toBe("expiry_due")
			local early = step(state, { kind = "expire", eventId = "early" }, 5)
			assert(not early.ok)
			expect(early.reason):toBe("expiry_not_due")
			local invalid = core.transition(
				state,
				definitions,
				{ kind = "expire", eventId = "e", expectedRevision = 0 },
				6,
				policy,
				authority
			)
			assert(not invalid.ok)
			expect(invalid.reason):toBe("revision_conflict")
			local denied = core.transition(state, definitions, {
				kind = "witness",
				eventId = "x",
				expectedRevision = state.revision,
				actorCharacterId = "ally",
				verdict = "witnessed",
			}, 2, nil, authority)
			assert(not denied.ok)
			expect(denied.reason):toBe("access_denied")
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
			expect(denied.reason):toBe("contribution_denied")
			expect(core.projectState(state, {})):toBeNil()
			local malformed = table.clone(definitions[1])
			malformed.id = "Bad..id"
			expect(core.projectState(state, { malformed })):toBeNil()
			local cfg = table.clone(settings)
			cfg.maxRevision = 1
			local bounded = Chronicle.chronicle(cfg)
			expect(bounded.projectState(state, definitions)):toBeNil()
			cfg = table.clone(settings)
			cfg.maxTime = 1
			expect(Chronicle.chronicle(cfg).projectState(state, definitions)):toBeNil()
			cfg = table.clone(settings)
			cfg.maxId = 1
			expect(Chronicle.chronicle(cfg).projectState(state, definitions)):toBeNil()
			cfg = table.clone(settings)
			cfg.maxFingerprint = 1
			expect(Chronicle.chronicle(cfg).projectState(state, definitions)):toBeNil()
		end)
	end)
end
