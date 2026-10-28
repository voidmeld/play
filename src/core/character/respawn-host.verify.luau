--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Respawn = require("./respawn-host")
local Verify = require("../../../.lute/dependencies/verify/src/core")
type Owner = { disposed: boolean, closes: { () -> () } }
type Job = { at: number, run: () -> (), cancelled: boolean }
local function fixture()
	local root: Owner = { disposed = false, closes = {} }
	local state = {
		now = 0,
		saved = true,
		automatic = true,
		ready = false,
		enginePending = false,
		respawns = 0,
		deaths = 0,
		context = "one",
		character = "old",
		humanoid = true,
		prepared = {} :: { string },
		jobs = {} :: { Job },
		changed = nil :: ((Respawn.Observation<string>) -> ())?,
		characterChanged = nil :: ((string?) -> ())?,
		onWait = nil :: (() -> ())?,
	}
	local observation: Respawn.Observation<string> = {
		character = "old",
		engineCharacter = "old",
		liveBody = true,
		actorPresent = true,
		alive = true,
		hp = 100,
		zoneId = "zone-a",
	}
	local function own(owner: Owner, close: () -> ())
		table.insert(owner.closes, close)
	end
	local function dispose(owner: Owner)
		if owner.disposed then
			return
		end
		owner.disposed = true
		for _, close in owner.closes do
			close()
		end
	end
	local function schedule(delay: number, callback: () -> ()): () -> ()
		local job = { at = state.now + delay, run = callback, cancelled = false }
		table.insert(state.jobs, job)
		return function()
			job.cancelled = true
		end
	end
	local deps: Respawn.Dependencies<number, string, string, Owner, string> = {
		owner = root,
		child = function(parent)
			local child = { disposed = false, closes = {} }
			own(parent, function()
				dispose(child)
			end)
			return child
		end,
		dispose = dispose,
		own = own,
		clock = function()
			return state.now
		end,
		schedule = schedule,
		spawn = function(callback)
			return schedule(0, callback)
		end,
		pollSec = 1,
		observe = function(owner, _player, callback)
			state.changed = callback
			own(owner, function()
				state.changed = nil
			end)
			callback(observation)
		end,
		sample = function()
			return observation
		end,
		stamp = function()
			return true
		end,
		record = function() end,
		error = function(_player, reason)
			error(reason)
		end,
		characterChanged = function() end,
		rememberBody = function() end,
		nextPending = function(_previous, alive, prior, now)
			return if alive then nil else prior or now
		end,
		recordDeath = function() end,
		onCancel = function() end,
		onUntrack = function() end,
		canSchedule = function()
			return state.saved and not state.ready
		end,
		delaySec = function()
			return 5
		end,
		automatic = function()
			return state.automatic
		end,
		respawn = function()
			state.respawns += 1
			return true
		end,
		ready = function()
			state.ready = true
		end,
		isNative = function()
			return true
		end,
		currentCharacter = function()
			return state.character
		end,
		observeCharacter = function(owner, _player, callback)
			state.characterChanged = callback
			own(owner, function()
				state.characterChanged = nil
			end)
		end,
		findHumanoid = function(character)
			return if state.humanoid then character .. "-body" else nil
		end,
		waitHumanoid = function(character)
			if state.onWait then
				state.onWait()
			end
			return character .. "-body"
		end,
		prepareHumanoid = function(humanoid)
			table.insert(state.prepared, humanoid)
		end,
		observeDeath = function() end,
		isDead = function()
			return false
		end,
		engineDeath = function()
			state.deaths += 1
		end,
		context = function()
			return state.context
		end,
		present = function()
			return true
		end,
		refreshPending = function(_player, pending)
			state.enginePending = pending
		end,
	}
	local lifecycle = Respawn.create(deps)
	local function advance(at: number)
		state.now = at
		for _, job in table.clone(state.jobs) do
			if not job.cancelled and job.at <= at then
				job.cancelled = true
				job.run()
			end
		end
	end
	return state, lifecycle, observation, advance
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("Cancellable character lifecycle", function()
		it("waits for recovery persistence and cancels delayed return on departure", function()
			local state, lifecycle, observation, advance = fixture()
			lifecycle.track(1)
			state.saved = false
			observation.alive, observation.hp = false, 0
			assert(state.changed)(observation)
			lifecycle.schedulePending(1)
			advance(6)
			expect(state.respawns):toBe(0)
			state.saved = true
			lifecycle.schedulePending(1)
			lifecycle.untrack(1)
			advance(20)
			expect(state.respawns):toBe(0)
			expect(lifecycle.pendingAt[1]):toBeNil()
			expect(state.changed):toBeNil()
		end)
		it("honors explicit recovery and invalidates a pending timer when the actor becomes alive", function()
			local state, lifecycle, observation, advance = fixture()
			state.automatic = false
			lifecycle.track(1)
			observation.alive, observation.hp = false, 0
			assert(state.changed)(observation)
			lifecycle.schedulePending(1)
			advance(5)
			expect(state.ready):toBe(true)
			expect(state.respawns):toBe(0)
			observation.alive, observation.hp = true, 100
			assert(state.changed)(observation)
			expect(lifecycle.pendingAt[1]):toBeNil()
			advance(20)
			expect(state.respawns):toBe(0)
			lifecycle.dispose()
		end)
		it("does not bind a humanoid returned after a character replacement", function()
			local state, lifecycle, _observation, advance = fixture()
			state.humanoid = false
			lifecycle.track(1)
			state.onWait = function()
				state.humanoid, state.character = true, "new"
				assert(state.characterChanged)("new")
			end
			advance(0)
			expect(state.prepared):toEqual({ "new-body" })
			lifecycle.dispose()
		end)
		it("refuses actor restoration after profile context changes during spawn", function()
			local state, lifecycle = fixture()
			lifecycle.track(1)
			local restores = 0
			local ok = lifecycle.refresh(1, function(current): (unknown, string?, string?)
				expect(current()):toBe(true)
				state.context = "two"
				return true, nil, "destination"
			end, function()
				return true
			end, function() end, function()
				restores += 1
			end)
			expect(ok):toBe(false)
			expect(restores):toBe(0)
			expect(lifecycle.refreshes[1]):toBeNil()
			lifecycle.dispose()
		end)
		it("retries failed spawns and restores only one valid acknowledged destination", function()
			local attempts, restores = 0, 0
			local ok = Respawn.completeSpawn(function(): (unknown, string?, string?)
				attempts += 1
				return attempts == 3, nil, if attempts == 3 then "destination" else nil
			end, function()
				return true
			end, function()
				return true
			end, function() end, function(destination)
				expect(destination):toBe("destination")
				restores += 1
			end)
			expect(ok):toBe(true)
			expect(attempts):toBe(3)
			expect(restores):toBe(1)
		end)
		it("keeps the replacement request active when an older spawn returns late", function()
			local state, lifecycle = fixture()
			lifecycle.track(1)
			local restored = 0
			local function operation()
				return lifecycle.refresh(1, function(): (unknown, string?, string?)
					coroutine.yield()
					return true, nil, "destination"
				end, function()
					return true
				end, function() end, function()
					restored += 1
				end)
			end
			local first, second = coroutine.create(operation), coroutine.create(operation)
			expect((coroutine.resume(first))):toBe(true)
			expect((coroutine.resume(second))):toBe(true)
			local ran, accepted = coroutine.resume(first)
			expect(ran):toBe(true)
			expect(accepted):toBe(false)
			expect(state.enginePending):toBe(true)
			expect(lifecycle.refreshes[1]).never:toBeNil()
			local completed, success = coroutine.resume(second)
			expect(completed):toBe(true)
			expect(success):toBe(true)
			expect(restored):toBe(1)
			expect(state.enginePending):toBe(false)
			lifecycle.dispose()
		end)
	end)
end
