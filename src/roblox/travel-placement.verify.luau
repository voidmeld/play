--!strict

local Clock = require("../test-scene/clock")
local Travel = require("./travel-placement")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	suite:case("occupied arrival selects the first clear supported floor before committing", function(t)
		local clock = Clock.new()
		local commits: { number } = {}
		local result = Travel.place({
			count = 2,
			candidate = function(index: number): number
				return index
			end,
			clear = function(frame: number): boolean
				return frame > 0
			end,
			ground = function(): number?
				return 3
			end,
			floor = function(frame: number): number?
				return if frame == 1 then nil else frame
			end,
			safe = function(floor: number, ground: number): boolean
				return floor == ground
			end,
			commit = function(frame: number)
				table.insert(commits, frame)
			end,
		})
		t:expect(result):toBe(3)
		t:expect(commits):toEqual({ 3 })
		t:expect(clock.clock()):toBe(0)
	end)
	suite:case("entrance skips occupancy and uses far ray only after a near miss", function(t)
		local farCalls: { number } = {}
		local result = Travel.entrance({
			count = 2,
			point = function(index: number): number
				return index
			end,
			clear = function(point: number): boolean
				return point > 0
			end,
			near = function(_point: number): number?
				return nil
			end,
			far = function(point: number): number?
				table.insert(farCalls, point)
				return point
			end,
			safe = function(floor: number): boolean
				return floor == 2
			end,
			frame = function(floor: number): number
				return floor + 10
			end,
		})
		t:expect(result):toBe(12)
		t:expect(farCalls):toEqual({ 1, 2 })
	end)
end
