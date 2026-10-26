--!strict

local Scene = require("../../test-scene/effects")
local Timed = require("./timed")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	suite:case("applications increment to the authored cap and reset duration and tick phase", function(t)
		local scene = Scene.new(1e-6)
		local application: Timed.Application = { durationSec = 10, stackLimit = 3, tickInSec = 2 }
		scene.apply("effect", application)
		local original = scene.snapshot()
		t:expect(original.effect.stacks):toBe(1)
		scene.advance(1)
		t:expect(scene.snapshot().effect.remainingSec):toBe(9)
		t:expect(scene.snapshot().effect.tickInSec):toBe(1)
		for _ = 1, 4 do
			scene.apply("effect", application)
		end
		t:expect(scene.snapshot().effect):toEqual({ remainingSec = 10, totalSec = 10, stacks = 3, tickInSec = 2 })
		t:expect(original.effect.stacks):toBe(1)
		t:expect(original.effect.remainingSec):toBe(10)
	end)
	suite:case("unlimited replacement uses supplied stacks and clears the old optional fields", function(t)
		local prior: Timed.Entry = { remainingSec = 3, totalSec = 5, stacks = 7, tickInSec = 1 }
		local replaced = Timed.application(prior, { durationSec = 8, stacks = 2 })
		t:expect(replaced):toEqual({ remainingSec = 8, totalSec = 8, stacks = 2 })
		t:expect(prior.stacks):toBe(7)
		t:expect(Timed.application(prior, { durationSec = 8 }).stacks):toBeNil()
		t:expect(Timed.application({ remainingSec = 1, totalSec = 1 }, { durationSec = 8, stackLimit = 3 }).stacks)
			:toBe(1)
	end)
	suite:case("independent effects expire at the configured inclusive boundary", function(t)
		local scene = Scene.new(0.125)
		scene.apply("short", { durationSec = 1 })
		scene.apply("long", { durationSec = 2, tickInSec = 0.25 })
		local original = scene.snapshot()
		scene.advance(0.875)
		t:expect(scene.snapshot().short):toBeNil()
		t:expect(scene.snapshot().long.remainingSec):toBe(1.125)
		t:expect(scene.snapshot().long.tickInSec):toBe(0)
		t:expect(scene.clock()):toBe(0.875)
		scene.advance(2)
		t:expect((next(scene.snapshot()))):toBeNil()
		t:expect(original.short.remainingSec):toBe(1)
		t:expect(original.long.tickInSec):toBe(0.25)
	end)
	suite:case("advancing a timer saturates zero and retains absent periodic ticks", function(t)
		local input: Timed.Entry = { remainingSec = 1, totalSec = 5, stacks = 2 }
		local advanced = Timed.advance(input, 2)
		t:expect(advanced):toEqual({ remainingSec = 0, totalSec = 5, stacks = 2 })
		t:expect(input.remainingSec):toBe(1)
		t:expect(Timed.expired(advanced, 0)):toBe(true)
		local remaining, tick = Timed.advanceTimes(4, 0, 0)
		t:expect(remaining):toBe(4)
		t:expect(tick):toBe(0)
	end)
	suite:case("refresh policy resets, extends or retains the timer without changing stacks or tick phase", function(t)
		local input: Timed.Entry = { remainingSec = 2, totalSec = 5, stacks = 3, tickInSec = 1 }
		t:expect(Timed.refresh(input, 7, "reset"))
			:toEqual({ remainingSec = 7, totalSec = 7, stacks = 3, tickInSec = 1 })
		t:expect(Timed.refresh(input, 7, "extend"))
			:toEqual({ remainingSec = 9, totalSec = 12, stacks = 3, tickInSec = 1 })
		t:expect(Timed.refresh(input, 7, "keep")):toEqual(input)
		t:expect(input):toEqual({ remainingSec = 2, totalSec = 5, stacks = 3, tickInSec = 1 })
	end)
	suite:case("dispel removes only the first eligible effect and independently copies survivors", function(t)
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
		t:expect(assert(removed).id):toBe("first")
		t:expect(kept):toEqual({ effects[1], effects[3] })
		kept[1].id = "changed"
		t:expect(effects[1].id):toBe("protected")
		assert(removed).id = "removed"
		t:expect(effects[2].id):toBe("first")
		local all, missing = Timed.dispelFirst(effects, function(_effect: { id: string, category: string }): boolean
			return false
		end, function(effect: { id: string, category: string }): { id: string, category: string }
			return table.clone(effect)
		end)
		t:expect(all):toEqual(effects)
		t:expect(missing):toBeNil()
	end)
	suite:case("presentation timing clamps endpoints and counts both effect maps", function(t)
		t:expect(Timed.remainingFraction(20, 10, 15)):toBe(0.5)
		t:expect(Timed.remainingFraction(20, 10, 0)):toBe(1)
		t:expect(Timed.remainingFraction(20, 10, 21)):toBe(0)
		t:expect(Timed.remainingFraction(20, 0, 15)):toBe(0)
		t:expect(Timed.remainingSec(20, 21)):toBe(0)
		t:expect(Timed.remainingSec(20, 15)):toBe(5)
		t:expect(Timed.count({ first = true }, { second = 1, third = 2 })):toBe(3)
	end)
end
