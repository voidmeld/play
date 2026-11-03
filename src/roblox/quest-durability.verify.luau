--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Host = require("./quest-durability")
local Journal = require("../core/quest/journal")
local LeaseStores = require("../core/identity/character-lease-store")
local Leases = require("../core/identity/character-lease")
local ProfileSessions = require("../core/persistence/profile-session")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Snapshot = { exists: boolean, generation: number, encoded: Host.Quests, private: string }
local lease = Leases.create({
	schemaVersion = 7,
	maxRevision = 10000,
	maxTime = 10000,
	maxFence = 10000,
	characterIdLimit = 64,
	zoneIdLimit = 64,
	sessionIdLimit = 64,
	acquisitionIdLimit = 64,
	operationIdLimit = 64,
	fingerprintLimit = 128,
	migrate = function(value: unknown): unknown
		return value
	end,
})
local leaseStore = LeaseStores.create({ record = lease, identityLimit = 64, zoneIdLimit = 64 })
local profiles = ProfileSessions.create({
	leaseSeconds = 20,
	renewBeforeSeconds = 5,
	coalesceSeconds = 2,
	shutdownSeconds = 5,
	ordinaryReason = "ordinary",
	immediateReasons = {},
})
local journal = Journal.journal({
	version = 7,
	maxIdLength = 32,
	maxCharacterIdLength = 64,
	maxEventIdLength = 32,
	maxEvents = 8,
	maxQuests = 16,
	maxCounts = 8,
	maxStep = 16,
	maxCount = 100,
	eventPrefix = "receipt:",
	statuses = { active = true, claimed = true },
	claimableStatuses = { active = true },
	receiptStatus = "claimed",
	eventIdAllowed = function(_id: string): boolean
		return true
	end,
})
local function rig()
	local raw: { [string]: unknown } = {}
	local snapshots: { [string]: Snapshot } = {}
	local pending: { () -> () } = {}
	local renewals: { () -> () } = {}
	local control = { clock = 0, failures = 0, saves = 0, diverge = false, reenter = false }
	local handle: Host.Handle? = nil
	local store: Host.OutcomeStore = {
		read = function(key: string): LeaseStores.StoreOutcome
			return { ok = true, value = raw[key] }
		end,
		update = function(key: string, transform: (unknown) -> unknown): LeaseStores.StoreOutcome
			local value = transform(raw[key])
			if value == nil then
				return { ok = false, value = nil, reason = "callback_cancelled" }
			end
			raw[key] = value
			return { ok = true, value = value }
		end,
	}
	local configured = Host.configure({
		journal = journal,
		copyLease = lease.copy,
		renew = leaseStore.renew,
		release = leaseStore.release,
		snapshot = function(snapshot: Snapshot): Host.SnapshotView
			return { found = snapshot.exists, revision = snapshot.generation, quests = snapshot.encoded }
		end,
		leaseSeconds = 20,
		renewSeconds = 5,
		retrySeconds = 1,
		defaultSaveDelay = 2,
		maxConsecutiveSaveFailures = 2,
		fenceLossReasons = { lease_stale = true, lease_lost = true, lease_expired = true },
		session = {
			acquireAndHydrate = function(
				deps: Host.SessionDependencies,
				zone: string,
				character: string,
				session: string,
				acquisition: string
			): Host.Acquisition<Snapshot>
				local acquired = leaseStore.acquire(
					deps.store,
					deps.leaseKeyFor,
					character,
					session,
					acquisition,
					deps.clock(),
					20,
					nil,
					nil,
					zone
				)
				if not acquired.ok then
					return { ok = false, reason = acquired.reason }
				end
				local state = assert(profiles.openAcquired(deps.clock(), acquired.value.expiresAt))
				local key = deps.zoneKeyFor(zone, character)
				local snapshot = snapshots[key] or { exists = false, generation = 0, encoded = {}, private = "opaque" }
				if control.diverge then
					snapshot = { exists = true, generation = snapshot.generation + 1, encoded = {}, private = "opaque" }
				end
				return { ok = true, session = state, lease = acquired.value, zoneSnapshot = snapshot }
			end,
			saveZoneQuests = function(
				deps: Host.SessionDependencies,
				_state: Host.SessionState,
				held: Host.Lease,
				snapshot: Snapshot,
				quests: Host.Quests
			): Host.SaveOutcome<Snapshot>
				if control.failures > 0 then
					control.failures -= 1
					return { ok = false, reason = "write_pending" }
				end
				local renewed = leaseStore.renew(
					deps.store,
					deps.leaseKeyFor,
					held.characterId,
					assert(held.sessionId),
					assert(held.acquisitionId),
					held.revision,
					deps.clock(),
					20
				)
				if not renewed.ok then
					return { ok = false, reason = renewed.reason }
				end
				if control.reenter then
					control.reenter = false
					assert(
						assert(handle).markDirty(
							held.characterId,
							assert(
								journal.create("zone", held.characterId, { later = { status = "active", step = 0 } })
							)
						)
					)
				end
				local nextSnapshot = {
					exists = true,
					generation = snapshot.generation + 1,
					encoded = quests,
					private = snapshot.private,
				}
				snapshots[deps.zoneKeyFor("zone", held.characterId)] = nextSnapshot
				control.saves += 1
				return { ok = true, lease = renewed.value, zoneSnapshot = nextSnapshot }
			end,
		},
	})
	handle = configured.new({
		store = store,
		leaseKeyFor = function(character: string): string
			return "lease:" .. character
		end,
		zoneKeyFor = function(zone: string, character: string): string
			return zone .. ":" .. character
		end,
		clock = function(): number
			return control.clock
		end,
		schedule = function(_delay: number, callback: () -> ())
			table.insert(pending, callback)
		end,
		scheduleLeaseRenewal = function(_delay: number, callback: () -> ())
			table.insert(renewals, callback)
		end,
	})
	local function record(character: string, id: string): Journal.Record
		return assert(journal.create("zone", character, { [id] = { status = "active", step = 0 } }))
	end
	return {
		handle = assert(handle),
		control = control,
		pending = pending,
		renewals = renewals,
		snapshots = snapshots,
		raw = raw,
		record = record,
	}
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("leased quest durability host", function()
		it("flushes a copied journal and releases only after pending work drains", function()
			local r = rig()
			assert(r.handle.attach("zone", "c", "session", "acquisition").ok)
			assert(r.handle.markDirty("c", r.record("c", "q")))
			expect(r.handle.detach("c").ok):toBe(true)
			expect(r.snapshots["zone:c"].encoded.q.status):toBe("active")
			expect(r.snapshots["zone:c"].private):toBe("opaque")
			expect(r.handle.isAttached("c")):toBe(false)
			expect(assert(lease.copy(r.raw["lease:c"])).sessionId):toBeNil()
		end)
		it("prepares a dirty batch atomically and rejects metatable payloads", function()
			local r = rig()
			assert(r.handle.attach("zone", "a", "session", "acquisition").ok)
			expect(r.handle.markDirtyBatch({
				{ characterId = "a", record = r.record("a", "q") },
				{ characterId = "b", record = r.record("b", "q") },
			})):toBe(false)
			expect(r.handle.flush("a").skipped):toBe(true)
			expect(r.control.saves):toBe(0)
			local wrapped = setmetatable({ quests = {} }, {})
			expect(r.handle.markDirty("a", wrapped)):toBe(false)
		end)
		it("stops admitting writes after repeated failures while retaining a drainable record", function()
			local r = rig()
			assert(r.handle.attach("zone", "c", "session", "acquisition").ok)
			assert(r.handle.markDirty("c", r.record("c", "q")))
			r.control.failures = 2
			expect(r.handle.flush("c").ok):toBe(false)
			expect(r.handle.flush("c").ok):toBe(false)
			expect(r.handle.phase("c")):toBe("stopping")
			expect(r.handle.markDirty("c", r.record("c", "later"))):toBe(false)
			expect(r.handle.detach("c").ok):toBe(true)
			expect(r.snapshots["zone:c"].encoded.q.status):toBe("active")
		end)
		it("does not let old save or retry callbacks flush a replacement attachment", function()
			local r = rig()
			assert(r.handle.attach("zone", "c", "session", "acquisition").ok)
			assert(r.handle.markDirty("c", r.record("c", "first")))
			local stale = assert(r.pending[1])
			r.control.failures = 1
			expect(r.handle.flush("c").ok):toBe(false)
			local staleRetry = assert(r.pending[2])
			assert(r.handle.detach("c").ok)
			assert(r.handle.attach("zone", "c", "other", "other-acquisition").ok)
			assert(r.handle.markDirty("c", r.record("c", "second")))
			local saves = r.control.saves
			stale()
			staleRetry()
			expect(r.control.saves):toBe(saves)
			expect(r.handle.flush("c").ok):toBe(true)
		end)
		it("retains updates accepted during an in-flight save", function()
			local r = rig()
			assert(r.handle.attach("zone", "c", "session", "acquisition").ok)
			assert(r.handle.markDirty("c", r.record("c", "first")))
			r.control.reenter = true
			assert(r.handle.flush("c").ok)
			expect(r.snapshots["zone:c"].encoded.first ~= nil):toBe(true)
			assert(r.handle.flush("c").ok)
			expect(r.snapshots["zone:c"].encoded.later ~= nil):toBe(true)
		end)
		it("renews ownership and fences reacquisition against a divergent snapshot", function()
			local r = rig()
			assert(r.handle.attach("zone", "c", "session", "acquisition").ok)
			r.control.clock = 5
			assert(r.renewals[1])()
			expect(assert(lease.copy(r.raw["lease:c"])).expiresAt):toBe(25)
			r.control.clock = 26
			r.control.diverge = true
			expect(r.handle.markDirty("c", r.record("c", "q"))):toBe(false)
			expect(r.handle.phase("c")):toBe("fenced")
		end)
	end)
end
