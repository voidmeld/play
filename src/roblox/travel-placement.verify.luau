--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Engine = require("../../tools/fixtures/engine")
local Travel = require("./travel-placement")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("travel placement", function()
		it("rejects invalid search counts before invoking native placement observations", function()
			for _, count in { -1, 0.5, math.nan, math.huge, -math.huge, 4503599627370496 } do
				local calls = 0
				local function reached(): never
					calls += 1
					error("invalid_count_observed", 0)
				end
				local function point(_value: number): number
					return reached()
				end
				local function clear(_value: number): boolean
					return reached()
				end
				local function ground(): number?
					return reached()
				end
				local function floor(_value: number): number?
					return reached()
				end
				local function safe(_floor: number, _ground: number): boolean
					return reached()
				end
				local function commit(_frame: number)
					reached()
				end
				local placement: Travel.PlacementHost<number, number> = {
					count = count,
					candidate = point,
					clear = clear,
					ground = ground,
					floor = floor,
					safe = safe,
					commit = commit,
				}
				local entrance: Travel.EntranceHost<number, number, number> = {
					count = count,
					point = point,
					clear = clear,
					near = floor,
					far = floor,
					safe = clear,
					frame = point,
				}
				expect(Travel.place(placement)):toBe(nil)
				expect(Travel.entrance(entrance)):toBe(nil)
				expect(calls):toBe(0)
			end
		end)
		it("exhausts a configured search without committing an occupied destination", function()
			local visits: { number } = {}
			local commits = 0
			local function candidate(index: number): number
				table.insert(visits, index)
				return index
			end
			local placement: Travel.PlacementHost<number, number>
			placement = {
				count = 1,
				candidate = candidate,
				clear = function(_frame: number): boolean
					return false
				end,
				ground = function(): number?
					placement.count = 2
					return nil
				end,
				floor = function(_frame: number): number?
					return nil
				end,
				safe = function(_floor: number, _ground: number): boolean
					return false
				end,
				commit = function(_frame: number)
					commits += 1
				end,
			}
			expect(Travel.place(placement)):toBe(nil)
			expect(visits):toEqual({ 0, 1, 2 })
			expect(commits):toBe(0)
			visits = {}
			expect(Travel.entrance({
				count = 1,
				point = candidate,
				clear = function(_point: number): boolean
					return false
				end,
				near = function(_point: number): number?
					return nil
				end,
				far = function(_point: number): number?
					return nil
				end,
				safe = function(_floor: number): boolean
					return false
				end,
				frame = function(floor: number): number
					return floor
				end,
			})):toBe(nil)
			expect(visits):toEqual({ 0, 1, 2 })
		end)
		it("occupied arrival selects the first clear supported floor before committing", function()
			local clock = Engine.clock()
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
