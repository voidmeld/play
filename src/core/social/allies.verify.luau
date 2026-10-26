--!strict

local Module = require("./allies")
local Shape = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local current: Verify.Context? = nil
	local function expect(value: unknown): Verify.Expectation
		return assert(current):expect(value)
	end
	local function it(name: string, body: () -> ())
		suite:case(name, function(context)
			current = context
			body()
		end)
	end
	local function describe(_name: string, body: () -> ())
		body()
	end
	local settings = {
		retentionSec = 30 * 24 * 60 * 60,
		maxAllies = 12,
		maxRevision = 1000000000,
		maxTime = 1000000000000,
		qualificationKinds = {
			shared_objective_contribution = true,
			expedition_clear_contribution = true,
			watch_contribution = true,
		},
		maxId = 128,
		maxFingerprint = 1024,
	}
	local Core = Module.allies(settings)
	describe("allies", function()
		local function policy(): Module.Policy
			return {
				revision = 1,
				ownerOptedOut = false,
				ownerModerationEligible = true,
				blockedUserIds = {},
				optedOutUserIds = {},
				moderationDeniedUserIds = {},
			}
		end

		local function qualify(
			state: Module.State,
			allyUserId: number,
			rules: Module.Policy,
			authority: Module.Authority
		): Module.Result
			return Core.transition(state, {
				kind = "qualify",
				eventId = "qualify:" .. allyUserId,
				expectedRevision = state.revision,
				allyUserId = allyUserId,
				qualificationKind = "shared_objective_contribution",
				qualificationReceiptId = "receipt:" .. allyUserId,
			}, 100, rules, authority)
		end

		it("combines every denial category without mutating the stored allies", function()
			local state = assert(Core.emptyState(1))
			local rules = policy()
			local authority: Module.Authority = {
				validate = function(): boolean
					return true
				end,
			}
			for userId = 2, 4 do
				state = assert(qualify(state, userId, rules, authority).state)
			end
			rules.blockedUserIds = { 2, 6 }
			rules.optedOutUserIds = { 3, 6 }
			rules.moderationDeniedUserIds = { 4, 6 }
			expect((#assert(Core.projectPrivate(state, rules, 1, 100)))):toBe(0)
			expect(#state.entries):toBe(3)
			expect(qualify(state, 6, rules, authority).reason):toBe("privacy_denied")
		end)

		it("requires each policy list to contain sorted unique positive user identities", function()
			local state = assert(Core.emptyState(1))
			local invalidLists: { unknown } = {
				{ 2, 2 },
				{ 3, 2 },
				{ [1] = 2, [3] = 3 },
				{ 0 },
				{ 1.5 },
				{ math.huge },
				{ "2" },
				false,
			}
			for _, field in { "blockedUserIds", "optedOutUserIds", "moderationDeniedUserIds" } do
				for _, invalid in invalidLists do
					local raw = assert(Shape.raw(policy()))
					raw[field] = invalid
					local result = Core.transition(state, {
						kind = "reconcile",
						eventId = "reconcile",
						expectedRevision = 0,
					}, 100, raw, nil)
					expect(result.reason):toBe("invalid_policy")
					expect((Core.projectPrivate(state, raw, 1, 100))):toBe(nil)
				end
			end
		end)

		it("snapshots policy eligibility before consulting qualification authority", function()
			local rules = policy()
			local result = qualify(assert(Core.emptyState(1)), 2, rules, {
				validate = function(): boolean
					rules.revision = 99
					rules.ownerOptedOut = true
					rules.ownerModerationEligible = false
					table.insert(rules.blockedUserIds, 2)
					return true
				end,
			})
			expect(result.ok):toBe(true)
			local state = assert(result.state)
			expect(state.policyRevision):toBe(1)
			expect(#state.entries):toBe(1)
			expect(state.entries[1].allyUserId):toBe(2)
		end)

		it("refreshes an existing ally without duplicating it or changing the prior state", function()
			local rules = policy()
			local authority: Module.Authority = {
				validate = function(): boolean
					return true
				end,
			}
			local first = assert(qualify(assert(Core.emptyState(1)), 2, rules, authority).state)
			local prior = assert(qualify(first, 3, rules, authority).state)
			local result = Core.transition(prior, {
				kind = "qualify",
				eventId = "refresh:3",
				expectedRevision = prior.revision,
				allyUserId = 3,
				qualificationKind = "expedition_clear_contribution",
				qualificationReceiptId = "expedition:3",
			}, 101, rules, authority)
			expect(result.ok):toBe(true)
			local state = assert(result.state)
			expect(#state.entries):toBe(2)
			expect(state.entries[1]):toEqual({
				allyUserId = 3,
				qualificationKind = "expedition_clear_contribution",
				qualificationReceiptId = "expedition:3",
				lastQualifiedAtSec = 101,
				expiresAtSec = 101 + Core.RETENTION_SEC,
			})
			expect(state.entries[2].allyUserId):toBe(2)
			expect(prior.entries[2].allyUserId):toBe(3)
			expect(prior.entries[2].lastQualifiedAtSec):toBe(100)
		end)
		it("uses configured qualification kinds, retention, capacity and projection bounds", function()
			local cfg: Module.Config = table.clone(settings)
			cfg.qualificationKinds, cfg.retentionSec, cfg.maxAllies = { helped = true }, 2, 1
			local core = Module.allies(cfg)
			local auth: Module.Authority = {
				validate = function(
					_receipt: string,
					_kind: string,
					_owner: number,
					_ally: number,
					_now: number
				): unknown
					return true
				end,
			}
			local initial = assert(core.emptyState(1))
			local state = assert(core.transition(initial, {
				kind = "qualify",
				eventId = "q",
				expectedRevision = 0,
				allyUserId = 2,
				qualificationKind = "helped",
				qualificationReceiptId = "r",
			}, 1, policy(), auth).state)
			expect(state.entries[1].expiresAtSec):toBe(3)
			state = assert(core.transition(state, {
				kind = "qualify",
				eventId = "q2",
				expectedRevision = 1,
				allyUserId = 3,
				qualificationKind = "helped",
				qualificationReceiptId = "r2",
			}, 2, policy(), auth).state)
			expect(#state.entries):toBe(1)
			expect(state.entries[1].allyUserId):toBe(3)
			local changes: { (Module.Config) -> () } = {
				function(value)
					value.maxAllies = 0
				end,
				function(value)
					value.maxRevision = 1
				end,
				function(value)
					value.maxTime = 1
				end,
				function(value)
					value.maxId = 1
				end,
				function(value)
					value.maxFingerprint = 1
				end,
			}
			for _, change in changes do
				local bounded: Module.Config = table.clone(cfg)
				change(bounded)
				expect(Module.allies(bounded).projectState(state)):toBeNil()
			end
		end)
	end)
end
