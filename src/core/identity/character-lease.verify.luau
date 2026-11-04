--!strict

local Atomic = require("./character-lease-store")
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Lease = require("./character-lease")
local Result = require("../../kernel/result")
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

local function unexpectedRead(): Result.Result<unknown>
	error("unexpected readback")
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("character lease custody", function()
		local record = Lease.create(config())
		it("confirms absent restoration without a write and preserves read refusals", function()
			local scene = Scene.new(config())
			local restored = scene.repository.restore(scene.store, keyFor, witness(1))
			assert(restored.ok)
			expect(restored.value.retirement):toBe(false)
			expect(restored.value.sessionId):toBeNil()
			expect(scene.writes()):toBe(0)
			expect(Result.unwrap(scene.store.read(keyFor("character")))):toBeNil()
			local refused = scene.repository.restore({
				read = function()
					return Result.fail("read_unavailable")
				end,
				update = scene.store.update,
			}, keyFor, witness(1))
			expect(refused.ok):toBe(false)
			expect(refused.reason):toBe("read_unavailable")
			expect(scene.writes()):toBe(0)
		end)
		it("refuses absent restoration when the uncached read finds a concurrent retirement", function()
			local scene = Scene.new(config())
			local foreign = assert((scene.record.retire(nil, witness(2, "other"))))
			local restored = scene.repository.restore({
				read = function(key)
					scene.seed(key, foreign)
					return scene.store.read(key)
				end,
				update = scene.store.update,
			}, keyFor, witness(1))
			expect(restored.ok):toBe(false)
			expect(restored.reason):toBe("readback_mismatch")
			expect(scene.writes()):toBe(1)
			expect(Result.unwrap(scene.store.read(keyFor("character")))):toEqual(foreign)
		end)
		it("refuses acquisition when a canceled retry has no durable lease", function()
			local scene = Scene.new(config(), { rerun = true })
			local acquired =
				scene.repository.acquire(scene.store, keyFor, "character", "session", "acquisition", 100, 180)
			expect(acquired.ok):toBe(false)
			expect(acquired.reason):toBe("readback_mismatch")
			expect(scene.writes()):toBe(0)
			expect(Result.unwrap(scene.store.read(keyFor("character")))):toBeNil()
		end)
		it("refuses retirement when a canceled retry has not stored the witness", function()
			local scene = Scene.new(config(), { rerun = true })
			scene.seed(keyFor("character"), assert((scene.record.create("character"))))
			local retired = scene.repository.retire(scene.store, keyFor, witness(1))
			expect(retired.ok):toBe(false)
			expect(retired.reason):toBe("readback_mismatch")
			expect(scene.writes()):toBe(1)
			local stored = assert((scene.record.copy(Result.unwrap(scene.store.read(keyFor("character"))))))
			expect(stored.retirement):toBe(false)
		end)
		it("retains a read refusal when an observed acquisition replay cannot be confirmed", function()
			local scene = Scene.new(config())
			scene.seed(keyFor("character"), owned())
			local acquired = scene.repository.acquire({
				read = function()
					return Result.fail("read_unavailable")
				end,
				update = scene.store.update,
			}, keyFor, "character", "session", "acquisition", 100, 180)
			expect(acquired.ok):toBe(false)
			expect(acquired.reason):toBe("read_unavailable")
			expect(scene.writes()):toBe(1)
		end)
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
		it("rejects unknown fields, empty owners and inconsistent unowned expiry", function()
			for _, patch in
				{
					{ future = true },
					{ sessionId = "" },
					{ acquisitionId = "" },
					{ zoneId = "" },
				}
			do
				local raw = assert(Value.raw(owned()))
				for field, value in patch do
					raw[field] = value
				end
				expect((record.copy(raw))):toBeNil()
			end
			local unowned = assert((record.create("character")))
			unowned.expiresAt = 1
			expect((record.copy(unowned))):toBeNil()
			for _, time in { math.huge, -math.huge, math.nan, -1, 10001 } do
				local invalid = owned()
				invalid.expiresAt = time
				expect((record.copy(invalid))):toBeNil()
			end
		end)
		it("rejects incomplete, malformed and foreign fields in both stored receipt slots", function()
			local receipts = {
				{
					field = "arrival",
					value = { sessionId = "session", acquisitionId = "acquisition", fence = 1, arrivedAtUnix = 0 },
				},
				{
					field = "retirement",
					value = { operationId = "operation", fingerprint = "fingerprint", fence = 1, retiredAtUnix = 0 },
				},
			}
			for _, receipt in receipts do
				for field, value in receipt.value do
					for _, mode in { "missing", "invalid" } do
						local payload = assert(Value.raw(receipt.value))
						payload[field] = if mode == "missing" then nil elseif type(value) == "string" then "" else -1
						local source = assert(Value.raw(owned()))
						source[receipt.field] = payload
						expect(select(2, record.copy(source))):toBe(receipt.field .. "_invalid")
					end
				end
				for _, fence in { 0, 1.5, 101 } do
					local payload = assert(Value.raw(receipt.value))
					payload.fence = fence
					local source = assert(Value.raw(owned()))
					source[receipt.field] = payload
					expect(select(2, record.copy(source))):toBe(receipt.field .. "_invalid")
				end
				local payload = assert(Value.raw(receipt.value))
				payload.extra = true
				local source = assert(Value.raw(owned()))
				source[receipt.field] = payload
				expect(select(2, record.copy(source))):toBe(receipt.field .. "_invalid")
			end
		end)
		it("validates every witness and claim field before any transition", function()
			for _, request in
				{
					{ value = assert(Value.raw(witness(3))), reason = "witness_invalid", run = record.retire },
					{ value = assert(Value.raw(claim(3))), reason = "claim_invalid", run = record.arrive },
				}
			do
				for field, value in request.value do
					for _, mode in { "missing", "invalid" } do
						local raw = table.clone(request.value)
						raw[field] = if mode == "missing" then nil elseif type(value) == "string" then "" else -1
						expect(select(2, request.run(owned(), raw))):toBe(request.reason)
						if request.reason == "witness_invalid" then
							expect(select(2, record.restore(owned(), raw))):toBe(request.reason)
						end
					end
				end
				for _, fence in { 0, 1.5, 101 } do
					local raw = table.clone(request.value)
					raw.fence = fence
					expect(select(2, request.run(owned(), raw))):toBe(request.reason)
				end
				local extra = table.clone(request.value)
				extra.routeId = "route"
				expect(select(2, request.run(owned(), extra))):toBe(request.reason)
			end
			local empty = assert(Value.raw(claim(3)))
			empty.revision = 0
			expect(select(2, record.arrive(owned(), empty))):toBe("claim_invalid")
			local missing = assert(Value.raw(owned()))
			missing.retirement = nil
			expect(select(2, record.retire(missing, witness(3)))):toBe("retirement_absent")
			missing = assert(Value.raw(owned()))
			missing.arrival = nil
			expect(select(2, record.arrive(missing, claim(3)))):toBe("arrival_absent")
		end)
		it("retires absent records and replays restoration without inventing ownership", function()
			local retired = assert((record.retire(nil, witness(3))))
			expect(retired.revision):toBe(0)
			expect(retired.sessionId):toBeNil()
			expect(assert(record.retirementOf(retired)).retiredAtUnix):toBe(900)
			local restored, status = record.restore(owned(), witness(3))
			expect(status):toBe("replayed")
			expect(record.equal(restored, owned())):toBe(true)
			local foreign = owned()
			foreign.characterId = "other"
			expect(select(2, record.retire(foreign, witness(3)))):toBe("identity_mismatch")
			expect(select(2, record.restore(foreign, witness(3)))):toBe("identity_mismatch")
			expect(record.retired(nil)):toBe(false)
		end)
		it("compares only complete valid records including zone and receipt contents", function()
			local source = owned()
			local changed = owned()
			changed.zoneId = "zone"
			expect(record.equal(source, changed)):toBe(false)
			changed = owned()
			changed.expiresAt += 1
			expect(record.equal(source, changed)):toBe(false)
			expect(record.equal(source, { schemaVersion = 7 })):toBe(false)
			local first = assert((record.retire(source, witness(2))))
			local second = assert((record.retire(source, witness(3))))
			expect(record.equal(first, second)):toBe(false)
			expect(record.equal(source, first)):toBe(false)
		end)
		it("fences retirement ownership, receipt conflicts and restoration without touching the lease", function()
			local source = owned()
			local retired, status = record.retire(source, witness(3))
			assert(retired ~= nil)
			expect(status):toBe("retired")
			expect(retired.sessionId):toBe(source.sessionId)
			expect(source.retirement):toBe(false)
			expect(select(2, record.retire(retired, witness(3)))):toBe("replayed")
			local replay = assert((record.retire(retired, witness(3))))
			expect(record.equal(replay, retired)):toBe(true)
			expect(replay).never:toBe(retired)
			expect(select(2, record.retire(retired, witness(2)))):toBe("stale_fence")
			expect(select(2, record.retire(retired, witness(3, "foreign")))):toBe("stale_fence")
			expect(select(2, record.restore(retired, witness(4, "foreign")))):toBe("retirement_not_owned")
			local conflict = witness(3)
			conflict.fingerprint = "different"
			expect(select(2, record.retire(retired, conflict))):toBe("receipt_conflict")
			expect(select(2, record.restore(retired, conflict))):toBe("receipt_conflict")
			local originalOwner = assert((record.copy(retired)))
			originalOwner.retirement = false
			expect(record.equal(originalOwner, source)):toBe(true)
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
			local mark = assert(record.arrivalOf(arrived))
			expect(mark):toEqual({
				sessionId = "session",
				acquisitionId = "acquisition",
				fence = 3,
				arrivedAtUnix = 900,
			})
			expect(arrived.revision):toBe(4)
			expect(arrived.expiresAt):toBe(280)
			expect(select(2, record.arrive(arrived, claim(3)))):toBe("replayed")
			expect(select(2, record.arrive(arrived, claim(2)))):toBe("stale_fence")
			expect(select(2, record.arrive(owned(), claim(4)))):toBe("fence_unacquired")
			expect(select(2, record.arrive(owned(), claim(5)))):toBe("fence_unacquired")
			local foreign = claim(3)
			foreign.sessionId = "foreign"
			expect(select(2, record.arrive(arrived, foreign))):toBe("lease_not_owned")
			local retired = assert((record.retire(owned(), witness(3))))
			expect(select(2, record.arrive(retired, claim(3)))):toBe("character_retired")
		end)
		it("refuses every foreign holder and admits only a later acquired departure after handoff", function()
			for _, field in { "sessionId", "acquisitionId", "revision", "characterId" } do
				local foreign = assert(Value.raw(claim(3)))
				foreign[field] = if field == "revision" then 5 else "other"
				expect(select(2, record.arrive(owned(), foreign))):toBe(
					if field == "characterId" then "identity_mismatch" else "lease_not_owned"
				)
			end
			expect(select(2, record.arrive(nil, claim(3)))):toBe("lease_not_owned")
			local first = assert((record.arrive(owned(), claim(3))))
			local nextOwner = assert((record.copy(first)))
			nextOwner.revision, nextOwner.sessionId, nextOwner.acquisitionId = 9, "next", "next-acquisition"
			local nextClaim: Lease.Claim = {
				characterId = "character",
				sessionId = "next",
				acquisitionId = "next-acquisition",
				revision = 9,
				fence = 3,
				atUnix = 901,
			}
			expect(select(2, record.arrive(nextOwner, nextClaim))):toBe("stale_fence")
			nextClaim.fence = 2
			expect(select(2, record.arrive(nextOwner, nextClaim))):toBe("stale_fence")
			nextClaim.fence = 7
			local advanced = assert((record.arrive(nextOwner, nextClaim)))
			expect(assert(record.arrivalOf(advanced)).fence):toBe(7)
			expect(assert(record.arrivalOf(first)).fence):toBe(3)
			local replay, status = record.arrive(advanced, nextClaim)
			expect(status):toBe("replayed")
			expect(record.equal(replay, advanced)):toBe(true)
			expect(replay).never:toBe(advanced)
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
				read = unexpectedRead,
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
				read = unexpectedRead,
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
