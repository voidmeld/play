--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Clock = require("../test-scene/clock")
local Owner = require("../test-scene/owner")
local Sessions = require("./profile-sessions")
local Transaction = require("./profile-transaction")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Profile = { revision: number, balance: number, note: string }
local function equal(a: Profile, b: Profile): boolean
	return a.revision == b.revision and a.balance == b.balance and a.note == b.note
end
local function change(p: Profile): (Profile?, string?)
	p.revision += 1
	p.balance += 2
	return p, nil
end
local function fixture()
	local clock = Clock.new()
	local state = {
		live = { revision = 0, balance = 0, note = "a" },
		stored = { revision = 0, balance = 0, note = "a" },
		failSave = false,
		throwSave = false,
		throwRead = false,
		writeBeforeFailure = false,
		duringSave = function() end,
		duringRead = function() end,
	}
	local sessions = Sessions.new(Owner.new(), {
		clock = clock.clock,
		schedule = clock.schedule,
		report = function(_kind: string, _key: string, _reason: string?) end,
		renewalDelay = 5,
		retryDelay = 1,
		drainBudget = 3,
		jitter = function(): number
			return 0
		end,
		jitterFraction = 0,
		keyFor = function(key: string): string
			return key
		end,
		same = function(a: string, b: string): boolean
			return a == b
		end,
		write = function(
			p: Profile,
			_context: string,
			expiry: number,
			current: () -> boolean,
			_release: boolean,
			_generation: number
		): Sessions.Outcome
			assert(current())
			if not state.failSave or state.writeBeforeFailure then
				state.stored = table.clone(p)
			end
			state.duringSave()
			if state.throwSave then
				error("unavailable")
			end
			return if state.failSave then { ok = false, reason = "offline" } else { ok = true, expiresAt = expiry + 10 }
		end,
	})
	sessions.admit("profile", 10, function(): Profile?
		return state.live
	end, function() end)
	local service = Transaction.new({
		sessions = sessions,
		keyFor = function(key: string): string
			return key
		end,
		live = function(_key: string): Profile?
			return state.live
		end,
		replace = function(key: string, expected: Profile, candidate: Profile): boolean
			if not sessions.isAdmitted(key) or not equal(state.live, expected) then
				return false
			end
			state.live = candidate
			return true
		end,
		readback = function(_key: string): (Profile?, string?)
			state.duringRead()
			if state.throwRead then
				error("unavailable")
			end
			return table.clone(state.stored), nil
		end,
		copy = function(p: Profile): Profile
			return table.clone(p)
		end,
		equal = equal,
		verify = function(expected: Profile, observed: Profile): boolean
			return expected.revision == observed.revision and expected.balance == observed.balance
		end,
	})
	return { state = state, sessions = sessions, service = service }
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("durable profile transaction", function()
		it("commits through admitted sessions and verifies expected fields after readback", function()
			local f = fixture()
			local source = f.state.live
			expect(f.service.commit("profile", change).outcome):toBe("committed")
			expect(f.state.live.balance):toBe(2)
			expect(f.state.stored.revision):toBe(1)
			expect(source.balance):toBe(0)
		end)
		it("refuses unadmitted and rejected changes and recovers from confirmed save refusal", function()
			local f = fixture()
			expect(f.service.commit("absent", change).outcome):toBe("rejected")
			expect(f.service.commit("profile", function(p: Profile): (Profile?, string?)
				p.balance = 90
				return nil, "capacity"
			end).reason):toBe("capacity")
			expect(f.state.live.balance):toBe(0)
			f.state.failSave = true
			local result = f.service.commit("profile", change)
			expect(result.outcome):toBe("rolled_back")
			expect(result.restoration):toBe("restored")
			expect(f.state.live.revision):toBe(0)
			f.state.failSave = false
			expect(f.service.commit("profile", change).outcome):toBe("committed")
		end)
		it("reports uncertainty when storage may contain the candidate or cannot be read", function()
			local f = fixture()
			f.state.failSave, f.state.writeBeforeFailure = true, true
			local uncertain = f.service.commit("profile", change)
			expect(uncertain.outcome):toBe("ambiguous")
			expect(uncertain.restoration):toBe("restored")
			expect(f.state.live.balance):toBe(0)
			expect(f.state.stored.balance):toBe(2)
			f.state.throwRead, f.state.failSave = true, false
			expect(f.service.commit("profile", change).outcome):toBe("ambiguous")
		end)
		it("preserves interleaved live edits and session replacement during save or readback", function()
			for _, phase in { "save", "read" } do
				local f = fixture()
				f.state.failSave = true
				local function edit()
					f.state.live.note = "new"
				end
				if phase == "save" then
					f.state.duringSave = edit
				else
					f.state.duringRead = edit
				end
				local result = f.service.commit("profile", change)
				expect(result.outcome):toBe("ambiguous")
				expect(result.restoration):toBe("superseded")
				expect(f.state.live.note):toBe("new")
				expect(f.state.live.balance):toBe(2)
			end
			local f = fixture()
			f.state.duringRead = f.sessions.dispose
			expect(f.service.commit("profile", change).reason):toBe("session_replaced")
			expect(f.state.live.balance):toBe(2)
		end)
		it("fences change-time interleavings and releases exclusion after exceptions", function()
			local f = fixture()
			local result = f.service.commit("profile", function(p: Profile): (Profile?, string?)
				f.state.live.balance = 7
				return change(p)
			end)
			expect(result.reason):toBe("live_changed")
			expect(f.state.live.balance):toBe(7)
			f.state.duringSave = function()
				expect(f.service.commit("profile", change).reason):toBe("transaction_busy")
			end
			f.state.throwSave = true
			expect(f.service.commit("profile", change).outcome):toBe("ambiguous")
			f.state.throwSave = false
			f.state.duringSave = function() end
			expect(f.service.commit("profile", change).outcome):toBe("committed")
		end)
	end)
end
