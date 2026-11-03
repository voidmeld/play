--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Channels = require("../core/chat/channels")
local NoteHost = require("./social-notes")
local Notes = require("../core/social/notes")
local Records = require("./social-records")
local Verify = require("../../.lute/dependencies/verify/src/core")
local WhisperHost = require("./social-whispers")

local core = Notes.notes({
	maxNotes = 4,
	maxNameLength = 32,
	maxIdLength = 64,
	maxPhraseIdLength = 32,
	maxPhraseTextLength = 80,
	maxReceipts = 8,
	maxPhrases = 4,
	noteTtlSec = 50,
	maxTime = 1000000000000,
	presetLabel = "Set phrases",
})
local noteHost = NoteHost.configure({
	phrases = core.phrases,
	live = core.live,
	presetLabel = core.PRESET_LABEL,
	sendIntervalSec = 3,
})
local whisperHost = WhisperHost.configure({
	pairName = function(a: number, b: number): string
		return Channels.pairName("private_", a, b)
	end,
	memberFallback = function(id: number): string
		return "Member " .. tostring(id)
	end,
})
local function noteRig()
	local values: { [string]: unknown } = {}
	local control =
		{ clock = 100, sequence = 0, permitted = true, filtered = true, hidden = false, notified = 0, writes = 0 }
	local inbox = assert(Records.inbox({
		store = {
			getOutcome = function(key: string): Records.Outcome
				return { ok = true, value = values[key] }
			end,
			updateOutcome = function(key: string, transform: (unknown) -> unknown): Records.Outcome
				local value = transform(values[key])
				if value == nil then
					return { ok = false, value = nil, reason = "cancelled" }
				end
				values[key] = value
				control.writes += 1
				return { ok = true, value = value }
			end,
		},
		keyFor = function(id: number): string
			return tostring(id)
		end,
		clock = function(): number
			return control.clock
		end,
		guid = function(): string
			control.sequence += 1
			return "note:" .. tostring(control.sequence)
		end,
		core = core,
		invalid = "notes_invalid",
	}))
	local service = noteHost.create({
		phraseNotes = inbox,
		phraseCatalog = function(): unknown
			return { label = "Set phrases", phrases = { { id = "greeting", text = "Hello" } } }
		end,
		clock = function(): number
			return control.clock
		end,
		notePermitted = function(_a: number, _b: number): string?
			return if control.permitted then nil else "contact_denied"
		end,
		filterPreset = function(_id: number, _text: string): string?
			return if control.filtered then nil else "filter_refused"
		end,
		canReadNotes = function(_id: number): boolean
			return not control.hidden
		end,
		notifyNote = function(id: number)
			control.notified = id
		end,
	}, function(_id: number): NoteHost.FellowshipView | false
		return { members = { { userId = 1, displayName = "One" }, { userId = 2, displayName = "Two" } } }
	end, function(_id: number): { NoteHost.Candidate }
		return {
			{ userId = 2, displayName = "Two", source = "recent" },
			{ userId = 3, displayName = "Three", source = "nearby" },
		}
	end, function(id: number): string
		return "Member " .. tostring(id)
	end)
	return { service = service, control = control }
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("social messaging hosts", function()
		it("filters catalog delivery, deduplicates recipients and observes cooldown", function()
			local r = noteRig()
			expect(#r.service.recipients(1)):toBe(2)
			expect(r.service.send(1, 2, "unknown").reason):toBe("phrase_unknown")
			assert(r.service.send(1, 2, "greeting").ok)
			expect(r.control.notified):toBe(2)
			expect(r.service.send(1, 3, "greeting").reason):toBe("note_cooldown")
			r.control.clock += 3
			r.control.filtered = false
			local writes = r.control.writes
			expect(r.service.send(1, 3, "greeting").reason):toBe("filter_refused")
			expect(r.control.writes):toBe(writes)
		end)
		it("keeps inbox privacy expiry and read acknowledgment authoritative", function()
			local r = noteRig()
			assert(r.service.send(1, 2, "greeting").ok)
			assert(r.service.refresh(2).ok)
			local note = assert(r.service.projection(2).notes[1])
			expect(note.text):toBe("Hello")
			assert(r.service.markRead(2, note.id).ok)
			expect(r.service.projection(2).notes[1].read):toBe(true)
			r.control.hidden = true
			expect(r.service.projection(2).hidden):toBe(true)
			expect(#r.service.projection(2).notes):toBe(0)
			r.control.hidden = false
			r.control.clock += 51
			expect(#r.service.projection(2).notes):toBe(0)
			r.service.forget(2)
			expect(r.service.projection(2).loaded):toBe(false)
		end)
		it("refuses unknown recipients and denied contact without storing messages", function()
			local r = noteRig()
			expect(r.service.send(1, 4, "greeting").reason):toBe("recipient_unknown")
			r.control.clock += 3
			r.control.permitted = false
			expect(r.service.send(1, 2, "greeting").reason):toBe("contact_denied")
			expect(r.control.writes):toBe(0)
		end)
		it("deduplicates an in-flight pair and closes both cached views", function()
			local pending: string? = nil
			local service: WhisperHost.Service? = nil
			local closed: { string } = {}
			service = whisperHost.create({
				realmFor = function(_id: number): string
					return "realm_a"
				end,
				openWhisper = function(_a: number, _b: number): (string?, string?)
					pending = assert(service).open(2, 1).reason
					return "channel", nil
				end,
				closeWhisper = function(name: string)
					table.insert(closed, name)
				end,
			}, function(_id: number): string?
				return nil
			end)
			assert(service.open(1, 2).ok)
			expect(pending):toBe("direct_chat_pending")
			expect(service.projection(1)[1].displayName):toBe("Member 2")
			expect(service.close(1)):toEqual({ 2 })
			expect(#service.projection(2)):toBe(0)
			expect(closed):toEqual({ "channel" })
		end)
		it("revalidates the admitted realm after an asynchronous open", function()
			local realm = "realm_a"
			local closed = 0
			local service = whisperHost.create({
				realmFor = function(id: number): string
					return if id == 1 then "realm_a" else realm
				end,
				openWhisper = function(_a: number, _b: number): (string?, string?)
					realm = "realm_b"
					return "channel", nil
				end,
				closeWhisper = function(_name: string)
					closed += 1
				end,
			}, function(_id: number): string
				return "Member"
			end)
			expect(service.open(1, 2).reason):toBe("direct_chat_target_absent")
			expect(closed):toBe(1)
			expect(#service.projection(1)):toBe(0)
		end)
	end)
end
