--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Motion = require("./npc-motion")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("NPC motion", function()
		it("limits planar movement, preserves elevation and admits the leash edge", function()
			local movement = Motion.movement(1e-6)
			local origin: Motion.Point = { x = 0, y = 7, z = 0 }
			local target: Motion.Point = { x = 3, y = 99, z = 4 }
			expect(movement.moveToward(origin, target, 2.5)):toEqual({ x = 1.5, y = 7, z = 2 })
			expect(movement.moveToward(origin, target, 0)):toEqual(origin)
			expect(movement.moveToward(origin, target, 10)):toEqual({ x = 3, y = 7, z = 4 })
			expect(movement.insideLeash(origin, 5, target)):toBe(true)
			expect(movement.insideLeash(origin, 4, target)):toBe(false)
			expect(movement.insideLeash(nil, nil, target)):toBe(true)
		end)
		it("reapplies an externally displaced body even when its cached projection is unchanged", function()
			local projection = Motion.projection({ epsilon = 1e-4, facingEpsilon = 0.01, minimumDt = 0.001 })
			local observed = { position = { x = 0, z = 0 }, facing = { x = 0, z = -1 } }
			local first = projection.plan(nil, observed, { x = 0, z = 0 }, nil, 0.1)
			local _, unchanged = projection.plan(first, observed, first.position, nil, 0.1)
			expect(unchanged.transform):toBe(false)
			observed.position.x = 2
			local _, displaced = projection.plan(first, observed, first.position, nil, 0.1)
			expect(displaced.transform):toBe(true)
			expect(projection.groundedPivotY(20, 2, 0.5, 1)):toBe(23.5)
			expect(projection.anchoredSurfaceY(4, 2)):toBe(4)
		end)
	end)
end
