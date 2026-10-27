--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Creation = require("./creation")
local Policy = require("../../test-scene/identity")
local Registry = require("./name-claims")
local Roster = require("./roster")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local creation = Creation.create(Policy)
local roster = Roster.create(Policy)
local registry = Registry.create(Policy)
type Result = Creation.Result
type State = Creation.State
type Plan = Creation.Plan
type Accepted = Creation.Accepted

type Receipt = typeof(creation.Types.Receipt)
type Claim = typeof(registry.Types.Claim)
type RosterValue = typeof(roster.Types.Roster)

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local function planOf(plan: Plan?): Plan
		return assert(plan, "transaction plan missing")
	end

	local function stateOf(result: Result): State
		return assert(result.state, "transaction state missing")
	end

	local function request(
		operationId: string,
		displayName: string?,
		fence: number?
	): Creation.Prepared & { [string]: unknown }
		return {
			userId = 101,
			operationId = operationId,
			characterId = "character.a",
			displayName = displayName or "Alden Vale",
			realmId = "red",
			peopleId = "first",
			classId = "fighter",
			appearancePresetId = "lobby.preset_first_watchward",
			createdAtUnix = 50,
			fence = fence or 7,
			leaseRevision = 1,
		}
	end

	local function prepared(): State
		local result = creation.prepare(nil, request("create.1"))
		expect(result.ok):toBe(true)
		return stateOf(result)
	end

	local function event(state: State): typeof(creation.Types.Completion)
		return { expectedRevision = state.revision, expectedFence = state.fence }
	end

	local function claim(state: State)
		return {
			displayName = state.displayName,
			userId = state.userId,
			characterId = state.characterId,
			claimedAtUnix = state.createdAtUnix,
			schemaVersion = 1,
		}
	end

	local function receipt(state: State, field: string): Receipt
		return (
			{
				operationId = state.operationId,
				fingerprint = state.fingerprint,
				characterId = state.characterId,
				revision = state.revision,
				fence = state.fence,
				[field] = true,
			} :: unknown
		) :: Receipt
	end

	local function emptyRoster()
		return { schemaVersion = roster.SCHEMA_VERSION, userId = 101, characters = {} }
	end

	local function ownName(state: State)
		local completion = event(state)
		completion.readback = claim(state)
		local result = creation.observeName(state, completion)
		expect(result.ok):toBe(true)
		return stateOf(result)
	end

	local function preparedProfile(state: State)
		local completion = event(state)
		completion.readback = receipt(state, "prepared")
		local result = creation.observeProfile(state, completion)
		expect(result.ok):toBe(true)
		return stateOf(result)
	end

	local function committed(state: State)
		local base = emptyRoster()
		local completion = event(state)
		completion.base = base
		completion.readback = roster.add(base, planOf(creation.plan(state)).character)
		local result = creation.observeRoster(state, completion)
		expect(result.ok):toBe(true)
		return stateOf(result)
	end

	describe("CharacterCreationTransaction preparation and resume", function()
		it("binds an immutable server character identity and normalized creation fingerprint", function()
			local first = creation.prepare(nil, request("create.1", "  Alden Vale  "))
			local resumed = creation.prepare(stateOf(first), request("create.1", "Alden Vale"))
			expect(first.ok):toBe(true)
			expect(stateOf(first).displayName):toBe("Alden Vale")
			expect(stateOf(first).characterId):toBe("character.a")
			expect(resumed.ok):toBe(true)
			expect((resumed :: Accepted).replayed):toBe(true)
			expect(stateOf(resumed)):toEqual(stateOf(first))
			for field, value in
				{
					userId = 102,
					characterId = "character.b",
					displayName = "Alden Stone",
					realmId = "green",
					peopleId = "second",
					classId = "guard",
					appearancePresetId = "preset.second.issued",
					createdAtUnix = 51,
				} :: { [string]: unknown }
			do
				local changed = request("create.1")
				changed[field] = value
				expect(creation.prepare(stateOf(first), changed).reason):toBe("receipt_conflict")
			end
			expect(creation.prepare(stateOf(first), request("create.2")).reason):toBe("creation_in_progress")
		end)

		it("accepts realistic safe timestamps and identities while rejecting unsafe numeric values", function()
			local realistic = request("create.1")
			realistic.userId = 4294967295
			realistic.createdAtUnix = 1780000000
			local state = stateOf(creation.prepare(nil, realistic))
			expect(state.userId):toBe(4294967295)
			expect(state.createdAtUnix):toBe(1780000000)
			for _, value in { math.nan, math.huge, -math.huge, creation.MAX_SAFE_INTEGER + 1 } do
				local malformed = request("create.1")
				malformed.userId = value
				expect(creation.prepare(nil, malformed).reason):toBe("malformed_request")
				malformed = request("create.1")
				malformed.createdAtUnix = value
				expect(creation.prepare(nil, malformed).reason):toBe("malformed_request")
			end
		end)

		it("keeps maximal valid fingerprints replayable and validate projections detached", function()
			local maximal = request(string.rep("o", 128), string.rep("A", 20))
			maximal.characterId = string.rep("c", 64)
			maximal.classId = string.rep("k", 64)
			maximal.appearancePresetId = string.rep("a", 64)
			local created = creation.prepare(nil, maximal)
			expect(created.ok):toBe(true)
			expect(#stateOf(created).fingerprint > 128):toBe(true)
			local validated = creation.validate(stateOf(created))
			expect(validated):toEqual(stateOf(created))
			assert(validated ~= nil, "expected valid creation transaction")
			validated.displayName = "Changed"
			expect(stateOf(created).displayName):toBe(string.rep("A", 20))
			expect(creation.plan(stateOf(created))).never:toBeNil()
		end)

		it("refuses malformed selection, invalid counters, and malformed persisted state", function()
			local malformed = request("create.1")
			malformed.fence = math.nan
			expect(creation.prepare(nil, malformed).reason):toBe("malformed_request")
			malformed = request("create.1")
			malformed.realmId = "elsewhere"
			expect(creation.prepare(nil, malformed).reason):toBe("malformed_request")
			local state = prepared()
			state.revision = math.huge
			expect(creation.prepare(state, request("create.1")).reason):toBe("malformed_state")
		end)
	end)

	describe("CharacterCreationTransaction precommit effects", function()
		it(
			"requires exact name ownership and treats response loss, foreign collisions, and future records distinctly",
			function()
				local state = prepared()
				local missing = event(state)
				missing.readback = nil
				local absent = creation.observeName(state, missing)
				expect(absent.reason):toBe("readback_absent")
				expect(stateOf(absent)):toEqual(state)
				local foreign = event(state)
				foreign.readback = claim(state);
				(foreign.readback :: Claim).userId = 202
				expect(creation.observeName(state, foreign).reason):toBe("foreign_collision")
				local future = event(state)
				future.readback = claim(state);
				(future.readback :: Claim).schemaVersion = 2
				expect(creation.observeName(state, future).reason):toBe("future_readback")
				local owned = ownName(state)
				expect(owned.phase):toBe("name_owned")
			end
		)

		it("requires exact profile readback and blocks stale revisions, fences, and duplicated callbacks", function()
			local state = ownName(prepared())
			local stale = event(state)
			stale.expectedRevision -= 1
			stale.readback = receipt(state, "prepared")
			expect(creation.observeProfile(state, stale).reason):toBe("stale_revision")
			local fenced = event(state)
			fenced.expectedFence += 1
			fenced.readback = receipt(state, "prepared")
			expect(creation.observeProfile(state, fenced).reason):toBe("stale_fence")
			local lost = event(state)
			expect(creation.observeProfile(state, lost).reason):toBe("readback_absent")
			local profile = preparedProfile(state)
			expect(creation.observeProfile(profile, event(profile)).reason):toBe("phase_order")
		end)

		it("refuses a profile receipt from another operation, another generation, or without its phase flag", function()
			local state = ownName(prepared())

			local foreign = event(state)
			foreign.readback = receipt(state, "prepared");
			(foreign.readback :: Receipt).operationId = "create.other"
			expect(creation.observeProfile(state, foreign).reason):toBe("foreign_collision")

			local renamed = event(state)
			renamed.readback = receipt(state, "prepared");
			(renamed.readback :: Receipt).characterId = "character.other"
			expect(creation.observeProfile(state, renamed).reason):toBe("foreign_collision")

			local ahead = event(state)
			ahead.readback = receipt(state, "prepared");
			(ahead.readback :: Receipt).revision += 1
			expect(creation.observeProfile(state, ahead).reason):toBe("future_readback")

			local fenced = event(state)
			fenced.readback = receipt(state, "prepared");
			(fenced.readback :: Receipt).fence += 1
			expect(creation.observeProfile(state, fenced).reason):toBe("future_readback")

			local behind = event(state)
			behind.readback = receipt(state, "prepared");
			(behind.readback :: Receipt).revision -= 1
			expect(creation.observeProfile(state, behind).reason):toBe("readback_mismatch")

			local unflagged = event(state)
			unflagged.readback = receipt(state, "prepared");
			(unflagged.readback :: Receipt).prepared = false
			expect(creation.observeProfile(state, unflagged).reason):toBe("readback_mismatch")

			local exact = event(state)
			exact.readback = receipt(state, "prepared")
			expect(creation.observeProfile(state, exact).ok):toBe(true)
		end)

		it("accepts only the exact roster CAS readback as the visibility commit", function()
			local state = preparedProfile(ownName(prepared()))
			local base = emptyRoster()
			local bad = event(state)
			bad.base = base
			bad.readback = emptyRoster()
			expect(creation.observeRoster(state, bad).reason):toBe("readback_mismatch")
			local value = committed(state)
			expect(value.phase):toBe("committed")
			expect(planOf(creation.plan(value)).kind):toBe("release_lease")
		end)
	end)

	describe("CharacterCreationTransaction rollback and lease recovery", function()
		it("allows unnamed rollback but requires named rollback to prove release or newer foreign ownership", function()
			local untouched = prepared()
			local requestAbort = event(untouched)
			requestAbort.readback = receipt(untouched, "acknowledged")
			local rollingUntouched = creation.requestRollback(untouched, requestAbort)
			expect(stateOf(rollingUntouched).rollbackNeedsNameRelease):toBe(false)
			local finishUntouched = event(stateOf(rollingUntouched))
			finishUntouched.profileReadback = receipt(stateOf(rollingUntouched), "aborted")
			expect(stateOf(creation.observeRollback(stateOf(rollingUntouched), finishUntouched)).phase):toBe("aborted")

			local state = preparedProfile(ownName(prepared()))
			local requested = event(state)
			requested.readback = receipt(state, "acknowledged")
			local rolling = creation.requestRollback(state, requested)
			expect(rolling.ok):toBe(true)
			expect(stateOf(rolling).rollbackNeedsNameRelease):toBe(true)
			local missingName = event(stateOf(rolling))
			missingName.profileReadback = receipt(stateOf(rolling), "aborted")
			expect(creation.observeRollback(stateOf(rolling), missingName).reason):toBe("readback_absent")
			local releasedAbsent = event(stateOf(rolling))
			releasedAbsent.profileReadback = receipt(stateOf(rolling), "aborted")
			releasedAbsent.nameReadbackReceived = true
			expect(stateOf(creation.observeRollback(stateOf(rolling), releasedAbsent)).phase):toBe("aborted")

			local ownedReadback = event(stateOf(rolling))
			ownedReadback.profileReadback = receipt(stateOf(rolling), "aborted")
			ownedReadback.nameReadbackReceived = true
			ownedReadback.nameReadback = claim(stateOf(rolling))
			expect(creation.observeRollback(stateOf(rolling), ownedReadback).reason):toBe("name_still_owned")
			local done = event(stateOf(rolling))
			done.profileReadback = receipt(stateOf(rolling), "aborted")
			done.nameReadbackReceived = true
			done.nameReadback = claim(stateOf(rolling));
			(done.nameReadback :: Claim).userId = 202
			(done.nameReadback :: Claim).characterId = "character.new"
			local aborted = creation.observeRollback(stateOf(rolling), done)
			expect(aborted.ok):toBe(true)
			expect(stateOf(aborted).phase):toBe("aborted")
			local live = committed(preparedProfile(ownName(prepared())))
			local forbidden = event(live)
			forbidden.readback = receipt(live, "acknowledged")
			expect(creation.requestRollback(live, forbidden).reason):toBe("postcommit_compensation_forbidden")
		end)

		it("fences takeover, permits postcommit release retry or expiry, and returns detached values", function()
			local state = committed(preparedProfile(ownName(prepared())))
			local stale = event(state)
			stale.fence = state.fence
			stale.readback = receipt(state, "acquired")
			expect(creation.takeover(state, stale).reason):toBe("stale_fence")
			local acquired = event(state)
			acquired.fence = state.fence + 1
			acquired.readback = receipt(state, "acquired");
			(acquired.readback :: Receipt).revision = state.revision + 1
			(acquired.readback :: Receipt).fence = acquired.fence :: number
			acquired.leaseRevision = state.leaseRevision + 1
			(acquired.readback :: Receipt).leaseRevision = acquired.leaseRevision :: number
			local taken = creation.takeover(state, acquired)
			expect(taken.ok):toBe(true)
			local released = event(stateOf(taken))
			released.readback = receipt(stateOf(taken), "expired")
			local finished = creation.observeLeaseRelease(stateOf(taken), released)
			expect(finished.ok):toBe(true)
			expect(stateOf(finished).phase):toBe("lease_released")
			stateOf(finished).displayName = "Changed"
			expect(stateOf(taken).displayName):toBe("Alden Vale")
		end)

		it("retains acquisition identity while persisting a later lease fence and revision", function()
			local state = committed(preparedProfile(ownName(prepared())))
			local acquired = event(state)
			acquired.fence = state.fence + 1
			acquired.leaseRevision = state.leaseRevision + 4
			acquired.readback = receipt(state, "acquired");
			(acquired.readback :: Receipt).revision = state.revision + 1
			(acquired.readback :: Receipt).fence = acquired.fence :: number
			(acquired.readback :: Receipt).leaseRevision = acquired.leaseRevision :: number
			local taken = creation.takeover(state, acquired)
			expect(taken.ok):toBe(true)
			expect(stateOf(taken).initialFence):toBe(state.initialFence)
			expect(stateOf(taken).initialLeaseRevision):toBe(state.initialLeaseRevision)
			expect(stateOf(taken).fence):toBe(acquired.fence)
			expect(stateOf(taken).leaseRevision):toBe(acquired.leaseRevision)
			expect(creation.validate(stateOf(taken))).never:toBeNil()
		end)
	end)
end
