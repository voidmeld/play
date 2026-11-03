--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Host = require("./leased-record-session")
local LeaseStores = require("../core/identity/character-lease-store")
local Leases = require("../core/identity/character-lease")
local Records = require("../core/persistence/record-store")
local Sessions = require("../core/persistence/profile-session")
local Value = require("../kernel/value")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Record = { bucket: string, owner: string, generation: number, content: number, tag: string }
local function copy(raw: unknown): (Record?, string?)
	if type(raw) ~= "table" or getmetatable(raw) ~= nil then
		return nil, "record_invalid"
	end
	local fields = assert(Value.raw(raw))
	if type(fields.bucket) ~= "string" or type(fields.owner) ~= "string" or type(fields.tag) ~= "string" then
		return nil, "record_invalid"
	end
	local revision = Value.whole(fields.generation, 0, 4)
	local content = Value.whole(fields.content, 0, 100)
	if revision == nil or content == nil then
		return nil, "record_invalid"
	end
	return { bucket = fields.bucket, owner = fields.owner, generation = revision, content = content, tag = fields.tag },
		nil
end
local records = Records.configure({
	copy = copy,
	empty = function(bucket: string, owner: string): (Record?, string?)
		return { bucket = bucket, owner = owner, generation = 0, content = 0, tag = "private" }, nil
	end,
	equal = function(a: Record, b: Record): boolean
		return a.bucket == b.bucket
			and a.owner == b.owner
			and a.generation == b.generation
			and a.content == b.content
			and a.tag == b.tag
	end,
	view = function(record: Record): Records.View
		return { partitionId = record.bucket, subjectId = record.owner, revision = record.generation }
	end,
	withRevision = function(record: Record, revision: number): Record
		local detached = assert(copy(record))
		detached.generation = revision
		return detached
	end,
	maxRevision = 4,
})
local leases = Leases.create({
	schemaVersion = 7,
	maxRevision = 100,
	maxTime = 10000,
	maxFence = 100,
	characterIdLimit = 32,
	zoneIdLimit = 32,
	sessionIdLimit = 32,
	acquisitionIdLimit = 32,
	operationIdLimit = 32,
	fingerprintLimit = 64,
	migrate = function(raw: unknown): unknown
		return raw
	end,
})
local leaseStore = LeaseStores.create({ record = leases, identityLimit = 32, zoneIdLimit = 32 })
local session = Sessions.create({
	leaseSeconds = 20,
	renewBeforeSeconds = 5,
	coalesceSeconds = 2,
	shutdownSeconds = 5,
	ordinaryReason = "ordinary",
	immediateReasons = { payload = true },
})
local host = Host.configure({
	leaseRecord = leases,
	leaseStore = leaseStore,
	session = session,
	records = records,
	copyRecord = copy,
	withPayload = function(record: Record, payload: unknown): (Record?, string?)
		local value = Value.whole(payload, 0, 100)
		if value == nil then
			return nil, "payload_invalid"
		end
		local detached = assert(copy(record))
		detached.content = value
		return detached, nil
	end,
	characterId = function(record: Record): string
		return record.owner
	end,
	leaseSeconds = 20,
	dirtyReason = "payload",
})
local function keyFor(partition: string, subject: string): string
	return partition .. ":" .. subject
end
local function leaseKey(subject: string): string
	return "lease:" .. subject
end
local function rig()
	local values: { [string]: unknown } = {}
	local control = { now = 0, failure = "", delay = "", delaySeconds = 0, retry = false, readback = false, writes = 0 }
	local store: Records.Store = {
		get = function(key: string): Records.StoreOutcome
			if key == control.failure then
				return { ok = false, reason = "offline" }
			end
			return { ok = true, value = values[key] }
		end,
		updateOutcome = function(key: string, transform: (unknown) -> unknown): Records.StoreOutcome
			control.writes += 1
			if key == control.failure then
				return { ok = false, reason = "offline" }
			end
			local nextValue = transform(values[key])
			if control.retry then
				control.retry = false
				local rival = assert(copy(nextValue))
				rival.tag = "rival"
				values[key] = rival
				nextValue = transform(rival)
			end
			if key == control.delay then
				control.now += control.delaySeconds
			end
			if nextValue == nil then
				return { ok = false, reason = "callback_cancelled" }
			end
			values[key] = nextValue
			return { ok = true, value = if control.readback then nil else nextValue }
		end,
	}
	local deps: Host.Dependencies = {
		store = store,
		leaseKeyFor = leaseKey,
		zoneKeyFor = keyFor,
		leaseZoneFamily = { "sector" },
		clock = function(): number
			return control.now
		end,
	}
	return deps, values, control
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("leased record sessions", function()
		it("saves a projected payload without losing opaque fields or mutating the read snapshot", function()
			local deps, values = rig()
			local opened = host.acquireAndHydrate(deps, "sector", "subject", "session", "attempt")
			assert(opened.ok)
			expect(opened.zoneSnapshot.found):toBe(false)
			local saved = host.savePayload(deps, opened.session, opened.lease, opened.zoneSnapshot, 9)
			assert(saved.ok)
			expect(saved.zoneSnapshot.value.content):toBe(9)
			expect(saved.zoneSnapshot.value.tag):toBe("private")
			expect(saved.zoneSnapshot.value.generation):toBe(1)
			expect(opened.zoneSnapshot.value.generation):toBe(0)
			expect(assert(copy(values["sector:subject"])).content):toBe(9)
			expect(opened.session.dirty):toBe(false)
		end)
		it("distinguishes read failure, wrong identity and exact snapshot conflicts", function()
			local deps, values, control = rig()
			control.failure = "sector:subject"
			local failed = records.read(deps.store, keyFor, "sector", "subject")
			expect(failed.ok):toBe(false)
			expect(failed.found):toBe(nil)
			control.failure = ""
			local initial = records.read(deps.store, keyFor, "sector", "subject")
			assert(initial.ok)
			values["sector:subject"] =
				{ bucket = "sector", owner = "other", generation = 0, content = 0, tag = "private" }
			expect(records.read(deps.store, keyFor, "sector", "subject").reason):toBe("identity_mismatch")
			expect(records.update(deps.store, keyFor, initial, initial.value).reason):toBe("readback_conflict")
		end)
		it("rejects final callback retry conflicts and uncertain readbacks", function()
			local deps, values, control = rig()
			local initial = records.read(deps.store, keyFor, "sector", "subject")
			assert(initial.ok)
			control.retry = true
			expect(records.update(deps.store, keyFor, initial, initial.value).reason):toBe("readback_conflict")
			expect(assert(copy(values["sector:subject"])).tag):toBe("rival")
			local current = records.read(deps.store, keyFor, "sector", "subject")
			assert(current.ok)
			control.readback = true
			expect(records.update(deps.store, keyFor, current, current.value).reason):toBe("readback_conflict")
		end)
		it("refuses malformed snapshots, mismatched expected versions and bounded revisions", function()
			local deps = rig()
			local initial = records.read(deps.store, keyFor, "sector", "subject")
			assert(initial.ok)
			expect(records.update(deps.store, keyFor, {}, initial.value).reason):toBe("snapshot_invalid")
			local other = assert(copy(initial.value))
			other.generation = 1
			expect(records.update(deps.store, keyFor, initial, other).reason):toBe("expected_mismatch")
			other.generation = 4
			expect(records.update(deps.store, keyFor, initial, other).reason):toBe("revision_max")
		end)
		it("releases an acquired lease when hydration fails", function()
			local deps, values, control = rig()
			control.failure = "sector:subject"
			local opened = host.acquireAndHydrate(deps, "sector", "subject", "session", "attempt")
			expect(opened.ok):toBe(false)
			expect(opened.reason):toBe("offline")
			expect(opened.releaseReason):toBe(nil)
			expect(assert(leases.copy(values["lease:subject"])).sessionId):toBe(nil)
		end)
		it("fences a prior partition before returning takeover hydration", function()
			local deps, values, control = rig()
			assert(host.acquireAndHydrate(deps, "sector", "subject", "old", "old-attempt").ok)
			control.now = 21
			local opened = host.acquireAndHydrate(deps, "next", "subject", "new", "new-attempt")
			assert(opened.ok)
			expect(assert(copy(values["sector:subject"])).generation):toBe(1)
			expect(opened.zoneSnapshot.value.bucket):toBe("next")
		end)
		for _, boundary in { "lease:subject", "sector:subject" } do
			it("retains a dirty fenced session after a lease-length delay at " .. boundary, function()
				local deps, _, control = rig()
				local opened = host.acquireAndHydrate(deps, "sector", "subject", "session", "attempt")
				assert(opened.ok)
				control.now = 1
				control.delay = boundary
				control.delaySeconds = 20
				local result = host.savePayload(deps, opened.session, opened.lease, opened.zoneSnapshot, 9)
				expect(result.ok):toBe(false)
				expect(result.reason):toBe("lease_lost")
				expect(opened.session.dirty):toBe(true)
				expect(opened.session.leaseLost):toBe(true)
			end)
		end
		it("retains the renewed lease and dirty state when game payload validation fails", function()
			local deps = rig()
			local opened = host.acquireAndHydrate(deps, "sector", "subject", "session", "attempt")
			assert(opened.ok)
			local result = host.savePayload(deps, opened.session, opened.lease, opened.zoneSnapshot, -1)
			expect(result.ok):toBe(false)
			expect(result.reason):toBe("payload_invalid")
			expect(result.lease ~= nil):toBe(true)
			expect(opened.session.dirty):toBe(true)
		end)
	end)
end
