--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Cargo = require("./cargo")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local claims = Cargo.create({
	maxText = 256,
	maxCount = 1000,
	maxAt = 10000,
	ledgerEventKind = "deposit",
	intentPrefix = "delivery",
	intentSeparator = "/",
})
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	type State = Cargo.State
	type Result = Cargo.Result

	local ORE = "ore"
	local HERB = "plant"
	local HAULER = "actor.hauler"
	local RIVAL = "actor.rival"
	local CAMP = "depot-a"

	local function carry(claimId: string, actorId: string, materialId: string, count: number)
		return { kind = "carry", claimId = claimId, actorId = actorId, materialId = materialId, count = count }
	end

	local function release(dropId: string, actorId: string, cause: string, expiresAtSec: number)
		return { kind = "release", dropId = dropId, actorId = actorId, cause = cause, expiresAtSec = expiresAtSec }
	end

	local function recover(dropId: string, actorId: string)
		return { kind = "recover", dropId = dropId, actorId = actorId }
	end

	local function expire(dropId: string)
		return { kind = "expire", dropId = dropId }
	end

	local function extract(extractionId: string, actorId: string, campId: string)
		return { kind = "extract", extractionId = extractionId, actorId = actorId, campId = campId }
	end

	local function ok(stateValue: unknown, command: unknown, nowSec: number): Result
		local result, reason = claims.step(stateValue, command, nowSec)
		expect(reason):toBeNil()
		expect(result).never:toBeNil()
		return assert(result)
	end

	local function refusal(stateValue: unknown, command: unknown, nowSec: unknown): string
		local result, reason = claims.step(stateValue, command, nowSec)
		expect(result):toBeNil()
		return tostring(reason)
	end

	local function censusRow(stateValue: State, materialId: string)
		local rows = assert(claims.census(stateValue))
		for _, row in rows do
			if row.materialId == materialId then
				return row
			end
		end
		return { materialId = materialId, carried = 0, dropped = 0, banked = 0, lost = 0 }
	end

	local function conserved(stateValue: State, materialId: string): number
		local row = censusRow(stateValue, materialId)
		return row.carried + row.dropped + row.banked + row.lost
	end

	local function statuses(stateValue: State, materialId: string): number
		local row = censusRow(stateValue, materialId)
		local live = 0
		if row.carried > 0 then
			live += 1
		end
		if row.dropped > 0 then
			live += 1
		end
		if row.banked > 0 then
			live += 1
		end
		if row.lost > 0 then
			live += 1
		end
		return live
	end

	local function carriedTotal(stateValue: State, actorId: string, materialId: string): number
		local rows = assert(claims.carriedOf(stateValue, actorId))
		for _, row in rows do
			if row.materialId == materialId then
				return row.count
			end
		end
		return 0
	end

	local function loadedHauler()
		local state = claims.emptyState()
		state = ok(state, carry("claim.a", HAULER, ORE, 4), 10).state
		state = ok(state, carry("claim.b", HAULER, ORE, 3), 20).state
		state = ok(state, carry("claim.c", HAULER, HERB, 2), 30).state
		return state
	end

	describe("Cargo carried stage", function()
		it("starts empty and carries a gathered yield into an unbanked load", function()
			local empty = claims.emptyState()
			expect(#empty.claims):toBe(0)
			expect(#empty.drops):toBe(0)
			expect(#empty.extractions):toBe(0)
			expect(table.isfrozen(empty)):toBe(true)

			local result = ok(empty, carry("claim.a", HAULER, ORE, 4), 10)
			expect(result.carriedCount):toBe(4)
			expect(result.replayed):toBe(false)
			expect(#result.intents):toBe(0)
			expect(censusRow(result.state, ORE).carried):toBe(4)
			expect(censusRow(result.state, ORE).banked):toBe(0)
		end)

		it("aggregates a multi-node haul per material without banking anything", function()
			local state = loadedHauler()
			expect(carriedTotal(state, HAULER, ORE)):toBe(7)
			expect(carriedTotal(state, HAULER, HERB)):toBe(2)
			expect(censusRow(state, ORE).banked):toBe(0)
			expect(censusRow(state, HERB).banked):toBe(0)
		end)

		it("refuses a malformed command, an unknown kind and a foreign field", function()
			local state = claims.emptyState()
			expect(refusal(state, { kind = "bank" }, 1)):toBe("command_kind_invalid")
			expect(
				refusal(
					state,
					{ kind = "carry", claimId = "c", actorId = HAULER, materialId = ORE, count = 1, campId = CAMP },
					1
				)
			):toBe("command_shape_invalid")
			expect(refusal(state, { kind = "carry", claimId = "c", actorId = HAULER, materialId = ORE }, 1)):toBe(
				"count_invalid"
			)
			expect(refusal(state, carry("c", HAULER, ORE, 0), 1)):toBe("count_invalid")
			expect(refusal(state, carry("", HAULER, ORE, 1), 1)):toBe("claim_invalid")
			expect(refusal(state, carry("c", "", ORE, 1), 1)):toBe("actor_invalid")
			expect(refusal(state, carry("c", HAULER, "", 1), 1)):toBe("material_invalid")
		end)

		it("takes the clock from the caller and refuses a regressed or unreal one", function()
			local state = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 100).state
			expect(refusal(state, carry("claim.b", HAULER, ORE, 1), 99)):toBe("clock_regressed")
			expect(refusal(state, carry("claim.b", HAULER, ORE, 1), math.nan)):toBe("clock_invalid")
			expect(refusal(state, carry("claim.b", HAULER, ORE, 1), -1)):toBe("clock_invalid")
			expect(refusal(state, carry("claim.b", HAULER, ORE, 1), "later")):toBe("clock_invalid")
			expect(ok(state, carry("claim.b", HAULER, ORE, 1), 100).carriedCount):toBe(5)
		end)
	end)

	describe("Cargo claim idempotency", function()
		it("replays a carry without adding a second stack", function()
			local first = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10)
			local again = ok(first.state, carry("claim.a", HAULER, ORE, 4), 11)
			expect(again.replayed):toBe(true)
			expect(again.carriedCount):toBe(4)
			expect(conserved(again.state, ORE)):toBe(4)
			expect(#again.state.claims):toBe(1)
		end)

		it("refuses a claim id reused with a different material, count or actor", function()
			local state = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10).state
			expect(refusal(state, carry("claim.a", HAULER, ORE, 5), 11)):toBe("claim_conflict")
			expect(refusal(state, carry("claim.a", HAULER, HERB, 4), 11)):toBe("claim_conflict")
			expect(refusal(state, carry("claim.a", RIVAL, ORE, 4), 11)):toBe("claim_conflict")
		end)

		it("never resurrects a banked claim through a replayed carry", function()
			local state = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10).state
			state = ok(state, extract("run.1", HAULER, CAMP), 20).state
			expect(censusRow(state, ORE).banked):toBe(4)

			local replayed = ok(state, carry("claim.a", HAULER, ORE, 4), 30)
			expect(replayed.replayed):toBe(true)
			expect(replayed.carriedCount):toBe(0)
			expect(conserved(replayed.state, ORE)):toBe(4)
			expect(censusRow(replayed.state, ORE).banked):toBe(4)
			expect(censusRow(replayed.state, ORE).carried):toBe(0)
		end)

		it("never resurrects a dropped claim through a replayed carry", function()
			local state = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10).state
			state = ok(state, release("drop.1", HAULER, "death", 200), 20).state
			local replayed = ok(state, carry("claim.a", HAULER, ORE, 4), 30)
			expect(replayed.replayed):toBe(true)
			expect(conserved(replayed.state, ORE)):toBe(4)
			expect(censusRow(replayed.state, ORE).dropped):toBe(4)
			expect(censusRow(replayed.state, ORE).carried):toBe(0)
		end)
	end)

	describe("Cargo death drops the load", function()
		it("moves the whole load into one recoverable world drop", function()
			local state = loadedHauler()
			local dropped = ok(state, release("drop.1", HAULER, "death", 400), 40)
			expect(dropped.dropId):toBe("drop.1")
			expect(dropped.droppedCount):toBe(9)
			expect(dropped.carriedCount):toBe(0)
			expect(censusRow(dropped.state, ORE).dropped):toBe(7)
			expect(censusRow(dropped.state, HERB).dropped):toBe(2)
			expect(conserved(dropped.state, ORE)):toBe(7)
			expect(statuses(dropped.state, ORE)):toBe(1)
			expect(statuses(dropped.state, HERB)):toBe(1)
		end)

		it("conserves exactly under drop and recovery, banking nothing extra", function()
			local state = loadedHauler()
			state = ok(state, release("drop.1", HAULER, "death", 400), 40).state
			local recovered = ok(state, recover("drop.1", RIVAL), 50)
			expect(recovered.recoveredCount):toBe(9)
			expect(recovered.carriedCount):toBe(9)
			expect(carriedTotal(recovered.state, HAULER, ORE)):toBe(0)
			expect(carriedTotal(recovered.state, RIVAL, ORE)):toBe(7)
			expect(conserved(recovered.state, ORE)):toBe(7)
			expect(conserved(recovered.state, HERB)):toBe(2)

			local banked = ok(recovered.state, extract("run.1", RIVAL, CAMP), 60)
			expect(banked.bankedCount):toBe(9)
			expect(conserved(banked.state, ORE)):toBe(7)
			expect(censusRow(banked.state, ORE).banked):toBe(7)
			expect(statuses(banked.state, ORE)):toBe(1)

			expect(refusal(banked.state, extract("run.2", HAULER, CAMP), 70)):toBe("nothing_carried")
		end)

		it("records the release once and refuses a drop id reused for another actor or cause", function()
			local state = loadedHauler()
			state = ok(state, release("drop.1", HAULER, "death", 400), 40).state
			local replayed = ok(state, release("drop.1", HAULER, "death", 400), 41)
			expect(replayed.replayed):toBe(true)
			expect(conserved(replayed.state, ORE)):toBe(7)
			expect(#replayed.state.drops):toBe(1)

			expect(refusal(state, release("drop.1", RIVAL, "death", 400), 42)):toBe("drop_conflict")
			expect(refusal(state, release("drop.1", HAULER, "teleport", 400), 42)):toBe("drop_conflict")
			expect(refusal(state, release("drop.1", HAULER, "death", 500), 42)):toBe("drop_conflict")
		end)

		it("refuses an unreal cause and an expiry that is not in the future", function()
			local state = loadedHauler()
			expect(refusal(state, release("drop.1", HAULER, "logout", 400), 40)):toBe("cause_invalid")
			expect(refusal(state, release("drop.1", HAULER, "death", 40), 40)):toBe("expiry_invalid")
			expect(refusal(state, release("drop.1", HAULER, "death", 39), 40)):toBe("expiry_invalid")
			expect(ok(state, release("drop.1", HAULER, "death", 41), 40).droppedCount):toBe(9)
		end)

		it("consumes the drop id even when the dying hauler carried nothing", function()
			local state = claims.emptyState()
			local dropped = ok(state, release("drop.1", HAULER, "death", 400), 40)
			expect(dropped.droppedCount):toBe(0)
			expect(dropped.dropId):toBe("drop.1")
			expect(#dropped.state.drops):toBe(1)
		end)
	end)

	describe("Cargo recovery and expiry", function()
		it("lets exactly one finder recover a drop with identity-bound replay", function()
			local state = loadedHauler()
			state = ok(state, release("drop.1", HAULER, "death", 400), 40).state
			state = ok(state, recover("drop.1", RIVAL), 50).state
			expect(refusal(state, recover("drop.1", HAULER), 51)):toBe("drop_taken")
			local replayed = ok(state, recover("drop.1", RIVAL), 52)
			expect(replayed.replayed):toBe(true)
			expect(conserved(replayed.state, ORE)):toBe(7)
		end)

		it("refuses recovery past the expiry and loses an expired drop", function()
			local state = loadedHauler()
			state = ok(state, release("drop.1", HAULER, "death", 400), 40).state
			expect(refusal(state, recover("drop.1", RIVAL), 400)):toBe("drop_expired")
			expect(refusal(state, expire("drop.1"), 399)):toBe("drop_live")

			local expired = ok(state, expire("drop.1"), 400)
			expect(expired.expiredCount):toBe(9)
			expect(censusRow(expired.state, ORE).lost):toBe(7)
			expect(conserved(expired.state, ORE)):toBe(7)
			expect(statuses(expired.state, ORE)):toBe(1)
			expect(refusal(expired.state, recover("drop.1", RIVAL), 401)):toBe("drop_expired")

			local replayed = ok(expired.state, expire("drop.1"), 402)
			expect(replayed.replayed):toBe(true)
			expect(conserved(replayed.state, ORE)):toBe(7)
		end)

		it("refuses expiry of a recovered drop and recovery of an unknown one", function()
			local state = loadedHauler()
			state = ok(state, release("drop.1", HAULER, "death", 400), 40).state
			state = ok(state, recover("drop.1", RIVAL), 50).state
			expect(refusal(state, expire("drop.1"), 500)):toBe("drop_taken")
			expect(refusal(state, recover("drop.absent", RIVAL), 60)):toBe("unknown_drop")
			expect(refusal(state, expire("drop.absent"), 60)):toBe("unknown_drop")
		end)

		it("lists only live unclaimed drops", function()
			local state = loadedHauler()
			state = ok(state, release("drop.1", HAULER, "death", 400), 40).state
			expect(#assert(claims.openDrops(state, 50))):toBe(1)
			expect(#assert(claims.openDrops(state, 400))):toBe(0)
			local taken = ok(state, recover("drop.1", RIVAL), 50).state
			expect(#assert(claims.openDrops(taken, 60))):toBe(0)
		end)
	end)

	describe("Cargo extraction settles one ledger intent per material", function()
		it("stamps every intent with the extraction clock, never a per-node begin time", function()
			local state = claims.emptyState()
			state = ok(state, carry("claim.a", HAULER, ORE, 4), 10).state
			state = ok(state, carry("claim.b", HAULER, HERB, 2), 25).state
			state = ok(state, carry("claim.c", HAULER, ORE, 3), 31).state

			local banked = ok(state, extract("run.1", HAULER, CAMP), 90)
			expect(#banked.intents):toBe(2)
			expect(banked.bankedCount):toBe(9)
			for _, intent in banked.intents do
				expect(intent.at):toBe(90)
				expect(intent.kind):toBe("deposit")
				expect(intent.actorId):toBe(HAULER)
			end
			expect(banked.intents[1].materialId):toBe(ORE)
			expect(banked.intents[1].count):toBe(7)
			expect(banked.intents[2].materialId):toBe(HERB)
			expect(banked.intents[2].count):toBe(2)
		end)

		it("derives every grant event id from the extraction id", function()
			local state = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10).state
			local banked = ok(state, extract("run.1", HAULER, CAMP), 20)
			expect(banked.intents[1].eventId):toBe("delivery/run.1/" .. ORE)
		end)

		it("returns an identical settlement on a replayed extraction and banks nothing twice", function()
			local state = claims.emptyState()
			state = ok(state, carry("claim.a", HAULER, ORE, 4), 10).state
			state = ok(state, carry("claim.b", HAULER, HERB, 2), 20).state
			local first = ok(state, extract("run.1", HAULER, CAMP), 30)
			local second = ok(first.state, extract("run.1", HAULER, CAMP), 900)

			expect(second.replayed):toBe(true)
			expect(second.bankedCount):toBe(6)
			expect(#second.intents):toBe(#first.intents)
			for index, intent in second.intents do
				expect(intent.eventId):toBe(first.intents[index].eventId)
				expect(intent.materialId):toBe(first.intents[index].materialId)
				expect(intent.count):toBe(first.intents[index].count)
				expect(intent.at):toBe(first.intents[index].at)
			end
			expect(second.intents[1].at):toBe(30)
			expect(conserved(second.state, ORE)):toBe(4)
			expect(#second.state.extractions):toBe(1)
		end)

		it("carries no per-node time at all, so an out-of-order harvest cannot reach the ledger", function()
			local late = { kind = "carry", claimId = "claim.a", actorId = HAULER, materialId = ORE, count = 4, at = 12 }
			expect(refusal(claims.emptyState(), late, 50)):toBe("command_shape_invalid")

			local state = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 50).state
			state = ok(state, carry("claim.b", HAULER, HERB, 3), 51).state
			local banked = ok(state, extract("run.1", HAULER, CAMP), 52)
			expect(banked.intents[1].at):toBe(52)
			expect(banked.intents[2].at):toBe(52)
		end)

		it("keeps haul grant times non-decreasing across successive extractions", function()
			local state = claims.emptyState()
			state = ok(state, carry("claim.a", HAULER, ORE, 4), 10).state
			local first = ok(state, extract("run.1", HAULER, CAMP), 40)
			state = ok(first.state, carry("claim.b", HAULER, ORE, 3), 41).state
			local second = ok(state, extract("run.2", HAULER, CAMP), 41)
			expect(first.intents[1].at):toBe(40)
			expect(second.intents[1].at):toBe(41)
			expect(second.intents[1].at >= first.intents[1].at):toBe(true)
		end)

		it("refuses an extraction id reused by another actor or camp, and an empty load", function()
			local state = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10).state
			state = ok(state, extract("run.1", HAULER, CAMP), 20).state
			expect(refusal(state, extract("run.1", RIVAL, CAMP), 30)):toBe("extraction_conflict")
			expect(refusal(state, extract("run.1", HAULER, "depot-b"), 30)):toBe("extraction_conflict")
			expect(refusal(state, extract("run.2", HAULER, CAMP), 30)):toBe("nothing_carried")
			expect(refusal(claims.emptyState(), extract("run.9", HAULER, ""), 1)):toBe("camp_invalid")
			expect(refusal(claims.emptyState(), extract("", HAULER, CAMP), 1)):toBe("extraction_invalid")
		end)

		it("refuses an extraction whose composed grant id would overflow the ledger id limit", function()
			local long = string.rep("x", 250)
			local state = ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10).state
			expect(refusal(state, extract(long, HAULER, CAMP), 20)):toBe("intent_id_too_long")
			expect(censusRow(state, ORE).carried):toBe(4)
		end)
	end)

	describe("Cargo conserves every unit under death, disconnect and teleport", function()
		it("resolves a disconnected load to exactly one custody, never two", function()
			local state = loadedHauler()
			local dropped = ok(state, release("drop.1", HAULER, "disconnect", 400), 40)
			expect(dropped.state.drops[1].cause):toBe("disconnect")
			expect(statuses(dropped.state, ORE)):toBe(1)
			expect(conserved(dropped.state, ORE)):toBe(7)
			expect(carriedTotal(dropped.state, HAULER, ORE)):toBe(0)

			local lost = ok(dropped.state, expire("drop.1"), 400)
			expect(statuses(lost.state, ORE)):toBe(1)
			expect(censusRow(lost.state, ORE).lost):toBe(7)
			expect(conserved(lost.state, ORE)):toBe(7)
		end)

		it("resolves a teleported load to exactly one custody, never two", function()
			local state = loadedHauler()
			local dropped = ok(state, release("drop.1", HAULER, "teleport", 400), 40)
			expect(dropped.state.drops[1].cause):toBe("teleport")
			local recovered = ok(dropped.state, recover("drop.1", HAULER), 50)
			expect(statuses(recovered.state, ORE)):toBe(1)
			expect(carriedTotal(recovered.state, HAULER, ORE)):toBe(7)
			expect(conserved(recovered.state, ORE)):toBe(7)
		end)

		it("holds the census invariant across a long death, recovery, expiry and extraction sequence", function()
			local state = claims.emptyState()
			local now = 0
			local minted = 0
			local sequence = { "death", "disconnect", "teleport" }
			for round = 1, 6 do
				now += 10
				state = ok(state, carry("claim." .. round .. ".a", HAULER, ORE, round), now).state
				minted += round
				now += 1
				state = ok(state, carry("claim." .. round .. ".b", HAULER, HERB, 1), now).state

				now += 1
				local cause = sequence[(round - 1) % 3 + 1]
				state = ok(state, release("drop." .. round, HAULER, cause, now + 100), now).state
				expect(conserved(state, ORE)):toBe(minted)

				now += 1
				if round % 2 == 0 then
					state = ok(state, recover("drop." .. round, RIVAL), now).state
					now += 1
					state = ok(state, extract("run." .. round, RIVAL, CAMP), now).state
				else
					now += 200
					state = ok(state, expire("drop." .. round), now).state
				end
				expect(conserved(state, ORE)):toBe(minted)
			end

			local row = censusRow(state, ORE)
			expect(row.carried):toBe(0)
			expect(row.dropped):toBe(0)
			expect(row.banked):toBe(2 + 4 + 6)
			expect(row.lost):toBe(1 + 3 + 5)
			expect(row.banked + row.lost):toBe(minted)
		end)
	end)

	local function mutable(state: State): State
		local value: State = { lastClockSec = state.lastClockSec, claims = {}, drops = {}, extractions = {} }
		for _, claim in state.claims do
			table.insert(value.claims, table.clone(claim))
		end
		for _, drop in state.drops do
			local copy = table.clone(drop)
			copy.claimIds = table.clone(drop.claimIds)
			table.insert(value.drops, copy)
		end
		for _, extraction in state.extractions do
			local copy = table.clone(extraction)
			copy.claimIds, copy.totals = table.clone(extraction.claimIds), {}
			for _, total in extraction.totals do
				table.insert(copy.totals, table.clone(total))
			end
			table.insert(value.extractions, copy)
		end
		return value
	end

	describe("Cargo saved custody", function()
		it("rejects a claim that names a drop it is not filed under", function()
			local state = mutable(ok(loadedHauler(), release("drop.1", HAULER, "death", 400), 40).state)
			state.drops[1].claimIds = {}
			local projected, reason = claims.projectState(state)
			expect(projected):toBeNil()
			expect(reason):toBe("state_invalid")
		end)
		it("rejects a claim banked into an extraction that does not exist", function()
			local state = mutable(ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10).state)
			state.claims[1].status, state.claims[1].holderId = "banked", "run.absent"
			local projected, reason = claims.projectState(state)
			expect(projected):toBeNil()
			expect(reason):toBe("state_invalid")
		end)
		it("rejects a receipt whose totals disagree with the claims it banked", function()
			local state = mutable(ok(loadedHauler(), extract("run.1", HAULER, CAMP), 40).state)
			state.extractions[1].totals[1].count += 1
			local projected, reason = claims.projectState(state)
			expect(projected):toBeNil()
			expect(reason):toBe("state_invalid")
		end)
		it("rejects a claim still filed under a drop that was already recovered", function()
			local state = mutable(ok(loadedHauler(), release("drop.1", HAULER, "death", 400), 40).state)
			state.drops[1].recoveredBy = RIVAL
			local projected, reason = claims.projectState(state)
			expect(projected):toBeNil()
			expect(reason):toBe("state_invalid")
		end)
		it("rejects a drop that is both recovered and expired, and a duplicate claim id", function()
			local state = mutable(ok(loadedHauler(), release("drop.1", HAULER, "death", 400), 40).state)
			state.drops[1].expired, state.drops[1].recoveredBy = true, RIVAL
			expect((claims.projectState(state))):toBeNil()
			local duplicate = mutable(ok(claims.emptyState(), carry("claim.a", HAULER, ORE, 4), 10).state)
			table.insert(duplicate.claims, table.clone(duplicate.claims[1]))
			expect((claims.projectState(duplicate))):toBeNil()
		end)
		it("round-trips a real state through projection unchanged", function()
			local state = ok(loadedHauler(), release("drop.1", HAULER, "death", 400), 40).state
			state = ok(state, recover("drop.1", RIVAL), 50).state
			state = ok(state, extract("run.1", RIVAL, CAMP), 60).state
			local projected = assert(claims.projectState(state))
			expect(projected):toEqual(state)
			expect(projected).never:toBe(state)
			expect(#projected.claims):toBe(#state.claims)
			expect(#projected.drops):toBe(1)
			expect(#projected.extractions):toBe(1)
			expect(table.isfrozen(projected)):toBe(true)
		end)
		it("hands off a dropped claim once and deposits it with replay-safe credit", function()
			local initial = loadedHauler()
			local state = ok(initial, release("drop.1", HAULER, "death", 400), 40).state
			state = ok(state, recover("drop.1", RIVAL), 50).state
			local delivered = ok(state, extract("run.1", RIVAL, CAMP), 60)
			local replay = ok(delivered.state, extract("run.1", RIVAL, CAMP), 61)
			expect(initial.claims[1].status):toBe("carried")
			expect(replay.intents):toEqual(delivered.intents)
			expect(replay.intents[1].eventId):toBe("delivery/run.1/ore")
			expect(replay.intents[1].kind):toBe("deposit")
		end)
		it("retires lost transient claims without retaining their drop", function()
			local state = ok(loadedHauler(), release("drop.1", HAULER, "disconnect", 400), 40).state
			state = ok(state, expire("drop.1"), 400).state
			local replay = ok(state, expire("drop.1"), 401)
			expect(replay.expiredCount):toBe(0)
			local retired = assert(claims.retireTransient(replay.state))
			expect(#retired.claims):toBe(0)
			expect(#retired.drops):toBe(0)
		end)
	end)
end
