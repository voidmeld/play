--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Scene = require("../../../tools/fixtures/effects")
local Timed = require("./timed")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("timed", function()
		it("applications increment to the authored cap and reset duration and tick phase", function()
			local scene = Scene.new(1e-6)
			local application: Timed.Application = { durationSec = 10, stackLimit = 3, tickInSec = 2 }
			scene.apply("effect", application)
			local original = scene.snapshot()
			expect(original.effect.stacks):toBe(1)
			scene.advance(1)
			expect(scene.snapshot().effect.remainingSec):toBe(9)
			expect(scene.snapshot().effect.tickInSec):toBe(1)
			for _ = 1, 4 do
				scene.apply("effect", application)
			end
			expect(scene.snapshot().effect):toEqual({ remainingSec = 10, totalSec = 10, stacks = 3, tickInSec = 2 })
			expect(original.effect.stacks):toBe(1)
			expect(original.effect.remainingSec):toBe(10)
		end)
		it("unlimited replacement uses supplied stacks and clears the old optional fields", function()
			local prior: Timed.Entry = { remainingSec = 3, totalSec = 5, stacks = 7, tickInSec = 1 }
			local replaced = Timed.application(prior, { durationSec = 8, stacks = 2 })
			expect(replaced):toEqual({ remainingSec = 8, totalSec = 8, stacks = 2 })
			expect(prior.stacks):toBe(7)
			expect(Timed.application(prior, { durationSec = 8 }).stacks):toBeNil()
			expect(Timed.application({ remainingSec = 1, totalSec = 1 }, { durationSec = 8, stackLimit = 3 }).stacks):toBe(
				1
			)
		end)
		it("independent effects expire at the configured inclusive boundary", function()
			local scene = Scene.new(0.125)
			scene.apply("short", { durationSec = 1 })
			scene.apply("long", { durationSec = 2, tickInSec = 0.25 })
			local original = scene.snapshot()
			scene.advance(0.875)
			expect(scene.snapshot().short):toBeNil()
			expect(scene.snapshot().long.remainingSec):toBe(1.125)
			expect(scene.snapshot().long.tickInSec):toBe(0)
			expect(scene.clock()):toBe(0.875)
			scene.advance(2)
			expect((next(scene.snapshot()))):toBeNil()
			expect(original.short.remainingSec):toBe(1)
			expect(original.long.tickInSec):toBe(0.25)
		end)
		it("advancing a timer saturates zero and retains absent periodic ticks", function()
			local input: Timed.Entry = { remainingSec = 1, totalSec = 5, stacks = 2 }
			local advanced = Timed.advance(input, 2)
			expect(advanced):toEqual({ remainingSec = 0, totalSec = 5, stacks = 2 })
			expect(input.remainingSec):toBe(1)
			expect(Timed.expired(advanced, 0)):toBe(true)
			local remaining, tick = Timed.advanceTimes(4, 0, 0)
			expect(remaining):toBe(4)
			expect(tick):toBe(0)
		end)
		it("refresh policy resets, extends or retains the timer without changing stacks or tick phase", function()
			local input: Timed.Entry = { remainingSec = 2, totalSec = 5, stacks = 3, tickInSec = 1 }
			expect(Timed.refresh(input, 7, "reset")):toEqual({
				remainingSec = 7,
				totalSec = 7,
				stacks = 3,
				tickInSec = 1,
			})
			expect(Timed.refresh(input, 7, "extend")):toEqual({
				remainingSec = 9,
				totalSec = 12,
				stacks = 3,
				tickInSec = 1,
			})
			expect(Timed.refresh(input, 7, "keep")):toEqual(input)
			expect(input):toEqual({ remainingSec = 2, totalSec = 5, stacks = 3, tickInSec = 1 })
		end)
		it("dispel removes only the first eligible effect and independently copies survivors", function()
			local effects = {
				{ id = "protected", category = "none" },
				{ id = "first", category = "magic" },
				{ id = "second", category = "magic" },
			}
			local kept, removed = Timed.dispelFirst(effects, function(effect: { id: string, category: string }): boolean
				return effect.category == "magic"
			end, function(effect: { id: string, category: string }): { id: string, category: string }
				return table.clone(effect)
			end)
			expect(assert(removed).id):toBe("first")
			expect(kept):toEqual({ effects[1], effects[3] })
			kept[1].id = "changed"
			expect(effects[1].id):toBe("protected")
			assert(removed).id = "removed"
			expect(effects[2].id):toBe("first")
			local all, missing = Timed.dispelFirst(effects, function(_effect: { id: string, category: string }): boolean
				return false
			end, function(effect: { id: string, category: string }): { id: string, category: string }
				return table.clone(effect)
			end)
			expect(all):toEqual(effects)
			expect(missing):toBeNil()
		end)
		it("presentation timing clamps endpoints and counts both effect maps", function()
			expect(Timed.remainingFraction(20, 10, 15)):toBe(0.5)
			expect(Timed.remainingFraction(20, 10, 0)):toBe(1)
			expect(Timed.remainingFraction(20, 10, 21)):toBe(0)
			expect(Timed.remainingFraction(20, 0, 15)):toBe(0)
			expect(Timed.remainingSec(20, 21)):toBe(0)
			expect(Timed.remainingSec(20, 15)):toBe(5)
			expect(Timed.count({ first = true }, { second = 1, third = 2 })):toBe(3)
		end)
	end)
end
