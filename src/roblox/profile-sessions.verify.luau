--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Engine = require("../../tools/fixtures/engine")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Sessions = require("./profile-sessions")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("profile sessions", function()
		local function fixture(parallel: boolean?, partition: ((string) -> string)?)
			local environment = Roblox.testEnvironment({ handlerErrors = "raise" })
			local clock = Engine.clock(environment)
			local owner = Engine.owner(environment)
			local writes: { { release: boolean, generation: number, profile: number } } = {}
			local state: {
				fail: boolean,
				releases: number,
				value: number,
				warnings: number,
				expiresAt: number?,
				beforeReply: ((number) -> ())?,
			} =
				{ fail = false, releases = 0, value = 1, warnings = 0 }
			local sessions = Sessions.new(owner, {
				clock = clock.clock,
				schedule = clock.schedule,
				spawn = if parallel
					then function(callback: () -> ()): () -> ()
						local pending = environment.scheduler.spawn(callback)
						return function()
							environment.scheduler.cancel(pending)
						end
					end
					else nil,
				wait = if parallel
					then function()
						environment.scheduler.wait(0.5)
					end
					else nil,
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
					return if partition ~= nil then partition(context) else context
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
					local result: Sessions.Outcome = if state.fail
						then { ok = false, reason = "offline" }
						else { ok = true, expiresAt = state.expiresAt or clock.clock() + 10 }
					if state.beforeReply ~= nil then
						state.beforeReply(generation)
					end
					return result
				end,
			})
			sessions.admit("profile", 10, function(): number?
				return state.value
			end, function()
				state.releases += 1
			end)
			return {
				clock = clock,
				owner = owner,
				sessions = sessions,
				writes = writes,
				state = state,
				environment = environment,
			}
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
		it("does not let stale committed replies shorten or revive a newer lease", function()
			for _, expiry in { { older = 20, newer = 2 }, { older = 2, newer = 20 } } do
				local newer = expiry.newer
				local f = fixture()
				local held: thread? = nil
				local stale: Sessions.Outcome? = nil
				f.state.expiresAt = expiry.older
				f.state.beforeReply = function(generation)
					if generation == 1 then
						f.environment.scheduler.block(function(pending)
							held = pending
						end)
					end
				end
				f.environment.scheduler.spawn(function()
					stale = f.sessions.save("profile")
				end)
				expect(#f.writes):toBe(1)
				f.state.expiresAt = newer
				expect(f.sessions.save("profile").ok):toBe(true)
				f.environment.scheduler.resume(assert(held))
				f.clock.advance(0)
				expect(assert(stale).reason):toBe("operation_cancelled")
				f.clock.advance(3)
				local result = f.sessions.save("profile")
				expect(result.ok):toBe(newer > 3)
				if newer < 3 then
					expect(result.reason):toBe("lock_lost")
				end
				expect(#f.writes):toBe(if newer > 3 then 3 else 2)
				expect(f.state.releases):toBe(0)
				expect(f.environment.scheduler.failures):toEqual({})
				f.sessions.dispose()
			end
		end)
		it("drains the captured sessions when closing one also closes its partner", function()
			for _, parallel in { false, true } do
				local f = fixture(parallel)
				f.sessions.admit("other", 10, function()
					return 2
				end, function()
					f.state.releases += 1
				end)
				local first = true
				f.state.beforeReply = function()
					if first then
						first = false
						local context = if f.writes[1].profile == 1 then "other" else "profile"
						expect(f.sessions.unload(context).ok):toBe(true)
					end
				end
				local outcomes = f.sessions.drain()
				expect(outcomes.profile.ok):toBe(true)
				expect(outcomes.other.ok):toBe(true)
				expect(#f.writes):toBe(2)
				expect(f.state.releases):toBe(2)
				expect(f.environment.scheduler.failures):toEqual({})
				f.sessions.dispose()
			end
		end)
		it("does not close a replacement session admitted while its captured predecessor drains", function()
			for _, parallel in { false, true } do
				local f = fixture(parallel, function(context)
					return string.match(context, "^[^:]+") or context
				end)
				f.sessions.admit("other", 10, function()
					return 2
				end, function()
					f.state.releases += 1
				end)
				local replacement = ""
				f.state.beforeReply = function()
					if replacement == "" then
						local context = if f.writes[1].profile == 1 then "other" else "profile"
						replacement = context .. ":next"
						expect(f.sessions.unload(context).ok):toBe(true)
						f.sessions.admit(replacement, 10, function()
							return 3
						end, function()
							f.state.releases += 100
						end)
					end
				end
				local outcomes = f.sessions.drain()
				local key = string.match(replacement, "^[^:]+") or replacement
				expect(outcomes[key].reason):toBe("not_admitted")
				expect(f.sessions.isAdmitted(replacement)):toBe(true)
				expect(#f.writes):toBe(2)
				expect(f.state.releases):toBe(2)
				expect(f.environment.scheduler.failures):toEqual({})
				f.sessions.dispose()
			end
		end)
		it("keeps a returned held drain receipt unchanged after a late committed reply", function()
			local f = fixture(true)
			local held: thread? = nil
			local outcomes: { [string]: Sessions.Outcome }? = nil
			f.state.beforeReply = function()
				f.environment.scheduler.block(function(pending)
					held = pending
				end)
			end
			f.environment.scheduler.spawn(function()
				outcomes = f.sessions.drain()
			end)
			f.clock.advance(3)
			local observed = assert(outcomes)
			expect(observed.profile.reason):toBe("drain_held")
			expect(f.state.releases):toBe(0)
			f.environment.scheduler.resume(assert(held))
			f.clock.advance(0)
			expect(observed.profile.ok):toBe(false)
			expect(observed.profile.reason):toBe("drain_held")
			expect(f.sessions.unload("profile").ok):toBe(true)
			expect(f.state.releases):toBe(1)
			expect(f.environment.scheduler.failures):toEqual({})
			f.sessions.dispose()
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
