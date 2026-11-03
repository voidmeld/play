--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Fellowships = require("./social-fellowship")
local Formations = require("./social-formation")
local Groups = require("../core/social/group")
local Homes = require("../core/social/guildhome")
local Social = require("../test-scene/social")
local SocialHost = require("./social-host")
local Transfer = require("./profile-transfer")
local Value = require("../core/internal/value")
local Verify = require("../../.lute/dependencies/verify/src/core")

local group = Groups.group({
	recoveryTtlSec = 100,
	relationsMaxAgeSec = 15,
	maxTickets = 4,
	maxRoster = 8,
	maxRevision = 10000,
	maxTime = 1000000000000,
	maxId = 128,
	maxFingerprint = 512,
})
local homes = Homes.guildhome({
	maxIdLength = 128,
	maxLabelLength = 32,
	maxSlots = 3,
	realms = { realm_a = true, realm_b = true },
})
local catalog = { slots = { { id = "home", hubId = "hub", realmId = "realm_a", label = "Home" } } }

local function rig(rejectFormation: boolean?)
	local corrupt: ((unknown) -> unknown)? = nil
	if rejectFormation then
		corrupt = function(value: unknown): unknown
			local raw = Value.raw(value)
			return if raw ~= nil and raw.phase == "forming" then nil else value
		end
	end
	local records, _values, counters = Social.rig(corrupt, { requiredFounders = 2, fee = 7 })
	local host = SocialHost.fellowships(records)
	local sequence = 0
	local balances: { [number]: number } = { [1] = 50 }
	local held: { [string]: boolean } = {}
	local committed: { [string]: boolean } = {}
	local refunded: { [string]: boolean } = {}
	local blocked: { [number]: { number } } = {}
	local commitFails = false
	local holdUncertain, refundFails = false, false
	local refundFailureReason = "save_failed"
	local function clock(): number
		return counters.clock
	end
	local function eventId(): string
		sequence += 1
		return "event-" .. sequence
	end
	local function nameFor(id: number): string?
		return "Member " .. id
	end
	local function realmFor(id: number): string?
		return if id == 3 then "realm_b" else "realm_a"
	end
	local function relationsFor(id: number, _others: { number }, at: number): Groups.Relations?
		return {
			readAtSec = at,
			memberUserId = id,
			moderationEligible = true,
			blockedUserIds = blocked[id] or {},
			moderationDeniedUserIds = {},
			optedOutUserIds = {},
		}
	end
	local deps = {
		fellowshipRecords = records,
		realmFor = realmFor,
		clock = clock,
		guildHomeCatalog = function(): unknown
			return catalog
		end,
		relationsFor = relationsFor,
	}
	local guilds = Fellowships.configure({
		slots = homes.slots,
		slotFor = homes.slotFor,
		admit = group.admit,
		visibleRoster = group.visibleRoster,
		inviteTtlSec = 300,
		stewardAbsenceSec = 30 * 24 * 60 * 60,
		seenRefreshSec = 7,
		fellowshipId = function(id: string): string
			return "fellowship:" .. id
		end,
		memberFallback = function(id: number): string
			return "Member " .. id
		end,
	}).create(deps, host, nameFor, eventId, function(_id: string) end)
	local fee: Formations.FeePort = {
		hold = function(id: number, key: string): Transfer.Result
			if held[key] then
				return { ok = true, outcome = "replayed" }
			end
			if (balances[id] or 0) < 7 then
				return { ok = false, outcome = "rejected", reason = "coin_insufficient" }
			end
			balances[id] -= 7
			held[key] = true
			if holdUncertain then
				return { ok = false, outcome = "not_durable", reason = "save_failed" }
			end
			return { ok = true, outcome = "committed" }
		end,
		commit = function(_id: number, key: string): Transfer.Result
			if commitFails then
				return { ok = false, outcome = "not_durable", reason = "save_failed" }
			end
			if not held[key] then
				return { ok = false, outcome = "rejected", reason = "fee_not_held" }
			end
			committed[key] = true
			return { ok = true, outcome = "committed" }
		end,
		refund = function(id: number, key: string): Transfer.Result
			if refundFails then
				return { ok = false, outcome = "not_durable", reason = refundFailureReason }
			end
			if refunded[key] then
				return { ok = true, outcome = "replayed" }
			end
			if not held[key] then
				return { ok = false, outcome = "rejected", reason = "fee_not_held" }
			end
			if committed[key] then
				return { ok = false, outcome = "rejected", reason = "fee_committed" }
			end
			balances[id] += 7
			refunded[key] = true
			return { ok = true, outcome = "committed" }
		end,
	}
	local formationDeps = table.clone(deps)
	local formations = Formations.configure({
		slotFor = homes.slotFor,
		admit = group.admit,
		requiredFounders = 2,
		fee = 7,
		proposerFallback = "Founder",
	}).create({
		fellowshipRecords = formationDeps.fellowshipRecords,
		realmFor = formationDeps.realmFor,
		clock = formationDeps.clock,
		guildHomeCatalog = formationDeps.guildHomeCatalog,
		relationsFor = formationDeps.relationsFor,
		guildFee = fee,
	}, host, nameFor, eventId, function(_id: string) end)
	return {
		guilds = guilds,
		formations = formations,
		records = records,
		counters = counters,
		balances = balances,
		blocked = blocked,
		failCommit = function(value: boolean)
			commitFails = value
		end,
		uncertainHold = function(value: boolean)
			holdUncertain = value
		end,
		failRefund = function(value: boolean, reason: string?)
			refundFails = value
			refundFailureReason = reason or "save_failed"
		end,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("fellowship host", function()
		it("creates a scoped guild and admits a member through durable records", function()
			local scene = rig()
			local created = scene.guilds.createFellowship(1, "group_a")
			assert(created.ok and created.state ~= nil)
			expect(scene.guilds.fellowshipInvite(1, 3).reason):toBe("realm_mismatch")
			expect(scene.guilds.fellowshipInvite(1, 2).ok):toBe(true)
			expect(scene.guilds.answerFellowshipInvite(2, true).ok):toBe(true)
			local membership = scene.guilds.bankMembership(2, true)
			assert(membership ~= nil)
			expect(membership.role):toBe("member")
			expect(membership.memberIds):toEqual({ 1, 2 })
		end)
		it("fails closed on privacy admission and expires pending invitations", function()
			local scene = rig()
			assert(scene.guilds.createFellowship(1, "group_a").ok)
			scene.blocked[2] = { 1 }
			expect(scene.guilds.fellowshipInvite(1, 2).ok):toBe(false)
			scene.blocked[2] = nil
			expect(scene.guilds.fellowshipInvite(1, 2).ok):toBe(true)
			scene.counters.clock += 301
			expect(scene.guilds.pendingFellowshipInvite(2)):toBe(false)
			expect(scene.guilds.answerFellowshipInvite(2, true).reason):toBe("invite_unknown")
		end)
		it("uses the configured steward refresh interval without redundant writes", function()
			local scene = rig()
			assert(scene.guilds.createFellowship(1, "group_a").ok)
			local writes = scene.counters.writes
			expect(scene.guilds.fellowshipSeen(1).ok):toBe(true)
			expect(scene.counters.writes):toBe(writes)
			scene.counters.clock += 8
			local seen = scene.guilds.fellowshipSeen(1)
			assert(seen.ok and seen.state ~= nil)
			expect(seen.state.stewardSeenAtSec):toBe(108)
		end)
	end)
	describe("formation host", function()
		it("keeps an uncertain fee absence closed until the refund is confirmed", function()
			local scene = rig()
			scene.uncertainHold(true)
			expect(scene.formations.start(1, "group_a").ok):toBe(false)
			scene.uncertainHold(false)
			scene.failRefund(true, "fee_not_held")
			expect(scene.formations.start(1, "group_a").ok):toBe(false)
			expect(scene.records.readProposerFormation(1).formationId ~= nil):toBe(true)
			expect(scene.balances[1]):toBe(43)
			scene.failRefund(false)
			expect(scene.formations.start(1, "group_a").ok):toBe(true)
			expect(scene.balances[1]):toBe(43)
		end)
		it("refunds an orphaned uncertain hold before accepting an immediate retry", function()
			local scene = rig()
			scene.uncertainHold(true)
			expect(scene.formations.start(1, "group_a").ok):toBe(false)
			expect(scene.balances[1]):toBe(43)
			scene.uncertainHold(false)
			local retried = scene.formations.start(1, "group_a")
			expect(retried.ok):toBe(true)
			expect(scene.balances[1]):toBe(43)
			local projected = scene.formations.projection(1)
			assert(projected ~= false)
			expect(projected.active):toBe(true)
		end)
		it("completes a two-founder charter with the configured fee exactly once", function()
			local scene = rig()
			expect(scene.formations.start(1, "group_a").ok):toBe(true)
			expect(scene.formations.invite(1, 2).ok):toBe(true)
			expect(scene.formations.answer(2, "consent").ok):toBe(true)
			local completed = scene.formations.complete(1)
			assert(completed.ok and completed.fellowshipId ~= nil)
			expect(scene.balances[1]):toBe(43)
			expect(scene.records.read(completed.fellowshipId).ok):toBe(true)
			expect(scene.formations.settle(1).ok):toBe(true)
			expect(scene.balances[1]):toBe(43)
		end)
		it("retains a proposer pointer until fee commit can be reconciled", function()
			local scene = rig()
			assert(scene.formations.start(1, "group_a").ok)
			assert(scene.formations.invite(1, 2).ok)
			assert(scene.formations.answer(2, "consent").ok)
			scene.failCommit(true)
			assert(scene.formations.complete(1).ok)
			expect(scene.records.readProposerFormation(1).formationId ~= nil):toBe(true)
			scene.failCommit(false)
			expect(scene.formations.settle(1).ok):toBe(true)
			expect(scene.records.readProposerFormation(1).formationId):toBeNil()
			expect(scene.balances[1]):toBe(43)
		end)
		it("retains an uncertain fee hold until its refund is durable", function()
			local scene = rig()
			scene.uncertainHold(true)
			expect(scene.formations.start(1, "group_a").ok):toBe(false)
			expect(scene.balances[1]):toBe(43)
			expect(scene.records.readProposerFormation(1).formationId ~= nil):toBe(true)
			scene.failRefund(true)
			scene.formations.settle(1)
			expect(scene.records.readProposerFormation(1).formationId ~= nil):toBe(true)
			scene.failRefund(false)
			scene.formations.settle(1)
			expect(scene.records.readProposerFormation(1).formationId):toBeNil()
			expect(scene.balances[1]):toBe(50)
		end)
		it("keeps failed charter creation recoverable across an uncertain refund", function()
			local scene = rig(true)
			scene.failRefund(true)
			expect(scene.formations.start(1, "group_a").ok):toBe(false)
			expect(scene.records.readProposerFormation(1).formationId ~= nil):toBe(true)
			scene.counters.clock += 601
			scene.failRefund(false)
			scene.formations.settle(1)
			expect(scene.records.readProposerFormation(1).formationId):toBeNil()
			expect(scene.balances[1]):toBe(50)
		end)
	end)
end
