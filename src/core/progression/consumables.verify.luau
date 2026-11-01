--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Consumables = require("./consumables")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("consumable recovery", function()
		local function fixture()
			local core = Consumables.create({
				maxBuffStat = 40,
				maxBuffSeconds = 3600,
				movementToleranceSquared = 0.25,
				drinksMana = function(actor)
					return actor.classId ~= "physical"
				end,
				consumedCue = "consumed",
				channelCue = "resting",
				finishedCue = "finished",
				interruptedCue = function(reason)
					return reason .. ":lost"
				end,
			})
			assert(core.register("food", { resource = "hp", verb = "eat", durationSec = 20, fractionPerSec = 0.025 }))
			assert(
				core.register("water", { resource = "mana", verb = "drink", durationSec = 20, fractionPerSec = 0.03 })
			)
			local actor: Consumables.Actor =
				{ id = "a", hp = 20, maxHp = 100, mana = 10, maxMana = 100, pos = { x = 0, z = 0 } }
			return core, actor
		end
		it("keeps catalogues isolated and copies validated definitions before freezing", function()
			local core = fixture()
			local other = fixture()
			local stats = { power = 2 }
			expect(core.register("buff", {
				resource = "none",
				verb = "use",
				durationSec = 0,
				fractionPerSec = 0,
				buff = { slot = "elixir", durationSec = 30, stats = stats },
			})):toBe(true)
			stats.power = 9
			expect(assert(assert(core.item("buff")).buff).stats.power):toBe(2)
			expect(other.item("buff")):toBeNil()
			expect(core.register("food", {})):toBe(false)
			for _, raw in { false, 1, {}, { resource = "other", verb = "use", durationSec = 1, fractionPerSec = 1 } } do
				expect(core.register("bad", raw)):toBe(false)
			end
		end)
		it("bounds definition values and rejects unsupported buff slots", function()
			local core = fixture()
			for _, seconds in { 0, -1, 3601, math.huge, math.nan } do
				expect(core.register("bad", {
					resource = "none",
					verb = "use",
					durationSec = 0,
					fractionPerSec = 0,
					buff = { slot = "food", durationSec = seconds, stats = {} },
				})):toBe(false)
			end
			for _, amount in { 0, -1, 41, math.huge, math.nan } do
				expect(core.register("bad", {
					resource = "none",
					verb = "use",
					durationSec = 0,
					fractionPerSec = 0,
					buff = { slot = "food", durationSec = 30, stats = { power = amount } },
				})):toBe(false)
			end
			expect(core.registerAll({
				valid = { resource = "hp", verb = "eat", durationSec = 1, fractionPerSec = 1 },
				invalid = {},
			})):toBe(1)
		end)
		it("advances both resources once and ignores repeated or reversed clock samples", function()
			local core, actor = fixture()
			local food = assert(core.begin(nil, actor, {}, "food", 1, 100))
			local both = assert(core.begin(food, actor, {}, "water", 2, 100))
			local state, hp, mana = core.tick(both, actor, {}, 104)
			expect(hp):toBe(10)
			expect(mana):toBe(12)
			expect(assert(both.hp).tickedAt):toBe(100)
			local _, repeated = core.tick(state, actor, {}, 104)
			local _, reversed = core.tick(state, actor, {}, 103)
			expect(repeated + reversed):toBe(0)
		end)
		it("caps recovery at the resource maximum and channel deadline", function()
			local core, actor = fixture()
			local food = assert(core.begin(nil, actor, {}, "food", 1, 100))
			actor.hp = 99
			local state, hp = core.tick(food, actor, {}, 10000)
			expect(hp):toBe(1)
			expect(assert(state).hp):toBeNil()
			expect(assert(state).cue):toBe("finished")
		end)
		it("refuses dead, engaged, controlled, full and stale uses", function()
			local core, actor = fixture()
			expect(core.eligibility(nil, {})):toBe("recover_before_rest")
			actor.hp = 0
			expect(select(2, core.begin(nil, actor, {}, "food", 1, 0))):toBe("recover_before_rest")
			actor.hp, actor.fights = 20, { enemy = 1 }
			expect(select(2, core.begin(nil, actor, {}, "food", 1, 0))):toBe("in_combat")
			actor.fights, actor.crowdControls = nil, { stun = { remainingSec = 1 } }
			expect(select(2, core.begin(nil, actor, {}, "food", 1, 0))):toBe("controlled")
			actor.crowdControls, actor.hp = nil, 100
			expect(select(2, core.begin(nil, actor, {}, "food", 1, 0))):toBe("resource_full")
			actor.hp = 20
			local state = assert(core.begin(nil, actor, {}, "food", 1, 0))
			expect(select(2, core.begin(state, actor, {}, "food", 1, 0))):toBe("stale_use")
			expect(select(2, core.begin(state, actor, {}, "food", 2, 0))):toBe("already_resting")
			for _, value in { false, "bad", math.huge, math.nan, -1 } do
				expect(select(2, core.begin(nil, actor, {}, "food", value, 0))):toBe("stale_use")
			end
		end)
		it("interrupts on movement or hostile contact and keeps consumed replay order", function()
			local core, actor = fixture()
			local state = assert(core.begin(nil, actor, {}, "food", 1, 0))
			actor.pos.x = 1
			local moved, hp = core.tick(state, actor, {}, 1)
			expect(hp):toBe(0)
			expect(assert(moved).hp):toBeNil()
			expect(assert(moved).serial):toBe(1)
			expect(assert(moved).cue):toBe("moved:lost")
			actor.pos.x = 0
			local engaged = core.tick(state, actor, { enemy = { hp = 10, threat = { a = 1 } } }, 1)
			expect(assert(engaged).hp):toBeNil()
			actor.sustenance = state
			core.interruptActor(actor, "damaged")
			expect(actor.sustenanceGeneration):toBe(1)
			expect(assert(actor.sustenance).hp):toBeNil()
		end)
		it("uses the game's resource policy even for an already active channel", function()
			local core, actor = fixture()
			local state = assert(core.begin(nil, actor, {}, "water", 1, 0))
			actor.classId = "physical"
			local _, _, mana = core.tick(state, actor, {}, 1)
			expect(mana):toBe(0)
			expect(select(2, core.begin(nil, actor, {}, "water", 1, 0))):toBe("no_mana_pool")
		end)
		it("grants food buffs only after an uninterrupted channel and expires them at their deadline", function()
			local core, actor = fixture()
			assert(core.register("cooked", {
				resource = "hp",
				verb = "eat",
				durationSec = 20,
				fractionPerSec = 0.025,
				buff = { slot = "food", durationSec = 30, stats = { power = 2 } },
			}))
			actor.hp = 100
			local state = assert(core.begin(nil, actor, {}, "cooked", 1, 0))
			local waiting = core.tick(state, actor, {}, 19)
			expect((next(core.activeStats(waiting, 19)))):toBeNil()
			local done = core.tick(waiting, actor, {}, 20)
			expect(assert(done).hp):toBeNil()
			expect(core.activeStats(done, 49).power):toBe(2)
			expect((next(core.activeStats(done, 50)))):toBeNil()
		end)
		it("applies immediate combat buffs once per active item and combines separate slots", function()
			local core, actor = fixture()
			for _, slot: "food" | "elixir" in { "food", "elixir" } do
				assert(core.register("buff_" .. slot, {
					resource = "none",
					combat = true,
					verb = "use",
					durationSec = 0,
					fractionPerSec = 0,
					buff = { slot = slot, durationSec = 30, stats = { power = 2 } },
				}))
			end
			actor.fights = { enemy = 0 }
			local state = assert(core.begin(nil, actor, {}, "buff_food", 1, 0))
			expect(select(2, core.begin(state, actor, {}, "buff_food", 2, 1))):toBe("already_active")
			state = assert(core.begin(state, actor, {}, "buff_elixir", 2, 1))
			expect(core.activeStats(state, 2).power):toBe(4)
		end)
	end)
end
