--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Membership = require("./membership")
local Value = require("../../kernel/value")
type Command = { operation: (unknown, unknown) -> (Membership.Result?, string?), request: unknown }
local Verify = require("../../../.lute/dependencies/verify/src/core")

local function configured(maxMembers: number)
	return Membership.membership({
		maxMembers = maxMembers,
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
end
local Core = configured(3)
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
local function grown(members: { string }, core: Membership.Core?): Membership.State
	local system = core or Core
	local state = assert(system.open({ partyId = "party", realmId = "realm", founderId = members[1], at = 0 })).state
	for index = 2, #members do
		local id = members[index]
		state = assert(system.invite(state, {
			accountId = id,
			invitedBy = state.leaderId,
			targetRealmId = "realm",
			targetGrouped = false,
			at = index * 2,
		})).state
		state = assert(
			system.accept(
				state,
				{ accountId = id, characterId = "c" .. id, accepterGrouped = false, at = index * 2 + 1 }
			)
		).state
	end
	return state
end
local function ids(state: Membership.State): { string }
	local result = {}
	for _, member in state.members do
		table.insert(result, member.accountId)
	end
	return result
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
		it("rejects extra admission fields and acceptance without an invitation", function()
			local invalid, shape =
				Core.open({ partyId = "party", realmId = "realm", founderId = "a", at = 0, extra = true })
			expect(invalid):toBeNil()
			expect(shape):toBe("request_shape_invalid")
			local unknown, reason = Core.accept(open(), { accountId = "b", accepterGrouped = false, at = 1 })
			expect(unknown):toBeNil()
			expect(reason):toBe("invite_unknown")
		end)
		it("replays invitations and declines without duplicating a reservation", function()
			local state = invite(open(), "b", 1)
			local replay = assert(
				Core.invite(
					state,
					{ accountId = "b", invitedBy = "a", targetRealmId = "realm", targetGrouped = false, at = 2 }
				)
			)
			expect(replay.replayed):toBe(true)
			expect(replay.state):toEqual(state)
			expect(#replay.state.invites):toBe(1)
			local first = assert(Core.decline(state, { accountId = "b", at = 2 }))
			expect(first.replayed):toBe(false)
			expect(#first.state.invites):toBe(0)
			expect(assert(Core.decline(first.state, { accountId = "b", at = 3 })).replayed):toBe(true)
			expect(#state.invites):toBe(1)
		end)
		it("rechecks grouped custody and refuses invitations to self or existing members", function()
			for _, row in
				{
					{ state = open(), id = "b", grouped = true, reason = "already_grouped" },
					{ state = grown({ "a", "b" }), id = "b", grouped = false, reason = "already_member" },
					{ state = open(), id = "a", grouped = false, reason = "self_target" },
				}
			do
				local result, reason = Core.invite(row.state, {
					accountId = row.id,
					invitedBy = "a",
					targetRealmId = "realm",
					targetGrouped = row.grouped,
					at = 100,
				})
				expect(result):toBeNil()
				expect(reason):toBe(row.reason)
			end
			local result, reason =
				Core.accept(invite(open(), "b", 1), { accountId = "b", accepterGrouped = true, at = 2 })
			expect(result):toBeNil()
			expect(reason):toBe("already_grouped")
		end)
		it("preserves ordered succession and closes below the configured minimum", function()
			local state = grown({ "a", "b", "c" })
			local departed = assert(Core.leave(state, { accountId = "a", at = 100 })).state
			expect(departed.leaderId):toBe("b")
			expect(ids(departed)):toEqual({ "b", "c" })
			expect(departed.disbandedAt):toBeNil()
			local shrunk = assert(Core.leave(state, { accountId = "c", at = 100 })).state
			expect(ids(shrunk)):toEqual({ "a", "b" })
			expect(shrunk.disbandedAt):toBeNil()
			local closed = assert(Core.leave(shrunk, { accountId = "b", at = 101 })).state
			expect(closed.disbandedAt):toBe(101)
			expect(#closed.members):toBe(0)
			expect(#closed.invites):toBe(0)
			local commands: { Command } = {
				{
					operation = Core.invite,
					request = {
						accountId = "c",
						invitedBy = "a",
						targetRealmId = "realm",
						targetGrouped = false,
						at = 102,
					},
				},
				{ operation = Core.leave, request = { accountId = "a", at = 102 } },
				{ operation = Core.transferLeader, request = { accountId = "b", by = "a", at = 102 } },
			}
			for _, row in commands do
				local result, reason = row.operation(closed, row.request)
				expect(result):toBeNil()
				expect(reason):toBe("party_disbanded")
			end
			expect(ids(state)):toEqual({ "a", "b", "c" })
		end)
		it("restricts kicks and transfer offers to current non-self members", function()
			local state = grown({ "a", "b" })
			state = invite(state, "c", 100)
			for _, operation in { Core.kick, Core.transferLeader } do
				for _, row in
					{
						{ accountId = "b", by = "b", reason = "not_leader" },
						{ accountId = "a", by = "a", reason = "self_target" },
						{ accountId = "z", by = "a", reason = "not_member" },
						{ accountId = "c", by = "a", reason = "not_member" },
					}
				do
					local result, reason = operation(state, { accountId = row.accountId, by = row.by, at = 101 })
					expect(result):toBeNil()
					expect(reason):toBe(row.reason)
				end
			end
		end)
		it("transfers authority without changing the roster, reservations or loot state", function()
			local state = invite(grown({ "a", "b" }), "c", 100)
			local proposal = assert(Core.transferLeader(state, { accountId = "b", by = "a", at = 101 })).state
			expect(proposal.leaderId):toBe("a")
			expect(assert(proposal.leaderTransfer).accountId):toBe("b")
			local moved = assert(Core.acceptLeaderTransfer(proposal, { accountId = "b", at = 102 })).state
			expect(moved.leaderId):toBe("b")
			expect(moved.members):toEqual(state.members)
			expect(moved.invites):toEqual(state.invites)
			expect(moved.lootMode):toBe(state.lootMode)
			expect(moved.lootCursor):toBe(state.lootCursor)
			expect(moved.disbandedAt):toBeNil()
			local commands: { Command } = {
				{
					operation = Core.invite,
					request = {
						accountId = "c",
						invitedBy = "a",
						targetRealmId = "realm",
						targetGrouped = false,
						at = 103,
					},
				},
				{ operation = Core.kick, request = { accountId = "b", by = "a", at = 103 } },
				{ operation = Core.disband, request = { by = "a", at = 103 } },
				{ operation = Core.transferLeader, request = { accountId = "a", by = "a", at = 103 } },
				{ operation = Core.setLootMode, request = { by = "a", lootMode = "round_robin", at = 103 } },
			}
			for _, row in commands do
				local result, reason = row.operation(moved, row.request)
				expect(result):toBeNil()
				expect(reason):toBe("not_leader")
			end
			local changed = assert(Core.setLootMode(moved, { by = "b", lootMode = "round_robin", at = 103 }))
			expect(changed.state.lootMode):toBe("round_robin")
			expect(assert(Core.setLootMode(changed.state, { by = "b", lootMode = "round_robin", at = 104 })).replayed):toBe(
				true
			)
			local trio = grown({ "a", "b", "c" })
			local offer = assert(Core.transferLeader(trio, { accountId = "c", by = "a", at = 100 })).state
			local transferred = assert(Core.acceptLeaderTransfer(offer, { accountId = "c", at = 101 })).state
			local departed = assert(Core.leave(transferred, { accountId = "c", at = 102 })).state
			expect(departed.leaderId):toBe("a")
			expect(ids(departed)):toEqual({ "a", "b" })
			expect(ids(assert(Core.kick(trio, { accountId = "c", by = "a", at = 100 })).state)):toEqual({ "a", "b" })
			expect(assert(Core.disband(trio, { by = "a", at = 100 })).state.disbandedAt):toBe(100)
		end)
		it("keeps duplicate transfer deadlines fixed and invalidates offers when custody changes", function()
			local state = grown({ "a", "b", "c" })
			local offer = assert(Core.transferLeader(state, { accountId = "b", by = "a", at = 100 })).state
			local duplicate = assert(Core.transferLeader(offer, { accountId = "b", by = "a", at = 104 }))
			expect(duplicate.replayed):toBe(true)
			expect(assert(duplicate.state.leaderTransfer).at):toBe(100)
			local expired, reason = Core.acceptLeaderTransfer(duplicate.state, { accountId = "b", at = 105 })
			expect(expired):toBeNil()
			expect(reason):toBe("leader_transfer_unknown")
			for _, id in { "a", "b" } do
				expect(assert(Core.markAbsent(offer, { accountId = id, at = 101 })).state.leaderTransfer):toBeNil()
			end
			expect(assert(Core.leave(offer, { accountId = "b", at = 101 })).state.leaderTransfer):toBeNil()
			local absent = assert(Core.markAbsent(state, { accountId = "b", at = 100 })).state
			local refused, absentReason = Core.transferLeader(absent, { accountId = "b", by = "a", at = 101 })
			expect(refused):toBeNil()
			expect(absentReason):toBe("member_absent")
		end)
		it("chooses connected successors by join order and stable character identity", function()
			local system = configured(4)
			local state = assert(Value.raw(grown({ "a", "b", "c", "d" }, system)))
			state.members = {
				{ accountId = "a", characterId = "leader", joinedAt = 0, absentSince = 100 },
				{ accountId = "b", characterId = "first", joinedAt = 1, absentSince = 100 },
				{ accountId = "c", characterId = "z", joinedAt = 2 },
				{ accountId = "d", characterId = "a", joinedAt = 2 },
			}
			state.lastAt = 100
			local succeeded = assert(system.sweep(state, { at = 110 })).state
			expect(succeeded.leaderId):toBe("d")
			expect(#succeeded.members):toBe(4)
			local trio = grown({ "a", "b", "c" })
			local absent = assert(Core.markAbsent(trio, { accountId = "b", at = 100 })).state
			expect(assert(Core.leave(absent, { accountId = "a", at = 101 })).state.leaderId):toBe("c")
			local pair = grown({ "a", "b" })
			pair = assert(Core.markAbsent(pair, { accountId = "a", at = 100 })).state
			pair = assert(Core.markAbsent(pair, { accountId = "b", at = 100 })).state
			expect(assert(Core.sweep(pair, { at = 110 })).state.leaderId):toBe("a")
		end)
		it("fences returning characters and preserves the original absence deadline", function()
			local state = grown({ "a", "b" })
			local absent = assert(Core.markAbsent(state, { accountId = "b", at = 100 })).state
			local repeated = assert(Core.markAbsent(absent, { accountId = "b", at = 120 })).state
			expect(repeated.members[2].absentSince):toBe(100)
			expect(ids(assert(Core.sweep(repeated, { at = 130 })).state)):toEqual({ "a" })
			local wrong, reason = Core.markPresent(repeated, { accountId = "b", characterId = "replacement", at = 121 })
			expect(wrong):toBeNil()
			expect(reason):toBe("character_mismatch")
			local returned = assert(Core.markPresent(repeated, { accountId = "b", characterId = "cb", at = 129 })).state
			expect(returned.members[2].absentSince):toBeNil()
			expect(#assert(Core.sweep(returned, { at = 130 })).state.members):toBe(2)
			local leader = assert(Core.markAbsent(state, { accountId = "a", at = 100 })).state
			local departed = assert(Core.sweep(leader, { at = 130 })).state
			expect(departed.leaderId):toBe("b")
			expect(ids(departed)):toEqual({ "b" })
			local everyone = assert(Core.markAbsent(leader, { accountId = "b", at = 100 })).state
			local closed = assert(Core.sweep(everyone, { at = 130 })).state
			expect(closed.disbandedAt):toBe(130)
			expect(#closed.members):toBe(0)
			local reserved = invite(open(), "b", 1)
			expect(#assert(Core.sweep(reserved, { at = 11 })).state.invites):toBe(0)
			local regressed, clockReason = Core.sweep(reserved, { at = 0 })
			expect(regressed):toBeNil()
			expect(clockReason):toBe("time_regressed")
		end)
	end)
end
