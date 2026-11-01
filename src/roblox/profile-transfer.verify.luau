--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Transfer = require("./profile-transfer")
local Verify = require("../../.lute/dependencies/verify/src/core")

local function identity(overrides: { leaseRevision: number?, sessionId: string? }): Transfer.Identity
	return {
		userId = 7,
		characterId = "c1",
		key = "k1",
		sessionId = overrides.sessionId or "s1",
		acquisitionId = "a1",
		leaseRevision = overrides.leaseRevision or 1,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("profile transfer", function()
		it("matches a session only when every lease field agrees", function()
			expect(Transfer.sameSession(identity({}), identity({}))):toBe(true)
			expect(Transfer.sameSession(identity({}), identity({ leaseRevision = 2 }))):toBe(false)
			expect(Transfer.sameSession(identity({}), identity({ sessionId = "s2" }))):toBe(false)
			expect(Transfer.sameSession(identity({}), nil)):toBe(false)
			expect(Transfer.sameSession(nil, nil)):toBe(false)
		end)

		it("reads the profile and its context, or neither", function()
			local profile = { gold = 3 }
			local reader = {
				profile = function(_context: Transfer.Identity)
					return {
						peek = function(): { gold: number }?
							return profile
						end,
					}
				end,
			}
			local found, context = Transfer.profileFor(reader, function(_userId: number): Transfer.Identity?
				return identity({})
			end, 7)
			expect(found == profile):toBe(true)
			expect(context ~= nil):toBe(true)
			local missing, none = Transfer.profileFor(reader, function(_userId: number): Transfer.Identity?
				return nil
			end, 7)
			expect(missing == nil):toBe(true)
			expect(none == nil):toBe(true)
		end)

		it("settles a write and reports a replaced session or a failed write as not durable", function()
			local current = identity({})
			local committed: Transfer.Result = { ok = true, outcome = "committed", reason = nil }
			local function contextFor(_userId: number): Transfer.Identity?
				return current
			end
			expect(Transfer.settle(contextFor, 7, identity({}), true, function(): Transfer.Result
				return committed
			end).outcome):toBe("committed")
			local replaced = Transfer.settle(
				contextFor,
				7,
				identity({ leaseRevision = 9 }),
				true,
				function(): Transfer.Result
					return committed
				end
			)
			expect(replaced.outcome):toBe("not_durable")
			expect(replaced.reason):toBe("session_replaced")
			expect(Transfer.settle(contextFor, 7, identity({ leaseRevision = 9 }), false, function(): Transfer.Result
				return committed
			end).ok):toBe(true)
			local failed = Transfer.settle(contextFor, 7, identity({}), true, function(): Transfer.Result
				error("store down")
			end)
			expect(failed.outcome):toBe("not_durable")
			expect(failed.reason):toBe("profile_unavailable")
		end)

		it("refuses a second entry for a busy key and releases the key after an error", function()
			local busy: { [number]: boolean } = {}
			local inner: string? = nil
			local outer = Transfer.exclusive(busy, 1, "busy", function(): string
				inner = Transfer.exclusive(busy, 1, "busy", function(): string
					return "ran"
				end)
				return "done"
			end)
			expect(outer):toBe("done")
			expect(inner):toBe("busy")
			expect(busy[1] == nil):toBe(true)
			local raised = pcall(Transfer.exclusive, busy, 1, "busy", function(): string
				error("boom")
			end)
			expect(raised):toBe(false)
			expect(busy[1] == nil):toBe(true)
		end)
	end)
end
