--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Membership = require("../core/social/membership")
local Party = require("./party")
local Rally = require("../core/social/rally")
local Social = require("./social-party")
local Verify = require("../../.lute/dependencies/verify/src/core")

local core = Membership.membership({
	maxMembers = 3,
	minimumPartyMembers = 2,
	disconnectGraceSec = 30,
	leaderSuccessionSec = 10,
	leaderTransferTtlSec = 5,
	inviteTtlSec = 10,
	maxText = 64,
	maxAt = 10000,
	realms = { alpha = true, beta = true },
	defaultLootMode = "need_greed",
})
local atomic = Party.party({ core = core, schemaVersion = 2, maxText = 64 })
local rally = Rally.rally({
	maxRows = 4,
	maxTime = 10000,
	maxId = 64,
	kinds = { rally = true },
	titles = { call = true },
	landmarks = { post = true },
	realms = { alpha = true, all = true },
	sharedRealm = "all",
})

local function rig()
	local values: { [string]: unknown } = {}
	local membership: { [string]: string } = {}
	local now = 100
	local refused = false
	local reports = 0
	local function membershipFor(id: string): unknown
		return membership[id]
	end
	local mounted = atomic.mount({
		keyForParty = function(id: string): string
			return id
		end,
		readMembership = membershipFor,
		store = {
			read = function(key: string): Party.StoreOutcome
				return { ok = true, value = values[key] }
			end,
			update = function(key: string, apply: (unknown) -> unknown): Party.StoreOutcome
				apply(values[key])
				local value = apply(values[key])
				if value == nil then
					return { ok = false, value = values[key], reason = "callback_cancelled" }
				end
				values[key] = value
				return { ok = true, value = value }
			end,
		},
	})
	assert(mounted.ok and mounted.service)
	local configured = Social.configure({
		lootMode = "round_robin",
		rally = rally.project,
		inviteTtlSec = 10,
		leaderTransferTtlSec = 5,
		maxProjectionRefusals = 2,
		maxDisplayName = 16,
		maxCandidates = 2,
		partyId = function(actor: number, _at: number, sequence: number): string
			return "group-" .. actor .. "-" .. sequence
		end,
		memberFallback = function(id: string): string
			return "Member " .. id
		end,
		inviterFallback = "Ally",
		reportProjectionRefusal = function(_id: string, _reason: string)
			reports += 1
		end,
	})
	local service = configured.create({
		projectPartyMembership = function(account: string, partyId: string?): string?
			if refused then
				return "projection_failed"
			end
			membership[account] = partyId
			return nil
		end,
		partyMembership = membershipFor,
		candidateRows = function(_id: number): unknown
			return {
				{ userId = 2, displayName = "Second", source = "nearby" },
				{ userId = 3, displayName = "Third", source = "nearby" },
			}
		end,
		realmFor = function(id: number): string?
			return if id == 3 then "beta" else "alpha"
		end,
		characterFor = function(id: number): string?
			return "character-" .. id
		end,
		displayNameFor = function(_id: number): string?
			return nil
		end,
		clock = function(): number
			return now
		end,
		projectRallyJoin = function(_id: number, _objective: string?) end,
		objectiveRows = function(): unknown
			return {
				{
					objectiveId = "objective",
					objectiveKind = "rally",
					titleId = "call",
					landmarkId = "post",
					zoneId = "zone",
					realmId = "alpha",
					expiresAtSec = 105,
					active = true,
					serverAuthored = true,
				},
			}
		end,
	}, mounted.service)
	return {
		service = service,
		configured = configured,
		membership = membership,
		advance = function(seconds: number)
			now += seconds
		end,
		refuse = function()
			refused = true
		end,
		reports = function()
			return reports
		end,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("social party host", function()
		it("admits known solo and current party rosters with an injected solo namespace", function()
			local scene = rig()
			local query = Social.admission(
				function(id: string): Social.MembershipOutcome
					return { ok = true, partyId = scene.membership[id] }
				end,
				scene.service.party,
				function(id: number): string
					return "individual:" .. tostring(id)
				end
			)
			local solo = query(1)
			assert(solo.ok)
			expect(solo.partyId):toBe("individual:1")
			expect(solo.members):toEqual({ 1 })
			assert(scene.service.partyInvite(1, 2).ok)
			assert(scene.service.partyAccept(2).ok)
			local grouped = query(2)
			assert(grouped.ok)
			expect(grouped.members):toEqual({ 1, 2 })
			expect(grouped.partyId):toBe(scene.membership["2"])
			scene.membership["3"] = grouped.partyId
			expect(query(3).reason):toBe("membership_mismatch")
		end)
		it("refuses missing failed or throwing membership reads instead of assuming solo", function()
			local scene = rig()
			local function solo(id: number): string
				return tostring(id)
			end
			expect(Social.admission(nil, scene.service.party, solo)(1).reason):toBe("membership_unavailable")
			expect(Social.admission(function(_id: string): Social.MembershipOutcome
				return { ok = false, partyId = nil }
			end, scene.service.party, solo)(1).reason):toBe("membership_unavailable")
			expect(Social.admission(function(_id: string): Social.MembershipOutcome
				error("unavailable")
			end, scene.service.party, solo)(1).reason):toBe("membership_unavailable")
			expect(Social.admission(function(_id: string): Social.MembershipOutcome
				return { ok = true, partyId = "missing" }
			end, scene.service.party, solo)(1).reason):toBe("party_unavailable")
		end)
		it("admits only visible same-domain candidates and projects durable membership", function()
			local scene = rig()
			expect(#scene.service.candidateProjection(1)):toBe(1)
			expect(scene.service.partyInvite(1, 3).ok):toBe(false)
			expect(scene.service.partyInvite(1, 2).ok):toBe(true)
			expect(scene.service.pendingInviteCount()):toBe(1)
			local incoming = scene.service.partyProjection(2).incoming
			assert(incoming ~= false)
			expect(incoming.inviterName):toBe("Ally")
			expect(scene.service.partyAccept(2).ok):toBe(true)
			expect(scene.membership["1"]):toBe(scene.membership["2"])
			expect(scene.service.partyAudience(1)):toEqual({ 1, 2 })
			expect(scene.service.pendingInviteCount()):toBe(0)
		end)
		it("settles reviewed leadership transfer and succeeds an absent leader", function()
			local scene = rig()
			assert(scene.service.partyInvite(1, 2).ok)
			assert(scene.service.partyAccept(2).ok)
			expect(scene.service.partyTransferLeader(1, 2).ok):toBe(true)
			expect(scene.service.partyAcceptLeaderTransfer(2).ok):toBe(true)
			expect(scene.service.partyDisconnect(2).ok):toBe(true)
			scene.advance(11)
			local state = scene.service.partySweep(scene.membership["1"]).party
			assert(state ~= nil)
			expect(state.leaderId):toBe("1")
			expect(scene.service.partyReconnect(2).ok):toBe(true)
		end)
		it("bounds projection refusal observations and refuses expired rally requests", function()
			local scene = rig()
			assert(scene.service.partyInvite(1, 2).ok)
			assert(scene.service.partyAccept(2).ok)
			scene.refuse()
			scene.service.partyProjection(1)
			scene.service.partyProjection(1)
			expect(scene.reports() > 0):toBe(true)
			expect(#scene.configured.projectionRefusals()):toBe(2)
			local copy = scene.configured.projectionRefusals()
			table.clear(copy)
			expect(#scene.configured.projectionRefusals()):toBe(2)
			expect(scene.service.joinRally(1, "objective", "zone").ok):toBe(true)
			local replay = scene.service.joinRally(1, "objective", "zone")
			assert(replay.ok)
			expect(replay.replayed):toBe(true)
			scene.advance(6)
			expect(scene.service.joinRally(1, "objective", "zone").ok):toBe(false)
		end)
	end)
end
