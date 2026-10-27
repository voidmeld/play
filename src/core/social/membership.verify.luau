--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Membership = require("./membership")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local Core = Membership.membership({
	maxMembers = 3,
	minimumPartyMembers = 2,
	disconnectGraceSec = 30,
	leaderSuccessionSec = 10,
	leaderTransferTtlSec = 5,
	inviteTtlSec = 10,
	maxText = 128,
	maxAt = 100000,
	realms = { realm = true, other = true },
	defaultLootMode = "need_greed",
})
local function open(): Membership.State
	local result =
		assert(Core.open({ partyId = "party", realmId = "realm", founderId = "a", founderCharacterId = "ca", at = 0 }))
	return result.state
end
local function invite(state: Membership.State, accountId: string, at: number): Membership.State
	local result = assert(
		Core.invite(
			state,
			{ accountId = accountId, invitedBy = "a", targetRealmId = "realm", targetGrouped = false, at = at }
		)
	)
	return result.state
end
local function accept(state: Membership.State, accountId: string, at: number): Membership.State
	local result = assert(
		Core.accept(state, { accountId = accountId, characterId = "c" .. accountId, accepterGrouped = false, at = at })
	)
	return result.state
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("party membership", function()
		it("reserves invitation capacity and admits only the named same-realm recipient", function()
			local state = invite(invite(open(), "b", 1), "c", 1)
			local denied, reason = Core.invite(
				state,
				{ accountId = "d", invitedBy = "a", targetRealmId = "realm", targetGrouped = false, at = 2 }
			)
			expect(denied):toBeNil()
			expect(reason):toBe("party_full")
			state = accept(state, "b", 2)
			expect(#state.members):toBe(2)
			expect(#state.invites):toBe(1)
			local unauthorized = Core.invite(
				state,
				{ accountId = "d", invitedBy = "b", targetRealmId = "realm", targetGrouped = false, at = 3 }
			)
			expect(unauthorized):toBeNil()
			local outside, outsideReason = Core.invite(
				open(),
				{ accountId = "b", invitedBy = "a", targetRealmId = "other", targetGrouped = false, at = 1 }
			)
			expect(outside):toBeNil()
			expect(outsideReason):toBe("realm_mismatch")
		end)
		it(
			"keeps the absent seat while transferring leadership and does not restore an old leader on return",
			function()
				local state = accept(invite(open(), "b", 1), "b", 2)
				local absent = assert(Core.markAbsent(state, { accountId = "a", at = 3 }))
				local repeated = assert(Core.markAbsent(absent.state, { accountId = "a", at = 7 }))
				expect(repeated.state.members[1].absentSince):toBe(3)
				local swept = assert(Core.sweep(repeated.state, { at = 13 }))
				expect(swept.state.leaderId):toBe("b")
				expect(#swept.state.members):toBe(2)
				local returned = assert(Core.markPresent(swept.state, { accountId = "a", characterId = "ca", at = 14 }))
				expect(returned.state.leaderId):toBe("b")
				local regressed, reason = Core.sweep(returned.state, { at = 12 })
				expect(regressed):toBeNil()
				expect(reason):toBe("time_regressed")
			end
		)
		it("requires the transfer recipient and preserves a disband tombstone against late intents", function()
			local state = accept(invite(open(), "b", 1), "b", 2)
			local proposed = assert(Core.transferLeader(state, { accountId = "b", by = "a", at = 3 }))
			local wrong = Core.acceptLeaderTransfer(proposed.state, { accountId = "a", at = 4 })
			expect(wrong):toBeNil()
			local accepted = assert(Core.acceptLeaderTransfer(proposed.state, { accountId = "b", at = 4 }))
			expect(accepted.state.leaderId):toBe("b")
			local left = assert(Core.leave(accepted.state, { accountId = "b", at = 5 }))
			expect(left.state.disbandedAt):toBe(5)
			local late, reason = Core.accept(left.state, { accountId = "b", accepterGrouped = false, at = 6 })
			expect(late):toBeNil()
			expect(reason):toBe("party_disbanded")
		end)
	end)
end
