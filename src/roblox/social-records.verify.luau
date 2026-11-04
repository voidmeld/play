--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Notes = require("../core/social/notes")
local Records = require("./social-records")
local Social = require("../test-scene/social")
local Value = require("../kernel/value")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	local CHARTER = {
		fellowshipId = "f1",
		nameId = "group_a",
		realmId = "realm_a",
		homeSlotId = "zone_a.guild_banner.village_courtyard",
		stewardUserId = 1,
		stewardName = "Alden",
	}

	local FORMATION_REQUEST = {
		formationId = "g1",
		nameId = "group_a",
		realmId = "realm_a",
		homeSlotId = "zone_a.guild_banner.village_courtyard",
		initiatorId = 1,
		initiatorName = "Alden",
	}

	describe("social records durable guild record", function()
		it(
			"refuses missing and malformed write results while preserving committed guild and formation records",
			function()
				local corruptors = {
					function(_value: unknown): unknown
						return nil
					end,
					function(_value: unknown): unknown
						return false
					end,
					function(_value: unknown): unknown
						return { invalid = true }
					end,
				}
				for _, corrupt in corruptors do
					local service, _values, counters = Social.rig(corrupt)
					local founded = service.found(CHARTER)
					expect(founded.ok):toBe(false)
					expect(founded.state):toBeNil()
					expect(founded.reason):toBe("readback_mismatch")
					expect(service.read("f1").ok):toBe(true)
					local formation = service.startFormation(FORMATION_REQUEST)
					expect(formation.ok):toBe(false)
					expect(formation.state):toBeNil()
					expect(formation.reason):toBe("readback_mismatch")
					expect(service.readFormation("g1").ok):toBe(true)
					expect(counters.writes):toBe(2)
				end
			end
		)

		it("refuses foreign guild and formation identities before applying events", function()
			local invitation = {
				kind = "invite",
				eventId = "i1",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "realm_a",
			}
			local service, values, counters = Social.rig()
			assert(service.found(CHARTER).ok)
			local guild = table.clone(assert(service.read("f1").state))
			guild.fellowshipId = "other"
			values["fellowship/f1"] = guild
			local before = counters.writes
			expect(service.read("f1").ok):toBe(false)
			expect(service.apply("f1", invitation).ok):toBe(false)
			expect(counters.writes):toBe(before)
			expect(values["fellowship/f1"]):toBe(guild)
			local formed = service.startFormation(FORMATION_REQUEST)
			local formation = table.clone(assert(formed.state))
			formation.formationId = "other"
			values["fellowship/formation:g1"] = formation
			before = counters.writes
			expect(service.readFormation("g1").ok):toBe(false)
			expect(service.applyFormation("g1", invitation).ok):toBe(false)
			expect(counters.writes):toBe(before)
			expect(values["fellowship/formation:g1"]):toBe(formation)
		end)

		it("founds a record once and refuses a second charter under the same id", function()
			local service = Social.rig()
			expect(service.found(CHARTER).ok):toBe(true)
			local again = service.found(CHARTER)
			expect(again.ok):toBe(false)
			expect(again.reason):toBe("fellowship_exists")
			expect(assert(service.read("f1").state).members[1].name):toBe("Alden")
			expect(service.read("missing").reason):toBe("fellowship_unknown")
		end)

		it("applies an event on a server whose clock trails the record's last write", function()
			local service, _values, counters = Social.rig()
			service.found(CHARTER)
			counters.clock = 90
			local invited = service.apply("f1", {
				kind = "invite",
				eventId = "e1",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "realm_a",
			})
			expect(invited.ok):toBe(true)
			expect(assert(invited.state).revision):toBe(1)
		end)

		it("refuses old schemas without rewriting their stored records", function()
			for _, version in { 2, 3 } do
				local service, values, counters = Social.rig()
				service.found(CHARTER)
				local previous = assert(Value.raw(values["fellowship/f1"]))
				previous.schemaVersion = version
				previous.creed = nil
				if version == 2 then
					previous.officers, previous.stewardSeenAtSec, previous.audit = nil, nil, nil
				end
				values["fellowship/f1"] = previous
				local before = counters.writes
				expect(service.read("f1").ok):toBe(false)
				local event = {
					kind = "invite",
					eventId = "e1",
					expectedRevision = 0,
					actorUserId = 1,
					targetUserId = 2,
					targetRealmId = "realm_a",
				}
				local refused = service.apply("f1", event)
				expect(refused.ok):toBe(false)
				expect(refused.reason):toBe("record_invalid")
				expect(counters.writes):toBe(before)
				expect(values["fellowship/f1"]):toBe(previous)
				expect(previous.schemaVersion):toBe(version)
			end
		end)

		it("lets only one of a returning steward and a claiming officer win the same revision", function()
			local service, _values, counters = Social.rig()
			service.found(CHARTER)
			local function step(event: unknown)
				return service.apply("f1", event)
			end
			expect(step({
				kind = "invite",
				eventId = "i2",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "realm_a",
			}).ok):toBe(true)
			expect(step({
				kind = "accept",
				eventId = "a2",
				expectedRevision = 1,
				actorUserId = 2,
				actorRealmId = "realm_a",
				actorName = "Bryn",
			}).ok):toBe(true)
			expect(
				step({ kind = "promote", eventId = "p2", expectedRevision = 2, actorUserId = 1, targetUserId = 2 }).ok
			):toBe(true)
			counters.clock += 31 * 24 * 60 * 60
			local claim = { kind = "claim", eventId = "claim", expectedRevision = 3, actorUserId = 2 }
			local returning = { kind = "seen", eventId = "seen", expectedRevision = 3, actorUserId = 1 }
			expect(step(returning).ok):toBe(true)
			local late = step(claim)
			expect(late.ok):toBe(false)
			expect(late.reason):toBe("revision_conflict")
			local retried = step({ kind = "claim", eventId = "claim2", expectedRevision = 4, actorUserId = 2 })
			expect(retried.reason):toBe("steward_present")
			expect(assert(service.read("f1").state).stewardUserId):toBe(1)
		end)

		it("forms a guild once from five consenting founders even when two servers complete together", function()
			local service = Social.rig()
			local formed = service.startFormation(FORMATION_REQUEST)
			expect(formed.ok):toBe(true)
			expect(service.startFormation(FORMATION_REQUEST).reason):toBe("formation_exists")
			local revision = 0
			local function apply(event: { [string]: unknown })
				event.expectedRevision = revision
				local result = service.applyFormation("g1", event)
				if result.ok and not result.replayed then
					revision = assert(result.state).revision
				end
				return result
			end
			for id = 2, 5 do
				expect(apply({
					kind = "invite",
					eventId = "i" .. id,
					actorUserId = 1,
					targetUserId = id,
					targetRealmId = "realm_a",
				}).ok):toBe(true)
				expect(apply({
					kind = "consent",
					eventId = "c" .. id,
					actorUserId = id,
					actorRealmId = "realm_a",
					actorName = "M" .. id,
				}).ok):toBe(true)
			end
			expect(apply({ kind = "fee_held", eventId = "fee", actorUserId = 1 }).ok):toBe(true)
			local before = revision
			local first = apply({ kind = "complete", eventId = "done-a", actorUserId = 1 })
			revision = before
			local second = apply({ kind = "complete", eventId = "done-b", actorUserId = 1 })
			expect(first.ok):toBe(true)
			expect(second.ok):toBe(false)
			expect(second.reason):toBe("revision_conflict")
			local state = assert(service.readFormation("g1").state)
			local founded = service.foundFromFormation(state)
			expect(founded.ok):toBe(true)
			expect(#assert(founded.state).members):toBe(5)
			expect(service.foundFromFormation(state).reason):toBe("fellowship_exists")
			local corrupt = Social.rig(function(_value: unknown): unknown
				return nil
			end)
			local uncertain = corrupt.foundFromFormation(state)
			expect(uncertain.ok):toBe(false)
			expect(uncertain.state):toBeNil()
			expect(uncertain.reason):toBe("readback_mismatch")
			expect(#assert(corrupt.read(state.fellowshipId).state).members):toBe(5)
		end)

		it("answers an exact replay from the record without writing again", function()
			local service, _values, counters = Social.rig()
			service.found(CHARTER)
			local event = {
				kind = "invite",
				eventId = "e1",
				expectedRevision = 0,
				actorUserId = 1,
				targetUserId = 2,
				targetRealmId = "realm_a",
			}
			service.apply("f1", event)
			local writes = counters.writes
			local replay = service.apply("f1", event)
			expect(replay.ok):toBe(true)
			expect(replay.replayed):toBe(true)
			expect(counters.writes):toBe(writes)
		end)

		it("refuses a stale revision and a corrupt record without writing", function()
			local service, values, counters = Social.rig()
			service.found(CHARTER)
			local writes = counters.writes
			local stale = service.apply("f1", { kind = "leave", eventId = "e2", expectedRevision = 7, actorUserId = 1 })
			expect(stale.reason):toBe("revision_conflict")
			values["fellowship/f1"] = { schemaVersion = 1 }
			expect(
				service.apply("f1", { kind = "leave", eventId = "e3", expectedRevision = 0, actorUserId = 1 }).reason
			):toBe("record_invalid")
			expect(counters.writes):toBe(writes)
		end)
	end)

	describe("social records durable membership index", function()
		for _, operation in { "membership", "formation pointer" } do
			it("refuses tentative " .. operation .. " authority after a cancelled speculative retry", function()
				local store: Records.Store = {
					getOutcome = function(_key: string): Records.Outcome
						return { ok = true, value = nil }
					end,
					updateOutcome = function(_key: string, transform: (unknown) -> unknown): Records.Outcome
						local proposed = transform(nil)
						assert(proposed ~= nil)
						assert(transform(proposed) == nil)
						return { ok = false, value = nil, reason = "callback_cancelled" }
					end,
				}
				local service = Social.rig(nil, { store = store })
				local outcome = if operation == "membership"
					then service.claimMembership(7, "f1")
					else service.setProposerFormation(7, "g1")
				expect(outcome.ok):toBe(false)
				expect(service.readMembership(7).membership):toBeNil()
				expect(service.readProposerFormation(7).formationId):toBeNil()
			end)
		end

		it("claims a pending membership, confirms it, and releases only its own guild", function()
			local service = Social.rig()
			local claimed = service.claimMembership(7, "f1")
			expect(claimed.ok):toBe(true)
			expect(assert(claimed.membership).pending):toBe(true)
			expect(assert(service.confirmMembership(7, "f1").membership).pending):toBe(false)
			local seen = assert(service.readMembership(7).membership)
			expect(
				assert(
					service.releaseMembership(7, { fellowshipId = "other", pending = false, revision = seen.revision }).membership
				).fellowshipId
			):toBe("f1")
			expect(service.releaseMembership(7, seen).membership):toBeNil()
			expect(service.readMembership(7).membership):toBeNil()
		end)

		it("refuses a second guild while one claim is held, even a pending one from another server", function()
			local service = Social.rig()
			service.claimMembership(7, "f1")
			local second = service.claimMembership(7, "f2")
			expect(second.ok):toBe(false)
			expect(second.reason):toBe("membership_held")
			expect(service.claimMembership(7, "f1").ok):toBe(true)
		end)

		it("refuses to confirm a claim that moved elsewhere", function()
			local service = Social.rig()
			service.claimMembership(7, "f1")
			expect(service.confirmMembership(7, "f2").reason):toBe("membership_moved")
		end)
	end)

	describe("social records membership release is compare-and-swap", function()
		it("keeps a claim that was rewritten after the releaser read it", function()
			local service = Social.rig()
			service.claimMembership(7, "f1")
			local stale = assert(service.readMembership(7).membership)
			service.confirmMembership(7, "f1")
			local kept = service.releaseMembership(7, stale)
			expect(kept.ok):toBe(true)
			expect(assert(kept.membership).fellowshipId):toBe("f1")
			expect(assert(kept.membership).pending):toBe(false)
			expect(assert(service.readMembership(7).membership).fellowshipId):toBe("f1")
		end)

		it("keeps a fresh claim of the same guild made after an earlier release", function()
			local service = Social.rig()
			service.claimMembership(7, "f1")
			local first = assert(service.readMembership(7).membership)
			service.releaseMembership(7, first)
			service.claimMembership(7, "f1")
			expect(assert(service.releaseMembership(7, first).membership).fellowshipId):toBe("f1")
			expect(assert(service.readMembership(7).membership).revision > first.revision):toBe(true)
		end)
	end)

	type Counter = { n: number }
	type Command = { kind: string, id: string }

	local function counterCore(): Records.LedgerCore<string, Counter, string>
		local applied: { [string]: boolean } = {}
		return {
			empty = function(_subject: string): Counter
				return { n = 0 }
			end,
			project = function(value: unknown): Counter?
				local raw = Value.raw(value)
				return if raw ~= nil and type(raw.n) == "number" then { n = raw.n } else nil
			end,
			apply = function(state: Counter, command: unknown, _nowSec: number): Records.LedgerOutcome<Counter, string>
				local fields = Value.raw(command)
				local id = if fields ~= nil then fields.id else nil
				if type(id) ~= "string" then
					return {
						ok = false,
						state = nil,
						replayed = false,
						reason = "invalid_request",
						receipts = nil,
						fence = nil,
					}
				end
				if fields ~= nil and fields.kind == "refuse" then
					return {
						ok = false,
						state = nil,
						replayed = false,
						reason = "no_supply",
						receipts = nil,
						fence = nil,
					}
				end
				if applied[id] then
					return { ok = true, state = state, replayed = true, reason = nil, receipts = nil, fence = "f" }
				end
				return {
					ok = true,
					state = { n = state.n + 1 },
					replayed = false,
					reason = nil,
					receipts = { id },
					fence = nil,
				}
			end,
			invalid = "ledger_invalid",
		}
	end

	local function storeRig(mode: string?)
		local values: { [string]: unknown } = {}
		local counters = { writes = 0 }
		local store = {
			getOutcome = function(key: string): Records.Outcome
				return { ok = true, value = values[key], reason = nil }
			end,
			getUncachedOutcome = function(key: string): Records.Outcome
				return { ok = true, value = values[key], reason = nil }
			end,
			updateOutcome = function(key: string, transform: (unknown) -> unknown): Records.Outcome
				if mode == "fail_before" then
					return { ok = false, value = nil, reason = "circuit_open" }
				end
				local nextValue = transform(values[key])
				if nextValue == nil then
					return { ok = false, value = nil, reason = "callback_cancelled" }
				end
				counters.writes += 1
				values[key] = nextValue
				if mode == "commit_then_fail" then
					return { ok = false, value = nil, reason = "retry_exhausted" }
				end
				return { ok = true, value = nextValue, reason = nil }
			end,
		}
		return store, values, counters
	end

	local function ledgerRig(mode: string?)
		local store, values, counters = storeRig(mode)
		local ledger, reason = Records.ledger({
			store = store,
			keyFor = function(subject: string): string
				return "ledger/" .. subject
			end,
			clock = function(): number
				return 1000
			end,
			core = counterCore(),
		})
		return assert(ledger, reason), values, counters
	end

	describe("social records settled ledger", function()
		it("writes one command and reports a definitive refusal without writing", function()
			local ledger, _values, counters = ledgerRig()
			local first = ledger.apply("a", { kind = "add", id = "c1" })
			expect(first.ok):toBe(true)
			expect(assert(first.state).n):toBe(1)
			expect(first.ambiguous):toBe(false)
			local refused = ledger.apply("a", { kind = "refuse", id = "c2" })
			expect(refused.ok):toBe(false)
			expect(refused.reason):toBe("no_supply")
			expect(refused.ambiguous):toBe(false)
			expect(counters.writes):toBe(1)
		end)

		it("answers a replay with its fence and no receipts and writes nothing", function()
			local store = storeRig()
			local core = counterCore()
			local replaying = {
				empty = core.empty,
				project = core.project,
				apply = function(
					state: Counter,
					command: unknown,
					nowSec: number
				): Records.LedgerOutcome<Counter, string>
					local result = core.apply(state, command, nowSec)
					return {
						ok = result.ok,
						state = result.state,
						replayed = true,
						reason = nil,
						receipts = nil,
						fence = "f",
					}
				end,
				invalid = core.invalid,
			}
			local ledger = assert(Records.ledger({
				store = store,
				keyFor = function(subject: string): string
					return subject
				end,
				clock = function(): number
					return 1
				end,
				core = replaying,
			}))
			local replay = ledger.apply("a", { kind = "add", id = "c1" })
			expect(replay.ok):toBe(true)
			expect(replay.replayed):toBe(true)
			expect(replay.fence):toBe("f")
			expect(#assert(replay.receipts)):toBe(0)
		end)

		it("reports a storage failure as ambiguous whether or not the write landed", function()
			local before = ledgerRig("fail_before")
			local failed = before.apply("a", { kind = "add", id = "c1" })
			expect(failed.ok):toBe(false)
			expect(failed.ambiguous):toBe(true)
			expect(failed.reason):toBe("circuit_open")
			local landed, values = ledgerRig("commit_then_fail")
			local lost = landed.apply("a", { kind = "add", id = "c1" })
			expect(lost.ambiguous):toBe(true)
			expect(lost.reason):toBe("retry_exhausted")
			expect(values["ledger/a"] ~= nil):toBe(true)
		end)

		it("refuses a corrupt stored state as definitive", function()
			local ledger, values = ledgerRig()
			values["ledger/a"] = { n = "bad" }
			local read = ledger.read("a")
			expect(read.ok):toBe(false)
			expect(read.reason):toBe("ledger_invalid")
			expect(read.ambiguous):toBe(false)
			expect(ledger.apply("a", { kind = "add", id = "c1" }).ambiguous):toBe(false)
		end)
	end)

	local noteCore = Notes.notes({
		maxNotes = 40,
		maxNameLength = 64,
		maxIdLength = 128,
		maxPhraseIdLength = 64,
		maxPhraseTextLength = 80,
		maxReceipts = 80,
		maxPhrases = 12,
		noteTtlSec = 900,
		maxTime = 1000000000000,
		presetLabel = "System preset",
	})

	local function inboxRig(mode: string?)
		local store, _values, counters = storeRig(mode)
		local sequence = 0
		local inbox, reason = Records.inbox({
			store = store,
			keyFor = function(userId: number): string
				return "notes/" .. tostring(userId)
			end,
			clock = function(): number
				return 1000
			end,
			guid = function(): string
				sequence += 1
				return "note-" .. tostring(sequence)
			end,
			core = noteCore,
			invalid = "inbox_invalid",
		})
		return assert(inbox, reason), counters
	end

	describe("social records inbox", function()
		local PHRASE = "need_help"

		it("delivers to the recipient key only and reads the note back", function()
			local inbox = inboxRig()
			local delivered = inbox.deliver(5, "Bryn", 9, PHRASE)
			expect(delivered.reason):toBeNil()
			expect(#assert(inbox.inbox(9).notes)):toBe(if delivered.ok then 1 else 0)
			expect(#assert(inbox.inbox(5).notes)):toBe(0)
		end)

		it("refuses a note to oneself and a store refusal without writing", function()
			local inbox, counters = inboxRig()
			expect(inbox.deliver(5, "Bryn", 5, PHRASE).reason):toBe("self_target")
			expect(counters.writes):toBe(0)
			local closed = inboxRig("fail_before")
			local result = closed.deliver(5, "Bryn", 9, PHRASE)
			expect(result.ok):toBe(false)
			expect(result.reason):toBe("circuit_open")
		end)

		it("writes nothing when a read mark changes nothing", function()
			local inbox, counters = inboxRig()
			inbox.deliver(5, "Bryn", 9, PHRASE)
			local notes = assert(inbox.inbox(9).notes)
			if #notes == 0 then
				return
			end
			expect(inbox.markRead(9, notes[1].id).ok):toBe(true)
			local writes = counters.writes
			expect(inbox.markRead(9, notes[1].id).ok):toBe(true)
			expect(counters.writes):toBe(writes)
			expect(inbox.markRead(9, "missing").reason):toBe("note_unknown")
			expect(counters.writes):toBe(writes)
		end)
	end)

	type Slip = { id: string, owner: number }

	local function slipProject(value: unknown): Slip?
		local raw = Value.raw(value)
		if raw ~= nil and type(raw.id) == "string" and type(raw.owner) == "number" then
			return { id = raw.id, owner = raw.owner }
		end
		return nil
	end

	describe("social records keyed record", function()
		local function keyedRig()
			local store, values = storeRig()
			local keyed, reason = Records.keyed({
				store = store,
				keyFor = function(id: string): string
					return "slip/" .. id
				end,
				project = slipProject,
				wire = function(slip: Slip): unknown
					return if slip.owner > 0 then { id = slip.id, owner = slip.owner } else nil
				end,
				idOf = function(slip: Slip): string
					return slip.id
				end,
				prefix = "",
				invalid = "slip_invalid",
			})
			return assert(keyed, reason), values
		end

		it("creates a record and reads it back by identity", function()
			local keyed = keyedRig()
			local created = keyed.updateOutcome("s1", function(_current: Slip?): Slip?
				return { id = "s1", owner = 3 }
			end)
			expect(created.ok):toBe(true)
			expect(assert(keyed.getOutcome("s1").value).owner):toBe(3)
			expect(keyed.getOutcome("s2").value):toBeNil()
		end)

		it("cancels without writing when the transform declines", function()
			local keyed, values = keyedRig()
			local declined = keyed.updateOutcome("s1", function(_current: Slip?): Slip?
				return nil
			end)
			expect(declined.ok):toBe(false)
			expect(values["slip/s1"]):toBeNil()
		end)

		it("refuses a result that fails its wire or names another identity", function()
			local keyed, values = keyedRig()
			local unwired = keyed.updateOutcome("s1", function(_current: Slip?): Slip?
				return { id = "s1", owner = 0 }
			end)
			expect(unwired.reason):toBe("slip_invalid")
			local foreign = keyed.updateOutcome("s1", function(_current: Slip?): Slip?
				return { id = "s2", owner = 3 }
			end)
			expect(foreign.reason):toBe("slip_invalid")
			expect(values["slip/s1"]):toBeNil()
		end)

		it("refuses a stored record that names another identity", function()
			local keyed, values = keyedRig()
			values["slip/s1"] = { id = "s9", owner = 3 }
			expect(keyed.getOutcome("s1").reason):toBe("slip_invalid")
			local updated = keyed.updateOutcome("s1", function(_current: Slip?): Slip?
				return { id = "s1", owner = 3 }
			end)
			expect(updated.reason):toBe("slip_invalid")
		end)
	end)

	describe("social records bounded index", function()
		local function indexRig(limit: number)
			local store, values = storeRig()
			local index, reason = Records.index({
				store = store,
				keyFor = function(userId: number): string
					return "index/" .. tostring(userId)
				end,
				read = slipProject,
				idOf = function(slip: Slip): string
					return slip.id
				end,
				owns = function(slip: Slip, userId: number): boolean
					return slip.owner == userId
				end,
				same = function(left: Slip, right: Slip): boolean
					return left.owner == right.owner
				end,
				limit = limit,
			})
			return assert(index, reason), values
		end

		it("adds, lists and removes entries for their owner", function()
			local index = indexRig(2)
			expect((index.add(3, { id = "a", owner = 3 }))):toBe(true)
			expect(assert(index.list(3).entries).a.owner):toBe(3)
			expect(index.remove(3, { id = "a", owner = 3 })):toBe(true)
			expect((next(assert(index.list(3).entries)))):toBeNil()
		end)

		it("keeps an exact repeat idempotent and reports a changed repeat as a conflict", function()
			local index = indexRig(2)
			index.add(3, { id = "a", owner = 3 })
			expect((index.add(3, { id = "a", owner = 3 }))):toBe(true)
			local added, reason = index.add(3, { id = "a", owner = 4 })
			expect(added):toBe(false)
			expect(reason):toBe("request_conflict")
		end)

		it("refuses entries past the limit and a stored index that names a foreign owner", function()
			local index, values = indexRig(1)
			expect((index.add(3, { id = "a", owner = 3 }))):toBe(true)
			expect((index.add(3, { id = "b", owner = 3 }))):toBe(false)
			values["index/4"] = { a = { id = "a", owner = 3 } }
			expect(index.list(4).ok):toBe(false)
			expect(index.list(4).reason):toBe("inbox_unavailable")
			expect((index.add(4, { id = "c", owner = 4 }))):toBe(false)
		end)
	end)
end
