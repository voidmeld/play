--!strict

local Mail = require("../core/mail/mailbox")
local Transfer = require("./profile-transfer")
local Value = require("../core/internal/value")

export type Context = Transfer.Identity
export type Envelope = Mail.Envelope
export type Pointer = Mail.Pointer
export type Result = {
	ok: boolean,
	reason: string?,
	pending: boolean?,
	envelope: Envelope?,
	outcomes: { [string]: Result }?,
}
export type Outcome = { read ok: boolean, read value: unknown, read reason: string? }
export type Effect<P> = (P) -> (P?, string?)
export type Dependencies<P, Surface> = {
	profiles: Surface,
	envelopes: {
		read getOutcome: (string) -> Outcome,
		read updateOutcome: (string, (Envelope?) -> Envelope?) -> Outcome,
	},
	contextFor: (number) -> Context?,
	identity: ((unknown) -> unknown)?,
	resolveRecipient: (number, unknown, number) -> unknown,
	tradeable: (number, P, string, number) -> boolean,
	allowed: (number, number) -> boolean,
	reserveInbox: (number, string, Envelope) -> (boolean, string?),
	releaseInbox: (number, string, Envelope) -> boolean,
	releaseRecipientInbox: ((number, string, Envelope) -> boolean)?,
	clock: () -> number,
	ttlSec: number,
	requireSessions: boolean?,
}
export type Service = {
	read send: (unknown, unknown) -> Result,
	read claim: (unknown, string) -> Result,
	read returnMail: (unknown, string) -> Result,
	read expire: (string) -> Result,
	read recover: (string, number?, Context?) -> Result,
	read admit: (number) -> Result,
	read status: (unknown, string) -> Result,
}
export type Config<P, Surface> = {
	read identity: (unknown) -> unknown,
	read core: Mail.Mailbox<P>,
	read profileFor: (Surface, (number) -> Context?, number) -> (P?, Context?),
	read commit: (Surface, Context, string, Effect<P>) -> Transfer.Result,
	read update: (Surface, Context, (P) -> P) -> (),
	read characterId: (P) -> string?,
	read pointers: (P) -> { [string]: Pointer }?,
	read withPointers: (P, { [string]: Pointer }) -> P,
	read envelopeKey: (string) -> string,
	read transactionId: (string, string) -> string,
	read senderId: (string) -> number?,
	read maxUserId: number,
	read maxPointers: number,
	read maxTtlSec: number,
	read idLimit: number,
	read rateWindowSec: number,
	read rateLimit: number,
}
export type Host<P, Surface> = {
	read create: (Dependencies<P, Surface>?) -> (Service?, string?),
	read RATE_LIMIT: number,
}

local function configure<P, Surface>(config: Config<P, Surface>): Host<P, Surface>
	config = table.freeze(table.clone(config))
	for _, bound in { config.maxUserId, config.maxPointers, config.maxTtlSec, config.idLimit, config.rateLimit } do
		assert(Value.whole(bound, 1, 9007199254740991) ~= nil, "invalid mail bound")
	end
	assert(Value.finite(config.rateWindowSec) and config.rateWindowSec > 0, "invalid mail rate window")
	type Profile = P
	type Deps = Dependencies<P, Surface>
	type Attachments = Mail.Attachments
	type CommitResult = Transfer.Result
	type ProfileEffect = Effect<P>
	type EnvelopeTransform = (Envelope?) -> Envelope?
	local MailCore = config.core

	local MAX_USER_ID = config.maxUserId
	local RATE_WINDOW = config.rateWindowSec
	local RATE_LIMIT = config.rateLimit

	local function whole(value: unknown, low: number, high: number): boolean
		return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
	end

	local function exact(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return false
		end
		for key in value do
			if type(key) ~= "string" or fields[key] ~= true then
				return false
			end
		end
		return true
	end

	local function actorId(player: unknown, deps: Deps): number?
		local ok, userId = pcall(function(): unknown
			if deps.identity ~= nil then
				return deps.identity(player)
			end
			return config.identity(player)
		end)
		return if ok and type(userId) == "number" and whole(userId, 1, MAX_USER_ID) then userId else nil
	end

	local function profileFor(deps: Deps, userId: number): (Profile?, Context?)
		return config.profileFor(deps.profiles, deps.contextFor, userId)
	end

	local sameSession = Transfer.sameSession

	local function commit(
		deps: Deps,
		userId: number,
		id: string,
		effect: ProfileEffect,
		envelope: Envelope?,
		expected: Context?
	): CommitResult
		local profile, context = profileFor(deps, userId)
		local characterId = if envelope == nil
			then nil
			elseif envelope.senderId == userId then envelope.senderCharacterId
			else envelope.recipientCharacterId
		if
			profile == nil
			or context == nil
			or (deps.requireSessions and (not sameSession(expected, context) or characterId ~= context.characterId))
		then
			return { ok = false, outcome = "not_durable", reason = "session_unavailable" }
		end
		local function guarded(source: Profile): (Profile?, string?)
			if
				deps.requireSessions
				and (not sameSession(context, deps.contextFor(userId)) or config.characterId(source) ~= characterId)
			then
				return nil, "session_replaced"
			end
			return effect(source)
		end
		return Transfer.settle(deps.contextFor, userId, context, deps.requireSessions == true, function(): CommitResult
			return config.commit(deps.profiles, context, id, guarded)
		end)
	end

	local function withPointer(profile: Profile, envelope: Envelope, intent: "hold" | "claim"): Profile?
		if config.pointers(profile) ~= nil and type(config.pointers(profile)) ~= "table" then
			return nil
		end
		local pointers = table.clone(config.pointers(profile) or {})
		if pointers[envelope.id] == nil then
			local count = 0
			for _ in pointers do
				count += 1
			end
			if count >= config.maxPointers then
				return nil
			end
		end
		pointers[envelope.id] = { id = envelope.id, envelope = envelope, intent = intent }
		return config.withPointers(profile, pointers)
	end

	local function clearPointer(profile: Profile, id: string): Profile
		local pointers = table.clone(config.pointers(profile) or {})
		pointers[id] = nil
		return config.withPointers(profile, pointers)
	end

	local function debitWithPointer(profile: Profile, envelope: Envelope): (Profile?, string?)
		local debited, reason = MailCore.debit(profile, envelope.attachments)
		if debited == nil then
			return nil, reason
		end
		local held = withPointer(debited, envelope, "hold")
		return held, if held == nil then "pending_mail_invalid" else nil
	end

	local function read(deps: Deps, id: string): (Envelope?, boolean)
		local ok, result = pcall(deps.envelopes.getOutcome, config.envelopeKey(id))
		if not ok or type(result) ~= "table" or result.ok ~= true then
			return nil, false
		end
		local envelope = MailCore.read(result.value)
		if result.value ~= nil and (envelope == nil or envelope.id ~= id) then
			return nil, false
		end
		return envelope, true
	end

	local function write(deps: Deps, id: string, phase: string, transform: EnvelopeTransform): Envelope?
		local ok, result = pcall(deps.envelopes.updateOutcome, config.envelopeKey(id), transform)
		local decoded = if ok and type(result) == "table" and result.ok then MailCore.read(result.value) else nil
		if decoded ~= nil and decoded.id == id and decoded.phase == phase then
			return decoded
		end
		local envelope, readable = read(deps, id)
		return if readable and envelope ~= nil and envelope.phase == phase then envelope else nil
	end

	local function same(envelope: Envelope, senderId: number, recipientId: number, attachments: Attachments): boolean
		if
			envelope.senderId ~= senderId
			or envelope.recipientId ~= recipientId
			or envelope.attachments.coin ~= attachments.coin
		then
			return false
		end
		if #envelope.attachments.items ~= #attachments.items then
			return false
		end
		for index, stack in attachments.items do
			local original = envelope.attachments.items[index]
			if original.itemId ~= stack.itemId or original.count ~= stack.count then
				return false
			end
		end
		return true
	end

	local MailService = {}

	function MailService.create(depsValue: Deps?): (Service?, string?)
		local deps = depsValue
		if
			type(deps) ~= "table"
			or type(deps.profiles) ~= "table"
			or type(deps.envelopes) ~= "table"
			or type(deps.envelopes.getOutcome) ~= "function"
			or type(deps.envelopes.updateOutcome) ~= "function"
			or type(deps.contextFor) ~= "function"
			or type(deps.resolveRecipient) ~= "function"
			or type(deps.tradeable) ~= "function"
			or type(deps.allowed) ~= "function"
			or type(deps.reserveInbox) ~= "function"
			or type(deps.releaseInbox) ~= "function"
			or type(deps.clock) ~= "function"
			or not whole(deps.ttlSec, 1, config.maxTtlSec)
		then
			return nil, "dependencies_invalid"
		end
		local inFlight: { [string]: boolean } = {}
		local rates: { [number]: { since: number, count: number } } = {}

		local function rate(userId: number): boolean
			local now = deps.clock()
			local previous = rates[userId]
			if previous == nil or now - previous.since >= RATE_WINDOW then
				rates[userId] = { since = now, count = 1 }
				return true
			end
			if previous.count >= RATE_LIMIT then
				return false
			end
			previous.count += 1
			return true
		end

		local function releaseInbox(envelope: Envelope): boolean
			local ok, released = pcall(deps.releaseInbox, envelope.recipientId, envelope.id, envelope)
			return ok and released == true
		end

		local function releaseRecipientInbox(envelope: Envelope): boolean
			local release = if type(deps.releaseRecipientInbox) == "function"
				then deps.releaseRecipientInbox
				else deps.releaseInbox
			local ok, released = pcall(release, envelope.recipientId, envelope.id, envelope)
			return ok and released == true
		end

		local function clearAdmittedPointer(userId: number, envelope: Envelope, expected: Context?): boolean
			local profile, context = profileFor(deps, userId)
			local characterId = if envelope.senderId == userId
				then envelope.senderCharacterId
				else envelope.recipientCharacterId
			if
				profile ~= nil
				and context ~= nil
				and type(config.pointers(profile)) == "table"
				and (
					(config.pointers(profile) or {})[envelope.id] ~= nil
					or not deps.requireSessions
					or config.characterId(profile) == characterId
				)
			then
				local cleared = false
				config.update(deps.profiles, context, function(source): Profile
					cleared = false
					if
						deps.requireSessions
						and (
							not sameSession(expected, deps.contextFor(userId))
							or config.characterId(source) ~= characterId
						)
					then
						return source
					end
					cleared = true
					return clearPointer(source, envelope.id)
				end)
				if not cleared then
					return false
				end
				local result = commit(deps, userId, config.transactionId(envelope.id, "clear"), function(source)
					return source, nil
				end, envelope, expected)
				return result.ok
			end
			return true
		end

		local function recoverInner(id: string, callerId: number?, callerContext: Context?): Result
			if inFlight[id] then
				return { ok = false, pending = true, reason = "mail_busy" }
			end
			inFlight[id] = true
			local senderId = config.senderId(id)
			local senderContext = if senderId ~= nil then deps.contextFor(senderId) else nil
			local observed, readable = read(deps, id)
			if not readable then
				inFlight[id] = nil
				return { ok = false, pending = true, reason = "envelope_unavailable" }
			end
			if observed == nil then
				inFlight[id] = nil
				return { ok = false, reason = "mail_unknown" }
			end
			local envelope: Envelope = observed
			local contexts =
				{ [envelope.senderId] = senderContext, [envelope.recipientId] = deps.contextFor(envelope.recipientId) }
			if callerId ~= nil then
				contexts[callerId] = callerContext
			end
			local function done(ok: boolean, pending: boolean, reason: string?, current: Envelope?): Result
				inFlight[id] = nil
				return { ok = ok, pending = pending, reason = reason, envelope = current }
			end
			if deps.requireSessions then
				local latest, fresh = read(deps, id)
				if not fresh or latest == nil then
					return done(false, true, "envelope_unavailable", nil)
				end
				for userId, context in contexts do
					if not sameSession(context, deps.contextFor(userId)) then
						return done(false, true, "session_replaced", latest)
					end
				end
				envelope = latest
			end
			local preparedPhase = envelope.phase
			if preparedPhase == "prepared" then
				local held = commit(deps, envelope.senderId, config.transactionId(id, "hold"), function(profile)
					for _, stack in envelope.attachments.items do
						if not deps.tradeable(envelope.senderId, profile, stack.itemId, stack.count) then
							return nil, "item_bound"
						end
					end
					return debitWithPointer(profile, envelope)
				end, envelope, contexts[envelope.senderId])
				if not held.ok then
					if held.outcome == "rejected" then
						local cancelled = write(deps, id, "cancelled", function(current: Envelope?): Envelope?
							return if current ~= nil then MailCore.advance(current, "cancel") else nil
						end)
						if cancelled ~= nil then
							return done(false, not releaseInbox(cancelled), "hold_rejected", cancelled)
						end
					end
					return done(false, true, "hold_pending", envelope)
				end
				local dispatched = write(deps, id, "in_transit", function(current: Envelope?): Envelope?
					return if current ~= nil then MailCore.advance(current, "dispatch") else nil
				end)
				if dispatched == nil then
					return done(false, true, "dispatch_pending", nil)
				end
				envelope = dispatched
			end
			local transitPhase = envelope.phase
			if transitPhase == "in_transit" then
				local action: string? = nil
				local phase: string? = nil
				if deps.clock() >= envelope.expiresAt then
					action = "expire"
					phase = "expired"
				else
					local recipient = profileFor(deps, envelope.recipientId)
					local pointer = if recipient ~= nil and type(config.pointers(recipient)) == "table"
						then (config.pointers(recipient) or {})[id]
						else nil
					if type(pointer) == "table" and pointer.intent == "claim" then
						action = "claim"
						phase = "claiming"
					end
				end
				if action ~= nil and phase ~= nil then
					local decision = action
					local decided = write(deps, id, phase, function(current: Envelope?): Envelope?
						return if current ~= nil then MailCore.advance(current, decision, deps.clock()) else nil
					end)
					if decided == nil then
						return done(false, true, "decision_pending", nil)
					end
					envelope = decided
				end
			end
			local expiryPhase = envelope.phase
			if expiryPhase == "expired" then
				if not releaseRecipientInbox(envelope) then
					return done(false, true, "inbox_release_pending", envelope)
				end
				if not clearAdmittedPointer(envelope.recipientId, envelope, contexts[envelope.recipientId]) then
					return done(false, true, "pointer_clear_pending", envelope)
				end
				return done(true, false, nil, envelope)
			end
			local deliveryPhase = envelope.phase
			if deliveryPhase == "claiming" or deliveryPhase == "returning" then
				local recipient = deliveryPhase == "claiming"
				local userId = if recipient then envelope.recipientId else envelope.senderId
				local marker = if recipient then "claim" else "return"
				local action = if recipient then "deliver" else "restore"
				local result = commit(deps, userId, config.transactionId(id, marker), function(profile)
					return MailCore.credit(profile, envelope.attachments)
				end, envelope, contexts[userId])
				if not result.ok then
					return done(false, true, "delivery_pending", envelope)
				end
				local phase = if recipient then "claimed" else "returned"
				local resolved = write(deps, id, phase, function(current: Envelope?): Envelope?
					return if current ~= nil then MailCore.advance(current, action) else nil
				end)
				if resolved == nil then
					return done(false, true, "resolution_pending", nil)
				end
				envelope = resolved
			end
			local terminalPhase = envelope.phase
			if terminalPhase == "claimed" or terminalPhase == "returned" or terminalPhase == "cancelled" then
				local released = releaseInbox(envelope)
				if released then
					local senderCleared = clearAdmittedPointer(envelope.senderId, envelope, contexts[envelope.senderId])
					local recipientCleared =
						clearAdmittedPointer(envelope.recipientId, envelope, contexts[envelope.recipientId])
					if not senderCleared or not recipientCleared then
						return done(false, true, "pointer_clear_pending", envelope)
					end
				end
				return done(released, not released, if released then nil else "inbox_release_pending", envelope)
			end
			return done(true, false, nil, envelope)
		end

		local function recover(id: string, callerId: number?, callerContext: Context?): Result
			local ran, result = pcall(recoverInner, id, callerId, callerContext)
			if not ran then
				inFlight[id] = nil
				return { ok = false, pending = true, reason = "mail_unavailable" }
			end
			return result
		end

		local function send(player: unknown, request: unknown): Result
			local senderId = actorId(player, deps)
			if senderId == nil or not rate(senderId) then
				return { ok = false, reason = "rate_or_actor_invalid" }
			end
			local senderContext = deps.contextFor(senderId)
			if
				not exact(
					request,
					{ requestId = true, recipientId = true, recipientCharacterId = true, attachments = true }
				)
			then
				return { ok = false, reason = "request_invalid" }
			end
			local raw = assert(Value.raw(request))
			local recipientId = raw.recipientId
			local id = MailCore.id(senderId, raw.requestId)
			local attachments = MailCore.attachments(raw.attachments)
			if
				id == nil
				or type(recipientId) ~= "number"
				or not whole(recipientId, 1, MAX_USER_ID)
				or recipientId == senderId
				or attachments == nil
			then
				return { ok = false, reason = "request_invalid" }
			end
			local existing, readable = read(deps, id)
			if not readable then
				return { ok = false, pending = true, reason = "envelope_unavailable" }
			end
			if existing ~= nil then
				if
					not same(existing, senderId, recipientId, attachments)
					or (
						deps.requireSessions
						and (
							senderContext == nil
							or existing.senderCharacterId ~= senderContext.characterId
							or existing.recipientCharacterId ~= raw.recipientCharacterId
						)
					)
				then
					return { ok = false, reason = "request_conflict" }
				end
				return recover(id, senderId, senderContext)
			end
			local profile = profileFor(deps, senderId)
			if
				profile == nil
				or not deps.allowed(senderId, recipientId)
				or deps.resolveRecipient(recipientId, raw.recipientCharacterId, senderId) ~= true
			then
				return { ok = false, reason = "mail_unavailable" }
			end
			local debited, reason = MailCore.debit(profile, attachments)
			if debited == nil then
				return { ok = false, reason = reason }
			end
			for _, stack in attachments.items do
				if not deps.tradeable(senderId, profile, stack.itemId, stack.count) then
					return { ok = false, reason = "item_bound" }
				end
			end
			local now = deps.clock()
			local prepared = MailCore.prepare(id, senderId, recipientId, attachments, now, deps.ttlSec)
			if prepared == nil then
				return { ok = false, reason = "mail_invalid" }
			end
			if deps.requireSessions then
				if senderContext == nil or not sameSession(senderContext, deps.contextFor(senderId)) then
					return { ok = false, reason = "session_replaced" }
				end
				prepared.senderCharacterId = senderContext.characterId
				if type(raw.recipientCharacterId) ~= "string" then
					return { ok = false, reason = "recipient_invalid" }
				end
				prepared.recipientCharacterId = raw.recipientCharacterId
				if not MailCore.valid(prepared) then
					return { ok = false, reason = "recipient_invalid" }
				end
			end
			local reserved, available, reserveReason = pcall(deps.reserveInbox, recipientId, id, prepared)
			if not reserved or available ~= true then
				if reserveReason == "request_conflict" then
					return { ok = false, reason = "request_conflict" }
				end
				local cancelled = write(deps, id, "cancelled", function(current: Envelope?): Envelope?
					return if current == nil then MailCore.advance(prepared, "cancel") else nil
				end)
				return { ok = false, pending = cancelled == nil or not releaseInbox(cancelled), reason = "inbox_full" }
			end
			local created = write(deps, id, "prepared", function(current: Envelope?): Envelope?
				return if current == nil then prepared else nil
			end)
			if created == nil then
				local after, confirmed = read(deps, id)
				if confirmed and after == nil then
					local released, removed = pcall(deps.releaseInbox, recipientId, id, prepared)
					if released and removed == true then
						return { ok = false, reason = "prepare_failed" }
					end
				end
				return { ok = false, pending = true, reason = "prepare_pending" }
			end
			if not same(created, senderId, recipientId, attachments) then
				return { ok = false, reason = "request_conflict" }
			end
			return recover(id, senderId, senderContext)
		end

		local function decide(player: unknown, id: string, action: string): Result
			local userId = actorId(player, deps)
			local context = if userId ~= nil then deps.contextFor(userId) else nil
			if userId == nil or type(id) ~= "string" or #id > config.idLimit then
				return { ok = false, reason = "request_invalid" }
			end
			local envelope, readable = read(deps, id)
			if not readable then
				return { ok = false, pending = true, reason = "envelope_unavailable" }
			end
			if envelope == nil or (userId ~= envelope.senderId and userId ~= envelope.recipientId) then
				return { ok = false, reason = "mail_unknown" }
			end
			if
				deps.requireSessions
				and (
					context == nil
					or not sameSession(context, deps.contextFor(userId))
					or context.characterId
						~= (if envelope.senderId == userId
							then envelope.senderCharacterId
							else envelope.recipientCharacterId)
				)
			then
				return { ok = false, reason = "session_replaced" }
			end
			if action == "claim" and (userId ~= envelope.recipientId or deps.clock() >= envelope.expiresAt) then
				return { ok = false, reason = "claim_unavailable" }
			end
			local nextPhase = if action == "claim" then "claiming" else "returning"
			if envelope.phase == nextPhase then
				return recover(id, userId, context)
			end
			local declining = action == "return" and envelope.phase == "in_transit" and userId == envelope.recipientId
			local reclaiming = action == "return" and envelope.phase == "expired" and userId == envelope.senderId
			if action == "claim" and envelope.phase ~= "in_transit" then
				return { ok = false, reason = "mail_decided" }
			end
			if action == "return" and not declining and not reclaiming then
				return {
					ok = false,
					reason = if action == "return" and envelope.phase == "in_transit"
						then "return_unavailable"
						else "mail_decided",
				}
			end
			if action == "claim" then
				local accepted = commit(
					deps,
					userId,
					config.transactionId(id, "accept"),
					function(profile): (Profile?, string?)
						local updated = withPointer(profile, envelope, "claim")
						return updated, if updated == nil then "pending_mail_invalid" else nil
					end,
					envelope,
					context
				)
				if not accepted.ok then
					return { ok = false, pending = true, reason = "accept_pending" }
				end
			end
			local updated = write(deps, id, nextPhase, function(current: Envelope?): Envelope?
				return if current ~= nil then MailCore.advance(current, action) else nil
			end)
			if updated == nil then
				return { ok = false, pending = true, reason = "decision_pending" }
			end
			return recover(id, userId, context)
		end

		local function expire(id: string): Result
			if type(id) ~= "string" or #id > config.idLimit then
				return { ok = false, reason = "request_invalid" }
			end
			local envelope, readable = read(deps, id)
			if not readable then
				return { ok = false, pending = true, reason = "envelope_unavailable" }
			end
			if envelope == nil then
				return { ok = false, reason = "mail_unknown" }
			end
			if deps.clock() < envelope.expiresAt then
				return { ok = false, reason = "not_expired" }
			end
			if envelope.phase == "in_transit" then
				local returning = write(deps, id, "expired", function(current: Envelope?): Envelope?
					return if current ~= nil then MailCore.advance(current, "expire", deps.clock()) else nil
				end)
				if returning == nil then
					return { ok = false, pending = true, reason = "decision_pending" }
				end
			end
			return recover(id)
		end

		local function status(player: unknown, id: string): Result
			local userId = actorId(player, deps)
			if userId == nil or type(id) ~= "string" or #id > config.idLimit then
				return { ok = false, reason = "request_invalid" }
			end
			local envelope, readable = read(deps, id)
			if not readable then
				return { ok = false, pending = true, reason = "envelope_unavailable" }
			end
			if envelope == nil or (userId ~= envelope.senderId and userId ~= envelope.recipientId) then
				return { ok = false, reason = "mail_unknown" }
			end
			return { ok = true, envelope = envelope }
		end

		local function admit(userId: number): Result
			local context = deps.contextFor(userId)
			local profile = profileFor(deps, userId)
			if profile == nil then
				return { ok = false, pending = true, reason = "session_unavailable" }
			end
			local pointers = config.pointers(profile) or {}
			if type(pointers) ~= "table" then
				return { ok = false, pending = true, reason = "pending_mail_invalid" }
			end
			local outcomes = {}
			for id, pointer in pointers do
				if
					type(id) ~= "string"
					or type(pointer) ~= "table"
					or pointer.id ~= id
					or not MailCore.valid(pointer.envelope)
					or pointer.envelope.id ~= id
					or (pointer.intent ~= "hold" and pointer.intent ~= "claim")
					or (pointer.intent == "hold" and pointer.envelope.senderId ~= userId)
					or (pointer.intent == "claim" and pointer.envelope.recipientId ~= userId)
				then
					return { ok = false, pending = true, reason = "pending_mail_invalid" }
				end
				outcomes[id] = recover(id, userId, context)
			end
			return { ok = true, outcomes = outcomes }
		end

		return table.freeze({
			send = send,
			claim = function(player: unknown, id: string): Result
				return decide(player, id, "claim")
			end,
			returnMail = function(player: unknown, id: string): Result
				return decide(player, id, "return")
			end,
			expire = expire,
			recover = recover,
			admit = admit,
			status = status,
		}),
			nil
	end

	MailService.RATE_LIMIT = RATE_LIMIT

	return table.freeze(MailService)
end

return table.freeze({ configure = configure })
