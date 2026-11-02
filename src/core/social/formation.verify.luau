--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./formation")
local Shape = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local settings = {
		requiredFounders = 5,
		fee = 1000,
		formationTtlSec = 600,
		maxReceipts = 32,
		maxTime = 1000000000000,
		maxNameLength = 64,
		realms = Shape.freezeDeep({ north = true, south = true, east = true }),
		nameIds = Shape.freezeDeep({ sentry = true, beacon = true, wardens = true }),
		fellowshipPrefix = "fellowship:",
		maxFormationId = 100,
		maxId = 128,
		maxRevision = 1000000000,
		maxFingerprint = 1024,
	}
	local Core = Module.formation(settings)

	local function started(): Module.State
		local result = Core.start({
			formationId = "f1",
			nameId = "sentry",
			realmId = "north",
			homeSlotId = "woodland.guild_banner.village_courtyard",
			initiatorId = 1,
			initiatorName = "Alden",
		}, 100)
		return assert(result.state)
	end

	local counter = 0

	local function step(state: Module.State, event: Module.EventDraft, at: number): Module.Result
		counter += 1
		event.eventId = event.eventId or ("e" .. counter)
		event.expectedRevision = event.expectedRevision or state.revision
		return Core.transition(state, event, at)
	end

	local function invited(state: Module.State, ids: { number }): Module.State
		for _, id in ids do
			state = assert(
				step(state, { kind = "invite", actorUserId = 1, targetUserId = id, targetRealmId = "north" }, 110).state
			)
		end
		return state
	end

	local function consented(state: Module.State, ids: { number }): Module.State
		for _, id in ids do
			state = assert(
				step(state, { kind = "consent", actorUserId = id, actorRealmId = "north", actorName = "M" .. id }, 120).state
			)
		end
		return state
	end

	local function ready(): Module.State
		local state = consented(invited(started(), { 2, 3, 4, 5 }), { 2, 3, 4, 5 })
		return assert(step(state, { kind = "fee_held", actorUserId = 1 }, 130).state)
	end

	describe("FellowshipFormationCore consent flow", function()
		it("needs five distinct consenting founders and a held fee before completion", function()
			local state = started()
			expect(Core.REQUIRED_FOUNDERS):toBe(5)
			expect(Core.FEE_COPPER):toBe(1000)
			expect(step(state, { kind = "complete", actorUserId = 1 }, 110).reason):toBe("founders_missing")
			state = consented(invited(state, { 2, 3, 4, 5 }), { 2, 3, 4, 5 })
			expect(#state.founders):toBe(5)
			expect(step(state, { kind = "complete", actorUserId = 1 }, 130).reason):toBe("fee_unpaid")
			expect(
				step(state, { kind = "invite", actorUserId = 1, targetUserId = 6, targetRealmId = "north" }, 130).reason
			):toBe("formation_full")
			state = assert(step(state, { kind = "fee_held", actorUserId = 1 }, 130).state)
			expect(step(state, { kind = "fee_held", actorUserId = 1 }, 131).reason):toBe("fee_already_held")
			expect(step(state, { kind = "complete", actorUserId = 2 }, 140).reason):toBe("forged_membership")
			local done = assert(step(state, { kind = "complete", actorUserId = 1 }, 140).state)
			expect(done.phase):toBe("completed")
			expect(done.feeState):toBe("consumed")
			expect(step(done, { kind = "fee_refunded" }, 150).reason):toBe("nothing_to_refund")
		end)

		it("counts each founder once and refuses a duplicate or uninvited consent", function()
			local state = invited(started(), { 2, 3 })
			state = consented(state, { 2 })
			local again =
				step(state, { kind = "consent", actorUserId = 2, actorRealmId = "north", actorName = "M2" }, 125)
			expect(again.reason):toBe("already_consented")
			expect(
				step(state, { kind = "consent", actorUserId = 9, actorRealmId = "north", actorName = "M9" }, 125).reason
			):toBe("invite_unknown")
			expect(
				step(state, { kind = "invite", actorUserId = 2, targetUserId = 7, targetRealmId = "north" }, 125).reason
			):toBe("forged_membership")
			expect(
				step(state, { kind = "invite", actorUserId = 1, targetUserId = 2, targetRealmId = "north" }, 125).reason
			):toBe("already_listed")
			local replayEvent = {
				kind = "consent",
				eventId = "same",
				actorUserId = 3,
				actorRealmId = "north",
				actorName = "M3",
				expectedRevision = state.revision,
			}
			local first = Core.transition(state, replayEvent, 126)
			expect(first.ok):toBe(true)
			local replay = Core.transition(first.state, replayEvent, 127)
			expect(replay.replayed):toBe(true)
			expect(#assert(replay.state).founders):toBe(3)
		end)

		it("cancels when a founder leaves or declines and refunds the held fee once", function()
			for _, kind in { "withdraw", "decline" } do
				local state = ready()
				local actor = if kind == "withdraw" then 3 else 1
				if kind == "decline" then
					state = invited(started(), { 2 })
					state = assert(step(state, { kind = "fee_held", actorUserId = 1 }, 120).state)
					actor = 2
				end
				local cancelled = assert(step(state, { kind = kind, actorUserId = actor }, 150).state)
				expect(cancelled.phase):toBe("cancelled")
				expect(step(cancelled, { kind = "complete", actorUserId = 1 }, 160).reason):toBe("formation_closed")
				local refunded = assert(step(cancelled, { kind = "fee_refunded" }, 170).state)
				expect(refunded.feeState):toBe("refunded")
				expect(step(refunded, { kind = "fee_refunded" }, 180).reason):toBe("nothing_to_refund")
			end
		end)

		it("expires after ten minutes and refunds instead of completing", function()
			local state = ready()
			local late = Core.FORMATION_TTL_SEC + 101
			local swept = assert(step(state, { kind = "sweep" }, late).state)
			expect(swept.phase):toBe("cancelled")
			expect(assert(step(state, { kind = "complete", actorUserId = 1 }, late).state).phase):toBe("cancelled")
			expect(assert(step(swept, { kind = "fee_refunded" }, late + 1).state).feeState):toBe("refunded")
		end)

		it("lets only one of two concurrent completions win", function()
			local state = ready()
			local first = Core.transition(
				state,
				{ kind = "complete", eventId = "c1", expectedRevision = state.revision, actorUserId = 1 },
				200
			)
			local second = Core.transition(
				state,
				{ kind = "complete", eventId = "c2", expectedRevision = state.revision, actorUserId = 1 },
				200
			)
			expect(first.ok):toBe(true)
			expect(second.ok):toBe(true)
			local stale = Core.transition(
				first.state,
				{ kind = "complete", eventId = "c2", expectedRevision = state.revision, actorUserId = 1 },
				201
			)
			expect(stale.reason):toBe("revision_conflict")
			local retry = Core.transition(
				assert(first.state),
				{ kind = "complete", eventId = "c3", expectedRevision = assert(first.state).revision, actorUserId = 1 },
				201
			)
			expect(retry.reason):toBe("formation_closed")
		end)

		it("founds the guild with all five founders and rejects malformed or tampered state", function()
			local done = assert(step(ready(), { kind = "complete", actorUserId = 1 }, 200).state)
			local fellowshipSettings = {
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
					questing = true,
					dungeons = true,
					crafting_trade = true,
					realm_war = true,
					fellowship_roleplay = true,
				}),
				paces = Shape.freezeDeep({ easygoing = true, steady = true, dedicated = true }),
				welcomes = Shape.freezeDeep({ new_players = true, all_levels = true, experienced = true }),
				maxId = 128,
				maxRevision = 1000000000,
				maxFingerprint = 1024,
				maxPursuits = 3,
				requiredFounders = 5,
			}

			local FellowshipModule = require("./fellowship")
			local Fellowship = FellowshipModule.fellowship(fellowshipSettings)
			local founded = Fellowship.createFromFormation({
				fellowshipId = done.fellowshipId,
				nameId = done.nameId,
				realmId = done.realmId,
				homeSlotId = done.homeSlotId,
				founders = done.founders,
			}, 210)
			expect(founded.ok):toBe(true)
			expect(#assert(founded.state).members):toBe(5)
			expect(assert(founded.state).stewardUserId):toBe(1)
			local tampered: Module.State = table.clone(done)
			tampered.founders = { done.founders[1] }
			expect((Core.projectState(tampered))):toBeNil()
			local future: Module.State = table.clone(done)
			future.schemaVersion = 2
			expect((Core.projectState(future))):toBeNil()
		end)
	end)

	it("uses configured founder, fee, lifetime, identity and receipt bounds", function()
		local source = ready()
		local changes: { (Module.Config) -> () } = {
			function(cfg)
				cfg.requiredFounders = 2
			end,
			function(cfg)
				cfg.fee = 1
			end,
			function(cfg)
				cfg.maxReceipts = 1
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
			expect(Module.formation(cfg).projectState(source)):toBeNil()
		end
		local cfg: Module.Config = table.clone(settings)
		cfg.formationTtlSec, cfg.fellowshipPrefix = 2, "team:"
		local request: Module.StartRequest = {
			formationId = "ab",
			nameId = "sentry",
			realmId = "north",
			homeSlotId = "h",
			initiatorId = 1,
			initiatorName = "Founder",
		}
		local begun = Module.formation(cfg).start(request, 0)
		expect(assert(begun.state).expiresAtSec):toBe(2)
		expect(assert(begun.state).fellowshipId):toBe("team:ab")
		cfg.maxFormationId = 1
		expect(Module.formation(cfg).start(request, 0).reason):toBe("invalid_request")
		cfg = table.clone(settings)
		cfg.realms, cfg.nameIds = { elsewhere = true }, { other = true }
		expect(Module.formation(cfg).start(request, 0).reason):toBe("invalid_request")
	end)
end
