--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Selection = require("./target-selection")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("target selection", function()
		it("cycles, wraps and recovers from an absent selection", function()
			expect(Selection.pickNext({}, nil)):toBeNil()
			for _, current in { "missing", "c" } do
				expect(Selection.pickNext({ "a", "b", "c" }, current)):toBe("a")
			end
			expect(Selection.pickNext({ "a", "b" }, "a")):toBe("b")
			expect(Selection.pickNext({ "a", "b" }, nil)):toBe("a")
		end)
		it("picks the nearest screen candidate with a stable tie break and retains an exact hit", function()
			local projected = Selection.create(function(point: { x: number, y: number }): (number, number)
				return point.x, point.y
			end)
			local tap = { x = 0, y = 0 }
			local candidates =
				{ { npcId = "b", screenPos = { x = 3, y = 4 } }, { npcId = "a", screenPos = { x = -3, y = 4 } } }
			expect(projected.pickNearestToTap(tap, candidates, 5)):toBe("a")
			expect(projected.pickNearestToTap(tap, candidates, 4.9)):toBeNil()
			expect(projected.tapSelection("b", tap, candidates, 5)):toBe("b")
			expect(projected.tapSelection(nil, tap, candidates, 5)):toBe("a")
		end)
		it("keeps in-range targets and resets the full grace period on return or explicit reset", function()
			local release = Selection.release(60, 6)
			for _, sample in
				{
					{ 10, 0, false },
					{ 60, 100, false },
					{ 80, 101, false },
					{ 90, 106.9, false },
					{ 400, 107, true },
					{ 30, 108, false },
					{ 80, 109, false },
					{ 80, 114.9, false },
					{ 80, 115, true },
				}
			do
				expect(release.observe(sample[1], sample[2])):toBe(sample[3])
			end
			release.reset()
			expect(release.observe(nil, 0)):toBe(false)
			expect(release.observe(nil, 6)):toBe(true)
			release.reset()
			expect(release.observe(nil, 7)):toBe(false)
		end)
	end)
end
