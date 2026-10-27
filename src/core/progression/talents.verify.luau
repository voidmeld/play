--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Talents = require("./talents")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type Runtime = { classId: string, limit: number }
local Core = Talents.rules(function(runtime: Runtime): string
	return runtime.classId
end, function(loadout: Talents.Loadout, classId: string, level: number, runtime: Runtime): (number?, string?)
	local total = 0
	for id, rank in loadout.roles[classId].ranks do
		if id ~= "node" or rank > runtime.limit then
			return nil, "invalid_talent_state"
		end
		total += rank
	end
	return if total <= level then total else nil, "invalid_talent_state"
end)
local runtime: Runtime = { classId = "role", limit = 2 }

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("talent state", function()
		it("loads valid detached ranks and refunds invalid saves only with a valid runtime", function()
			local saved = { classId = "role", revision = 3, ranks = { node = 1 }, respecCount = 2 }
			local state, reason, compiled = Core.normalize(saved, "role", 1, runtime)
			expect(reason):toBeNil()
			expect(compiled):toBe(1)
			assert(state)
			state.ranks.node = 2
			expect(saved.ranks.node):toBe(1)
			for _, bad in
				{
					false,
					{ classId = "role", revision = 0, ranks = { node = 3 }, respecCount = 0 },
					setmetatable(saved, {}),
				}
			do
				expect((Core.normalize(bad, "role", 1, runtime))):toBeNil()
				expect((Core.load(bad, "role", 1, runtime))):toEqual(Talents.default("role"))
			end
			expect((Core.load(false, "role", 1, nil))):toBeNil()
			expect((Core.load(false, "other", 1, runtime))):toBeNil()
		end)
		it("rejects malformed shapes, identities, ranks and nonfinite persisted counts", function()
			local valid = Talents.default("role")
			for _, key in { "revision", "respecCount" } do
				for _, count in { -1, 0.5, math.huge, math.nan } do
					local raw: { [string]: unknown } = {
						classId = valid.classId,
						revision = valid.revision,
						ranks = valid.ranks,
						respecCount = valid.respecCount,
					}
					raw[key] = count
					expect((Core.normalize(raw, "role", 2, runtime))):toBeNil()
				end
			end
			for _, ranks in { { node = 0 }, { node = -1 }, { node = math.huge }, setmetatable({}, {}), { [1] = 1 } } do
				local raw: { [string]: unknown } = {
					classId = valid.classId,
					revision = valid.revision,
					ranks = valid.ranks,
					respecCount = valid.respecCount,
				}
				raw.ranks = ranks
				expect((Core.normalize(raw, "role", 2, runtime))):toBeNil()
			end
			expect(
				(
					Core.normalize(
						{ classId = "role", revision = 0, ranks = {}, respecCount = 0, extra = true },
						"role",
						2,
						runtime
					)
				)
			):toBeNil()
		end)
		it("decodes exact plain requests and preserves the existing revision wire bound", function()
			local hostile = setmetatable({ kind = "view" }, {
				__iter = function()
					error("untrusted iterator ran")
				end,
			})
			expect((Talents.decodeIntent(hostile))):toBeNil()
			expect(
				(
					Core.normalize(
						{ classId = "role", revision = 0, ranks = hostile, respecCount = 0 },
						"role",
						1,
						runtime
					)
				)
			):toBeNil()
			for _, bad in
				{
					false,
					{},
					{ kind = "view", extra = true },
					setmetatable({ kind = "view" }, {}),
					{ kind = "select", revision = 0, talentId = "" },
					{ kind = "respec", revision = -1 },
					{ kind = "respec", revision = math.nan },
					{ kind = "select", revision = 0, talentId = string.rep("x", 129) },
				}
			do
				local intent, reason = Talents.decodeIntent(bad)
				expect(intent):toBeNil()
				expect(reason):toBe("invalid_intent")
			end
			for _, good in
				{
					{ kind = "view" },
					{ kind = "respec", revision = math.huge },
					{ kind = "select", revision = 0, talentId = string.rep("x", 128) },
				}
			do
				expect((Talents.decodeIntent(good))):toEqual(good)
			end
		end)
		it("spends once, rejects stale replay, gates respec and leaves the input unchanged", function()
			local calls = 0
			local function advance(loadout: Talents.Loadout, intent: Talents.Intent): Talents.Result
				calls += 1
				local bucket = loadout.roles.role
				if intent.kind == "select" then
					if intent.talentId ~= "node" then
						return { ok = false, state = loadout, reason = "unknown talent" }
					end
					bucket.ranks.node = (bucket.ranks.node or 0) + 1
				else
					bucket.ranks = {}
					bucket.respecCount += 1
				end
				return { ok = true, state = loadout }
			end
			local initial = Talents.default("role")
			local spent =
				assert(Talents.change(initial, { kind = "select", revision = 0, talentId = "node" }, nil, advance))
			expect(initial.ranks):toEqual({})
			expect(spent.ranks.node):toBe(1)
			local stale, staleReason =
				Talents.change(spent, { kind = "select", revision = 0, talentId = "node" }, nil, advance)
			expect(stale):toBeNil()
			expect(staleReason):toBe("stale_projection")
			local refused, reason = Talents.change(spent, { kind = "respec", revision = 1 }, "in_combat", advance)
			expect(refused):toBeNil()
			expect(reason):toBe("in_combat")
			expect(calls):toBe(1)
			local invalid, invalidReason =
				Talents.change(spent, { kind = "select", revision = 1, talentId = "absent" }, nil, advance)
			expect(invalid):toBeNil()
			expect(invalidReason):toBe("unknown talent")
			local reset = assert(Talents.change(spent, { kind = "respec", revision = 1 }, true, advance))
			expect(reset):toEqual({ classId = "role", revision = 2, ranks = {}, respecCount = 1 })
			expect(spent.ranks.node):toBe(1)
			expect((Talents.change(reset, { kind = "view" }, nil, advance))):toBe(reset)
		end)
	end)
end
