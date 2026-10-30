--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Ranks = require("./talent-ranks")
local Talents = require("./talents")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type NamedNode = Ranks.Node & { label: string }
type NamedSpec = {
	class: string,
	lines: { { id: string, label: string } },
	tiers: { Ranks.Tier },
	nodes: { NamedNode },
}

local spec: NamedSpec = {
	class = "role",
	lines = { { id = "a", label = "First" }, { id = "b", label = "Second" } },
	tiers = { { tier = 1, gate = 0, costPerRank = 1 }, { tier = 2, gate = 5, costPerRank = 2 } },
	nodes = {
		{ id = "first", lineId = "a", tier = 1, ranks = 4, label = "First" },
		{ id = "second", lineId = "a", tier = 1, ranks = 4, label = "Second" },
		{ id = "upper", lineId = "a", tier = 2, ranks = 2, label = "Upper" },
		{ id = "other", lineId = "b", tier = 1, ranks = 4, label = "Other" },
	},
}
local specs: { NamedSpec } = { spec }

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("ranked talent spending", function()
		it("uses enriched game specifications without copying or changing them", function()
			local initial: Talents.Loadout = { roles = {} }
			local spent = Ranks.addRank(initial, specs, "role", 1, "first")
			expect(spent.ok):toBe(true)
			expect(initial.roles.role):toBeNil()
			expect(Ranks.spentPoints(spent.state, specs, "role")):toBe(1)
			expect(Ranks.rankRefusal(spent.state, specs, "role", 1, "first")):toBe(Ranks.NO_POINTS)
			expect(spec.nodes[1].ranks):toBe(4)
		end)
		it("requires five points in the same lower line and charges the upper rank cost", function()
			local split: Talents.Loadout = {
				roles = { role = { ranks = { first = 4, other = 1 }, respecCount = 0 } },
			}
			expect(Ranks.rankRefusal(split, specs, "role", 10, "upper")):toBe(Ranks.TIER_LOCKED)
			local lower = Ranks.addRank(split, specs, "role", 10, "second")
			expect(lower.ok):toBe(true)
			local upper = Ranks.addRank(lower.state, specs, "role", 10, "upper")
			expect(upper.ok):toBe(true)
			expect(Ranks.spentPoints(upper.state, specs, "role")):toBe(8)
			expect(Ranks.availablePoints(upper.state, specs, "role", 10)):toBe(2)
			expect(Ranks.rankRefusal(upper.state, specs, "role", 10, "first")):toBe(Ranks.FULL_RANK)
		end)
		it("rejects malformed stored ranks and budgets", function()
			for _, ranks in
				{
					{ missing = 1 },
					{ first = 0 },
					{ first = 1.5 },
					{ first = math.nan },
					{ first = 5 },
					{ upper = 1 },
					{ first = 4, second = 4 },
				}
			do
				expect(Ranks.stateProblem(spec, { ranks = ranks, respecCount = 0 }, 7)):toBe(Ranks.INVALID_STATE)
			end
			for _, points in { -1, 0.5, math.huge, math.nan } do
				expect(Ranks.stateProblem(spec, { ranks = {}, respecCount = 0 }, points)):toBe(Ranks.INVALID_STATE)
			end
		end)
		it("detaches rejected results and resets only the selected role", function()
			local original: Talents.Loadout = {
				roles = {
					role = { ranks = { first = 4 }, respecCount = 2 },
					other = { ranks = { other = 2 }, respecCount = 1 },
				},
			}
			local refused = Ranks.addRank(original, specs, "role", 10, "missing")
			expect(refused.reason):toBe(Ranks.UNKNOWN_TALENT)
			refused.state.roles.role.ranks.first = 1
			expect(original.roles.role.ranks.first):toBe(4)
			local reset = Ranks.respecRole(original, specs, "role")
			expect(reset.ok):toBe(true)
			expect(reset.state.roles.role):toEqual({ ranks = {}, respecCount = 3 })
			expect(reset.state.roles.other):toEqual(original.roles.other)
			reset.state.roles.other.ranks.other = 1
			expect(original.roles.other.ranks.other):toBe(2)
			expect(Ranks.respecRole(original, specs, "missing").reason):toBe("unknown role")
			expect(Ranks.respecRole(original, { spec, spec }, "role").reason):toBe("ambiguous role")
		end)
	end)
end
