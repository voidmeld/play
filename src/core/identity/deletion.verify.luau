--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Creation = require("./creation")
local Deletion = require("./deletion")
local NameRegistry = require("./name-claims")
local Policy = require("../../test-scene/identity")
local Registry = require("./name-claims")
local Roster = require("./roster")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local roster = Roster.create(Policy)
local deletion = Deletion.create(Policy)
local nameregistry = NameRegistry.create(Policy)
local Value = require("../internal/value")
type Raw = Value.Raw
local function nested(value: { [string]: unknown }, key: string): Raw
	local result = assert(Value.raw(value[key]))
	value[key] = result
	return result
end
local function nudge(value: Raw, key: string, delta: number)
	local current = value[key]
	assert(type(current) == "number")
	value[key] = current + delta
end

type Result = Deletion.Result
type State = Deletion.State
type Plan = Deletion.Plan
type Accepted = Deletion.Accepted

type Receipt = Creation.Receipt
type Claim = Registry.Claim
type RosterValue = Roster.Roster

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local function planOf(plan: Plan?): Plan
		return assert(plan, "transaction plan missing")
	end

	local function stateOf(result: Result): State
		return assert(result.state, "transaction state missing")
	end

	local function request(operationId: string, fence: number?): Raw
		return {
			userId = 101,
			operationId = operationId,
			characterId = "character.a",
			displayName = "Alden Vale",
			requestedAtUnix = 90,
			fence = fence or 7,
			leaseRevision = 1,
		}
	end

	local function prepared(): State
		local result = deletion.prepare(nil, request("delete.1"))
		expect(result.ok):toBe(true)
		assert(result.ok)
		return stateOf(result)
	end

	local function event(state: State): Creation.Completion
		return { expectedRevision = state.revision, expectedFence = state.fence }
	end

	local function receipt(state: State, field: string): Receipt
		return {
			operationId = state.operationId,
			fingerprint = state.fingerprint,
			characterId = state.characterId,
			revision = state.revision,
			fence = state.fence,
			[field] = true,
		}
	end

	local function claim(state: State)
		return {
			displayName = state.displayName,
			userId = state.userId,
			characterId = state.characterId,
			claimedAtUnix = 50,
			schemaVersion = 1,
		}
	end

	local function character(state: State)
		return {
			characterId = state.characterId,
			displayName = state.displayName,
			realmId = "red",
			peopleId = "first",
			classId = "fighter",
			appearancePresetId = "preset.issued",
			createdAtUnix = 50,
			lastPlayedAtUnix = 60,
			level = roster.MIN_LEVEL,
			lastDestinationId = roster.NEVER_DEPARTED,
		}
	end

	local function other()
		return {
			characterId = "character.b",
			displayName = "Berwyn Ash",
			realmId = "green",
			peopleId = "second",
			classId = "shifter",
			appearancePresetId = "preset.issued",
			createdAtUnix = 51,
			lastPlayedAtUnix = 61,
			level = roster.MIN_LEVEL,
			lastDestinationId = roster.NEVER_DEPARTED,
		}
	end

	local function populatedRoster(state: State)
		local value = { schemaVersion = roster.SCHEMA_VERSION, userId = state.userId, characters = {} }
		value = roster.add(value, character(state))
		return roster.add(value, other())
	end

	local function rosterRemoved(state: State)
		local base = populatedRoster(state)
		local completion = event(state)
		completion.base = base
		completion.readback = (roster.remove(base, state.characterId))
		local result = deletion.observeRoster(state, completion)
		expect(result.ok):toBe(true)
		assert(result.ok)
		return stateOf(result)
	end

	local function nameReleased(state: State)
		local completion = event(state)
		completion.readbackReceived = true
		local result = deletion.observeNameRelease(state, completion)
		expect(result.ok):toBe(true)
		assert(result.ok)
		return stateOf(result)
	end

	describe("CharacterDeletionTransaction preparation and resume", function()
		it("binds a fingerprinted deletion identity and replays the identical request", function()
			local first = deletion.prepare(nil, request("delete.1"))
			local resumed = deletion.prepare(stateOf(first), request("delete.1"))
			expect(first.ok):toBe(true)
			assert(first.ok)
			expect(stateOf(first).phase):toBe("prepared")
			expect(resumed.ok):toBe(true)
			assert(resumed.ok)
			expect((resumed).replayed):toBe(true)
			expect(stateOf(resumed)):toEqual(stateOf(first))
			for field, value in
				assert(Value.raw({
					userId = 102,
					characterId = "character.b",
					displayName = "Alden Stone",
					requestedAtUnix = 91,
				}))
			do
				local changed = request("delete.1")
				changed[field] = value
				expect(deletion.prepare(stateOf(first), changed).reason):toBe("receipt_conflict")
			end
			expect(deletion.prepare(stateOf(first), request("delete.2")).reason):toBe("deletion_in_progress")
		end)

		it("refuses malformed requests, identity reuse, and malformed persisted state", function()
			for _, value in assert(Value.raw({ math.nan, math.huge, -math.huge, deletion.MAX_SAFE_INTEGER + 1 })) do
				local malformed = request("delete.1")
				malformed.userId = value
				expect(deletion.prepare(nil, malformed).reason):toBe("malformed_request")
				malformed = request("delete.1")
				malformed.fence = value
				expect(deletion.prepare(nil, malformed).reason):toBe("malformed_request")
			end
			local reused = request("delete.1")
			reused.characterId = "Alden Vale"
			expect(deletion.prepare(nil, reused).reason):toBe("malformed_request")
			local reserved = request("delete.1")
			reserved.displayName = "Reserved"
			expect(deletion.prepare(nil, reserved).reason):toBe("malformed_request")
			local state = prepared()
			state.revision = math.huge
			expect(deletion.prepare(state, request("delete.1")).reason):toBe("malformed_state")
		end)

		it("keeps validate projections detached from the persisted state", function()
			local state = prepared()
			local validated = deletion.validate(state)
			expect(validated):toEqual(state)
			assert(validated ~= nil, "expected valid deletion transaction")
			validated.displayName = "Changed"
			expect(state.displayName):toBe("Alden Vale")
			expect(planOf(deletion.plan(state)).kind):toBe("remove_roster")
		end)
	end)

	describe("CharacterDeletionTransaction roster removal", function()
		it("accepts only the exact roster-minus-character readback as the removal commit", function()
			local state = prepared()
			local base = populatedRoster(state)
			local stale = event(state)
			stale.base = base
			stale.readback = base
			expect(deletion.observeRoster(state, stale).reason):toBe("readback_mismatch")
			local value = rosterRemoved(state)
			expect(value.phase):toBe("roster_removed")
			expect(planOf(deletion.plan(value)).kind):toBe("release_name")
			expect(assert(planOf(deletion.plan(value)).release, "release plan missing").displayName):toBe("Alden Vale")
		end)

		it("frees the realm slot so the removal readback admits a replacement character", function()
			local state = prepared()
			local base = populatedRoster(state)
			local removed = (roster.remove(base, state.characterId))
			local replacement = character(state)
			replacement.characterId = "character.c"
			replacement.displayName = "Cadfan Rees"
			replacement.lastPlayedAtUnix = replacement.createdAtUnix
			expect(#roster.validate(roster.add(removed, replacement)).characters):toBe(2)
		end)

		it("distinguishes absent characters, foreign rosters, response loss, and future records", function()
			local state = prepared()
			local absentBase = event(state)
			absentBase.base = { schemaVersion = roster.SCHEMA_VERSION, userId = state.userId, characters = { other() } }
			absentBase.readback = absentBase.base
			expect(deletion.observeRoster(state, absentBase).reason):toBe("character_absent")
			local foreign = event(state)
			foreign.base = populatedRoster(state)
			nested(foreign, "base").userId = 202
			foreign.readback = foreign.base
			expect(deletion.observeRoster(state, foreign).reason):toBe("foreign_collision")
			local renamed = event(state)
			local renamedRow = character(state)
			renamedRow.displayName = "Alden Stone"
			renamed.base = roster.add(
				{ schemaVersion = roster.SCHEMA_VERSION, userId = state.userId, characters = {} },
				renamedRow
			)
			renamed.readback = (roster.remove(renamed.base, state.characterId))
			expect(deletion.observeRoster(state, renamed).reason):toBe("foreign_collision")
			local lost = event(state)
			lost.base = populatedRoster(state)
			expect(deletion.observeRoster(state, lost).reason):toBe("readback_absent")
			local future = event(state)
			future.base = populatedRoster(state)
			future.readback = { schemaVersion = roster.SCHEMA_VERSION + 1, userId = state.userId, characters = {} }
			expect(deletion.observeRoster(state, future).reason):toBe("future_readback")
			local staleRevision = event(state)
			staleRevision.expectedRevision += 1
			expect(deletion.observeRoster(state, staleRevision).reason):toBe("stale_revision")
			local staleFence = event(state)
			staleFence.expectedFence += 1
			expect(deletion.observeRoster(state, staleFence).reason):toBe("stale_fence")
		end)
	end)

	describe("CharacterDeletionTransaction name release", function()
		it("requires the post-release read to prove the claim is gone before finishing", function()
			local state = rosterRemoved(prepared())
			local silent = event(state)
			expect(deletion.observeNameRelease(state, silent).reason):toBe("readback_absent")
			local held = event(state)
			held.readbackReceived = true
			held.readback = claim(state)
			expect(deletion.observeNameRelease(state, held).reason):toBe("name_still_owned")
			local reclaimed = event(state)
			reclaimed.readbackReceived = true
			reclaimed.readback = claim(state)
			nested(reclaimed, "readback").userId = 202
			nested(reclaimed, "readback").characterId = "character.new"
			local passed = deletion.observeNameRelease(state, reclaimed)
			expect(passed.ok):toBe(true)
			assert(passed.ok)
			expect(stateOf(passed).phase):toBe("name_released")
			local freed = nameReleased(state)
			expect(planOf(deletion.plan(freed)).kind):toBe("release_lease")
		end)

		it("rejects wrong-key, malformed, and future name readbacks distinctly", function()
			local state = rosterRemoved(prepared())
			local wrongKey = event(state)
			wrongKey.readbackReceived = true
			wrongKey.readback = claim(state)
			nested(wrongKey, "readback").displayName = "Berwyn Ash"
			expect(deletion.observeNameRelease(state, wrongKey).reason):toBe("readback_mismatch")
			local malformed = event(state)
			malformed.readbackReceived = true
			malformed.readback = { displayName = "Alden Vale" }
			expect(deletion.observeNameRelease(state, malformed).reason):toBe("malformed_readback")
			local future = event(state)
			future.readbackReceived = true
			future.readback = claim(state)
			nested(future, "readback").schemaVersion = nameregistry.SCHEMA_VERSION + 1
			expect(deletion.observeNameRelease(state, future).reason):toBe("future_readback")
		end)

		it(
			"refuses a lease-release receipt from another operation, another generation, or without its phase flag",
			function()
				local state = nameReleased(rosterRemoved(prepared()))

				local foreign = event(state)
				foreign.readback = receipt(state, "released")
				nested(foreign, "readback").operationId = "delete.other"
				expect(deletion.observeLeaseRelease(state, foreign).reason):toBe("foreign_collision")

				local renamed = event(state)
				renamed.readback = receipt(state, "released")
				nested(renamed, "readback").characterId = "character.other"
				expect(deletion.observeLeaseRelease(state, renamed).reason):toBe("foreign_collision")

				local ahead = event(state)
				ahead.readback = receipt(state, "released")
				nudge(nested(ahead, "readback"), "revision", 1)
				expect(deletion.observeLeaseRelease(state, ahead).reason):toBe("future_readback")

				local fenced = event(state)
				fenced.readback = receipt(state, "released")
				nudge(nested(fenced, "readback"), "fence", 1)
				expect(deletion.observeLeaseRelease(state, fenced).reason):toBe("future_readback")

				local behind = event(state)
				behind.readback = receipt(state, "released")
				nudge(nested(behind, "readback"), "revision", -1)
				expect(deletion.observeLeaseRelease(state, behind).reason):toBe("readback_mismatch")

				local unflagged = event(state)
				unflagged.readback = receipt(state, "released")
				nested(unflagged, "readback").released = false
				expect(deletion.observeLeaseRelease(state, unflagged).reason):toBe("readback_mismatch")

				local exact = event(state)
				exact.readback = receipt(state, "released")
				expect(deletion.observeLeaseRelease(state, exact).ok):toBe(true)
			end
		)

		it("makes the released name claimable again for a different account", function()
			local state = nameReleased(rosterRemoved(prepared()))
			local successor = {
				displayName = state.displayName,
				userId = 202,
				characterId = "character.new",
				claimedAtUnix = 120,
				schemaVersion = nameregistry.SCHEMA_VERSION,
			}
			local record, status = nameregistry.claim(nil, successor)
			expect(status):toBe("claimed")
			expect(record.userId):toBe(202)
		end)
	end)

	describe("CharacterDeletionTransaction rollback, lease, and takeover", function()
		it("allows rollback only before the roster removal is visible", function()
			local untouched = prepared()
			local requestAbort = event(untouched)
			requestAbort.readback = receipt(untouched, "acknowledged")
			local rolling = deletion.requestRollback(untouched, requestAbort)
			expect(rolling.ok):toBe(true)
			assert(rolling.ok)
			expect(stateOf(rolling).phase):toBe("rolling_back")
			expect(planOf(deletion.plan(stateOf(rolling))).kind):toBe("rollback_deletion")
			local finish = event(stateOf(rolling))
			finish.readback = receipt(stateOf(rolling), "aborted")
			local aborted = deletion.observeRollback(stateOf(rolling), finish)
			expect(aborted.ok):toBe(true)
			assert(aborted.ok)
			expect(stateOf(aborted).phase):toBe("aborted")
			expect(deletion.plan(stateOf(aborted))):toBeNil()
			local removed = rosterRemoved(prepared())
			local forbidden = event(removed)
			forbidden.readback = receipt(removed, "acknowledged")
			expect(deletion.requestRollback(removed, forbidden).reason):toBe("postremoval_compensation_forbidden")
		end)

		it("finishes at lease release and refuses further transitions", function()
			local state = nameReleased(rosterRemoved(prepared()))
			local lost = event(state)
			expect(deletion.observeLeaseRelease(state, lost).reason):toBe("readback_absent")
			local released = event(state)
			released.readback = receipt(state, "released")
			local finished = deletion.observeLeaseRelease(state, released)
			expect(finished.ok):toBe(true)
			assert(finished.ok)
			expect(stateOf(finished).phase):toBe("lease_released")
			expect(deletion.plan(stateOf(finished))):toBeNil()
			local again = event(stateOf(finished))
			again.readback = receipt(stateOf(finished), "released")
			expect(deletion.observeLeaseRelease(stateOf(finished), again).reason):toBe("phase_order")
			local expired = event(state)
			expired.readback = receipt(state, "released")
			nested(expired, "readback").released = nil
			nested(expired, "readback").expired = true
			expect(stateOf(deletion.observeLeaseRelease(state, expired)).phase):toBe("lease_released")
		end)

		it("fences takeover while retaining the initial acquisition identity", function()
			local state = rosterRemoved(prepared())
			local stale = event(state)
			stale.fence = state.fence
			stale.readback = receipt(state, "acquired")
			expect(deletion.takeover(state, stale).reason):toBe("stale_fence")
			local acquired = event(state)
			acquired.fence = state.fence + 1
			acquired.leaseRevision = state.leaseRevision + 3
			acquired.readback = receipt(state, "acquired")
			nested(acquired, "readback").revision = state.revision + 1
			nested(acquired, "readback").fence = acquired.fence
			nested(acquired, "readback").leaseRevision = acquired.leaseRevision
			local taken = deletion.takeover(state, acquired)
			expect(taken.ok):toBe(true)
			assert(taken.ok)
			expect(stateOf(taken).initialFence):toBe(state.initialFence)
			expect(stateOf(taken).initialLeaseRevision):toBe(state.initialLeaseRevision)
			expect(stateOf(taken).fence):toBe(acquired.fence)
			expect(stateOf(taken).leaseRevision):toBe(acquired.leaseRevision)
			expect(deletion.validate(stateOf(taken))).never:toBeNil()
		end)
	end)
end
