--!strict
local Bdd = require("@verify/src/bdd")
local Claims = require("./claims")
local Run = require("./run")
local Verify = require("@verify/src/core")
local destination = 1

local package: Run.Package = {
	id = "route",
	entryId = "entry",
	returnId = "return",
	recoveryWindowSec = 10,
	group = { minPlayers = 2, maxPlayers = 2 },
	phases = {
		{ id = "first", kind = "checkpoint", contentId = "rest" },
		{ id = "last", kind = "boss", contentId = "opponent" },
	},
}
local Core = Run.run({
	describe = function(value: Run.Package): Run.Package
		return value
	end,
	readPackage = function(value: unknown): Run.Package?
		return if value == package then package else nil
	end,
	validCheckpoint = function(_, state)
		return state.checkpointId == (if state.phaseIndex == 1 then nil else "rest")
	end,
	wipePhase = function(_, state)
		return state.phaseIndex
	end,
	replacementAllowed = function(_, state)
		return state.status == "active" and state.checkpointId ~= nil
	end,
	maxMembers = 2,
})
local Claim = Claims.claims({
	recordTtlSec = 100,
	claimLeaseSec = 10,
	carrierContract = "test.carrier",
	memberCount = 2,
	maxText = 256,
	retryDelaysSec = { 1 },
})
local function start(): Run.RunState
	local result = Core.transition(package, nil, {
		kind = "start",
		eventId = "start",
		runId = "run",
		leaderId = "a",
		memberIds = { "b", "a" },
	}, 0)
	assert(result.ok)
	return result.state
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("encounter progress", function()
		local config: Run.WaveConfig<{ Run.WaveRoom }, Run.WaveRoom, string> = {
			room = function(rooms, index)
				return rooms[index]
			end,
			describe = function(room)
				return room
			end,
			wave = function(room, _, index)
				return { room.waves[index][1].placementId }
			end,
			adds = function()
				return { "add" }
			end,
			call = function(_, _, caller, sequence, index)
				return caller .. "/call/" .. sequence .. "/" .. index
			end,
			ids = function(id)
				return id, "spawn/" .. id
			end,
			isCall = function(id)
				return string.find(id, "/call/", 1, true) ~= nil
			end,
			isCallerSpawn = function(id, caller)
				return string.find(id, caller .. "/call/", 1, true) == 1
			end,
			perCast = 1,
			liveCap = 2,
			checkpointRadius = 5,
		}
		local rules = Run.encounters(config)
		local rooms: { Run.WaveRoom } = {
			{
				kind = "encounter",
				position = { x = 0, z = 0 },
				waves = { { { placementId = "a" } }, { { placementId = "b" } } },
			},
			{ kind = "checkpoint", position = { x = 3, z = 4 }, waves = {} },
			{
				kind = "boss",
				position = { x = 0, z = 0 },
				waves = { { { placementId = "c" } } },
				adds = { atHealthFraction = 0.4 },
			},
		}
		it("advances only after the wave and its called enemies are defeated", function()
			local initial, first = rules.enterRoom(rooms, "party", 1, 1)
			expect(first):toEqual({ "a" })
			local readings: { [string]: Run.WaveReading } = {
				a = { hp = 1, maxHp = 1, resolvedAbilitySequence = 1, resolvedReinforcementCount = 3 },
			}
			local called, spawns = rules.calledSpawns(rooms, initial, readings)
			expect(spawns):toEqual({ "a/call/1/1" })
			expect(initial.calledSequences.a):toBeNil()
			local _, replay = rules.calledSpawns(rooms, called, readings)
			expect(#replay):toBe(0)
			readings.a = { hp = 0, maxHp = 1 }
			local partial, decision = rules.observe(rooms, called, readings)
			expect(decision.kind):toBe("wait")
			readings[spawns[1]] = { hp = 0, maxHp = 1 }
			local installed = partial
			local spawned: { string } = {}
			local function track(nextTracker: Run.Tracker)
				installed = nextTracker
			end
			local function spawn(rows: { string })
				for _, id in rows do
					table.insert(spawned, id)
				end
			end
			local function readMob(instanceId: string): Run.WaveReading?
				return readings[string.sub(instanceId, #"spawn/" + 1)]
			end
			local function noPositions(): never
				error("combat does not sample checkpoint positions")
			end
			expect(rules.advance(rooms, partial, readMob, noPositions, spawn, track)):toBe(false)
			expect(spawned):toEqual({ "b" })
			expect(installed.waveIndex):toBe(2)
			expect(table.isfrozen(installed.pending)):toBe(true)
			readings.b = { hp = 0, maxHp = 1 }
			expect(rules.advance(rooms, installed, readMob, noPositions, spawn, track)):toBe(true)
		end)
		it("requires positive observed health and an advancing call sequence", function()
			local tracker = rules.enterRoom(rooms, "party", 1, 1)
			local unknown = 0 / 0
			for _, reading in
				{
					{ hp = unknown, maxHp = 10, resolvedAbilitySequence = 1, resolvedReinforcementCount = 1 },
					{ hp = 10, maxHp = 10, resolvedAbilitySequence = unknown, resolvedReinforcementCount = 1 },
				}
			do
				local observed, calls = rules.calledSpawns(rooms, tracker, { a = reading })
				expect(#calls):toBe(0)
				expect(observed.calledSequences.a):toBeNil()
			end
		end)
		it("resets attempts, checks horizontal checkpoint reach and calls boss adds once", function()
			local fresh, empty = rules.enterRoom(rooms, "party", 2, 2)
			expect(#empty):toBe(0)
			local function noCombat(): Run.WaveReading?
				error("checkpoint sampled combat")
			end
			local function noEffects(_effect: unknown): ()
				error("checkpoint emitted combat effects")
			end
			expect(rules.advance(rooms, fresh, noCombat, function(runId)
				expect(runId):toBe("party")
				return { { x = 3, z = 4 } }
			end, noEffects, noEffects)):toBe(true)
			expect(fresh.attempt):toBe(2)
			expect(rules.reachedCheckpoint(rooms, 2, { { x = 0, z = 0 } })):toBe(true)
			expect(rules.reachedCheckpoint(rooms, 2, { { x = -1, z = 0 } })):toBe(false)
			expect(rules.reachedCheckpoint(rooms, 1, { rooms[1].position })):toBe(false)
			local boss = rules.enterRoom(rooms, "party", 2, 3)
			local observed, decision = rules.observe(rooms, boss, { c = { hp = 4, maxHp = 10 } })
			expect(decision.kind):toBe("spawn_adds")
			local withAdds, adds = rules.addSpawns(rooms, observed)
			expect(adds):toEqual({ "add" })
			local _, again = rules.addSpawns(rooms, withAdds)
			expect(#again):toBe(0)
			local _, cleared = rules.observe(rooms, withAdds, { c = { hp = 0, maxHp = 10 } })
			expect(cleared.kind):toBe("room_cleared")
		end)
		it("starts a fresh warning after occupancy lifts or reaches its delay cap", function()
			local cycle =
				Run.sharedCycle({ warningSeconds = 3, perCast = 2, liveCap = 3, pocketRadius = 5, heightTolerance = 2 })
			local row: Run.Repopulation = { dueAt = 10 }
			local waiting = cycle.repopulation(row, 14, true, 5)
			local warned, early = cycle.repopulation(waiting, 15, true, 5)
			expect(early):toBe(false)
			expect(warned.warnedAt):toBe(15)
			local _, ready = cycle.repopulation(warned, 18, true, 5)
			expect(ready):toBe(true)
			expect(row.warnedAt):toBeNil()
			local count, sequence =
				cycle.rollCount(1, { hp = 3, resolvedAbilitySequence = 2, resolvedReinforcementCount = 4 }, 2)
			expect(count):toBe(1)
			expect(sequence):toBe(2)
		end)
	end)
	describe("run progress and claims", function()
		it("replays accepted phases and refuses conflicts without progressing the caller", function()
			local state = start()
			local event = { kind = "complete_phase", eventId = "phase", expectedRevision = 1, phaseId = "first" }
			local next = Core.transition(package, state, event, 1)
			assert(next.ok)
			expect(next.state.checkpointId):toBe("rest")
			expect(state.phaseIndex):toBe(1)
			local replay = Core.transition(package, next.state, event, 2)
			assert(replay.ok)
			expect(replay.replayed):toBe(true)
			expect(replay.state.revision):toBe(2)
			event.phaseId = "last"
			local conflict = Core.transition(package, next.state, event, 2)
			assert(not conflict.ok)
			expect(conflict.reason):toBe("receipt_conflict")
			local complete = Core.transition(package, next.state, {
				kind = "complete_phase",
				eventId = "end",
				expectedRevision = 2,
				phaseId = "last",
			}, 3)
			assert(complete.ok)
			expect(complete.state.status):toBe("completed")
		end)
		it("keeps a disconnected seat through its recovery window and admits replacement after expiry", function()
			local state = start()
			local phase = Core.transition(package, state, {
				kind = "complete_phase",
				eventId = "phase",
				expectedRevision = 1,
				phaseId = "first",
			}, 1)
			assert(phase.ok)
			local disconnected = Core.transition(package, phase.state, {
				kind = "disconnect",
				eventId = "lost",
				expectedRevision = 2,
				memberId = "b",
			}, 2)
			assert(disconnected.ok)
			local request =
				{ kind = "replace", eventId = "replace", expectedRevision = 3, memberId = "b", replacementId = "c" }
			local held = Core.transition(package, disconnected.state, request, 12)
			assert(not held.ok)
			expect(held.reason):toBe("replacement_seat_reserved")
			local replaced = Core.transition(package, disconnected.state, request, 13)
			assert(replaced.ok)
			expect(replaced.state.members[2].id):toBe("c")
		end)
		it("fences old jobs and stale revisions after claim takeover", function()
			local record = assert(Claim.newRecord({
				runId = "run",
				packageId = "route",
				placeId = destination,
				accessCode = "access",
				privateServerId = "server",
				partyId = "party",
				leaderUserId = 1,
				request = {},
				rows = {},
				runState = start(),
				members = { { userId = 1, characterId = "a" }, { userId = 2, characterId = "b" } },
			}, 0))
			local held = assert(Claim.claimTransform("server", "job-a", 0)(record))
			expect(Claim.claimTransform("server", "job-b", 10)(held)):toBeNil()
			local taken = assert(Claim.claimTransform("server", "job-b", 11)(held))
			expect(Claim.renewTransform("run", "job-a", 11)(taken)):toBeNil()
			expect(Claim.writeThroughTransform("run", start(), "job-b", 11)(taken)):toBeNil()
			local advanced = table.clone(start())
			advanced.revision = 2
			local written = assert(Claim.writeThroughTransform("run", advanced, "job-b", 12)(taken))
			expect(written.stateRevision):toBe(2)
			expect(taken.stateRevision):toBe(1)
			expect(Claim.claimTransform("other", "job-b", 12)(written)):toBeNil()
		end)
	end)
end
