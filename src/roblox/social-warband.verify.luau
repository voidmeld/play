--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Host = require("./social-warband")
local Membership = require("../core/social/membership")
local Scene = require("../test-scene/social")
local Verify = require("../../.lute/dependencies/verify/src/core")
local Warband = require("../core/social/warband")

local core = Warband.warband({
	maxParties = 20,
	inviteSeconds = 60,
	transferSeconds = 30,
	successionSeconds = 60,
	orders = { Attack = true, Defend = true, Regroup = true, NeedAid = true },
	realms = { realm_a = true },
	maxId = 128,
	maxInteger = 9007199254740991,
	maxAssistants = 2,
})
local membership = Membership.membership({
	maxMembers = 4,
	minimumPartyMembers = 2,
	disconnectGraceSec = 180,
	leaderSuccessionSec = 90,
	leaderTransferTtlSec = 20,
	inviteTtlSec = 90,
	maxText = 128,
	maxAt = 1000000000000,
	realms = { realm_a = true },
	defaultLootMode = "round_robin",
})
local configured = Host.configure({
	unitOf = core.unitOf,
	command = core.command,
	maxParties = 20,
	requestTtlSec = 7,
	rallyZone = "zone_a",
	warbandId = function(partyId: string, _now: number, sequence: number): string
		return partyId .. ":band:" .. tostring(sequence)
	end,
	memberFallback = function(id: number): string
		return "Member " .. tostring(id)
	end,
})
local function rig()
	local records, _, counters = Scene.rig()
	local parties: { [string]: Membership.State } = {}
	local members: { [string]: string } = {}
	for _, id in { 1, 3, 5 } do
		local partyId = "p" .. tostring(id)
		local opened = assert(membership.open({
			partyId = partyId,
			realmId = "realm_a",
			founderId = tostring(id),
			founderCharacterId = "c" .. tostring(id),
			at = 100,
		}))
		local invited = assert(membership.invite(opened.state, {
			accountId = tostring(id + 1),
			invitedBy = tostring(id),
			targetRealmId = "realm_a",
			targetGrouped = false,
			at = 100,
		}))
		parties[partyId] = assert(membership.accept(invited.state, {
			accountId = tostring(id + 1),
			characterId = "c" .. tostring(id + 1),
			accepterGrouped = false,
			at = 100,
		})).state
		members[tostring(id)] = partyId
		members[tostring(id + 1)] = partyId
	end
	local control = { blocked = false, unavailable = false }
	local function create()
		return configured.create({
			records = records,
			membership = function(id: string): unknown
				return members[id]
			end,
			readParty = function(id: string): Host.PartyResult
				return {
					ok = not control.unavailable,
					found = parties[id] ~= nil,
					party = parties[id],
					reason = if control.unavailable then "party_unavailable" else nil,
				}
			end,
			clock = function(): number
				return counters.clock
			end,
			nameFor = function(id: number): string
				return "Member " .. tostring(id)
			end,
			objectiveAllowed = function(_id: number, objective: string, zone: string): boolean
				return objective == "objective_a" and zone == "zone_a"
			end,
			inviteAllowed = function(_a: number, _b: number): boolean
				return not control.blocked
			end,
		})
	end
	local social = create()
	local function act(id: number, kind: string, target: number?): Host.Result
		return social.act(id, kind, target or 0, social.project(id, true).revision, "objective_a", "zone_a")
	end
	return {
		social = social,
		act = act,
		counters = counters,
		parties = parties,
		records = records,
		control = control,
		reconnect = create,
	}
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("configured coordination", function()
		it("keeps party authority and loot separate while routing a shared command", function()
			local r = rig()
			assert(r.act(1, "found").ok)
			for _, id in { 3, 5 } do
				assert(r.act(1, "invite", id).ok)
				assert(r.act(id, "accept").ok)
			end
			expect(#r.social.project(6, true).units):toBe(3)
			expect(r.act(2, "order:Defend").reason):toBe("warband_not_leader")
			local ordered = r.act(1, "order:Defend")
			expect(ordered.ok):toBe(true)
			expect(#ordered.audience):toBe(6)
			expect(r.parties.p1.lootMode):toBe("round_robin")
			expect(r.reconnect().project(3, true).warbandId):toBe(r.social.project(1).warbandId)
		end)
		it("uses configured rally location and request lifetime without extending spam", function()
			local r = rig()
			assert(r.act(1, "found").ok)
			assert(r.act(1, "rally").ok)
			expect(#r.social.project(3, true).rallyHosts):toBe(1)
			local writes = r.counters.writes
			assert(r.social.act(3, "request_invite", 1, 0, "objective_a", "zone_a").ok)
			r.counters.clock = 105
			assert(r.social.act(3, "request_invite", 1, 0, "objective_a", "zone_a").ok)
			expect(r.counters.writes):toBe(writes)
			r.counters.clock = 107
			expect(#r.social.project(1, true).requests):toBe(0)
			r.control.blocked = true
			expect(#r.social.project(3, true).rallyHosts):toBe(0)
		end)
		it("reconciles departure and releases membership before forming again", function()
			local r = rig()
			assert(r.act(1, "found").ok)
			assert(r.act(1, "invite", 3).ok)
			assert(r.act(3, "accept").ok)
			assert(r.act(3, "leave").ok)
			expect(r.records.readWarbandMembership("p3").membership):toBe(nil)
			expect(r.reconnect().project(3, true).warbandId):toBe(nil)
			assert(r.act(3, "found").ok)
		end)
		it("fails closed on unavailable parties and stale command revisions", function()
			local r = rig()
			assert(r.act(1, "found").ok)
			local stale = r.social.project(1).revision
			assert(r.act(1, "rally").ok)
			expect(r.social.act(1, "marker", 0, stale, "objective_a", "zone_a").reason):toBe("warband_stale")
			r.control.unavailable = true
			expect(r.act(1, "invite", 3).ok):toBe(false)
		end)
	end)
end
