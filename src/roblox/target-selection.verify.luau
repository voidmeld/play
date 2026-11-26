--!strict

local Bdd = require("@verify/src/bdd")
local Selection = require("./target-selection")
local Verify = require("@verify/src/core")

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
		it("retains the ranked order through the idle boundary and visits newcomers before repeating", function()
			local function initial(): { string }
				return { "b", "a" }
			end
			local function cached(): { string }
				error("a live cycle already owns its order")
			end
			local first = assert(Selection.nextInCycle(nil, nil, 0, 3, "ab", initial))
			local second = assert(Selection.nextInCycle(first.cycle, first.id, 3, 3, "ab", cached))
			local wrap = assert(Selection.nextInCycle(second.cycle, second.id, 4, 3, "ab", cached))
			expect({ first.id, second.id, wrap.id }):toEqual({ "b", "a", "b" })
			expect(first.cycle.visited):toEqual({ b = true })
			local function changed(): { string }
				return { "a", "c", "b" }
			end
			local added = assert(Selection.nextInCycle(wrap.cycle, wrap.id, 5, 3, "abc", changed))
			expect(added.id):toBe("c")
			expect(added.cycle.visited):toEqual({ a = true, b = true, c = true })
			local exhausted = assert(Selection.nextInCycle(added.cycle, added.id, 6, 3, "ab", initial))
			expect(exhausted.id):toBe("b")
			expect(exhausted.cycle.visited):toEqual({ b = true })
		end)
		it("reranks after idle or manual selection and skips the current first choice when possible", function()
			local function ranked(): { string }
				return { "a", "b", "c" }
			end
			local first = assert(Selection.nextInCycle(nil, "a", 0, 1, "abc", ranked))
			expect(first.id):toBe("b")
			local idle = assert(Selection.nextInCycle(first.cycle, "b", 1.1, 1, "abc", ranked))
			expect(idle.id):toBe("a")
			local manual = assert(Selection.nextInCycle(first.cycle, "c", 0.5, 1, "abc", ranked))
			expect(manual.id):toBe("a")
			local only = assert(Selection.nextInCycle(manual.cycle, "a", 1, 1, "a", function()
				return { "a" }
			end))
			expect(only.id):toBe("a")
			expect(Selection.nextInCycle(only.cycle, only.id, 2, 1, "", function()
				return {}
			end)):toBeNil()
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
					{ distance = 10, at = 0, expected = false },
					{ distance = 60, at = 100, expected = false },
					{ distance = 80, at = 101, expected = false },
					{ distance = 90, at = 106.9, expected = false },
					{ distance = 400, at = 107, expected = true },
					{ distance = 30, at = 108, expected = false },
					{ distance = 80, at = 109, expected = false },
					{ distance = 80, at = 114.9, expected = false },
					{ distance = 80, at = 115, expected = true },
				}
			do
				expect(release.observe(sample.distance, sample.at)):toBe(sample.expected)
			end
			release.reset()
			expect(release.observe(nil, 0)):toBe(false)
			expect(release.observe(nil, 6)):toBe(true)
			release.reset()
			expect(release.observe(nil, 7)):toBe(false)
		end)
	end)
end
