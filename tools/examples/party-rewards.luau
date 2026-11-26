--!strict

local Membership = require("../../src/core/social/membership")
local Roster = require("../../src/core/social/roster")

local membership = Membership.membership({
	maxMembers = 4,
	minimumPartyMembers = 2,
	disconnectGraceSec = 60,
	leaderSuccessionSec = 30,
	leaderTransferTtlSec = 10,
	inviteTtlSec = 20,
	maxText = 64,
	maxAt = 1000,
	realms = { north = true },
	defaultLootMode = "round_robin",
})
local rewards = Roster.sharing({
	projectParty = membership.projectState,
	radius = 10,
	maxCoordinate = 1000,
	maxText = 64,
	maxAt = 1000,
	maxAmount = 10000,
	maxUnits = 100,
	contributionKind = function(kind: string): string?
		return if kind == "rescue" then kind else nil
	end,
	eventIdFor = function(event: string, member: string): string
		return tostring(#event) .. ":" .. event .. member
	end,
})

local party = assert(membership.open({ partyId = "group", realmId = "north", founderId = "a", at = 0 })).state
party = assert(membership.invite(party, {
	accountId = "b",
	invitedBy = "a",
	targetRealmId = "north",
	targetGrouped = false,
	at = 1,
})).state
party = assert(membership.accept(party, { accountId = "b", accepterGrouped = false, at = 2 })).state

local origin = { x = 0, y = 0, z = 0 }
local positions = { a = origin, b = { x = 0, y = 6, z = 8 } }
local shares = assert(rewards.shareXp(party, { eventId = "r1", at = 3, origin = origin, amount = 9 }, positions))
assert(#shares == 2 and shares[1].amount == 5 and shares[2].amount == 4)
local awards = assert(rewards.splitContribution(party, {
	eventId = "r1",
	at = 3,
	origin = origin,
	kind = "rescue",
	units = 1,
}, positions))
assert(#awards == 1 and awards[1].accountId == "a" and awards[1].eventId == "2:r1a")
print("Party rewards: shared 9 XP and assigned 1 contribution unit")
