--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Engine = require("../../tools/fixtures/engine")
local Lease = require("../kernel/lease")
local Roblox = require("../../.lute/dependencies/verify/src/roblox")
local Sessions = require("./profile-sessions")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Context = { key: string, sessionId: string, acquisitionId: string }
type Profile = { revision: number }
type Stored = { lease: Lease.State, profile: Profile }

local rules = Lease.configure({
	maxRevision = 1000,
	maxTime = 1000000,
	sessionIdLimit = 64,
	acquisitionIdLimit = 64,
	integerTime = false,
})

local function fixture(own: (() -> ()) -> ())
	local environment = Roblox.testEnvironment({ handlerErrors = "raise" })
	local clock = Engine.clock(environment)
	local root = Engine.owner(environment)
	own(function()
		root.dispose()
		environment.root:Destroy()
	end)
	local stored: { [string]: Stored } = {}
	local commits: { [string]: number } = {}
	local released: { [string]: number } = {}
	local blocked: { [string]: boolean } = {}
	local held: { [string]: thread } = {}
	for index = 1, 200 do
		stored["profile-" .. tostring(index)] = { lease = { revision = 0, expiresAt = 0 }, profile = { revision = 1 } }
	end
	local function server(sessionId: string)
		local profiles: { [string]: Profile } = {}
		local contexts: { [string]: Context } = {}
		local sessions = Sessions.new(root.createChild(), {
			clock = clock.clock,
			schedule = clock.schedule,
			spawn = function(callback)
				local pending = environment.scheduler.spawn(callback)
				return function()
					environment.scheduler.cancel(pending)
				end
			end,
			wait = function()
				environment.scheduler.wait(0.25)
			end,
			report = function() end,
			renewalDelay = 20,
			retryDelay = 1,
			drainBudget = 3,
			jitter = function()
				return 0
			end,
			jitterFraction = 0,
			keyFor = function(context: Context)
				return context.key
			end,
			same = function(first: Context, second: Context)
				return first.key == second.key
					and first.sessionId == second.sessionId
					and first.acquisitionId == second.acquisitionId
			end,
			write = function(
				profile: Profile,
				context: Context,
				_expiry: number,
				current: () -> boolean,
				release: boolean,
				_generation: number
			): Sessions.Outcome
				if blocked[context.key] then
					environment.scheduler.block(function(pending)
						held[context.key] = pending
					end)
				else
					environment.scheduler.wait(0.25)
				end
				if not current() then
					return { ok = false, reason = "operation_cancelled" }
				end
				local previous = stored[context.key]
				local renewed = rules.renew(previous.lease, {
					sessionId = context.sessionId,
					acquisitionId = context.acquisitionId,
					revision = previous.lease.revision,
					now = clock.clock(),
					ttl = 60,
				})
				if not renewed.ok then
					return { ok = false, reason = renewed.reason }
				end
				local lease = renewed.value.state
				if release then
					local closed = rules.release(lease, {
						sessionId = context.sessionId,
						acquisitionId = context.acquisitionId,
						revision = lease.revision,
					})
					if not closed.ok then
						return { ok = false, reason = closed.reason }
					end
					lease = closed.value.state
				end
				stored[context.key] = { lease = lease, profile = table.clone(profile) }
				commits[context.key] = (commits[context.key] or 0) + 1
				return { ok = true, expiresAt = stored[context.key].lease.expiresAt }
			end,
		})
		own(sessions.dispose)
		local function acquire(key: string): (Context?, string?)
			local context = { key = key, sessionId = sessionId, acquisitionId = sessionId .. ":" .. key }
			local previous = stored[key]
			local acquired = rules.acquire(
				previous.lease,
				{ sessionId = context.sessionId, acquisitionId = context.acquisitionId, now = clock.clock(), ttl = 60 }
			)
			if not acquired.ok then
				return nil, acquired.reason
			end
			stored[key] = { lease = acquired.value.state, profile = table.clone(previous.profile) }
			profiles[key] = table.clone(stored[key].profile)
			contexts[key] = context
			sessions.admit(context, stored[key].lease.expiresAt, function()
				return profiles[key]
			end, function()
				released[sessionId] = (released[sessionId] or 0) + 1
			end)
			return context, nil
		end
		return { sessions = sessions, profiles = profiles, contexts = contexts, acquire = acquire }
	end
	return {
		server = server,
		stored = stored,
		commits = commits,
		released = released,
		blocked = blocked,
		held = held,
		environment = environment,
		clock = clock,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("bounded profile save load", function()
		it("coalesces repeated requests for 200 profiles and persists each current revision", function(own)
			local f = fixture(own)
			local server = f.server("server-a")
			for key in f.stored do
				local context = assert(server.acquire(key))
				expect(server.sessions.requestSave(context)):toBe(true)
				expect(server.sessions.requestSave(context)):toBe(true)
				server.profiles[key] = { revision = 2 }
				expect(server.sessions.requestSave(context)):toBe(true)
				expect(server.sessions.ownedTaskCount(context)):toBe(1)
			end
			f.clock.advance(0)
			f.clock.advance(0.25)
			local total = 0
			for key, record in f.stored do
				expect(record.profile.revision):toBe(2)
				expect(record.lease.sessionId):toBe("server-a")
				expect(f.commits[key]):toBe(1)
				expect(server.sessions.isAdmitted(server.contexts[key])):toBe(true)
				total += 1
			end
			expect(total):toBe(200)
			expect(f.released["server-a"]):toBeNil()
			expect(f.environment.scheduler.failures):toEqual({})
		end)
		it("holds delayed closes at budget and fences their old payloads after lawful takeover", function(own)
			local f = fixture(own)
			local first, second = f.server("server-a"), f.server("server-b")
			for key in f.stored do
				assert(first.acquire(key))
				first.profiles[key] = { revision = 2 }
			end
			for index = 1, 10 do
				f.blocked["profile-" .. tostring(index)] = true
			end
			local outcomes: { [string]: Sessions.Outcome }? = nil
			f.environment.scheduler.spawn(function()
				outcomes = first.sessions.drain()
			end)
			for _ = 1, 12 do
				f.clock.advance(0.25)
			end
			local observed = assert(outcomes)
			local complete, pending = 0, 0
			for key, outcome in observed do
				if f.blocked[key] then
					expect(outcome.reason):toBe("drain_held")
					pending += 1
				else
					expect(outcome.ok):toBe(true)
					expect(f.stored[key].profile.revision):toBe(2)
					complete += 1
				end
			end
			expect({ complete, pending }):toEqual({ 190, 10 })
			expect(f.released["server-a"]):toBe(190)
			local key = "profile-1"
			expect(second.acquire(key)):toBeNil()
			f.clock.advance(58)
			local acquired = assert(second.acquire(key))
			for _, thread in f.held do
				f.environment.scheduler.resume(thread)
			end
			f.clock.advance(0)
			for blocked in f.blocked do
				expect(observed[blocked].reason):toBe("drain_held")
				expect(f.stored[blocked].profile.revision):toBe(1)
				expect(f.commits[blocked]):toBeNil()
			end
			expect(f.stored[key].lease.sessionId):toBe("server-b")
			f.blocked[key] = nil
			second.profiles[key] = { revision = 3 }
			local saved: Sessions.Outcome? = nil
			f.environment.scheduler.spawn(function()
				saved = second.sessions.save(acquired)
			end)
			f.clock.advance(0.25)
			expect(assert(saved).ok):toBe(true)
			expect(f.stored[key].profile.revision):toBe(3)
			expect(f.stored[key].lease.sessionId):toBe("server-b")
			expect(f.released["server-a"]):toBe(190)
			expect(f.environment.scheduler.failures):toEqual({})
		end)
	end)
end
