--!strict

local SocialShape = require("./shape")

export type Note = {
	id: string,
	fromUserId: number,
	fromName: string,
	phraseId: string,
	sentAtSec: number,
	read: boolean,
}
export type State = {
	schemaVersion: number,
	ownerUserId: number,
	notes: { Note },
	receiptOrder: { string },
}
export type Result = { ok: boolean, state: State?, changed: boolean, reason: string? }
export type Phrase = { id: string, text: string }

export type Catalog = { label: string, phrases: { Phrase } }
export type Delivery = { noteId: string, fromUserId: number, fromName: string, phraseId: string }
export type Config = {
	maxNotes: number,
	maxNameLength: number,
	maxIdLength: number,
	maxPhraseIdLength: number,
	maxPhraseTextLength: number,
	maxReceipts: number,
	maxPhrases: number,
	noteTtlSec: number,
	maxTime: number,
	presetLabel: string,
}

local System = {}

function System.notes(config: Config)
	local function readNote(value: unknown): Note?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(
				value,
				{ id = true, fromUserId = true, fromName = true, phraseId = true, sentAtSec = true, read = true }
			)
		then
			return nil
		end
		local id = SocialShape.string(raw.id)
		if id == nil then
			return nil
		end
		local fromUserId = SocialShape.number(raw.fromUserId)
		if fromUserId == nil then
			return nil
		end
		local fromName = SocialShape.string(raw.fromName)
		if fromName == nil then
			return nil
		end
		local phraseId = SocialShape.string(raw.phraseId)
		if phraseId == nil then
			return nil
		end
		local sentAtSec = SocialShape.number(raw.sentAtSec)
		if sentAtSec == nil then
			return nil
		end
		local read = SocialShape.boolean(raw.read)
		if read == nil then
			return nil
		end
		return {
			id = id,
			fromUserId = fromUserId,
			fromName = fromName,
			phraseId = phraseId,
			sentAtSec = sentAtSec,
			read = read,
		}
	end

	local function readState(value: unknown): State?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(
				value,
				{ schemaVersion = true, ownerUserId = true, notes = true, receiptOrder = true }
			)
		then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local ownerUserId = SocialShape.number(raw.ownerUserId)
		if ownerUserId == nil then
			return nil
		end
		local notes = SocialShape.array(raw.notes, readNote)
		if notes == nil then
			return nil
		end
		local receiptOrder = SocialShape.array(raw.receiptOrder, SocialShape.string)
		if receiptOrder == nil then
			return nil
		end
		return { schemaVersion = schemaVersion, ownerUserId = ownerUserId, notes = notes, receiptOrder = receiptOrder }
	end

	local function readPhrase(value: unknown): Phrase?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { id = true, text = true }) then
			return nil
		end
		local id = SocialShape.string(raw.id)
		if id == nil then
			return nil
		end
		local text = SocialShape.string(raw.text)
		if text == nil then
			return nil
		end
		return { id = id, text = text }
	end

	local function readCatalog(value: unknown): Catalog?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { label = true, phrases = true }) then
			return nil
		end
		local label = SocialShape.string(raw.label)
		if label == nil then
			return nil
		end
		local phrases = SocialShape.array(raw.phrases, readPhrase)
		if phrases == nil then
			return nil
		end
		return { label = label, phrases = phrases }
	end

	local function readDelivery(value: unknown): Delivery?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, { noteId = true, fromUserId = true, fromName = true, phraseId = true })
		then
			return nil
		end
		local noteId = SocialShape.string(raw.noteId)
		if noteId == nil then
			return nil
		end
		local fromUserId = SocialShape.number(raw.fromUserId)
		if fromUserId == nil then
			return nil
		end
		local fromName = SocialShape.string(raw.fromName)
		if fromName == nil then
			return nil
		end
		local phraseId = SocialShape.string(raw.phraseId)
		if phraseId == nil then
			return nil
		end
		return { noteId = noteId, fromUserId = fromUserId, fromName = fromName, phraseId = phraseId }
	end

	local SCHEMA_VERSION = 1
	local MAX_NOTES = config.maxNotes
	local MAX_NAME_LENGTH = config.maxNameLength
	local MAX_ID_LENGTH = config.maxIdLength
	local MAX_PHRASE_ID_LENGTH = config.maxPhraseIdLength
	local MAX_PHRASE_TEXT_LENGTH = config.maxPhraseTextLength
	local MAX_RECEIPTS = config.maxReceipts
	local MAX_PHRASES = config.maxPhrases
	local NOTE_TTL_SEC = config.noteTtlSec
	local PRESET_LABEL = config.presetLabel
	local MAX_TIME = config.maxTime

	local STATE_FIELDS =
		SocialShape.freezeDeep({ schemaVersion = true, ownerUserId = true, notes = true, receiptOrder = true })
	local NOTE_FIELDS = SocialShape.freezeDeep({
		id = true,
		fromUserId = true,
		fromName = true,
		phraseId = true,
		sentAtSec = true,
		read = true,
	})
	local DELIVERY_FIELDS =
		SocialShape.freezeDeep({ noteId = true, fromUserId = true, fromName = true, phraseId = true })
	local PHRASE_FIELDS = SocialShape.freezeDeep({ id = true, text = true })
	local CATALOG_FIELDS = SocialShape.freezeDeep({ label = true, phrases = true })

	local whole = SocialShape.whole
	local opaque = SocialShape.opaque
	local exact = SocialShape.exact
	local dense = SocialShape.dense
	local freezeDeep = SocialShape.freezeDeep

	local function phraseIdValid(value: unknown): boolean
		return opaque(value, MAX_PHRASE_ID_LENGTH)
			and string.match(assert(SocialShape.string(value)), "^[%l_]+$") ~= nil
	end

	local function copyNote(value: unknown): Note?
		local raw = readNote(value)
		if raw == nil then
			return nil
		end
		if
			not exact(value, NOTE_FIELDS)
			or not opaque(raw.id, MAX_ID_LENGTH)
			or not whole(raw.fromUserId, 1, MAX_TIME)
			or not opaque(raw.fromName, MAX_NAME_LENGTH)
			or not phraseIdValid(raw.phraseId)
			or not whole(raw.sentAtSec, 0, MAX_TIME)
			or type(raw.read) ~= "boolean"
		then
			return nil
		end
		return {
			id = raw.id,
			fromUserId = raw.fromUserId,
			fromName = raw.fromName,
			phraseId = raw.phraseId,
			sentAtSec = raw.sentAtSec,
			read = raw.read,
		}
	end

	local function copyState(value: unknown): State?
		if not exact(value, STATE_FIELDS) then
			return nil
		end
		local raw = readState(value)
		if raw == nil then
			return nil
		end
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or not whole(raw.ownerUserId, 1, MAX_TIME)
			or dense(raw.notes, MAX_NOTES) == nil
			or dense(raw.receiptOrder, MAX_RECEIPTS) == nil
		then
			return nil
		end
		local notes: { Note } = {}
		local seen: { [string]: boolean } = {}
		for _, entry in raw.notes do
			local note = copyNote(entry)
			if note == nil or seen[note.id] then
				return nil
			end
			seen[note.id] = true
			notes[#notes + 1] = note
		end
		local receiptOrder: { string } = {}
		local receipts: { [string]: boolean } = {}
		for _, id in raw.receiptOrder do
			if not opaque(id, MAX_ID_LENGTH) or receipts[id] then
				return nil
			end
			receipts[id] = true
			receiptOrder[#receiptOrder + 1] = id
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			ownerUserId = raw.ownerUserId,
			notes = notes,
			receiptOrder = receiptOrder,
		}
	end

	local function result(state: State?, changed: boolean, reason: string?): Result
		return freezeDeep({ ok = reason == nil, state = state, changed = changed, reason = reason })
	end

	local PhraseNoteCore = {}

	function PhraseNoteCore.emptyState(ownerUserId: unknown): State?
		if not whole(ownerUserId, 1, MAX_TIME) then
			return nil
		end
		return freezeDeep({
			schemaVersion = SCHEMA_VERSION,
			ownerUserId = assert(SocialShape.number(ownerUserId)),
			notes = {},
			receiptOrder = {},
		})
	end

	function PhraseNoteCore.projectState(value: unknown): State?
		local state = copyState(value)
		return if state == nil then nil else freezeDeep(state)
	end

	local function presetTextValid(value: unknown): boolean
		return opaque(value, MAX_PHRASE_TEXT_LENGTH)
			and string.match(assert(SocialShape.string(value)), "^%u[%a ]*%a$") ~= nil
			and string.find(assert(SocialShape.string(value)), "  ", 1, true) == nil
	end

	function PhraseNoteCore.phrases(catalog: unknown): { Phrase }?
		local parsed = readCatalog(catalog)
		if parsed == nil then
			return nil
		end
		if
			not exact(catalog, CATALOG_FIELDS)
			or parsed.label ~= PRESET_LABEL
			or dense(parsed.phrases, MAX_PHRASES) == nil
		then
			return nil
		end
		local phrases: { Phrase } = {}
		local seen: { [string]: boolean } = {}
		for _, entry in parsed.phrases do
			if
				not exact(entry, PHRASE_FIELDS)
				or not phraseIdValid(entry.id)
				or not presetTextValid(entry.text)
				or seen[entry.id]
			then
				return nil
			end
			seen[entry.id] = true
			phrases[#phrases + 1] = SocialShape.freezeDeep({ id = entry.id, text = entry.text })
		end
		return SocialShape.freezeDeep(phrases)
	end

	function PhraseNoteCore.deliver(previous: unknown, request: unknown, nowSecValue: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return result(nil, false, "invalid_state")
		end
		if not exact(request, DELIVERY_FIELDS) or not whole(nowSecValue, 0, MAX_TIME) then
			return result(state, false, "invalid_request")
		end
		local raw = readDelivery(request)
		if raw == nil then
			return result(state, false, "invalid_request")
		end
		if
			not opaque(raw.noteId, MAX_ID_LENGTH)
			or not whole(raw.fromUserId, 1, MAX_TIME)
			or not opaque(raw.fromName, MAX_NAME_LENGTH)
			or not phraseIdValid(raw.phraseId)
		then
			return result(state, false, "invalid_request")
		end
		if raw.fromUserId == state.ownerUserId then
			return result(state, false, "self_target")
		end
		if table.find(state.receiptOrder, raw.noteId) ~= nil then
			return result(freezeDeep(state), false, nil)
		end
		local nowSec = assert(SocialShape.number(nowSecValue))
		local live: { Note } = {}
		for _, note in state.notes do
			if note.sentAtSec + NOTE_TTL_SEC > nowSec then
				live[#live + 1] = note
			end
		end
		state.notes = live
		state.notes[#state.notes + 1] = {
			id = raw.noteId,
			fromUserId = raw.fromUserId,
			fromName = raw.fromName,
			phraseId = raw.phraseId,
			sentAtSec = nowSec,
			read = false,
		}
		if #state.notes > MAX_NOTES then
			table.remove(state.notes, 1)
		end
		state.receiptOrder[#state.receiptOrder + 1] = raw.noteId
		if #state.receiptOrder > MAX_RECEIPTS then
			table.remove(state.receiptOrder, 1)
		end
		return result(freezeDeep(state), true, nil)
	end

	function PhraseNoteCore.markRead(previous: unknown, noteId: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return result(nil, false, "invalid_state")
		end
		if not opaque(noteId, MAX_ID_LENGTH) then
			return result(state, false, "invalid_request")
		end
		for index, note in state.notes do
			if note.id == noteId then
				if note.read then
					return result(freezeDeep(state), false, nil)
				end
				local marked = table.clone(note)
				marked.read = true
				state.notes[index] = marked
				return result(freezeDeep(state), true, nil)
			end
		end
		return result(state, false, "note_unknown")
	end

	function PhraseNoteCore.live(notes: { Note }, nowSec: number): { Note }
		local kept: { Note } = {}
		for _, note in notes do
			if note.sentAtSec + NOTE_TTL_SEC > nowSec then
				kept[#kept + 1] = note
			end
		end
		return kept
	end

	PhraseNoteCore.MAX_NOTES = MAX_NOTES
	PhraseNoteCore.MAX_PHRASES = MAX_PHRASES
	PhraseNoteCore.NOTE_TTL_SEC = NOTE_TTL_SEC
	PhraseNoteCore.PRESET_LABEL = PRESET_LABEL
	PhraseNoteCore.MAX_NAME_LENGTH = MAX_NAME_LENGTH

	return SocialShape.freezeDeep(PhraseNoteCore)
end

return System
