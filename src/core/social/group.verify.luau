--!strict

local Module = require("./group")
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
		recoveryTtlSec = 900,
		relationsMaxAgeSec = 15,
		maxTickets = 12,
		maxRoster = 64,
		maxRevision = 1000000000,
		maxTime = 1000000000000,
		maxId = 128,
		maxFingerprint = 1024,
	}
	local Core = Module.group(settings)

	type Relations = Shape.Raw
	type Request = Shape.Raw
	type Authority = Module.Authority
	type AuthorityCall = {
		groupId: string,
		operation: string,
		actorUserId: number,
		subjectUserId: number,
		nowSec: number,
	}
	local GROUP = "group.woodland.1"
	local NOW = 1000
	local INVITER = 201
	local MEMBER = 202
	local CANDIDATE = 301

	local function relations<T>(userId: number, readAtSec: number, overrides: T?)
		local row: Shape.Raw = {
			readAtSec = readAtSec,
			memberUserId = userId,
			moderationEligible = true,
			blockedUserIds = {},
			moderationDeniedUserIds = {},
			optedOutUserIds = {},
		}
		if overrides ~= nil then
			for key, value in assert(Shape.raw(overrides)) do
				row[key] = value
			end
		end
		return row
	end

	local function admission(memberRows: unknown, subject: unknown)
		return { members = memberRows, subject = subject }
	end

	local function standard(readAtSec: number?)
		local at = readAtSec or NOW
		return admission({ relations(INVITER, at), relations(MEMBER, at) }, relations(CANDIDATE, at))
	end

	local function request<T>(overrides: T?)
		local row: Shape.Raw = { groupId = GROUP, inviterUserId = INVITER, candidateUserId = CANDIDATE }
		if overrides ~= nil then
			for key, value in assert(Shape.raw(overrides)) do
				row[key] = value
			end
		end
		return row
	end

	local function authority(accept: boolean): (Authority, { AuthorityCall })
		local calls: { AuthorityCall } = {}
		local surface: Authority = {
			validate = function(
				groupId: string,
				operation: string,
				actorUserId: number,
				subjectUserId: number,
				nowSec: number
			)
				table.insert(calls, {
					groupId = groupId,
					operation = operation,
					actorUserId = actorUserId,
					subjectUserId = subjectUserId,
					nowSec = nowSec,
				})
				return accept
			end,
		}
		return surface, calls
	end

	local function accepting()
		local surface = authority(true)
		return surface
	end

	local function stateCopy(value: Module.State): Module.State
		local out = table.clone(value)
		out.tickets = {}
		for _, ticket in value.tickets do
			table.insert(out.tickets, table.clone(ticket))
		end
		out.receipts = table.clone(value.receipts)
		return out
	end

	local function expectDeepFrozen(value: unknown)
		if type(value) ~= "table" then
			return
		end
		expect((table.isfrozen(value))):toBe(true)
		for key, child in value do
			expectDeepFrozen(key)
			expectDeepFrozen(child)
		end
	end

	local function refusedUntouched(admissionValue: unknown, requestValue: unknown, reason: string, nowSec: number?)
		local surface, calls = authority(true)
		local decision = Core.admit(admissionValue, requestValue, nowSec or NOW, surface)
		expect(decision.ok):toBe(false)
		expect(decision.reason):toBe(reason)
		expect(#calls):toBe(0)
	end

	local function applied(result: Module.Result): Module.State
		if not result.ok then
			error("expected applied, got " .. tostring(result.reason), 2)
		end
		return assert(result.state)
	end

	local function rejected(result: Module.Result, reason: string)
		expect(result.ok):toBe(false)
		expect(result.reason):toBe(reason)
	end

	local function empty(): Module.State
		return assert(Core.emptyState(GROUP))
	end

	local function depart(
		state: Module.State,
		userId: number,
		nowSec: number,
		memberRows: unknown?,
		eventId: string?
	): Module.Result
		local surface = authority(true)
		local rows = memberRows or { relations(INVITER, nowSec), relations(MEMBER, nowSec) }
		return Core.transition(state, {
			kind = "depart",
			eventId = eventId or ("depart." .. userId),
			expectedRevision = state.revision,
			userId = userId,
		}, nowSec, admission(rows, relations(userId, nowSec)), surface)
	end

	describe("GroupCore", function()
		it("refuses a candidate a non-inviting member has blocked before the authority is consulted", function()
			refusedUntouched(
				admission(
					{ relations(INVITER, NOW), relations(MEMBER, NOW, { blockedUserIds = { CANDIDATE } }) },
					relations(CANDIDATE, NOW)
				),
				request(),
				"blocked"
			)
		end)

		it("refuses a candidate who has blocked a non-inviting member before the authority is consulted", function()
			refusedUntouched(
				admission(
					{ relations(INVITER, NOW), relations(MEMBER, NOW) },
					relations(CANDIDATE, NOW, { blockedUserIds = { MEMBER } })
				),
				request(),
				"blocked"
			)
		end)

		it("refuses a moderation-denied candidate in either direction", function()
			refusedUntouched(
				admission(
					{ relations(INVITER, NOW), relations(MEMBER, NOW) },
					relations(CANDIDATE, NOW, { moderationEligible = false })
				),
				request(),
				"moderation_denied"
			)
			refusedUntouched(
				admission(
					{ relations(INVITER, NOW), relations(MEMBER, NOW, { moderationDeniedUserIds = { CANDIDATE } }) },
					relations(CANDIDATE, NOW)
				),
				request(),
				"moderation_denied"
			)
			refusedUntouched(
				admission(
					{ relations(INVITER, NOW), relations(MEMBER, NOW) },
					relations(CANDIDATE, NOW, { moderationDeniedUserIds = { MEMBER } })
				),
				request(),
				"moderation_denied"
			)
		end)

		it("refuses an opted-out candidate in either direction", function()
			refusedUntouched(
				admission(
					{ relations(INVITER, NOW), relations(MEMBER, NOW, { optedOutUserIds = { CANDIDATE } }) },
					relations(CANDIDATE, NOW)
				),
				request(),
				"privacy_denied"
			)
			refusedUntouched(
				admission(
					{ relations(INVITER, NOW), relations(MEMBER, NOW) },
					relations(CANDIDATE, NOW, { optedOutUserIds = { MEMBER } })
				),
				request(),
				"privacy_denied"
			)
		end)

		it("refuses a platform read older than the freshness window and admits at the exact boundary", function()
			refusedUntouched(standard(NOW - Core.RELATIONS_MAX_AGE_SEC - 1), request(), "relations_stale")
			local surface, calls = authority(true)
			local boundary = Core.admit(standard(NOW - Core.RELATIONS_MAX_AGE_SEC), request(), NOW, surface)
			expect(boundary.ok):toBe(true)
			expect(#calls):toBe(1)
		end)

		it("refuses a platform read stamped after the decision clock", function()
			refusedUntouched(standard(NOW + 1), request(), "relations_unread")
		end)

		it("refuses an admission carrying no member reads at all", function()
			refusedUntouched(admission({}, relations(CANDIDATE, NOW)), request(), "relations_missing")
			refusedUntouched(admission({ relations(INVITER, NOW) }, nil), request(), "relations_missing")
		end)

		it("refuses a subject read that is not the candidate's own", function()
			refusedUntouched(
				admission({ relations(INVITER, NOW), relations(MEMBER, NOW) }, relations(999, NOW)),
				request(),
				"relations_conflict"
			)
			refusedUntouched(
				admission({ relations(INVITER, NOW), relations(INVITER, NOW) }, relations(CANDIDATE, NOW)),
				request(),
				"relations_conflict"
			)
		end)

		it("refuses an unknown inviter, a self invite, and an existing member", function()
			refusedUntouched(standard(), request({ inviterUserId = 999 }), "inviter_unknown")
			refusedUntouched(
				admission({ relations(INVITER, NOW), relations(MEMBER, NOW) }, relations(CANDIDATE, NOW)),
				request({ inviterUserId = CANDIDATE }),
				"self_target"
			)
			refusedUntouched(
				admission({ relations(INVITER, NOW), relations(MEMBER, NOW) }, relations(MEMBER, NOW)),
				request({ candidateUserId = MEMBER }),
				"already_member"
			)
		end)

		it("refuses malformed clocks, requests, and relation shapes before the authority is consulted", function()
			refusedUntouched(standard(), request(), "invalid_clock", -1)
			refusedUntouched(standard(), request({ extra = 1 }), "invalid_request")
			refusedUntouched(standard(), request({ candidateUserId = 0 }), "invalid_request")
			refusedUntouched(
				admission({ relations(INVITER, NOW, { blockedUserIds = { 5, 4 } }) }, relations(CANDIDATE, NOW)),
				request(),
				"invalid_relations"
			)
			refusedUntouched(
				admission({ relations(INVITER, NOW, { extra = true }) }, relations(CANDIDATE, NOW)),
				request(),
				"invalid_relations"
			)
		end)

		it("admits only through the server-observed authority named last", function()
			local surface, calls = authority(true)
			local decision = Core.admit(standard(), request(), NOW, surface)
			expect(decision.ok):toBe(true)
			expect(decision.reason):toBeNil()
			expect(#calls):toBe(1)
			expect(calls[1]):toEqual({
				groupId = GROUP,
				operation = "admit",
				actorUserId = INVITER,
				subjectUserId = CANDIDATE,
				nowSec = NOW,
			})
			expectDeepFrozen(decision)

			local refusing = authority(false)
			local refused = Core.admit(standard(), request(), NOW, refusing)
			expect(refused.ok):toBe(false)
			expect(refused.reason):toBe("admission_denied")

			expect(Core.admit(standard(), request(), NOW, {
				validate = function()
					return true
				end,
				extra = 1,
			}).reason):toBe("admission_denied")
			expect(Core.admit(standard(), request(), NOW, nil).reason):toBe("admission_denied")
		end)

		it("hides blocked, moderation-denied, and opted-out rows from a projected roster", function()
			local viewer = relations(INVITER, NOW, {
				blockedUserIds = { 301 },
				moderationDeniedUserIds = { 302 },
				optedOutUserIds = { 303 },
			})
			local visible = assert(Core.visibleRoster(viewer, { INVITER, 301, 302, 303, 304 }, NOW))
			expect(visible):toEqual({ INVITER, 304 })
			expectDeepFrozen(visible)
		end)

		it("shows a viewer who is not moderation-eligible an empty roster", function()
			local viewer = relations(INVITER, NOW, { moderationEligible = false })
			expect((Core.visibleRoster(viewer, { INVITER, MEMBER, CANDIDATE }, NOW))):toEqual({})
		end)

		it("refuses to project a roster from a stale, unread, or malformed read", function()
			expect((Core.visibleRoster(relations(INVITER, NOW - Core.RELATIONS_MAX_AGE_SEC - 1), { MEMBER }, NOW))):toBeNil()
			expect((Core.visibleRoster(relations(INVITER, NOW + 1), { MEMBER }, NOW))):toBeNil()
			expect((Core.visibleRoster(relations(INVITER, NOW), { MEMBER, MEMBER }, NOW))):toBeNil()
			expect((Core.visibleRoster(relations(INVITER, NOW), { 0 }, NOW))):toBeNil()
			expect((Core.visibleRoster(relations(INVITER, NOW), { MEMBER }, -1))):toBeNil()
			local oversize: { number } = {}
			for index = 1, Core.MAX_ROSTER + 1 do
				oversize[index] = 400 + index
			end
			expect((Core.visibleRoster(relations(INVITER, NOW), oversize, NOW))):toBeNil()
		end)

		it("mints a recovery ticket expiring at the exact recovery window", function()
			local state = applied(depart(empty(), CANDIDATE, NOW))
			expect(state.tickets):toEqual({
				{ userId = CANDIDATE, departedAtSec = NOW, expiresAtSec = NOW + Core.RECOVERY_TTL_SEC },
			})
			expect(state.revision):toBe(1)
			expect(state.lastClockSec):toBe(NOW)
			expect(state.relationsReadAtSec):toBe(NOW)
			expectDeepFrozen(state)
		end)

		it("refreshes an existing recovery ticket without duplicating it or changing the prior state", function()
			local first = applied(depart(empty(), CANDIDATE, NOW))
			local prior = applied(depart(first, CANDIDATE + 1, NOW + 1))
			local state = applied(depart(prior, CANDIDATE, NOW + 2, nil, "depart.refresh"))
			expect(#state.tickets):toBe(2)
			expect(state.tickets[1].userId):toBe(CANDIDATE + 1)
			expect(state.tickets[2]):toEqual({
				userId = CANDIDATE,
				departedAtSec = NOW + 2,
				expiresAtSec = NOW + 2 + Core.RECOVERY_TTL_SEC,
			})
			expect(prior.tickets[1].userId):toBe(CANDIDATE)
			expect(prior.tickets[1].departedAtSec):toBe(NOW)
		end)

		it("refuses recovery for a member blocked while away before the authority is consulted", function()
			local state = applied(depart(empty(), CANDIDATE, NOW))
			local surface, calls = authority(true)
			local result = Core.transition(
				state,
				{
					kind = "recover",
					eventId = "recover.1",
					expectedRevision = state.revision,
					userId = CANDIDATE,
				},
				NOW + 100,
				admission({
					relations(INVITER, NOW + 100),
					relations(MEMBER, NOW + 100, { blockedUserIds = { CANDIDATE } }),
				}, relations(CANDIDATE, NOW + 100)),
				surface
			)
			rejected(result, "blocked")
			expect(#calls):toBe(0)
			expect((assert(result.state)).tickets[1].userId):toBe(CANDIDATE)
		end)

		it("recovers a departed member through the authority and consumes the ticket exactly once", function()
			local state = applied(depart(empty(), CANDIDATE, NOW))
			local surface, calls = authority(true)
			local result = Core.transition(
				state,
				{
					kind = "recover",
					eventId = "recover.1",
					expectedRevision = state.revision,
					userId = CANDIDATE,
				},
				NOW + 100,
				admission({
					relations(INVITER, NOW + 100),
					relations(MEMBER, NOW + 100),
				}, relations(CANDIDATE, NOW + 100)),
				surface
			)
			local recovered = applied(result)
			expect(result.recoveredUserId):toBe(CANDIDATE)
			expect(recovered.tickets):toEqual({})
			expect(#calls):toBe(1)
			expect(calls[1].operation):toBe("recover")

			local second = Core.transition(
				recovered,
				{
					kind = "recover",
					eventId = "recover.2",
					expectedRevision = recovered.revision,
					userId = CANDIDATE,
				},
				NOW + 200,
				admission({
					relations(INVITER, NOW + 200),
					relations(MEMBER, NOW + 200),
				}, relations(CANDIDATE, NOW + 200)),
				accepting()
			)
			rejected(second, "ticket_unknown")
		end)

		it("expires a recovery ticket at the exact recovery boundary", function()
			local state = applied(depart(empty(), CANDIDATE, NOW))
			local last = NOW + Core.RECOVERY_TTL_SEC - 1
			local live = applied(
				Core.transition(
					state,
					{
						kind = "recover",
						eventId = "recover.last",
						expectedRevision = state.revision,
						userId = CANDIDATE,
					},
					last,
					admission({ relations(INVITER, last), relations(MEMBER, last) }, relations(CANDIDATE, last)),
					accepting()
				)
			)
			expect(live.tickets):toEqual({})

			local at = NOW + Core.RECOVERY_TTL_SEC
			local surface, calls = authority(true)
			rejected(
				Core.transition(state, {
					kind = "recover",
					eventId = "recover.expired",
					expectedRevision = state.revision,
					userId = CANDIDATE,
				}, at, admission({ relations(INVITER, at), relations(MEMBER, at) }, relations(CANDIDATE, at)), surface),
				"ticket_unknown"
			)
			expect(#calls):toBe(0)
		end)

		it("refuses recovery for a user who is already a current member", function()
			local state = applied(depart(empty(), CANDIDATE, NOW))
			local at = NOW + 10
			local surface, calls = authority(true)
			rejected(
				Core.transition(
					state,
					{
						kind = "recover",
						eventId = "recover.member",
						expectedRevision = state.revision,
						userId = CANDIDATE,
					},
					at,
					admission({ relations(INVITER, at), relations(CANDIDATE, at) }, relations(CANDIDATE, at)),
					surface
				),
				"already_member"
			)
			expect(#calls):toBe(0)
		end)

		it("drops tickets of users blocked or denied since departure on reconciliation", function()
			local state = applied(depart(empty(), CANDIDATE, NOW))
			state = applied(depart(state, 302, NOW + 1))
			expect(#state.tickets):toBe(2)
			local at = NOW + 10
			local reconciled = applied(Core.transition(
				state,
				{
					kind = "reconcile",
					eventId = "reconcile.1",
					expectedRevision = state.revision,
				},
				at,
				admission({
					relations(INVITER, at),
					relations(MEMBER, at, { blockedUserIds = { CANDIDATE } }),
				}, nil),
				accepting()
			))
			expect(#reconciled.tickets):toBe(1)
			expect(reconciled.tickets[1].userId):toBe(302)
		end)

		it("never leaves a persisting ticket for a departing member the group has denied", function()
			local result = depart(empty(), CANDIDATE, NOW, {
				relations(INVITER, NOW),
				relations(MEMBER, NOW, { blockedUserIds = { CANDIDATE } }),
			})
			local state = applied(result)
			expect(state.tickets):toEqual({})
			expect(state.revision):toBe(1)
		end)

		it("evicts the earliest-expiring ticket rather than refusing a departure when full", function()
			local state = empty()
			for offset = 0, Core.MAX_TICKETS do
				state = applied(depart(state, 301 + offset, NOW + offset))
			end
			expect(#state.tickets):toBe(Core.MAX_TICKETS)
			expect(state.tickets[1].userId):toBe(302)
			expect(state.tickets[Core.MAX_TICKETS].userId):toBe(301 + Core.MAX_TICKETS)
			for _, ticket in state.tickets do
				expect((ticket.userId == 301)):toBe(false)
			end
		end)

		it("refuses a platform read older than the one the ledger has already observed", function()
			local state = applied(depart(empty(), CANDIDATE, NOW))
			local surface, calls = authority(true)
			local at = NOW + 5
			rejected(
				Core.transition(state, {
					kind = "reconcile",
					eventId = "reconcile.regressed",
					expectedRevision = state.revision,
				}, at, admission({ relations(INVITER, NOW - 5), relations(MEMBER, at) }, nil), surface),
				"relations_regressed"
			)
			expect(#calls):toBe(0)
		end)

		it("replays exact receipts without recovering anyone and rejects conflicts and stale revisions", function()
			local source = empty()
			local event = {
				kind = "depart",
				eventId = "depart.301",
				expectedRevision = 0,
				userId = CANDIDATE,
			}
			local first = applied(
				Core.transition(
					source,
					event,
					NOW,
					admission({ relations(INVITER, NOW), relations(MEMBER, NOW) }, relations(CANDIDATE, NOW)),
					accepting()
				)
			)
			local replayResult = Core.transition(
				first,
				event,
				NOW,
				admission({ relations(INVITER, NOW), relations(MEMBER, NOW) }, relations(CANDIDATE, NOW)),
				accepting()
			)
			local replay = applied(replayResult)
			expect(replayResult.replayed):toBe(true)
			expect(replayResult.recoveredUserId):toBeNil()
			expect(replay.revision):toBe(1)
			expect(#replay.tickets):toBe(1)

			local conflict = table.clone(event)
			conflict.userId = 302
			rejected(
				Core.transition(
					first,
					conflict,
					NOW,
					admission({ relations(INVITER, NOW), relations(MEMBER, NOW) }, relations(302, NOW)),
					accepting()
				),
				"receipt_conflict"
			)

			local stale = table.clone(event)
			stale.eventId = "depart.stale"
			rejected(
				Core.transition(
					first,
					stale,
					NOW,
					admission({ relations(INVITER, NOW), relations(MEMBER, NOW) }, relations(CANDIDATE, NOW)),
					accepting()
				),
				"revision_conflict"
			)
			expect(source.tickets):toEqual({})
		end)

		it("refuses malformed state, events, and backward clocks before the authority is consulted", function()
			local surface, calls = authority(true)
			rejected(
				Core.transition({ schemaVersion = 2 }, {
					kind = "reconcile",
					eventId = "e",
					expectedRevision = 0,
				}, NOW, standard(), surface),
				"invalid_state"
			)
			local state = applied(depart(empty(), CANDIDATE, NOW))
			rejected(
				Core.transition(state, {
					kind = "browse",
					eventId = "e",
					expectedRevision = state.revision,
				}, NOW, standard(), surface),
				"invalid_event"
			)
			rejected(
				Core.transition(state, {
					kind = "reconcile",
					eventId = "e",
					expectedRevision = state.revision,
				}, NOW - 1, standard(NOW - 1), surface),
				"invalid_clock"
			)
			rejected(
				Core.transition(state, {
					kind = "depart",
					eventId = "e",
					expectedRevision = state.revision,
					userId = CANDIDATE,
				}, NOW, admission({ relations(INVITER, NOW) }, relations(302, NOW)), surface),
				"relations_conflict"
			)
			expect(#calls):toBe(0)
		end)

		it("rejects malformed tickets and returns deeply fresh frozen projections", function()
			local state = applied(depart(empty(), CANDIDATE, NOW))
			local malformed = stateCopy(state)
			malformed.tickets[1].expiresAtSec += 1
			expect((Core.projectState(malformed))):toBeNil()
			malformed = stateCopy(state)
			malformed.tickets[2] = table.clone(malformed.tickets[1])
			expect((Core.projectState(malformed))):toBeNil()
			malformed = stateCopy(state)
			malformed.tickets[1].departedAtSec = state.lastClockSec + 1
			malformed.tickets[1].expiresAtSec = state.lastClockSec + 1 + Core.RECOVERY_TTL_SEC
			expect((Core.projectState(malformed))):toBeNil()

			local first = assert(Core.projectState(state))
			local second = assert(Core.projectState(state))
			expect((first == second)):toBe(false)
			expect((first.tickets == second.tickets)):toBe(false)
			expect((first.tickets[1] == second.tickets[1])):toBe(false)
			expectDeepFrozen(first)
			expect((Core.projectRelations(relations(INVITER, NOW), NOW))):toEqual(relations(INVITER, NOW))
			expect((Core.projectRelations(relations(INVITER, NOW - 100), NOW))):toBeNil()
		end)
	end)

	it("refuses nonnumeric roster entries without throwing", function()
		expect(Core.visibleRoster(relations(INVITER, NOW), { "invalid" }, NOW)):toBeNil()
	end)

	it("uses configured recovery, projection, roster and relation freshness bounds", function()
		local source = applied(depart(empty(), CANDIDATE, NOW))
		local changes: { (Module.Config) -> () } = {
			function(cfg)
				cfg.maxTickets = 0
			end,
			function(cfg)
				cfg.maxRevision = 0
			end,
			function(cfg)
				cfg.maxTime = NOW - 1
			end,
			function(cfg)
				cfg.maxId = 1
			end,
			function(cfg)
				cfg.maxFingerprint = 1
			end,
			function(cfg)
				cfg.recoveryTtlSec = 1
			end,
		}
		for _, change in changes do
			local cfg: Module.Config = table.clone(settings)
			change(cfg)
			expect(Module.group(cfg).projectState(source)):toBeNil()
		end
		local cfg: Module.Config = table.clone(settings)
		cfg.maxRoster = 1
		expect(Module.group(cfg).admit(standard(), request(), NOW, accepting()).reason):toBe("invalid_relations")
		cfg = table.clone(settings)
		cfg.relationsMaxAgeSec = 0
		expect(Module.group(cfg).admit(standard(NOW - 1), request(), NOW, accepting()).reason):toBe("relations_stale")
	end)
end
