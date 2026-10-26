--!strict

local Diminishing = require("./diminishing")
local Scene = require("../../test-scene/diminishing")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local function config(): Diminishing.Config
	return {
		resetSec = 40,
		multipliers = { 1, 0.75, 0.5, 0 },
		categories = {
			alpha = {
				family = "shared",
				durationCapSec = 3,
				immunityPrice = 5,
				immunityMinSec = 10,
				immunityMaxSec = 25,
			},
			beta = {
				family = "shared",
				durationCapSec = 6,
				immunityPrice = 5,
				immunityMinSec = 10,
				immunityMaxSec = 25,
			},
			gamma = {
				family = "separate",
				durationCapSec = 5,
				immunityPrice = 0,
				immunityMinSec = 0,
				immunityMaxSec = 0,
			},
		},
	}
end

return function(suite: Verify.Harness)
	suite:case("duration steps retain a fixed reset deadline and saturate until exact expiry", function(t)
		local scene = Scene.new(config())
		local first = scene.apply("alpha", 30)
		t:expect({ first.grantedSec, first.multiplier, first.step, first.immune }):toEqual({ 3, 1, "full", false })
		scene.clock.advance(15)
		local second = scene.apply("alpha", 30)
		t:expect({ second.grantedSec, second.multiplier, second.step }):toEqual({ 2.25, 0.75, "reduced" })
		scene.clock.advance(11.25)
		t:expect(scene.apply("alpha", 30).grantedSec):toBe(1.5)
		scene.clock.advance(10)
		local fourth = scene.apply("alpha", 30)
		t:expect({ fourth.grantedSec, fourth.multiplier, fourth.step, fourth.immune }):toEqual({ 0, 0, "immune", true })
		t:expect(scene.apply("alpha", 30).dr.alpha):toEqual({ count = 5, windowExpiry = 40 })
		scene.clock.advance(3.75)
		local reset = scene.apply("alpha", 30)
		t:expect(reset.grantedSec):toBe(3)
		t:expect(reset.dr.alpha):toEqual({ count = 1, windowExpiry = 80 })
		t:expect(first.dr.alpha):toEqual({ count = 1, windowExpiry = 40 })
	end)
	suite:case(
		"family immunity blocks sibling categories without counting or extending and expires exactly",
		function(t)
			local scene = Scene.new(config())
			scene.apply("alpha", 3)
			local original = scene.snapshot()
			scene.clock.advance(14.999)
			local blocked = scene.apply("beta", 6)
			t:expect(blocked.immune):toBe(true)
			t:expect(blocked.dr):toEqual(original)
			t:expect(blocked.dr.beta):toBeNil()
			t:expect(scene.apply("gamma", 5).grantedSec):toBe(5)
			local law = Diminishing.rules(config())
			local boundary = law.apply(original, "beta", 6, 15)
			t:expect(boundary.grantedSec):toBe(6)
			t:expect(boundary.dr.shared):toEqual({ count = 2, windowExpiry = 40 })
			t:expect(boundary.dr.alpha):toEqual(original.alpha)
			t:expect(boundary.dr.beta):toEqual({ count = 1, windowExpiry = 55 })
		end
	)
	suite:case(
		"immunity pricing clamps granted duration and starts at application rather than effect expiry",
		function(t)
			local law = Diminishing.rules(config())
			t:expect(law.apply({}, "alpha", 1, 100).dr.shared.windowExpiry):toBe(110)
			t:expect(law.apply({}, "beta", 6, 100).dr.shared.windowExpiry):toBe(125)
			t:expect(law.apply({}, "alpha", 3, 100).dr.shared.windowExpiry):toBe(115)
			local zeroPrice = config()
			zeroPrice.categories.alpha.immunityPrice = 0
			t:expect(Diminishing.rules(zeroPrice).apply({}, "alpha", 1, 100).dr.shared.windowExpiry):toBe(110)
		end
	)
	suite:case("categories without immunity advance independently and owners keep isolated histories", function(t)
		local scene = Scene.new(config())
		local other = Scene.new(config())
		for _, expected in { 5, 3.75, 2.5, 0, 0 } do
			t:expect(scene.apply("gamma", 5).grantedSec):toBe(expected)
		end
		t:expect(scene.snapshot().separate):toBeNil()
		t:expect(other.apply("gamma", 5).grantedSec):toBe(5)
		local snapshot = scene.snapshot()
		snapshot.gamma.count = 0
		t:expect(scene.snapshot().gamma.count):toBe(5)
		scene.clock.advance(40)
		t:expect(scene.apply("gamma", 5).grantedSec):toBe(5)
	end)
	suite:case("unknown categories and invalid clocks preserve values with detached buckets", function(t)
		local law = Diminishing.rules(config())
		local original = law.apply({}, "alpha", 3, 0).dr
		for _, now in { math.huge, -math.huge, (math.huge - math.huge) } do
			local result = law.apply(original, "gamma", 5, now)
			t:expect(result.immune):toBe(true)
			t:expect(result.dr):toEqual(original)
			t:expect(result.dr == original):toBe(false)
			t:expect(result.dr.alpha == original.alpha):toBe(false)
		end
		t:expect(law.apply(original, "unknown", 5, 100).dr):toEqual(original)
		t:expect(Diminishing.empty()):toEqual({})
	end)
	suite:case(
		"zero or invalid requested durations still consume a category step without granting immunity",
		function(t)
			local law = Diminishing.rules(config())
			for _, duration in { 0, -1, math.huge, -math.huge, (math.huge - math.huge) } do
				local result = law.apply({}, "alpha", duration, 0)
				t:expect({ result.grantedSec, result.multiplier, result.step, result.immune })
					:toEqual({ 0, 1, "full", false })
				t:expect(result.dr.alpha):toEqual({ count = 1, windowExpiry = 40 })
				t:expect(result.dr.shared):toBeNil()
			end
		end
	)
	suite:case("captured configuration resists caller mutation and invalid policy fails at construction", function(t)
		local supplied = config()
		local law = Diminishing.rules(supplied)
		supplied.resetSec = 1
		supplied.multipliers[1] = 0
		supplied.categories.alpha.durationCapSec = 100
		t:expect(law.apply({}, "alpha", 30, 0).grantedSec):toBe(3)
		t:expect(law.apply({}, "alpha", 30, 0).dr.alpha.windowExpiry):toBe(40)
		local invalid = config()
		invalid.resetSec = 0
		t:expect((pcall(Diminishing.rules, invalid))):toBe(false)
		invalid = config()
		invalid.multipliers = {}
		t:expect((pcall(Diminishing.rules, invalid))):toBe(false)
		invalid = config()
		invalid.multipliers[2] = math.huge
		t:expect((pcall(Diminishing.rules, invalid))):toBe(false)
		invalid = config()
		invalid.categories.alpha.family = "beta"
		t:expect((pcall(Diminishing.rules, invalid))):toBe(false)
		invalid = config()
		invalid.categories.alpha.immunityMaxSec = 1
		t:expect((pcall(Diminishing.rules, invalid))):toBe(false)
	end)
end
