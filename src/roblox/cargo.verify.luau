--!strict
local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Cargo = require("./cargo")
local CargoRules = require("../core/inventory/cargo")
local Ledger = require("./material-ledger")
local LedgerRules = require("../core/ledger/ledger")
local Value = require("../core/internal/value")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Control = { failKey: string, replyKey: string, reply: unknown, retryKey: string }
local ledger = Ledger.configure({
	core = LedgerRules.ledger({ maxText = 32, maxCount = 100, maxAt = 1000, minGroupSize = 2, maxGroupSize = 4 }),
	schemaVersion = 7,
	windowLimit = 2,
	maxText = 32,
	boundary = "fixture",
})
local realms = { north = true }
local cargo = Cargo.configure({
	core = CargoRules.create({
		maxText = 32,
		maxCount = 100,
		maxAt = 1000,
		ledgerEventKind = "grant",
		intentPrefix = "cargo",
		intentSeparator = ":",
	}),
	ledger = ledger,
	schemaVersion = 7,
	maxText = 32,
	maxAt = 1000,
	carriedSpaceKind = "risk",
	bankedSpaceKind = "safe",
	bankedSpaceReason = "already_banked",
	dropExpirySeconds = 3,
	realms = realms,
	boundary = "fixture",
})
local function keyForLedger(actor: string): string
	return "ledger:" .. actor
end
local function rig()
	local values: { [string]: unknown } = {}
	local control: Control = { failKey = "", replyKey = "", reply = nil, retryKey = "" }
	local store: Ledger.Store = {
		update = function(key: string, transform: (unknown) -> unknown): Ledger.StoreOutcome
			if key == control.failKey then
				return { ok = false, value = nil, reason = "offline" }
			end
			local nextValue = transform(values[key])
			if key == control.retryKey then
				control.retryKey = ""
				values[key] = {}
				nextValue = transform(values[key])
			end
			if nextValue == nil then
				return { ok = false, value = nil, reason = "callback_cancelled" }
			end
			values[key] = nextValue
			return { ok = true, value = if key == control.replyKey then control.reply else nextValue }
		end,
	}
	local mounted = cargo.mount({
		loadCamps = function(): unknown
			return { { campId = "alpha", realmId = "north", center = { x = 0, y = 0, z = 0 }, radiusStuds = 2 } }
		end,
		store = store,
		keyForHaul = function(zone: string): string
			return "cargo:" .. zone
		end,
		keyForLedger = keyForLedger,
	})
	assert(mounted.ok)
	local service = assert(mounted.service)
	local function carry(id: string, material: string, count: number, now: number): Cargo.Outcome
		return service.carry({
			zoneId = "sector",
			nowSec = now,
			claimId = id,
			actorId = "one",
			materialId = material,
			count = count,
			spaceKind = "risk",
		})
	end
	local function extract(actor: string, now: number): Cargo.Outcome
		return service.extract({
			zoneId = "sector",
			nowSec = now,
			extractionId = "settle",
			actorId = actor,
			realmId = "north",
			campId = "alpha",
			position = { x = 2, y = 0, z = 0 },
		})
	end
	return { values = values, control = control, store = store, service = service, carry = carry, extract = extract }
end
local function event(id: string, count: number, at: number): LedgerRules.Event
	return { eventId = id, kind = "grant", materialId = "ore", count = count, actorId = "one", at = at }
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("configured durable cargo and material ledger", function()
		it("conserves multiple materials through drop recovery and one ledger extraction", function()
			local r = rig()
			assert(r.carry("first", "ore", 3, 1).ok)
			assert(r.carry("second", "fiber", 4, 2).ok)
			assert(r.service.release({
				zoneId = "sector",
				nowSec = 3,
				dropId = "drop",
				actorId = "one",
				cause = "disconnect",
			}).ok)
			assert(r.service.recover({ zoneId = "sector", nowSec = 4, dropId = "drop", actorId = "two" }).ok)
			local settled = r.extract("two", 5)
			expect(settled.ok):toBe(true)
			expect(settled.bankedCount):toBe(7)
			local snapshot = ledger.snapshot(r.store, keyForLedger, "two")
			assert(snapshot.ok)
			expect(snapshot.value.balances.two.ore):toBe(3)
			expect(snapshot.value.balances.two.fiber):toBe(4)
			expect(snapshot.value.boundary):toBe("fixture")
		end)
		it("heals a torn cargo-to-ledger settlement without minting a second grant", function()
			local r = rig()
			assert(r.carry("first", "ore", 3, 1).ok)
			r.control.failKey = "ledger:one"
			expect(r.extract("one", 2).ok):toBe(false)
			r.control.failKey = ""
			expect(r.extract("one", 2).ok):toBe(true)
			expect(r.extract("one", 2).ledgerReplayed):toBe(true)
			local snapshot = ledger.snapshot(r.store, keyForLedger, "one")
			assert(snapshot.ok)
			expect(snapshot.value.eventCount):toBe(1)
			expect(snapshot.value.balances.one.ore):toBe(3)
		end)
		it("uses configured spaces, realm custody, radius boundary and drop lifetime", function()
			local r = rig()
			expect(r.service.carry({
				zoneId = "sector",
				nowSec = 1,
				claimId = "safe",
				actorId = "one",
				materialId = "ore",
				count = 1,
				spaceKind = "safe",
			}).reason):toBe("already_banked")
			local foreign = r.service.admitsExtraction("alpha", "south", { x = 0, y = 0, z = 0 })
			local boundary = r.service.admitsExtraction("alpha", "north", { x = 2, y = 0, z = 0 })
			local outside = r.service.admitsExtraction("alpha", "north", { x = 2.01, y = 0, z = 0 })
			expect(foreign):toBe(false)
			expect(boundary):toBe(true)
			expect(outside):toBe(false)
			assert(r.carry("first", "ore", 3, 1).ok)
			assert(r.service.release({
				zoneId = "sector",
				nowSec = 2,
				dropId = "drop",
				actorId = "one",
				cause = "disconnect",
			}).ok)
			local expired = r.service.expire({ zoneId = "sector", nowSec = 5, dropId = "drop" })
			expect(expired.ok):toBe(true)
			expect(expired.expiredCount):toBe(3)
		end)
		it("refuses replay outside a configured receipt window and acknowledges a retained replay", function()
			local r = rig()
			for index = 1, 3 do
				assert(ledger.append(r.store, keyForLedger, "one", event("event" .. index, 1, index)).ok)
			end
			local old = ledger.append(r.store, keyForLedger, "one", event("event1", 1, 1))
			expect(old.ok):toBe(false)
			expect(old.reason):toBe("replay_unverifiable")
			local replay = ledger.append(r.store, keyForLedger, "one", event("event3", 1, 3))
			assert(replay.ok)
			expect(replay.value.replayed):toBe(true)
		end)
		it("discards speculative callback results when the final transform refuses", function()
			local r = rig()
			r.control.retryKey = "ledger:one"
			expect(ledger.append(r.store, keyForLedger, "one", event("first", 1, 1)).ok):toBe(false)
			r.control.retryKey = "cargo:sector"
			expect(r.carry("first", "ore", 1, 1).ok):toBe(false)
		end)
		it("refuses a valid but different ledger readback with the same receipt identity", function()
			local r = rig()
			r.control.replyKey = "ledger:one"
			r.control.reply = {
				schemaVersion = 7,
				events = { event("first", 2, 1) },
				recentEventIds = { "first" },
				windowFloorAt = -1,
			}
			local result = ledger.append(r.store, keyForLedger, "one", event("first", 1, 1))
			expect(result.ok):toBe(false)
			expect(result.reason):toBe("readback_mismatch")
		end)
		it("refuses a valid stale cargo readback and permits receipt-based reconciliation", function()
			local r = rig()
			assert(r.carry("first", "ore", 1, 1).ok)
			r.control.reply = r.values["cargo:sector"]
			r.control.replyKey = "cargo:sector"
			local result = r.carry("second", "fiber", 2, 2)
			expect(result.ok):toBe(false)
			expect(result.reason):toBe("readback_mismatch")
			r.control.replyKey = ""
			expect(r.carry("second", "fiber", 2, 2).replayed):toBe(true)
		end)
		it("refuses a divergent outer ledger readback and reconciles the committed grant", function()
			local r = rig()
			assert(r.carry("first", "ore", 3, 1).ok)
			r.control.replyKey = "ledger:one"
			r.control.reply = { schemaVersion = 7, events = {}, recentEventIds = {}, windowFloorAt = -1 }
			local result = r.extract("one", 2)
			expect(result.ok):toBe(false)
			expect(result.reason):toBe("readback_mismatch")
			r.control.replyKey = ""
			expect(r.extract("one", 2).ledgerReplayed):toBe(true)
			local snapshot = ledger.snapshot(r.store, keyForLedger, "one")
			assert(snapshot.ok)
			expect(snapshot.value.balances.one.ore):toBe(3)
		end)
		it("copies configured realm membership and rejects malformed mount sources", function()
			realms.north = false
			expect(cargo.REALMS.north):toBe(true)
			expect(cargo.mount(nil).ok):toBe(false)
			expect(cargo.mountFromContent(nil).reason):toBe("sources_malformed")
			local r = rig()
			local read = r.service.read("sector", "one", 0)
			expect(read.ok):toBe(true)
			expect(read.found):toBe(false)
			expect(Value.raw(r.values["cargo:sector"])):toBe(nil)
		end)
	end)
end
