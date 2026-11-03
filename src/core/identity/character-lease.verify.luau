--!strict

local Atomic = require("./character-lease-store")
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Lease = require("./character-lease")
local Scene = require("../../test-scene/character-leases")
local Value = require("../../kernel/value")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local function config(): Lease.Config
	return {
		schemaVersion = 7,
		maxRevision = 100,
		maxTime = 10000,
		maxFence = 100,
		characterIdLimit = 32,
		zoneIdLimit = 16,
		sessionIdLimit = 32,
		acquisitionIdLimit = 32,
		operationIdLimit = 32,
		fingerprintLimit = 64,
		migrate = function(value)
			return value
		end,
	}
end

local function owned(): Lease.Record
	return {
		schemaVersion = 7,
		revision = 4,
		characterId = "character",
		sessionId = "session",
		acquisitionId = "acquisition",
		expiresAt = 280,
		retirement = false,
		arrival = false,
	}
end

local function witness(fence: number, operationId: string?): Lease.Witness
	return {
		characterId = "character",
		operationId = operationId or "delete",
		fingerprint = "identity",
		fence = fence,
		atUnix = 900,
	}
end

local function claim(fence: number): Lease.Claim
	return {
		characterId = "character",
		sessionId = "session",
		acquisitionId = "acquisition",
		revision = 4,
		fence = fence,
		atUnix = 900,
	}
end

local function keyFor(id: string): string
	return "lease:" .. id
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("character lease custody", function()
		local record = Lease.create(config())
		it("uses supplied schemas and bounds and returns detached records", function()
			local source = owned()
			local copied = assert((record.copy(source)))
			expect(record.equal(source, copied)):toBe(true)
			copied.revision = 5
			expect(source.revision):toBe(4)
			expect(record.equal(source, copied)):toBe(false)
			local empty = assert((record.create("new")))
			expect(empty.schemaVersion):toBe(7)
			expect(empty.revision):toBe(0)
			expect(empty.retirement):toBe(false)
			expect(empty.arrival):toBe(false)
			for _, revision in { -1, 0.5, 101, math.huge, math.nan } do
				local invalid = owned()
				invalid.revision = revision
				expect((record.copy(invalid))):toBeNil()
			end
			expect((record.create(string.rep("x", 33)))):toBeNil()
		end)
		it("refuses erased slots, inconsistent owners and unapproved schemas", function()
			for _, field in { "retirement", "arrival" } do
				local raw = assert(Value.raw(owned()))
				raw[field] = nil
				expect(select(2, record.copy(raw))):toBe(field .. "_absent")
			end
			for version = 1, 8 do
				if version ~= 7 then
					local raw = owned()
					raw.schemaVersion = version
					expect(select(2, record.copy(raw))):toBe("schema_unsupported")
				end
			end
			local broken = owned()
			broken.acquisitionId = nil
			expect(select(2, record.copy(broken))):toBe("lease_invalid")
		end)
		it("keeps migration in the caller and still validates the projected result", function()
			local migrated = Lease.create({
				schemaVersion = 9,
				maxRevision = 100,
				maxTime = 10000,
				maxFence = 100,
				characterIdLimit = 32,
				zoneIdLimit = 16,
				sessionIdLimit = 32,
				acquisitionIdLimit = 32,
				operationIdLimit = 32,
				fingerprintLimit = 64,
				migrate = function(value)
					local raw = Value.raw(value)
					if raw ~= nil and raw.schemaVersion == 7 then
						raw.schemaVersion = 9
					end
					return raw
				end,
			})
			local prior = owned()
			local nextRecord = assert((migrated.copy(prior)))
			expect(nextRecord.schemaVersion):toBe(9)
			expect(prior.schemaVersion):toBe(7)
			local malformed = assert(Value.raw(prior))
			malformed.arrival = nil
			expect(select(2, migrated.copy(malformed))):toBe("arrival_absent")
		end)
		it("fences retirement ownership, receipt conflicts and restoration without touching the lease", function()
			local source = owned()
			local retired, status = record.retire(source, witness(3))
			assert(retired ~= nil)
			expect(status):toBe("retired")
			expect(retired.sessionId):toBe(source.sessionId)
			expect(source.retirement):toBe(false)
			expect(select(2, record.retire(retired, witness(3)))):toBe("replayed")
			expect(select(2, record.retire(retired, witness(2)))):toBe("stale_fence")
			expect(select(2, record.retire(retired, witness(3, "foreign")))):toBe("stale_fence")
			expect(select(2, record.restore(retired, witness(4, "foreign")))):toBe("retirement_not_owned")
			local conflict = witness(3)
			conflict.fingerprint = "different"
			expect(select(2, record.retire(retired, conflict))):toBe("receipt_conflict")
			local takeover = assert((record.retire(retired, witness(4, "foreign"))))
			expect(select(2, record.restore(takeover, witness(3, "foreign")))):toBe("stale_fence")
			local restored = assert((record.restore(takeover, witness(4, "foreign"))))
			expect(restored.retirement):toBe(false)
			expect(record.retired(takeover)):toBe(true)
			expect(record.retired(restored)):toBe(false)
		end)
		it("requires acquired revisions and consumes each arrival fence only for its exact holder", function()
			local arrived, status = record.arrive(owned(), claim(3))
			assert(arrived ~= nil)
			expect(status):toBe("arrived")
			expect(select(2, record.arrive(arrived, claim(3)))):toBe("replayed")
			expect(select(2, record.arrive(arrived, claim(2)))):toBe("stale_fence")
			expect(select(2, record.arrive(owned(), claim(4)))):toBe("fence_unacquired")
			local foreign = claim(3)
			foreign.sessionId = "foreign"
			expect(select(2, record.arrive(arrived, foreign))):toBe("lease_not_owned")
			local retired = assert((record.retire(owned(), witness(3))))
			expect(select(2, record.arrive(retired, claim(3)))):toBe("character_retired")
		end)
	end)

	describe("character lease atomic store", function()
		it("acquires once, renews exactly and refuses stale release after takeover", function()
			local scene = Scene.new(config())
			local repo, store = scene.repository, scene.store
			local first = repo.acquire(store, keyFor, "character", "a", "one", 100, 10, nil, nil, "zone")
			assert(first.ok)
			expect(first.value.revision):toBe(1)
			local replay = repo.acquire(store, keyFor, "character", "a", "one", 101, 10)
			assert(replay.ok)
			expect(replay.value.revision):toBe(1)
			expect(repo.acquire(store, keyFor, "character", "b", "two", 109, 10).reason):toBe("lease_held")
			local renewed = repo.renew(store, keyFor, "character", "a", "one", 1, 109, 10)
			assert(renewed.ok)
			expect(renewed.value.revision):toBe(2)
			expect(repo.renew(store, keyFor, "character", "a", "one", 2, 119, 10).reason):toBe("lease_expired")
			local nextOwner = repo.acquire(store, keyFor, "character", "b", "two", 119, 10)
			assert(nextOwner.ok)
			expect(nextOwner.value.revision):toBe(3)
			expect(repo.release(store, keyFor, "character", "a", "one", 2).reason):toBe("lease_not_owned")
			local released = repo.release(store, keyFor, "character", "b", "two", 3)
			assert(released.ok)
			expect(released.value.sessionId):toBeNil()
			expect(released.value.zoneId):toBe("zone")
		end)
		it("honors live-session policy at and before expiry", function()
			for _, now in { 100, 280 } do
				local scene = Scene.new(config())
				scene.seed(keyFor("character"), owned())
				local function live(): boolean
					return true
				end
				local function absent(): boolean
					return false
				end
				expect(
					scene.repository.acquire(scene.store, keyFor, "character", "new", "new", now, 10, live, live).reason
				):toBe("lease_held")
				local admitted =
					scene.repository.acquire(scene.store, keyFor, "character", "new", "new", now, 10, absent, absent)
				assert(admitted.ok)
				expect(admitted.takeoverPrior ~= nil):toBe(true)
			end
		end)
		it("returns terminal transport failures after a committed retirement and reconciles by receipt", function()
			local fail = false
			local scene = Scene.new(config(), {
				fault = function()
					return if fail then "retry_exhausted" else nil
				end,
			})
			fail = true
			local uncertain = scene.repository.retire(scene.store, keyFor, witness(3))
			expect(uncertain.ok):toBe(false)
			expect(uncertain.reason):toBe("retry_exhausted")
			fail = false
			local count = scene.writes()
			local reconciled = scene.repository.retire(scene.store, keyFor, witness(3))
			assert(reconciled.ok)
			expect(scene.writes()):toBe(count)
			expect(scene.repository.acquire(scene.store, keyFor, "character", "a", "b", 0, 10).reason):toBe(
				"character_retired"
			)
			assert(scene.repository.restore(scene.store, keyFor, witness(3)).ok)
			assert(scene.repository.acquire(scene.store, keyFor, "character", "a", "b", 0, 10).ok)
		end)
		it("refuses malformed input before persistence and rejects forged readback", function()
			local scene = Scene.new(config())
			local called = 0
			local store: Atomic.Store = {
				update = function(_key: string, _transform: (unknown) -> unknown)
					called += 1
					return { ok = true, value = owned(), reason = nil }
				end,
			}
			expect(scene.repository.acquire(store, keyFor, "", "a", "b", 0, 10).reason):toBe("identity_invalid")
			expect(called):toBe(0)
			expect(scene.repository.retire(store, keyFor, witness(3)).reason):toBe("retirement_conflict")
			expect(called):toBe(1)
		end)
		it("uses only the final retry outcome and preserves foreign retirement ownership", function()
			local scene = Scene.new(config())
			local record = scene.record
			local first = assert((record.retire(nil, witness(3))))
			local foreign = assert((record.retire(nil, witness(4, "other"))))
			local store: Atomic.Store = {
				update = function(_key: string, transform: (unknown) -> unknown)
					transform(first)
					local final = transform(foreign)
					return { ok = true, value = final, reason = nil }
				end,
			}
			expect(scene.repository.retire(store, keyFor, witness(3)).reason):toBe("stale_fence")
			expect(assert(record.retirementOf(foreign)).operationId):toBe("other")
		end)
	end)
end
