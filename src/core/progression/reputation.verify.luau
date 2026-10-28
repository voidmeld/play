--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Reputation = require("./reputation")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local ledger = Reputation.create({
	maxText = 80,
	maxAt = 10000,
	maxUnits = 100,
	maxPointsPerUnit = 100,
	maxThreshold = 10000,
	kinds = { supply = true, objective = true },
	realms = { west = true, east = true },
	increasingIncrements = true,
	firstGrantReachesRank = true,
})
local ladder = {
	seasonId = "one",
	thresholds = { 2, 8, 20 },
	pointsPerUnit = { supply = 2, objective = 5 },
	rankNames = { west = { "A", "B", "C" }, east = { "D", "E", "F" } },
}
local function event(id: string, season: string, at: number): Reputation.Event
	return {
		eventId = id,
		kind = "supply",
		accountId = "account",
		realmId = "west",
		seasonId = season,
		units = 4,
		at = at,
	}
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("Reputation event credit", function()
		it("derives seasonal and lifetime standing without duplicating replayed credit", function()
			local initial = ledger.emptyState()
			local first = assert(ledger.apply(initial, event("first", "one", 1), ladder))
			local second = assert(ledger.apply(first.state, event("second", "two", 2), ladder))
			local replay = assert(ledger.apply(second.state, event("first", "one", 1), ladder))
			expect(replay.replayed):toBe(true)
			expect(replay.points):toBe(0)
			expect(#initial.events):toBe(0)
			local standing = assert(ledger.standings(replay.state, ladder))
			expect(#standing):toBe(2)
			expect(standing[1].rank):toBe(2)
			expect(standing[1].rankName):toBe("B")
			expect(standing[1].lifetimePoints):toBe(16)
			expect(standing[2].points):toBe(8)
		end)
		it("refuses changed replay, unlisted earning kinds and regressed new events", function()
			local first = assert(ledger.apply(ledger.emptyState(), event("first", "one", 3), ladder))
			local changed = event("first", "one", 3)
			changed.units = 5
			local result, reason = ledger.apply(first.state, changed, ladder)
			expect(result):toBeNil()
			expect(reason):toBe("event_id_conflict")
			local unknown = event("new", "one", 4)
			unknown.kind = "unlisted"
			local decoded, decodeReason = ledger.projectEvent(unknown)
			expect(decoded):toBeNil()
			expect(decodeReason):toBe("event_kind_invalid")
			local regressed, clockReason = ledger.apply(first.state, event("new", "one", 2), ladder)
			expect(regressed):toBeNil()
			expect(clockReason):toBe("time_regressed")
		end)
		it("refuses inconsistent saved history and incomplete configured ladders", function()
			local saved, reason = ledger.projectState({ events = { event("a", "one", 3), event("b", "one", 2) } })
			expect(saved):toBeNil()
			expect(reason):toBe("state_invalid")
			local broken = table.clone(ladder)
			broken.thresholds = { 2, 4, 6 }
			local projected, ladderReason = ledger.projectLadder(broken)
			expect(projected):toBeNil()
			expect(ladderReason):toBe("curve_not_front_loaded")
		end)
	end)
end
