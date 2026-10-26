--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./warband")
local Shape = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local settings = {
		maxParties = 20,
		inviteSeconds = 60,
		transferSeconds = 30,
		successionSeconds = 60,
		orders = { Attack = true, Defend = true, Regroup = true, NeedAid = true },
		realms = { north = true, south = true, east = true },
		maxId = 128,
		maxInteger = 9007199254740991,
		maxAssistants = 2,
	}
	local Core = Module.warband(settings)
	describe("warband", function()
		local function parties(): Module.Parties
			return {
				p1 = { realmId = "north", leaderId = "1", characterId = "c1", connected = true },
				p2 = { realmId = "north", leaderId = "3", characterId = "c3", connected = true },
				p3 = { realmId = "north", leaderId = "5", characterId = "c5", connected = true },
			}
		end

		local function step(
			state: Module.State,
			command: string,
			actor: string,
			target: string?,
			now: number?,
			context: Module.Parties?
		): Module.Result
			local rows = context or parties()
			return Core.transition(state, {
				kind = command,
				actorPartyId = actor,
				actorId = rows[actor].leaderId,
				expectedRevision = state.revision,
				targetPartyId = target,
				membershipRevision = 1,
				orderKind = "Attack",
				objectiveId = "oathfall",
			}, rows, now or 100)
		end

		local function joined(): Module.State
			local state = assert(Core.found("w1", "p1", parties().p1, 1, 100).state)
			for _, id in { "p2", "p3" } do
				state = assert(step(state, "invite", "p1", id).state)
				state = assert(step(state, "accept", id, nil).state)
			end
			return state
		end

		it("joins whole party identities and records coordination without party loot or credit", function()
			local state = joined()
			expect(#state.units):toBe(3)
			expect(state.units[2].partyId):toBe("p2")
			expect(state.units[2].membershipRevision):toBe(1)
			local ordered = assert(step(state, "order", "p1", nil).state)
			expect(assert(ordered.order).kind):toBe("Attack")
			expect(state.order):toBe(nil)
			expect(assert(Shape.raw(ordered)).lootMode):toBe(nil)
			expect(assert(Shape.raw(ordered)).standing):toBe(nil)
		end)

		it("expires invites at sixty seconds and rechecks inviter authority and realm", function()
			local state = assert(Core.found("w1", "p1", parties().p1, 1, 100).state)
			state = assert(step(state, "invite", "p1", "p2").state)
			expect(step(state, "accept", "p2", nil, 160).reason):toBe("warband_invite_invalid")
			local changed = parties()
			changed.p2.realmId = "south"
			expect(step(state, "accept", "p2", nil, 101, changed).reason):toBe("warband_wrong_realm")
			state = assert(step(state, "invite", "p1", "p3").state)
			state = assert(step(state, "accept", "p3", nil).state)
			state = assert(step(state, "transfer", "p1", "p3").state)
			state = assert(step(state, "accept_transfer", "p3", nil).state)
			expect(step(state, "accept", "p2", nil).reason):toBe("warband_invite_invalid")
		end)

		it("fences objective markers to current command without exposing enemy locations", function()
			local state = joined()
			expect(step(state, "marker", "p2", nil).reason):toBe("warband_not_command")
			local assistant = assert(step(state, "assistant", "p1", "p2").state)
			local marked = assert(step(assistant, "marker", "p2", nil).state)
			expect(marked.targetObjectiveId):toBe("oathfall")
			expect(marked.targetByActorId):toBe(parties().p2.leaderId)
			expect(assistant.targetObjectiveId):toBe(nil)
			expect((Core.project(marked))):toBe(marked)
			local malformed = table.clone(marked)
			malformed.targetObjectiveId = ""
			expect((Core.project(malformed))):toBe(nil)
			malformed = table.clone(marked)
			malformed.targetByActorId = ""
			expect((Core.project(malformed))):toBe(nil)
			local rallied = assert(step(marked, "rally", "p1", nil).state)
			expect(rallied.rallyByActorId):toBe(parties().p1.leaderId)
			local ordered = assert(step(rallied, "order", "p1", nil).state)
			expect(assert(ordered.order).byActorId):toBe(parties().p1.leaderId)
		end)

		it("checks accepted leadership and rejects stale actions", function()
			local state = joined()
			local rows = parties()
			rows.p1.leaderId = "2"
			expect(Core.transition(state, {
				kind = "invite",
				actorPartyId = "p1",
				actorId = "1",
				expectedRevision = state.revision,
				targetPartyId = "p2",
			}, rows, 101).reason):toBe("warband_not_leader")
			expect(step(state, "order", "p1", nil, 101, rows).ok):toBe(true)
			expect(Core.transition(state, {
				kind = "leave",
				actorPartyId = "p2",
				actorId = "3",
				expectedRevision = state.revision - 1,
			}, rows, 101).reason):toBe("warband_stale")
		end)

		it("assistants issue orders but cannot remove parties or take command", function()
			local state = assert(step(joined(), "assistant", "p1", "p2").state)
			expect(step(state, "order", "p2", nil).ok):toBe(true)
			expect(step(state, "rally", "p2", nil).ok):toBe(true)
			expect(step(state, "remove", "p2", "p3").reason):toBe("warband_not_commander")
			expect(step(state, "transfer", "p2", "p3").reason):toBe("warband_not_commander")
			state = assert(step(state, "leave", "p2", nil).state)
			expect(#state.assistants):toBe(0)
		end)

		it("transfers command only after the recipient accepts within thirty seconds", function()
			local state = assert(step(joined(), "transfer", "p1", "p2").state)
			expect(state.commanderPartyId):toBe("p1")
			expect(step(state, "accept_transfer", "p3", nil).reason):toBe("warband_transfer_invalid")
			expect(step(state, "accept_transfer", "p2", nil, 130).reason):toBe("warband_transfer_invalid")
			expect(assert(step(state, "accept_transfer", "p2", nil, 129).state).commanderPartyId):toBe("p2")
		end)

		it("holds offline command for sixty seconds then uses joined time and character identity", function()
			local state = joined()
			local rows = parties()
			rows.p1.connected = false
			rows.p2.characterId = "z"
			rows.p3.characterId = "a"
			state = assert(step(state, "observe", "p1", nil, 101, rows).state)
			state = assert(step(state, "observe", "p1", nil, 160, rows).state)
			expect(state.commanderPartyId):toBe("p1")
			state = assert(step(state, "observe", "p1", nil, 161, rows).state)
			expect(state.commanderPartyId):toBe("p3")
			rows.p1.connected = true
			state = assert(step(state, "observe", "p1", nil, 162, rows).state)
			expect(state.commanderPartyId):toBe("p3")
		end)

		it("keeps all offline parties and resumes succession when an eligible leader returns", function()
			local state = joined()
			local rows = parties()
			for _, row in rows do
				row.connected = false
			end
			state = assert(step(state, "observe", "p1", nil, 101, rows).state)
			state = assert(step(state, "observe", "p1", nil, 1000, rows).state)
			expect(#state.units):toBe(3)
			expect(state.commanderPartyId):toBe("p1")
			rows.p2.connected = true
			expect(assert(step(state, "observe", "p1", nil, 1001, rows).state).commanderPartyId):toBe("p2")
		end)

		it("voluntary commander departure transfers immediately without dissolving other units", function()
			local state = assert(step(joined(), "leave", "p1", nil).state)
			expect(state.commanderPartyId):toBe("p2")
			expect(#state.units):toBe(2)
			expect((Core.unitOf(state, "p1"))):toBe(nil)
		end)

		it("enforces twenty accepted units at acceptance rather than invitation time", function()
			local state = joined()
			local rows = parties()
			for index = 4, 21 do
				local id = "p" .. index
				rows[id] =
					{ realmId = "north", leaderId = tostring(index), characterId = "c" .. index, connected = true }
				state = assert(step(state, "invite", "p1", id, 100, rows).state)
				local result = step(state, "accept", id, nil, 100, rows)
				if index <= 20 then
					state = assert(result.state)
				else
					expect(result.reason):toBe("warband_invite_invalid")
				end
			end
			expect(#state.units):toBe(20)
		end)

		it("succeeds immediately from a closed commander party even at clock zero", function()
			local rows = parties()
			local state = assert(Core.found("w1", "p1", rows.p1, 1, 0).state)
			state = assert(step(state, "invite", "p1", "p2", 0, rows).state)
			state = assert(step(state, "accept", "p2", nil, 0, rows).state)
			rows.p1.closed = true
			rows.p1.connected = false
			local nextState = assert(step(state, "observe", "p2", nil, 0, rows).state)
			expect(nextState.commanderPartyId):toBe("p2")
			expect(#nextState.units):toBe(1)
			expect((Core.project(nextState) ~= nil)):toBe(true)
		end)
		it("uses configured unit, identity, realm, assistant and order limits", function()
			local state = joined()
			local cfg: Module.Config = table.clone(settings)
			cfg.maxParties = 2
			expect(Module.warband(cfg).project(state)):toBeNil()
			cfg = table.clone(settings)
			cfg.maxId = 1
			expect(Module.warband(cfg).project(state)):toBeNil()
			cfg = table.clone(settings)
			cfg.maxInteger = 100
			expect(Module.warband(cfg).project(state)):toBeNil()
			cfg = table.clone(settings)
			cfg.realms = { elsewhere = true }
			expect(Module.warband(cfg).project(state)):toBeNil()
			cfg = table.clone(settings)
			cfg.maxAssistants = 0
			expect(Module.warband(cfg).transition(state, {
				kind = "assistant",
				actorPartyId = "p1",
				actorId = "1",
				expectedRevision = state.revision,
				targetPartyId = "p2",
			}, parties(), 100).reason):toBe("warband_assistants_full")
			cfg.orders = {}
			expect(Module.warband(cfg).transition(state, {
				kind = "order",
				actorPartyId = "p1",
				actorId = "1",
				expectedRevision = state.revision,
				objectiveId = "o",
				orderKind = "Attack",
			}, parties(), 100).reason):toBe("warband_order_invalid")
			cfg = table.clone(settings)
			cfg.inviteSeconds = 2
			local invited = assert(Module.warband(cfg).transition(state, {
				kind = "invite",
				actorPartyId = "p1",
				actorId = "1",
				expectedRevision = state.revision,
				targetPartyId = "p4",
			}, {
				p1 = parties().p1,
				p4 = { realmId = "north", leaderId = "4", characterId = "c4", connected = true },
			}, 100).state)
			expect(invited.invites.p4.expiresAtSec):toBe(102)
			cfg.transferSeconds = 2
			local transfer = assert(Module.warband(cfg).transition(state, {
				kind = "transfer",
				actorPartyId = "p1",
				actorId = "1",
				expectedRevision = state.revision,
				targetPartyId = "p2",
			}, parties(), 100).state)
			expect(assert(transfer.transfer).expiresAtSec):toBe(102)
			cfg.successionSeconds = 1
			local rows = parties()
			rows.p1.connected, rows.p1.absentSinceSec = false, 100
			local observed = assert(
				Module.warband(cfg)
					.transition(state, { kind = "observe", actorPartyId = "", actorId = "", expectedRevision = 0 }, rows, 101).state
			)
			expect(observed.commanderPartyId):toBe("p2")
		end)
	end)
end
