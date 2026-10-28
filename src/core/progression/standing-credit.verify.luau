--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Credit = require("./standing-credit")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local function fixture()
	local state = { now = 0, authority = true, ready = true, totals = {} :: { [string]: number } }
	local delivery = Credit.create({
		clock = function()
			return state.now
		end,
		intervalSec = 2,
		maxPoints = 100,
		capacity = 2,
		authority = function()
			return state.authority
		end,
		writeReady = function()
			return state.ready
		end,
		read = function()
			return state.totals
		end,
		validId = function(id)
			return #id > 0 and #id <= 80
		end,
	})
	local function commit(totals: { [string]: number }): Credit.Outcome
		state.totals = totals
		return { ok = true }
	end
	return state, delivery, commit
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("Standing credit delivery", function()
		it("retains accrual during a yielding write and removes only its captured credit", function()
			local state, delivery, commit = fixture()
			expect(delivery.accrue("a", 3)):toBe(true)
			local result = delivery.flush(true, false, function(totals)
				expect(delivery.accrue("a", 2)):toBe(true)
				expect(delivery.flush(true, false, commit).reason):toBe("write_in_flight")
				return commit(totals)
			end)
			expect(result.ok):toBe(true)
			expect(state.totals.a):toBe(3)
			expect(delivery.pending().a):toBe(2)
			expect(delivery.flush(true, false, commit).ok):toBe(true)
			expect(state.totals.a):toBe(5)
		end)
		it("defers budget failures, preserves pending amounts and fails closed on uncertain writes", function()
			local state, delivery, commit = fixture()
			delivery.accrue("a", 3)
			local deferred = delivery.flush(true, false, function()
				return { ok = false, reason = "budget_deferred" }
			end)
			expect(deferred.reason):toBe("budget_deferred")
			expect(delivery.pending().a):toBe(3)
			expect(delivery.authority()):toBe(true)
			local failed = delivery.flush(true, false, function()
				error("uncertain")
			end)
			expect(failed.ok):toBe(false)
			expect(delivery.authority()):toBe(false)
			expect(delivery.accrue("a", 1)):toBe(false)
			expect((next(state.totals))):toBeNil()
			expect(delivery.flush(true, false, commit).ok):toBe(false)
		end)
		it("reconciles offline readback before acknowledging a committed award", function()
			local state, delivery, commit = fixture()
			state.totals = { a = 8 }
			local bad = delivery.recoverNext(function()
				return { ok = true, characterId = "a", standing = 7 }
			end, function()
				return true
			end)
			expect(bad.reason):toBe("profile_recovery_readback_conflict")
			local recovered = delivery.recoverNext(function(id, total)
				return { ok = true, characterId = id, standing = total }
			end, function()
				return true
			end)
			expect(recovered.ok):toBe(true)
			expect(delivery.recoverNext(function()
				error("already acknowledged")
			end, function()
				return true
			end).idle):toBe(true)
			delivery.flush(true, false, commit)
			expect((next(state.totals))):toBeNil()
		end)
		it("honors saved floors, capacity, clock and authority fences", function()
			local state, delivery, commit = fixture()
			expect(delivery.seed("a", 10).ok):toBe(true)
			delivery.accrue("a", 3)
			delivery.accrue("b", 2)
			expect(delivery.accrue("c", 1)):toBe(false)
			expect(delivery.retire("a")):toBe(false)
			state.now = 2
			expect(delivery.flush(false, false, commit).ok):toBe(true)
			expect(state.totals.a):toBe(13)
			state.now = 1
			expect(delivery.flush(true, false, commit).reason):toBe("war_clock_invalid")
			expect(delivery.authority()):toBe(false)
		end)
	end)
end
