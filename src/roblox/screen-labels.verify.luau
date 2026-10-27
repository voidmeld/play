--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Labels = require("./screen-labels")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local policy =
		Labels.create({ maximum = 8, farDistance = 20, farCount = 2, focusPriority = 2, defaultPriority = 0 })
	describe("screen labels", function()
		it("hides conflicting labels without displacing their anchors", function()
			local first: Labels.ScreenPlate = { id = "first", distanceStuds = 10, rect = Labels.rect(76, 312, 220, 45) }
			local second: Labels.ScreenPlate =
				{ id = "second", distanceStuds = 11, rect = Labels.rect(94, 320, 220, 45) }
			local together = policy.placementForScreen({ first, second })
			expect(together.first.collapsed):toBe(false)
			expect(together.second.collapsed):toBe(true)
			expect(together.first.rect):toEqual(first.rect)
			expect(together.second.rect):toEqual(second.rect)
			second.rect = Labels.rect(600, 320, 220, 45)
			expect(policy.placementForScreen({ first, second }).second.collapsed):toBe(false)
		end)
		it("yields to HUD reserves and topbar and never mutates the reserve list", function()
			local reserve = { Labels.rect(12, 70, 208, 208) }
			local plates: { Labels.ScreenPlate } = {
				{ id = "near", distanceStuds = 30, rect = Labels.rect(120, 315, 160, 69) },
				{ id = "blocked", distanceStuds = 39, rect = Labels.rect(166, 265, 150, 28) },
				{ id = "top", distanceStuds = 5, rect = Labels.rect(400, 40, 160, 69) },
			}
			local placed = policy.placementForScreen(plates, reserve, 74)
			expect(placed.near.collapsed):toBe(false)
			expect(placed.blocked.collapsed):toBe(true)
			expect(placed.top.collapsed):toBe(true)
			expect(#reserve):toBe(1)
		end)
		it("moves floating text by the shorter horizontal escape and leaves separated rectangles alone", function()
			local band = Labels.rect(20, 20, 40, 40)
			expect(Labels.horizontalAvoidance(Labels.rect(10, 30, 20, 20), band, 8)):toBe(-18)
			expect(Labels.horizontalAvoidance(Labels.rect(50, 30, 20, 20), band, 8)):toBe(18)
			expect(Labels.horizontalAvoidance(Labels.rect(80, 30, 20, 20), band, 8)):toBe(0)
		end)
	end)
end
