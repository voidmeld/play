--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Routing = require("./routing")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local fixtureUniverse = 101
local fixtureSource = 202
local fixtureDestination = 303

local realms = { side_a = "Side A", side_b = "Side B" }
local api = Routing.create({
	realms = realms,
	structuralId = function(value: unknown): string?
		return if type(value) == "string"
				and #value <= 20
				and string.match(value, "^[%w_]+$") ~= nil
			then value
			else nil
	end,
	namespacedId = function(value: unknown): string?
		return if type(value) == "string"
				and #value <= 20
				and string.match(value, "^[%w_]+:[%w_]+$") ~= nil
			then value
			else nil
	end,
	idLimit = 20,
	refusalLineLimit = 64,
	unroutedStatusLimit = 8,
	unroutedReasonLimit = 32,
	unknownRequestId = "missing",
	invalidBinding = {
		id = "binding_invalid",
		recoverable = false,
		retryable = false,
		holdsAtDoor = true,
		line = "Choose an available route",
	},
})
local function source()
	local refusals: { Routing.RefusalRow } = {}
	for _, id in api.REASON_IDS do
		table.insert(refusals, { id = id, recoverable = true, retryable = true, holdsAtDoor = true, line = id })
	end
	return {
		binding = {
			channel = "alpha",
			universeId = fixtureUniverse,
			sourcePlaceId = fixtureSource,
			places = { { destinationId = "hub:entry", placeId = fixtureDestination } },
		},
		budget = { targetSeconds = 5, maxAttemptsPerSession = 2 },
		handoff = { freshnessSeconds = 10 },
		refusals = refusals,
		destinations = {
			{
				id = "hub:entry",
				zoneId = "sector",
				realm = "Side A",
				isStarter = true,
				requiresUnlock = false,
				unlockId = "",
				minLevel = 2,
			},
		},
		unroutedChannels = {},
	}
end
local function resolution()
	return {
		destination = { id = "hub:entry", zoneId = "sector", realm = "Side A" },
		characterId = "subject",
		realmId = "side_a",
	}
end
local function request(resolved: unknown)
	return {
		channel = "alpha",
		universeId = fixtureUniverse,
		sourcePlaceId = fixtureSource,
		requestId = "attempt",
		destinationId = "hub:entry",
		character = { characterId = "subject", realmId = "side_a", level = 2 },
		requestSession = { sessionId = "session", acquisitionId = "acquisition", leaseRevision = 1 },
		heldSession = { sessionId = "session", acquisitionId = "acquisition", leaseRevision = 1 },
		selectionAtUnix = 9,
		issuedAtUnix = 10,
		nowUnix = 11,
		attempt = 1,
		resolution = resolved,
	}
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("configured route admission", function()
		it("projects custom identity policy and detaches the configured realm map", function()
			local policy = assert(api.projectPolicy(source()))
			realms.side_a = "Changed"
			expect(api.REALMS.side_a):toBe("Side A")
			expect(table.isfrozen(policy)):toBe(true)
			expect(api.boundPlaceIds(policy)[1]):toBe(fixtureDestination)
			local decision = api.decide(policy, request(resolution()))
			expect(decision.outcome):toBe("routed")
			local route = assert(decision.route)
			expect(route.destinationPlaceId):toBe(fixtureDestination)
			expect(route.carrierExpiresAtUnix):toBe(20)
		end)
		it("enforces attempt, exact deadline, clock ordering and session fencing", function()
			local policy = assert(api.projectPolicy(source()))
			local intent = request(resolution())
			intent.nowUnix = 15
			expect(api.decide(policy, intent).outcome):toBe("routed")
			intent.nowUnix = 16
			expect(assert(api.decide(policy, intent).refusal).reason):toBe("target_missed")
			intent.nowUnix = 9
			expect(assert(api.decide(policy, intent).refusal).reason):toBe("intent_stale")
			intent.nowUnix = 11
			intent.attempt = 3
			expect(assert(api.decide(policy, intent).refusal).reason):toBe("attempts_exhausted")
			intent.attempt = 1
			intent.heldSession.leaseRevision = 2
			expect(assert(api.decide(policy, intent).refusal).reason):toBe("session_split")
		end)
		it("classifies absent authoritative resolutions using configured destination facts", function()
			local policy = assert(api.projectPolicy(source()))
			local intent = request(nil)
			intent.character.realmId = "side_b"
			expect(assert(api.decide(policy, intent).refusal).reason):toBe("realm_mismatch")
			intent.character.realmId = "side_a"
			intent.character.level = 1
			expect(assert(api.decide(policy, intent).refusal).reason):toBe("below_min_level")
			local locked = source()
			locked.destinations[1].requiresUnlock = true
			intent.character.level = 2
			expect(assert(api.decide(assert(api.projectPolicy(locked)), intent).refusal).reason):toBe(
				"destination_locked"
			)
		end)
		it("rejects a mismatched resolver result and foreign arrival binding", function()
			local policy = assert(api.projectPolicy(source()))
			local resolved = resolution()
			resolved.characterId = "other"
			expect(assert(api.decide(policy, request(resolved)).refusal).reason):toBe("intent_malformed")
			local arrival = {
				channel = "alpha",
				universeId = fixtureUniverse,
				placeId = fixtureDestination,
				sourceUniverseId = fixtureUniverse,
				sourcePlaceId = fixtureSource,
				destinationId = "hub:entry",
				characterId = "subject",
			}
			expect(api.accept(policy, arrival).outcome):toBe("accepted")
			arrival.placeId = fixtureDestination + 1
			expect(api.accept(policy, arrival).outcome):toBe("refused")
		end)
		it("fails closed on malformed policies, metatable input and overlong request identities", function()
			local policy = assert(api.projectPolicy(source()))
			expect(api.projectPolicy(setmetatable(source(), {}))):toBe(nil)
			local duplicated = source()
			table.insert(duplicated.binding.places, duplicated.binding.places[1])
			expect(api.projectPolicy(duplicated)):toBe(nil)
			local intent = request(resolution())
			intent.requestId = string.rep("r", 21)
			local refusal = assert(api.decide(policy, intent).refusal)
			expect(refusal.requestId):toBe("missing")
			expect(refusal.reason):toBe("intent_malformed")
			expect(api.decide(policy, setmetatable(request(resolution()), {})).outcome):toBe("refused")
		end)
		it("uses the adopter fallback text for unrecognized or unbound refusal policy", function()
			local refusal = assert(api.refuse(nil, nil, "unknown", nil).refusal)
			expect(refusal.reason):toBe("binding_invalid")
			expect(refusal.line):toBe("Choose an available route")
			expect(refusal.requestId):toBe("missing")
		end)
	end)
end
