--!strict

local Module = require("./notes")
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
		maxNotes = 40,
		maxNameLength = 64,
		maxIdLength = 128,
		maxPhraseIdLength = 64,
		maxPhraseTextLength = 80,
		maxReceipts = 80,
		maxPhrases = 12,
		noteTtlSec = 900,
		presetLabel = "System preset",
		maxTime = 1000000000000,
	}
	local Core = Module.notes(settings)
	local SocialPhrases = {
		label = settings.presetLabel,
		phrases = { { id = "need_help", text = "Need help" }, { id = "ready", text = "Ready" } },
	}

	local function empty(): Module.State
		return assert(Core.emptyState(9))
	end

	local function deliver(state: unknown, noteId: string, fromUserId: number): Module.Result
		return Core.deliver(
			state,
			{ noteId = noteId, fromUserId = fromUserId, fromName = "Bryn", phraseId = "need_help" },
			100
		)
	end

	describe("PhraseNoteCore authored phrases", function()
		it("accepts the authored phrase catalog", function()
			local phrases = Core.phrases(SocialPhrases)
			expect((phrases ~= nil)):toBe(true)
			expect((#assert(phrases))):toBe(#SocialPhrases.phrases)
		end)

		it("refuses a catalog with duplicate or malformed phrase ids", function()
			local label = Core.PRESET_LABEL
			expect((Core.phrases({
				label = label,
				phrases = { { id = "a", text = "Ready" }, { id = "a", text = "Wait" } },
			}))):toBeNil()
			expect((Core.phrases({ label = label, phrases = { { id = "Hello there", text = "Ready" } } }))):toBeNil()
		end)

		it("refuses presets with terminal punctuation, an unlabelled catalog, or more than twelve", function()
			local label = Core.PRESET_LABEL
			for _, text in { "Ready.", "Need help!", "Ready?", "On my way,", "ready" } do
				expect((Core.phrases({ label = label, phrases = { { id = "a", text = text } } }))):toBeNil()
			end
			expect((Core.phrases({ phrases = { { id = "a", text = "Ready" } } }))):toBeNil()
			expect((Core.phrases({ label = "Quick chat", phrases = { { id = "a", text = "Ready" } } }))):toBeNil()
			local many = {}
			for index = 1, 13 do
				table.insert(many, { id = "p" .. string.rep("a", index), text = "Ready" })
			end
			expect((Core.phrases({ label = label, phrases = many }))):toBeNil()
		end)

		it("authors only gameplay intent: no greeting, schedule, question, or relationship line", function()
			local banned = {
				"hi",
				"hello",
				"hey",
				"met",
				"friend",
				"later",
				"soon",
				"today",
				"tonight",
				"tomorrow",
				"you",
				"where",
				"why",
				"how",
			}
			for _, phrase in SocialPhrases.phrases do
				for word in string.gmatch(string.lower(phrase.text), "%a+") do
					expect((table.find(banned, word))):toBeNil()
				end
			end
			expect(SocialPhrases.label):toBe("System preset")
		end)
	end)

	describe("PhraseNoteCore stores phrase ids, never player text", function()
		it("delivers a phrase note unread and holds no text field", function()
			local result = deliver(empty(), "n1", 5)
			expect(result.ok):toBe(true)
			expect(result.changed):toBe(true)
			assert(result.state ~= nil)
			local note = result.state.notes[1]
			expect(note.phraseId):toBe("need_help")
			expect(note.read):toBe(false)
			expect(assert(Shape.raw(note)).text):toBeNil()
		end)

		it("refuses free text in place of a phrase id and any extra field", function()
			local prose = Core.deliver(empty(), {
				noteId = "n1",
				fromUserId = 5,
				fromName = "Bryn",
				phraseId = "meet me behind the mill at nine",
			}, 100)
			expect(prose.reason):toBe("invalid_request")
			local extra = Core.deliver(empty(), {
				noteId = "n1",
				fromUserId = 5,
				fromName = "Bryn",
				phraseId = "need_help",
				text = "hidden prose",
			}, 100)
			expect(extra.reason):toBe("invalid_request")
			expect((Core.projectState({
				schemaVersion = 1,
				ownerUserId = 9,
				notes = {
					{
						id = "n1",
						fromUserId = 5,
						fromName = "Bryn",
						phraseId = "need_help",
						sentAtSec = 1,
						read = false,
						text = "prose",
					},
				},
				receiptOrder = {},
			}))):toBeNil()
		end)

		it("refuses a note to oneself", function()
			expect(deliver(empty(), "n1", 9).reason):toBe("self_target")
		end)

		it("replays a delivered note id without a change", function()
			local first = deliver(empty(), "n1", 5)
			local again = deliver(first.state, "n1", 5)
			expect(again.ok):toBe(true)
			expect(again.changed):toBe(false)
			assert(again.state ~= nil)
			expect(#again.state.notes):toBe(1)
		end)

		it("lets a preset expire after its moment and drops it on the next delivery", function()
			local first = deliver(empty(), "n1", 5)
			local later = Core.deliver(first.state, {
				noteId = "n2",
				fromUserId = 6,
				fromName = "Cora",
				phraseId = "ready",
			}, 100 + Core.NOTE_TTL_SEC)
			assert(first.state ~= nil and later.state ~= nil)
			expect(#later.state.notes):toBe(1)
			expect(later.state.notes[1].id):toBe("n2")
			expect((#Core.live(first.state.notes, 100 + Core.NOTE_TTL_SEC - 1))):toBe(1)
			expect((#Core.live(first.state.notes, 100 + Core.NOTE_TTL_SEC))):toBe(0)
		end)

		it("keeps only the newest notes once the satchel is full", function()
			local state = empty()
			for index = 1, Core.MAX_NOTES + 2 do
				local nextState = deliver(state, "n" .. tostring(index), 5).state
				assert(nextState ~= nil)
				state = nextState
			end
			expect(#state.notes):toBe(Core.MAX_NOTES)
			expect(state.notes[1].id):toBe("n3")
		end)

		it("marks a note read once and reports no change on a repeat", function()
			local delivered = deliver(empty(), "n1", 5)
			local marked = Core.markRead(delivered.state, "n1")
			expect(marked.changed):toBe(true)
			assert(marked.state ~= nil)
			expect(marked.state.notes[1].read):toBe(true)
			local again = Core.markRead(marked.state, "n1")
			expect(again.ok):toBe(true)
			expect(again.changed):toBe(false)
			expect(Core.markRead(marked.state, "missing").reason):toBe("note_unknown")
		end)
	end)

	it("uses configured note, receipt, identity, text and lifetime limits", function()
		local source = assert(deliver(empty(), "n1", 5).state)
		local changes: { (Module.Config) -> () } = {
			function(cfg)
				cfg.maxNotes = 0
			end,
			function(cfg)
				cfg.maxReceipts = 0
			end,
			function(cfg)
				cfg.maxTime = 99
			end,
			function(cfg)
				cfg.maxNameLength = 3
			end,
			function(cfg)
				cfg.maxIdLength = 1
			end,
			function(cfg)
				cfg.maxPhraseIdLength = 1
			end,
		}
		for _, change in changes do
			local cfg: Module.Config = table.clone(settings)
			change(cfg)
			expect(Module.notes(cfg).projectState(source)):toBeNil()
		end
		local cfg: Module.Config = table.clone(settings)
		cfg.maxPhrases = 1
		expect(Module.notes(cfg).phrases(SocialPhrases)):toBeNil()
		cfg = table.clone(settings)
		cfg.maxPhraseTextLength = 2
		expect(Module.notes(cfg).phrases(SocialPhrases)):toBeNil()
		cfg = table.clone(settings)
		cfg.presetLabel = "Authored"
		expect(Module.notes(cfg).phrases(SocialPhrases)):toBeNil()
		cfg = table.clone(settings)
		cfg.noteTtlSec = 1
		expect(#Module.notes(cfg).live(source.notes, 101)):toBe(0)
	end)
end
