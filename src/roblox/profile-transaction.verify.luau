--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Engine = require("../../tools/fixtures/engine")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
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
	local environment = Roblox.testEnvironment({ handlerErrors = "raise" })
	local clock = Engine.clock(environment)
	local state = {
		live = { revision = 0, balance = 0, note = "a" },
		stored = { revision = 0, balance = 0, note = "a" },
		failSave = false,
		throwSave = false,
		throwRead = false,
		writeBeforeFailure = false,
		duringSave = function() end,
		duringRead = function() end,
		beforeRelease = function() end,
	}
	local sessions = Sessions.new(Engine.owner(environment), {
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
			release: boolean,
			_generation: number
		): Sessions.Outcome
			assert(current())
			local failed, threw = state.failSave, state.throwSave
			if release then
				state.beforeRelease()
			end
			if not failed or state.writeBeforeFailure then
				state.stored = table.clone(p)
			end
			state.duringSave()
			if threw then
				error("unavailable")
			end
			return if failed then { ok = false, reason = "offline" } else { ok = true, expiresAt = expiry + 10 }
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
	return { state = state, sessions = sessions, service = service, environment = environment, clock = clock }
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("durable profile transaction", function()
		it("retains uncertainty when a closing writer can commit after the old save is cancelled", function()
			local f = fixture()
			local held: thread? = nil
			local closed: Sessions.Outcome? = nil
			f.state.failSave = true
			f.state.beforeRelease = function()
				f.environment.scheduler.block(function(pending)
					held = pending
				end)
			end
			f.state.duringSave = function()
				f.state.duringSave = function() end
				f.state.failSave = false
				f.environment.scheduler.spawn(function()
					closed = f.sessions.unload("profile")
				end)
			end
			local result = f.service.commit("profile", change)
			expect(held == nil):toBe(false)
			expect(result.outcome):toBe("ambiguous")
			expect(result.reason):toBe("operation_cancelled")
			expect(result.restoration):toBe("superseded")
			expect(f.state.stored.balance):toBe(0)
			expect(f.state.live.balance):toBe(2)
			f.environment.scheduler.resume(assert(held))
			f.clock.advance(0)
			expect(assert(closed).ok):toBe(true)
			expect(f.state.stored.balance):toBe(2)
			expect(result.outcome):toBe("ambiguous")
			expect(f.environment.scheduler.failures):toEqual({})
			f.sessions.dispose()
		end)
		it("does not restore across a refused write fence even when logical custody remains", function()
			for _, reason in { "operation_cancelled", "not_admitted", "lock_lost" } do
				local f = fixture()
				f.sessions.save = function(_context: string): Sessions.Outcome
					return { ok = false, reason = reason }
				end
				local result = f.service.commit("profile", change)
				expect(result.outcome):toBe("ambiguous")
				expect(result.restoration):toBe("superseded")
				expect(result.reason):toBe(reason)
				expect(f.state.live.balance):toBe(2)
				f.sessions.dispose()
			end
		end)
		it("keeps a thrown save uncertain even when an immediate read sees the baseline", function()
			local f = fixture()
			f.state.failSave, f.state.throwSave = true, true
			local result = f.service.commit("profile", change)
			expect(result.outcome):toBe("ambiguous")
			expect(result.reason):toBe("save_failed")
			expect(result.restoration):toBe("restored")
			expect(f.state.live.balance):toBe(0)
			expect(f.state.stored.balance):toBe(0)
			f.sessions.dispose()
		end)
		it("finalizes an installed candidate using the caller baseline without reinstalling it", function()
			local f = fixture()
			local previous = table.clone(f.state.live)
			local candidate = { revision = 1, balance = 2, note = "a" }
			f.state.live = candidate
			f.state.duringSave = function()
				expect(f.state.live):toBe(candidate)
				expect(f.service.finalize("profile", previous, candidate).reason):toBe("transaction_busy")
				expect(f.service.commit("profile", change).reason):toBe("transaction_busy")
			end
			expect(f.service.finalize("profile", previous, candidate).outcome):toBe("committed")
			expect(previous.balance):toBe(0)
			expect(f.state.stored.balance):toBe(2)
		end)
		it("verifies installed state before saving and preserves a superseding candidate", function()
			local f = fixture()
			local previous = table.clone(f.state.live)
			local expected = { revision = 1, balance = 2, note = "a" }
			f.state.live = { revision = 2, balance = 4, note = "new" }
			local saves = 0
			f.state.duringSave = function()
				saves += 1
			end
			local result = f.service.finalize("profile", previous, expected)
			expect(result.reason):toBe("verification_failed")
			expect(result.restoration):toBe("superseded")
			expect(saves):toBe(0)
			expect(f.state.live.balance):toBe(4)
		end)
		it("restores before readback on refused or throwing finalize saves and retains uncertainty", function()
			for _, throws in { false, true } do
				local f = fixture()
				local previous = table.clone(f.state.live)
				f.state.live = { revision = 1, balance = 2, note = "a" }
				f.state.failSave, f.state.throwSave = true, throws
				f.state.writeBeforeFailure = true
				local reads = 0
				f.state.duringRead = function()
					reads += 1
				end
				local result = f.service.finalize("profile", previous, f.state.live)
				expect(result.outcome):toBe("ambiguous")
				expect(result.restoration):toBe("restored")
				expect(result.reason):toBe(if throws then "save_failed" else "offline")
				expect(reads):toBe(0)
				expect(f.state.live.balance):toBe(0)
				expect(f.state.stored.balance):toBe(2)
				f.state.failSave, f.state.throwSave = false, false
				f.state.live = { revision = 1, balance = 2, note = "a" }
				expect(f.service.finalize("profile", previous, f.state.live).outcome):toBe("committed")
			end
		end)
		it("verifies finalize readback and conditionally restores only the exact installed candidate", function()
			for _, superseded in { false, true } do
				local f = fixture()
				local previous = table.clone(f.state.live)
				f.state.live = { revision = 1, balance = 2, note = "a" }
				f.state.duringRead = function()
					f.state.stored.balance = 99
					if superseded then
						f.state.live.note = "new"
					end
				end
				local result = f.service.finalize("profile", previous, f.state.live)
				expect(result.reason):toBe("verification_failed")
				expect(result.restoration):toBe(if superseded then "superseded" else "restored")
				expect(f.state.live.balance):toBe(if superseded then 2 else 0)
			end
		end)
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
