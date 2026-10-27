--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Creation = require("./creation")
local Names = require("./name-record")
local Policy = require("../../test-scene/identity")
local Records = require("./creation-record")
local Roster = require("./roster")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local names = Names.create(Policy)
local creation = Creation.create(Policy)
local records = Records.create(Policy)
local roster = Roster.create(Policy)

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("identity records", function()
		it("retains revision tombstones, refuses foreign release and honors the supplied key namespace", function()
			local requested =
				{ schemaVersion = 1, displayName = "Example", userId = 7, characterId = "id", claimedAtUnix = 10 }
			local claimed, status = names.claim(nil, requested)
			assert(claimed)
			expect(status):toBe("claimed")
			expect(claimed.registryKey):toBe("claim/example")
			expect(table.isfrozen(claimed)):toBe(true)
			expect(select(2, names.release(claimed, "Example", 8, "id"))):toBe("mismatch")
			local released, releaseStatus = names.release(claimed, "Example", 7, "id")
			assert(released)
			expect(releaseStatus):toBe("released")
			expect(released.claim):toBe(false)
			expect(released.revision):toBe(claimed.revision + 1)
			expect(names.availability(released, "Example", 8, "other")):toBe("available")
			local successor = table.clone(requested)
			successor.userId = 8
			local reclaimed = assert(names.claim(released, successor))
			expect(reclaimed.revision):toBe(released.revision + 1)
			expect(select(2, names.release(reclaimed, "Example", 7, "id"))):toBe("mismatch")
			local wrongKey = table.clone(claimed)
			wrongKey.registryKey = "other/example"
			expect(names.validate(wrongKey)):toBeNil()
			local exhausted = table.clone(released)
			exhausted.revision = names.MAX_REVISION
			expect(select(2, names.claim(exhausted, successor))):toBe("exhausted")
			expect(names.validate(setmetatable(table.clone(claimed), {}))):toBeNil()
		end)
		it("binds the prepared seed and committed receipt to the same immutable creation generation", function()
			local prepared = assert(creation.prepare(nil, {
				userId = 7,
				operationId = "create",
				characterId = "id",
				displayName = "Example",
				realmId = "red",
				peopleId = "first",
				classId = "role",
				appearancePresetId = "preset",
				createdAtUnix = 10,
				fence = 1,
				leaseRevision = 1,
			}).state)
			expect(records.fromTransaction(prepared)):toBeNil()
			local claim = assert(creation.plan(prepared)).claim
			local owned = assert(creation.observeName(prepared, {
				expectedRevision = prepared.revision,
				expectedFence = prepared.fence,
				readback = claim,
			}).state)
			local profile = assert(creation.observeProfile(owned, {
				expectedRevision = owned.revision,
				expectedFence = owned.fence,
				readback = {
					operationId = owned.operationId,
					fingerprint = owned.fingerprint,
					characterId = owned.characterId,
					revision = owned.revision,
					fence = owned.fence,
					prepared = true,
				},
			}).state)
			local seed = assert(records.fromTransaction(profile))
			expect(records.receiptFromTransaction(profile)):toBeNil()
			local base = { schemaVersion = 1, userId = 7, characters = {} }
			local committed = assert(creation.observeRoster(profile, {
				expectedRevision = profile.revision,
				expectedFence = profile.fence,
				base = base,
				readback = roster.add(base, assert(creation.plan(profile)).character),
			}).state)
			local receipt = assert(records.receiptFromTransaction(committed))
			expect(records.receiptMatchesSeed(receipt, seed)):toBe(true)
			expect(records.seedMatchesReceipt(seed, receipt)):toBe(true)
			expect(records.matchesTransaction(seed, profile)):toBe(true)
			expect(table.isfrozen(seed)):toBe(true)
			local foreign = table.clone(receipt)
			foreign.fence += 1
			expect(records.receiptMatchesSeed(foreign, seed)):toBe(false)
			local corrupted = table.clone(seed)
			corrupted.displayName = "Different"
			expect(records.validate(corrupted)):toBeNil()
			expect(records.validate(setmetatable(table.clone(seed), {}))):toBeNil()
		end)
	end)
end
