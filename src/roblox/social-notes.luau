--!strict

local PhraseNoteCore = require("../core/social/notes")
local Records = require("./social-records")

export type Response = { ok: boolean, reason: string? }
export type Recipient = { read userId: number, read displayName: string, read source: "guild" | "nearby" | "recent" }
export type Candidate = { read userId: number, read displayName: string, read source: "nearby" | "recent" }
export type Projection = {
	read available: boolean,
	read hidden: boolean,
	read loaded: boolean,
	read notes: { { read id: string, read fromName: string, read text: string, read read: boolean } },
	read phrases: { PhraseNoteCore.Phrase },
	read label: string?,
}
export type Dependencies = {
	read phraseNotes: Records.Inbox?,
	read phraseCatalog: (() -> unknown)?,
	read clock: () -> number,
	read notePermitted: ((number, number) -> string?)?,
	read filterPreset: ((number, string) -> string?)?,
	read notifyNote: ((number) -> ())?,
	read canReadNotes: ((number) -> boolean)?,
}
type NoteResponse = Response
type NoteRecipientView = Recipient
export type FellowshipView = { read members: { { read userId: number, read displayName: string } } }
export type Service = {
	read recipients: (number) -> { Recipient },
	read projection: (number) -> Projection,
	read send: (number, number, string) -> Response,
	read refresh: (number) -> Response,
	read markRead: (number, string) -> Response,
	read noticed: (number) -> (),
	read forget: (number) -> (),
}

export type Config = {
	read phrases: (unknown) -> { PhraseNoteCore.Phrase }?,
	read live: ({ PhraseNoteCore.Note }, number) -> { PhraseNoteCore.Note },
	read presetLabel: string,
	read sendIntervalSec: number,
}
export type API = {
	read create: (
		Dependencies,
		(number) -> FellowshipView | false,
		(number) -> { Candidate },
		(number) -> string?
	) -> Service,
}
local function configure(config: Config): API
	config = table.freeze(table.clone(config))
	assert(config.sendIntervalSec >= 0 and config.sendIntervalSec < math.huge, "invalid note interval")
	local NOTE_SEND_INTERVAL_SEC = config.sendIntervalSec

	local function create(
		deps: Dependencies,
		fellowshipProjection: (number) -> FellowshipView | false,
		candidateProjection: (number) -> { Candidate },
		memberNameFor: (number) -> string?
	): Service
		local lastNoteSentAtByUser: { [number]: number } = {}
		local inboxCache: { [number]: { PhraseNoteCore.Note } } = {}
		local function phraseCatalog(): { PhraseNoteCore.Phrase }
			if deps.phraseCatalog == nil then
				return {}
			end
			return config.phrases(deps.phraseCatalog()) or {}
		end

		local function phraseText(phraseId: string): string?
			for _, phrase in phraseCatalog() do
				if phrase.id == phraseId then
					return phrase.text
				end
			end
			return nil
		end

		local function noteRecipients(actorUserId: number)
			local rows: { NoteRecipientView } = {}
			local seen: { [number]: boolean } = { [actorUserId] = true }
			local projected: FellowshipView | false = fellowshipProjection(actorUserId)
			if projected ~= false then
				for _, member in projected.members do
					if not seen[member.userId] then
						seen[member.userId] = true
						local recipient: NoteRecipientView =
							{ userId = member.userId, displayName = member.displayName, source = "guild" }
						rows[#rows + 1] = table.freeze(recipient)
					end
				end
			end
			for _, candidate in candidateProjection(actorUserId) do
				if not seen[candidate.userId] then
					seen[candidate.userId] = true
					local recipient: NoteRecipientView = {
						userId = candidate.userId,
						displayName = candidate.displayName,
						source = candidate.source,
					}
					rows[#rows + 1] = table.freeze(recipient)
				end
			end
			return rows
		end

		local function noteInboxRefresh(userId: number): NoteResponse
			if deps.phraseNotes == nil then
				return { ok = false, reason = "notes_unavailable" }
			end
			local outcome = deps.phraseNotes.inbox(userId)
			if outcome.ok then
				inboxCache[userId] = outcome.notes
			end
			return { ok = outcome.ok, reason = outcome.reason }
		end

		local function noteSend(
			actorUserId: number,
			targetUserId: number,
			phraseId: string
		): { ok: boolean, reason: string? }
			if deps.phraseNotes == nil then
				return { ok = false, reason = "notes_unavailable" }
			end
			local text = phraseText(phraseId)
			if text == nil then
				return { ok = false, reason = "phrase_unknown" }
			end
			local nowSec = deps.clock()
			local last = lastNoteSentAtByUser[actorUserId]
			if last ~= nil and nowSec - last < NOTE_SEND_INTERVAL_SEC then
				return { ok = false, reason = "note_cooldown" }
			end
			lastNoteSentAtByUser[actorUserId] = nowSec
			local known = false
			for _, recipient in noteRecipients(actorUserId) do
				if recipient.userId == targetUserId then
					known = true
					break
				end
			end
			if not known then
				return { ok = false, reason = "recipient_unknown" }
			end
			local senderName = memberNameFor(actorUserId)
			if senderName == nil then
				return { ok = false, reason = "notes_unavailable" }
			end
			if deps.notePermitted ~= nil then
				local refusal = deps.notePermitted(actorUserId, targetUserId)
				if refusal ~= nil then
					return { ok = false, reason = refusal }
				end
			end
			if deps.filterPreset == nil then
				return { ok = false, reason = "notes_unavailable" }
			end
			local filterRefusal = deps.filterPreset(actorUserId, text)
			if filterRefusal ~= nil then
				return { ok = false, reason = filterRefusal }
			end
			local delivered = deps.phraseNotes.deliver(actorUserId, senderName, targetUserId, phraseId)
			if delivered.ok then
				if inboxCache[targetUserId] ~= nil then
					noteInboxRefresh(targetUserId)
				end
				if deps.notifyNote ~= nil then
					deps.notifyNote(targetUserId)
				end
			end
			return { ok = delivered.ok, reason = delivered.reason }
		end

		local function noteMarkRead(userId: number, noteId: string): { ok: boolean, reason: string? }
			if deps.phraseNotes == nil then
				return { ok = false, reason = "notes_unavailable" }
			end
			local cached = inboxCache[userId]
			if cached ~= nil then
				local found = false
				for _, note in cached do
					if note.id == noteId then
						found = true
						if note.read then
							return { ok = true, reason = nil }
						end
					end
				end
				if not found then
					return { ok = false, reason = "note_unknown" }
				end
			end
			local outcome = deps.phraseNotes.markRead(userId, noteId)
			if outcome.ok then
				inboxCache[userId] = outcome.notes
			end
			return { ok = outcome.ok, reason = outcome.reason }
		end

		local function notesProjection(userId: number): Projection
			if deps.phraseNotes == nil then
				return table.freeze({ available = false, hidden = false, loaded = false, notes = {}, phrases = {} })
			end
			local phrases = phraseCatalog()
			if deps.canReadNotes ~= nil and not deps.canReadNotes(userId) then
				return table.freeze({ available = true, hidden = true, loaded = false, notes = {}, phrases = phrases })
			end
			local cached = inboxCache[userId]
			local stored: { PhraseNoteCore.Note } = if cached ~= nil then config.live(cached, deps.clock()) else {}
			local notes = {}
			for _, note in stored do
				local text = phraseText(note.phraseId)
				if text ~= nil then
					notes[#notes + 1] =
						table.freeze({ id = note.id, fromName = note.fromName, text = text, read = note.read })
				end
			end
			return table.freeze({
				available = true,
				hidden = false,
				loaded = cached ~= nil,
				notes = table.freeze(notes),
				phrases = phrases,
				label = config.presetLabel,
			})
		end

		return table.freeze({
			recipients = noteRecipients,
			projection = notesProjection,
			send = noteSend,
			refresh = noteInboxRefresh,
			markRead = noteMarkRead,
			noticed = function(userId: number)
				if inboxCache[userId] ~= nil then
					noteInboxRefresh(userId)
				end
			end,
			forget = function(userId: number)
				lastNoteSentAtByUser[userId] = nil
				inboxCache[userId] = nil
			end,
		})
	end

	return table.freeze({ create = create })
end

return table.freeze({ configure = configure })
