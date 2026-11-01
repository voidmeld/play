--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Contribution = require("./contribution")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local core = Contribution.create({
		categories = { damage = "damage", heal = "healing", interrupt = "control" },
		eligibleRelation = function(observation)
			return observation.sourceActorId ~= observation.targetActorId
				and (
					if observation.kind == "heal"
						then observation.targetRelation == "ally"
						else observation.targetRelation == "enemy"
				)
		end,
		participationRadius = 100,
		inactiveSeconds = 30,
		recentDefeatSeconds = 30,
		rewardRadius = 100,
		shortEncounterSeconds = 10,
		actionSpanSeconds = 5,
		interruptActiveSeconds = 10,
		interruptKind = "interrupt",
	})
	describe("encounter contribution", function()
		it("credits only effective contested actions against an eligible relation", function()
			local observation: Contribution.Observation = {
				kind = "damage",
				sourceActorId = "a",
				targetActorId = "b",
				targetRelation = "enemy",
				contested = true,
				targetEligible = true,
				attemptedAmount = 100,
				effectiveAmount = 80,
				eligibleAmountCap = 20,
			}
			expect(assert(core.creditFor(observation)).amount):toBe(20)
			observation.targetRelation = "self"
			expect(core.creditFor(observation)):toBeNil()
			observation.targetRelation, observation.contested = "enemy", false
			expect(core.creditFor(observation)):toBeNil()
			observation.contested, observation.effectiveAmount = true, 0
			expect(core.creditFor(observation)):toBeNil()
			observation.effectiveAmount = math.nan
			expect(core.creditFor(observation)):toBeNil()
		end)
		it("counts living nearby participation and expires inactive records without mutating its input", function()
			local before = core.record(nil, "a", "damage", 0)
			local actors: { [string]: Contribution.Participant } = {
				a = { hp = 1, pos = { x = 100, z = 0 } },
				dead = { hp = 0, pos = { x = 0, z = 0 } },
				far = { hp = 1, pos = { x = 101, z = 0 } },
			}
			local observed = assert(core.observe(before, actors, core.asParticipant, { x = 0, z = 0 }, 1, 0.5))
			expect(observed.actors.a.activeSec):toBe(0.5)
			expect(before.actors.a.activeSec):toBe(0)
			expect(observed.actors.dead):toBeNil()
			expect(observed.actors.far):toBeNil()
			expect(assert(core.observe(observed, {}, core.asParticipant, { x = 0, z = 0 }, 32, 1)).actors.a):toBeNil()
		end)
		it("freezes end identity, three-dimensional distance and dungeon admission against later movement", function()
			local record = core.record(core.record(nil, "a", "heal", 0), "a", "heal", 5)
			local actor: Contribution.Participant = {
				hp = 10,
				characterId = "hero",
				pos = { x = 80, y = 260, z = 0 },
				dungeonAdmission = { dungeonId = "d", cycleId = "c", characterId = "hero" },
			}
			local ended = assert(core.finish(record, 20, { a = actor }, core.asParticipant, { x = 0, y = 200, z = 0 }))
			actor.pos.x = 900
			assert(actor.dungeonAdmission).cycleId = "next"
			expect(core.eligibleAtEnd(ended, "a", "hero")):toBe(true)
			expect(core.eligibleAtEnd(ended, "a", "replacement")):toBe(false)
			local endActor = assert(ended.endActors).a
			expect(endActor.distance):toBe(100)
			expect(assert(endActor.dungeonAdmission).cycleId):toBe("c")
			expect(core.finish(ended, 999, {}, core.asParticipant, { x = 0, z = 0 })):toBe(ended)
		end)
		it("admits recent defeat only within the configured inclusive window", function()
			local record = core.record(core.record(nil, "a", "damage", 0), "a", "damage", 5)
			local actor: Contribution.Participant =
				{ hp = 0, characterId = "hero", pos = { x = 0, z = 0 }, defeatedAtSec = 10 }
			local ended = core.finish(record, 40, { a = actor }, core.asParticipant, { x = 0, z = 0 })
			expect(core.eligibleAtEnd(ended, "a", "hero")):toBe(true)
			actor.defeatedAtSec = 9.999
			expect(
				core.eligibleAtEnd(
					core.finish(record, 40, { a = actor }, core.asParticipant, { x = 0, z = 0 }),
					"a",
					"hero"
				)
			):toBe(false)
		end)
		it("requires sustained action or a qualifying interrupt for a long encounter", function()
			local short = core.record(nil, "a", "damage", 0)
			local actors: { [string]: Contribution.Participant } =
				{ a = { hp = 1, characterId = "hero", pos = { x = 0, z = 0 } } }
			expect(
				core.eligibleAtEnd(core.finish(short, 10, actors, core.asParticipant, { x = 0, z = 0 }), "a", "hero")
			):toBe(true)
			expect(
				core.eligibleAtEnd(core.finish(short, 11, actors, core.asParticipant, { x = 0, z = 0 }), "a", "hero")
			):toBe(false)
			local interrupted = core.record(nil, "a", "interrupt", 0)
			local observed = core.observe(interrupted, actors, core.asParticipant, { x = 0, z = 0 }, 9, 10)
			expect(
				core.eligibleAtEnd(core.finish(observed, 11, actors, core.asParticipant, { x = 0, z = 0 }), "a", "hero")
			):toBe(true)
		end)
	end)
end
