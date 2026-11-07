--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Engine = require("../../tools/fixtures/engine")
local Sessions = require("./profile-sessions")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("profile sessions", function()
		local function fixture()
			local clock = Engine.clock()
			local owner = Engine.owner()
			local writes: { { release: boolean, generation: number, profile: number } } = {}
			local state = { fail = false, releases = 0, value = 1, warnings = 0 }
			local sessions = Sessions.new(owner, {
				clock = clock.clock,
				schedule = clock.schedule,
				report = function(_kind: string, _key: string, _reason: string?)
					state.warnings += 1
				end,
				renewalDelay = 5,
				retryDelay = 1,
				drainBudget = 3,
				jitter = function(): number
					return 0
				end,
				jitterFraction = 0.1,
				keyFor = function(context: string): string
					return context
				end,
				same = function(a: string, b: string): boolean
					return a == b
				end,
				write = function(
					profile: number,
					_context: string,
					expiry: number,
					current: () -> boolean,
					release: boolean,
					generation: number
				): Sessions.Outcome
					assert(current())
					assert(clock.clock() < expiry)
					table.insert(writes, { release = release, generation = generation, profile = profile })
					return if state.fail
						then { ok = false, reason = "offline" }
						else { ok = true, expiresAt = clock.clock() + 10 }
				end,
			})
			sessions.admit("profile", 10, function(): number?
				return state.value
			end, function()
				state.releases += 1
			end)
			return { clock = clock, owner = owner, sessions = sessions, writes = writes, state = state }
		end
		it("renews from the current profile and retries failures without releasing ownership", function()
			local f = fixture()
			f.clock.advance(5)
			expect(#f.writes):toBe(1)
			f.state.value = 2
			f.state.fail = true
			expect(f.sessions.save("profile").ok):toBe(false)
			expect(f.sessions.isAdmitted("profile")):toBe(true)
			f.state.fail = false
			f.clock.advance(1)
			expect(#f.writes):toBe(3)
			expect(f.writes[3].profile):toBe(2)
			expect(f.state.releases):toBe(0)
			f.sessions.dispose()
			f.clock.advance(100)
			expect(#f.writes):toBe(3)
		end)
		it("failed close retains the lease until a committed retry and close replay is idempotent", function()
			local f = fixture()
			f.state.fail = true
			expect(f.sessions.unload("profile").ok):toBe(false)
			expect(f.state.releases):toBe(0)
			expect(f.sessions.requestSave("profile")):toBe(false)
			f.state.fail = false
			f.clock.advance(1)
			expect(f.state.releases):toBe(1)
			expect(f.sessions.isAdmitted("profile")):toBe(false)
			expect(f.sessions.unload("profile").ok):toBe(true)
			expect(f.writes[2].release):toBe(true)
			expect(f.sessions.ownedTaskCount("profile")):toBe(0)
		end)
		it("expiry fails closed without further store writes and disposal cancels queued retries", function()
			local f = fixture()
			f.state.fail = true
			f.clock.advance(10)
			local count = #f.writes
			expect(f.sessions.save("profile").reason):toBe("lock_lost")
			expect(#f.writes):toBe(count)
			expect(f.state.releases):toBe(0)
			f.owner.dispose()
			f.clock.advance(100)
			expect(#f.writes):toBe(count)
		end)
		it("coalesced request saves and synchronous drain release only admitted contexts", function()
			local f = fixture()
			expect(f.sessions.save("other").reason):toBe("not_admitted")
			expect(f.sessions.requestSave("profile")):toBe(true)
			f.clock.advance(0)
			expect(#f.writes):toBe(1)
			expect(f.sessions.drain().profile.ok):toBe(true)
			expect(f.state.releases):toBe(1)
		end)
	end)
end
