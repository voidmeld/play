--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./tracking")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local Policy = Module.tracking({
	statuses = {
		InProgress = true,
		Completed = true,
		ReplayInProgress = true,
		ReplayCompleted = true,
	},
})
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("quest tracking authority", function()
		it("allows accepted and completed authored progress", function()
			expect(Policy.canTrack({ status = "InProgress", step = 1 })):toBe(true)
			expect(Policy.canTrack({ status = "Completed", step = 6 })):toBe(true)
			expect(Policy.canTrack({ status = "ReplayInProgress", step = 1 })):toBe(true)
			expect(Policy.canTrack({ status = "ReplayCompleted", step = 6 })):toBe(true)
		end)

		it("refuses unavailable, turned-in, and malformed progress", function()
			expect(Policy.canTrack(nil)):toBe(false)
			expect(Policy.canTrack({})):toBe(false)
			expect(Policy.canTrack({ status = "Available" })):toBe(false)
			expect(Policy.canTrack({ status = "TurnedIn", step = 6 })):toBe(false)
			expect(Policy.canTrack({ status = "ReplayTurnedIn", step = 6 })):toBe(false)
		end)
	end)
	it("accepts only configured statuses", function()
		local law = Module.tracking({ statuses = { Active = true, Disabled = false } })
		expect(law.canTrack({ status = "Active" })):toBe(true)
		expect(law.canTrack({ status = "InProgress" })):toBe(false)
		expect(law.canTrack({ status = "Disabled" })):toBe(false)
		expect(law.canTrack({ status = {} })):toBe(false)
	end)
end
