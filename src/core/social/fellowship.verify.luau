--!strict

local Module = require("./fellowship")
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
		inviteTtlSec = 300,
		maxMembers = 300,
		maxOfficers = 12,
		maxAudit = 8,
		stewardAbsenceSec = 30 * 24 * 60 * 60,
		maxInvites = 16,
		maxReceipts = 64,
		maxTime = 1000000000000,
		maxNameLength = 64,
		realms = Shape.freezeDeep({ north = true, south = true, east = true }),
		nameIds = Shape.freezeDeep({ sentry = true, beacon = true, wardens = true }),
		pursuits = Shape.freezeDeep({
			exploration = true,
			homeland_quests = true,
			dungeons = true,
			crafting_trade = true,
			realm_war = true,
			fellowship_roleplay = true,
		}),
		paces = Shape.freezeDeep({ easygoing = true, steady = true, dedicated = true }),
		welcomes = Shape.freezeDeep({ new_players = true, all_levels = true, level_ten = true }),
		maxId = 128,
		maxRevision = 1000000000,
		maxFingerprint = 1024,
		maxPursuits = 3,
		requiredFounders = 5,
	}
	local Core = Module.fellowship(settings)

	local function created(): Module.State
		local result = Core.create({
			fellowshipId = "fellowship:ash-vigil",
			nameId = "sentry",
			realmId = "north",
			homeSlotId = "woodland.guild_banner.village_courtyard",
			stewardUserId = 11,
			stewardName = "Alden",
		}, 100)
		expect(result.ok):toBe(true)
		return assert(result.state)
	end

	local function invite(state: Module.State, target: number, at: number): Module.Result
		return Core.transition(state, {
			kind = "invite",
			eventId = "invite:" .. tostring(target),
			expectedRevision = state.revision,
			actorUserId = 11,
			targetUserId = target,
			targetRealmId = "north",
		}, at)
	end

	local function accept(state: Module.State, actor: number, at: number): Module.Result
		return Core.transition(state, {
			kind = "accept",
			eventId = "accept:" .. tostring(actor),
			expectedRevision = state.revision,
			actorUserId = actor,
			actorRealmId = "north",
			actorName = "Member" .. tostring(actor),
		}, at)
	end

	describe("FellowshipCore fixed identity and invitation lifecycle", function()
		it("creates only a fixed-vocabulary same-realm identity", function()
			expect(created().nameId):toBe("sentry")
			expect(Core.create({
				fellowshipId = "f",
				nameId = "Player wrote this",
				realmId = "north",
				homeSlotId = "woodland.guild_banner.village_courtyard",
				stewardUserId = 11,
				stewardName = "Alden",
			}, 1).reason):toBe("invalid_request")
		end)

		it("invites, accepts, declines, and expires without admitting a stale claim", function()
			local first = invite(created(), 22, 101)
			expect(first.ok):toBe(true)
			local joined = accept(assert(first.state), 22, 102)
			expect(joined.ok):toBe(true)
			expect(#(assert(joined.state)).members):toBe(2)

			local second = invite(assert(joined.state), 33, 103)
			local declined = Core.transition(second.state, {
				kind = "decline",
				eventId = "decline:33",
				expectedRevision = (assert(second.state)).revision,
				actorUserId = 33,
			}, 104)
			expect(declined.ok):toBe(true)
			expect(#(assert(declined.state)).invites):toBe(0)

			local expiring = invite(assert(declined.state), 44, 105)
			local stale = accept(assert(expiring.state), 44, 105 + Core.INVITE_TTL_SEC)
			expect(stale.ok):toBe(false)
			expect(stale.reason):toBe("invite_unknown")
		end)

		it("fails closed on cross-realm and forged steward claims", function()
			local state = created()
			local cross = Core.transition(state, {
				kind = "invite",
				eventId = "cross",
				expectedRevision = 0,
				actorUserId = 11,
				targetUserId = 22,
				targetRealmId = "south",
			}, 101)
			expect(cross.reason):toBe("realm_mismatch")
			local forged = Core.transition(state, {
				kind = "invite",
				eventId = "forged",
				expectedRevision = 0,
				actorUserId = 99,
				targetUserId = 22,
				targetRealmId = "north",
			}, 101)
			expect(forged.reason):toBe("forged_membership")
		end)
	end)

	describe("FellowshipCore home memory and remembered names", function()
		it("founds the charter at its home banner slot and remembers the founding second", function()
			local state = created()
			expect(state.homeSlotId):toBe("woodland.guild_banner.village_courtyard")
			expect(state.foundedAtSec):toBe(100)
			expect(state.members[1].name):toBe("Alden")
		end)

		it("refuses a charter without a home slot or a founder name", function()
			for _, field in { "homeSlotId", "stewardName" } do
				local request = {
					fellowshipId = "f",
					nameId = "sentry",
					realmId = "north",
					homeSlotId = "woodland.guild_banner.village_courtyard",
					stewardUserId = 11,
					stewardName = "Alden",
				}
				request[field] = ""
				expect(Core.create(request, 1).reason):toBe("invalid_request")
			end
		end)

		it("records the accepting member's own name and keeps home and founding through projection", function()
			local joined = accept(assert(invite(created(), 22, 101).state), 22, 102)
			local projected = assert(Core.projectState(joined.state))
			expect(projected.members[2].name):toBe("Member22")
			expect(projected.homeSlotId):toBe("woodland.guild_banner.village_courtyard")
			expect(projected.foundedAtSec):toBe(100)
		end)

		it("refuses an accept that carries no member name", function()
			local invited = assert(invite(created(), 22, 101).state)
			local nameless = Core.transition(invited, {
				kind = "accept",
				eventId = "accept:22",
				expectedRevision = invited.revision,
				actorUserId = 22,
				actorRealmId = "north",
				actorName = "",
			}, 102)
			expect(nameless.ok):toBe(false)
			expect(nameless.reason):toBe("invalid_event")
		end)
	end)

	describe("FellowshipCore durable membership recovery", function()
		it("keeps membership through projection and recovers stewardship when the steward leaves", function()
			local invited = invite(created(), 22, 101)
			local joined = accept(assert(invited.state), 22, 102)
			local projected = assert(Core.projectState(joined.state))
			expect(projected.members[2].userId):toBe(22)
			local left = Core.transition(projected, {
				kind = "leave",
				eventId = "leave:11",
				expectedRevision = projected.revision,
				actorUserId = 11,
			}, 103)
			expect(left.ok):toBe(true)
			expect((assert(left.state)).stewardUserId):toBe(22)
		end)

		it("replays an exact event idempotently and rejects a conflicting forgery", function()
			local first = invite(created(), 22, 101)
			local replay = Core.transition(first.state, {
				kind = "invite",
				eventId = "invite:22",
				expectedRevision = 0,
				actorUserId = 11,
				targetUserId = 22,
				targetRealmId = "north",
			}, 102)
			expect(replay.ok):toBe(true)
			expect(replay.replayed):toBe(true)
			local conflict = Core.transition(first.state, {
				kind = "invite",
				eventId = "invite:22",
				expectedRevision = 0,
				actorUserId = 11,
				targetUserId = 23,
				targetRealmId = "north",
			}, 102)
			expect(conflict.reason):toBe("receipt_conflict")
		end)

		it("contains no gameplay, reward, quest, loot, or rally priority field", function()
			local state = assert(Shape.raw(created()))
			for _, forbidden in { "stats", "power", "loot", "questCredit", "rallyPriority", "bank", "perks" } do
				expect(state[forbidden]):toBeNil()
			end
		end)
	end)

	local function ev(state: Module.State, kind: string, actor: number, target: number?, at: number): Module.Result
		return Core.transition(state, {
			kind = kind,
			eventId = kind .. ":" .. tostring(actor) .. ":" .. tostring(target) .. ":" .. tostring(state.revision),
			expectedRevision = state.revision,
			actorUserId = actor,
			targetUserId = target,
		}, at)
	end

	local function roster(): Module.State
		local state = created()
		local at = 200
		for _, userId in { 12, 13, 14 } do
			state = assert(invite(state, userId, at).state)
			state = assert(accept(state, userId, at + 1).state)
			at += 2
		end
		return state
	end

	describe("FellowshipCore ranks and stewardship", function()
		it("lets the steward appoint officers who may invite and remove ordinary members only", function()
			local state = roster()
			expect(ev(state, "promote", 12, 13, 300).reason):toBe("forged_membership")
			state = assert(ev(state, "promote", 11, 12, 300).state)
			state = assert(ev(state, "promote", 11, 13, 300).state)
			expect(ev(state, "promote", 11, 12, 300).reason):toBe("already_officer")
			local invited = Core.transition(state, {
				kind = "invite",
				eventId = "officer-invite",
				expectedRevision = state.revision,
				actorUserId = 12,
				targetUserId = 30,
				targetRealmId = "north",
			}, 310)
			expect(invited.ok):toBe(true)
			expect(ev(state, "remove", 12, 13, 310).reason):toBe("target_invalid")
			expect(ev(state, "remove", 12, 11, 310).reason):toBe("target_invalid")
			expect(ev(state, "transfer", 12, 14, 310).reason):toBe("forged_membership")
			local removed = assert(ev(state, "remove", 12, 14, 310).state)
			expect(#removed.members):toBe(3)
			local demoted = assert(ev(state, "demote", 11, 13, 320).state)
			expect(ev(demoted, "demote", 11, 13, 330).reason):toBe("not_officer")
			expect(ev(demoted, "remove", 13, 14, 330).reason):toBe("forged_membership")
		end)

		it("hands stewardship to an officer first when the steward leaves and drops the leaver's rank", function()
			local state = roster()
			state = assert(ev(state, "promote", 11, 13, 300).state)
			local left = assert(ev(state, "leave", 11, nil, 400).state)
			expect(left.stewardUserId):toBe(13)
			expect(#left.officers):toBe(0)
			local both = assert(ev(state, "promote", 11, 12, 310).state)
			local officerLeaves = assert(ev(both, "leave", 12, nil, 320).state)
			expect(#officerLeaves.officers):toBe(1)
			expect(officerLeaves.officers[1]):toBe(13)
		end)

		it("lets an officer claim stewardship only after thirty days of absence and records the audit", function()
			local state = roster()
			state = assert(ev(state, "promote", 11, 12, 300).state)
			local day = 24 * 60 * 60
			expect(ev(state, "claim", 12, nil, 300 + 29 * day).reason):toBe("steward_present")
			expect(ev(state, "claim", 13, nil, 300 + 31 * day).reason):toBe("forged_membership")
			local present = assert(ev(state, "seen", 11, nil, 300 + 20 * day).state)
			expect(ev(present, "claim", 12, nil, 300 + 40 * day).reason):toBe("steward_present")
			local claimed = assert(ev(present, "claim", 12, nil, 300 + 51 * day).state)
			expect(claimed.stewardUserId):toBe(12)
			expect(#claimed.officers):toBe(0)
			expect(claimed.audit[1]):toEqual({ kind = "claim", userId = 12, fromUserId = 11, atSec = 300 + 51 * day })
			local stale = Core.transition(present, {
				kind = "claim",
				eventId = "stale-claim",
				expectedRevision = present.revision - 1,
				actorUserId = 12,
			}, 300 + 52 * day)
			expect(stale.reason):toBe("revision_conflict")
		end)

		it("holds three hundred members", function()
			expect(Core.MAX_MEMBERS):toBe(300)
			local state = created()
			for userId = 100, 398 do
				state = assert(Core.transition(state, {
					kind = "invite",
					eventId = "i" .. userId,
					expectedRevision = state.revision,
					actorUserId = 11,
					targetUserId = userId,
					targetRealmId = "north",
				}, 1000).state)
				state = assert(accept(state, userId, 1000).state)
			end
			expect(#state.members):toBe(300)
		end)
	end)

	describe("FellowshipCore creed", function()
		local function creedEvent(
			actor: number,
			state: Module.State,
			pursuits: { string } | string,
			pace: string,
			welcome: string
		): Module.Result
			return Core.transition(state, {
				kind = "creed",
				eventId = "creed:" .. tostring(actor) .. ":" .. tostring(state.revision),
				expectedRevision = state.revision,
				actorUserId = actor,
				pursuits = pursuits,
				pace = pace,
				welcome = welcome,
			}, 400)
		end

		it("stores fixed ids set by the steward or an officer and nothing else", function()
			local state = created()
			for _, userId in { 12, 13 } do
				state = assert(invite(state, userId, 200 + userId).state)
				state = assert(accept(state, userId, 201 + userId).state)
			end
			expect((next(assert(Shape.raw(state.creed))))):toBeNil()
			state = assert(ev(state, "promote", 11, 12, 300).state)
			expect(creedEvent(13, state, { "dungeons" }, "steady", "all_levels").reason):toBe("forged_membership")
			local set = assert(creedEvent(12, state, { "realm_war", "dungeons" }, "dedicated", "level_ten").state)
			expect(set.creed.pursuits):toEqual({ "dungeons", "realm_war" })
			expect(set.creed.pace):toBe("dedicated")
			expect(set.creed.welcome):toBe("level_ten")
			local again = assert(creedEvent(11, set, { "crafting_trade" }, "easygoing", "new_players").state)
			expect(again.creed.pace):toBe("easygoing")
			expect((Core.projectState(again) ~= nil)):toBe(true)
		end)

		it("refuses unknown, duplicate, empty, oversized and free-text creeds without a write", function()
			local state = created()
			expect(creedEvent(11, state, { "dungeons" }, "steady", "Anyone is welcome").reason):toBe("creed_invalid")
			expect(creedEvent(11, state, { "dungeons" }, "fast", "all_levels").reason):toBe("creed_invalid")
			expect(creedEvent(11, state, { "Dungeons" }, "steady", "all_levels").reason):toBe("creed_invalid")
			expect(creedEvent(11, state, { "dungeons", "dungeons" }, "steady", "all_levels").reason):toBe(
				"creed_invalid"
			)
			expect(creedEvent(11, state, {}, "steady", "all_levels").reason):toBe("creed_invalid")
			expect(
				creedEvent(
					11,
					state,
					{ "dungeons", "exploration", "realm_war", "crafting_trade" },
					"steady",
					"all_levels"
				).reason
			):toBe("creed_invalid")
			expect(creedEvent(11, state, "dungeons", "steady", "all_levels").reason):toBe("creed_invalid")
			local stored = assert(Shape.raw(table.clone(state)))
			stored.creed = { pursuits = { "free text" }, pace = "steady", welcome = "all_levels" }
			expect((Core.projectState(stored))):toBeNil()
			stored.creed = { pursuits = { "dungeons" }, pace = "steady", welcome = "all_levels", motd = "hi" }
			expect((Core.projectState(stored))):toBeNil()
		end)

		it("refuses both prior fellowship shapes without upgrading them", function()
			for _, version in { 2, 3 } do
				local input: { [string]: unknown } = {}
				for key, value in assert(Shape.raw(created())) do
					assert(type(key) == "string")
					input[key] = value
				end
				input.schemaVersion = version
				input.creed = nil
				if version == 2 then
					input.officers, input.stewardSeenAtSec, input.audit = nil, nil, nil
				end
				table.freeze(input)
				expect((Core.projectState(input))):toBeNil()
			end
		end)

		it("refuses missing and non-table creeds without throwing", function()
			local input: { [string]: unknown } = {}
			for key, value in assert(Shape.raw(created())) do
				assert(type(key) == "string")
				input[key] = value
			end
			local malformed: { unknown } = { false, 7, "creed", function() end }
			for _, creed in malformed do
				input.creed = creed
				expect((Core.projectState(input))):toBeNil()
			end
			input.creed = nil
			expect((Core.projectState(input))):toBeNil()
		end)
	end)

	it("uses configured membership, invitation, identity, receipt and creed limits", function()
		local source = assert(invite(created(), 22, 101).state)
		local changes: { (Module.Config) -> () } = {
			function(cfg)
				cfg.maxMembers = 0
			end,
			function(cfg)
				cfg.maxInvites = 0
			end,
			function(cfg)
				cfg.maxReceipts = 0
			end,
			function(cfg)
				cfg.maxTime = 0
			end,
			function(cfg)
				cfg.maxNameLength = 1
			end,
			function(cfg)
				cfg.maxId = 1
			end,
			function(cfg)
				cfg.maxRevision = 0
			end,
			function(cfg)
				cfg.maxFingerprint = 1
			end,
		}
		for _, change in changes do
			local cfg: Module.Config = table.clone(settings)
			change(cfg)
			expect(Module.fellowship(cfg).projectState(source)):toBeNil()
		end
		local cfg: Module.Config = table.clone(settings)
		cfg.inviteTtlSec = 2
		local event = {
			kind = "invite",
			eventId = "short",
			expectedRevision = 0,
			actorUserId = 11,
			targetUserId = 22,
			targetRealmId = "north",
		}
		expect(assert(Module.fellowship(cfg).transition(created(), event, 101).state).invites[1].expiresAtSec):toBe(103)
		cfg.maxPursuits = 1
		expect(Module.fellowship(cfg).validCreed({ "dungeons", "realm_war" }, "steady", "all_levels")):toBeNil()
		cfg.pursuits, cfg.paces, cfg.welcomes = { travel = true }, { relaxed = true }, { everyone = true }
		expect(Module.fellowship(cfg).validCreed({ "travel" }, "relaxed", "everyone") ~= nil):toBe(true)
		cfg = table.clone(settings)
		cfg.requiredFounders = 2
		expect(Module.fellowship(cfg).createFromFormation({
			fellowshipId = "ab",
			nameId = "sentry",
			realmId = "north",
			homeSlotId = "h",
			founders = { { userId = 1, name = "One" }, { userId = 2, name = "Two" } },
		}, 0).ok):toBe(true)
	end)

	it("uses configured officer, succession and audit bounds", function()
		local state = assert(ev(roster(), "promote", 11, 12, 300).state)
		local cfg: Module.Config = table.clone(settings)
		cfg.maxOfficers, cfg.stewardAbsenceSec, cfg.maxAudit = 1, 1, 1
		local core = Module.fellowship(cfg)
		local function event(
			previous: Module.State,
			kind: string,
			actor: number,
			target: number?,
			at: number
		): Module.Result
			return core.transition(previous, {
				kind = kind,
				eventId = kind .. tostring(at),
				expectedRevision = previous.revision,
				actorUserId = actor,
				targetUserId = target,
			}, at)
		end
		expect(event(state, "promote", 11, 13, 300).reason):toBe("officers_full")
		state = assert(event(state, "claim", 12, nil, 301).state)
		expect(state.stewardUserId):toBe(12)
		state = assert(event(state, "promote", 12, 13, 302).state)
		state = assert(event(state, "claim", 13, nil, 303).state)
		expect(#state.audit):toBe(1)
		expect(state.audit[1].userId):toBe(13)
	end)
end
