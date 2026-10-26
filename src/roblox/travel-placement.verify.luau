--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Clock = require("../test-scene/clock")
local Travel = require("./travel-placement")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("travel placement", function()
		it("occupied arrival selects the first clear supported floor before committing", function()
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
			expect(result):toBe(3)
			expect(commits):toEqual({ 3 })
			expect(clock.clock()):toBe(0)
		end)
		it("entrance skips occupancy and uses far ray only after a near miss", function()
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
			expect(result):toBe(12)
			expect(farCalls):toEqual({ 1, 2 })
		end)
	end)
end
