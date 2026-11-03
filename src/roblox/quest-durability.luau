--!strict
local Journal = require("../core/quest/journal")
local LeaseRecordTypes = require("../core/identity/character-lease")
local LeaseStore = require("../core/identity/character-lease-store")
local ProfileSessionTypes = require("../core/persistence/profile-session")
local Value = require("../core/internal/value")

export type Lease = LeaseRecordTypes.Record
export type SessionState = ProfileSessionTypes.State
export type Quests = { [string]: Journal.QuestProgress }
export type QuestRecord = Journal.Record
export type OutcomeStore = LeaseStore.Store & { get: (string) -> LeaseStore.StoreOutcome }
export type SessionDependencies = {
	store: OutcomeStore,
	leaseKeyFor: (string) -> string,
	zoneKeyFor: (string, string) -> string,
	leaseZoneFamily: { string }?,
	clock: () -> number,
}
export type Deps = SessionDependencies & {
	schedule: (number, () -> ()) -> (),
	scheduleLeaseRenewal: ((number, () -> ()) -> ())?,
	saveDelaySeconds: number?,
}
export type Acquired<Z> = { ok: true, reason: string?, session: SessionState, lease: Lease, zoneSnapshot: Z }
export type Refused = { ok: false, reason: string?, session: nil, lease: nil, zoneSnapshot: nil }
export type Acquisition<Z> = Acquired<Z> | Refused
export type Saved<Z> = { ok: true, reason: string?, lease: Lease, zoneSnapshot: Z }
export type SaveRefused = { ok: false, reason: string?, lease: Lease?, zoneSnapshot: nil }
export type SaveOutcome<Z> = Saved<Z> | SaveRefused
export type SessionPort<Z> = {
	read acquireAndHydrate: (SessionDependencies, string, string, string, string) -> Acquisition<Z>,
	read saveZoneQuests: (SessionDependencies, SessionState, Lease, Z, Quests) -> SaveOutcome<Z>,
}
export type SnapshotView = { read found: boolean, read revision: number, read quests: unknown }
export type Config<Z> = {
	read journal: Journal.API,
	read copyLease: index<LeaseRecordTypes.API, "copy">,
	read renew: index<LeaseStore.API, "renew">,
	read release: index<LeaseStore.API, "release">,
	read session: SessionPort<Z>,
	read snapshot: (Z) -> SnapshotView,
	read leaseSeconds: number,
	read renewSeconds: number,
	read retrySeconds: number,
	read defaultSaveDelay: number,
	read maxConsecutiveSaveFailures: number,
	read fenceLossReasons: { [string]: boolean },
}
export type AttachAccepted = {
	ok: true,
	reason: string?,
	found: boolean?,
	quests: Quests,
	semanticEventIds: { [string]: boolean },
	record: QuestRecord,
}
export type AttachRefused = {
	ok: false,
	reason: string?,
	found: nil?,
	quests: nil?,
	semanticEventIds: nil?,
	record: nil?,
}
export type AttachOutcome = AttachAccepted | AttachRefused
export type Result = { ok: boolean, reason: string?, skipped: boolean? }
export type Handle = {
	read attach: (string, string, string, string) -> AttachOutcome,
	read flush: (string) -> Result,
	read markDirty: (string, unknown) -> boolean,
	read markDirtyBatch: ({ unknown }) -> boolean,
	read stopWrites: (string) -> boolean,
	read overwriteRecord: (string, unknown) -> Result,
	read detach: (string) -> { ok: boolean, reason: string? },
	read drain: () -> { [string]: { ok: boolean, reason: string? } },
	read isAttached: (string) -> boolean,
	read canWrite: (string) -> boolean,
	read phase: (string) -> string?,
}
export type API = { read new: (Deps) -> Handle }
type Entry<Z> = {
	zoneId: string,
	sessionId: string,
	acquisitionId: string,
	session: SessionState,
	lease: Lease,
	zoneSnapshot: Z,
	failures: number,
	phase: string,
	reason: string?,
	reacquiring: boolean?,
	flushing: boolean?,
	flushScheduled: boolean?,
	renewBackoff: number?,
	record: QuestRecord?,
	dirtyRecord: QuestRecord?,
	dirty: Quests?,
}
type PreparedDirty<Z> = { characterId: string, entry: Entry<Z>, stored: Quests, record: QuestRecord }

local function configure<Z>(config: Config<Z>): API
	config = table.freeze(table.clone(config))
	for _, seconds in { config.leaseSeconds, config.renewSeconds, config.retrySeconds } do
		assert(seconds > 0 and seconds < math.huge, "invalid quest durability interval")
	end
	assert(
		config.retrySeconds <= config.renewSeconds and config.renewSeconds < config.leaseSeconds,
		"invalid quest renewal cadence"
	)
	assert(config.defaultSaveDelay >= 0 and config.defaultSaveDelay < math.huge, "invalid quest save delay")
	assert(
		config.maxConsecutiveSaveFailures >= 1 and config.maxConsecutiveSaveFailures % 1 == 0,
		"invalid quest failure limit"
	)
	local LeaseRecord = { copy = config.copyLease }
	local LeaseRepository = { renew = config.renew, release = config.release }
	local ProfileSession = { LEASE_SECONDS = config.leaseSeconds }
	local Session = config.session
	local ZoneQuestRecord = config.journal
	local MAX_CONSECUTIVE_SAVE_FAILURES = config.maxConsecutiveSaveFailures
	local LEASE_RENEW_SECONDS = config.renewSeconds
	local LEASE_RETRY_SECONDS = config.retrySeconds
	local FENCE_LOSS_REASONS = table.freeze(table.clone(config.fenceLossReasons))

	local function newerOwnedLease(candidate: Lease?, entry: Entry<Z>): boolean
		return candidate ~= nil
			and candidate.characterId == entry.lease.characterId
			and candidate.sessionId == entry.sessionId
			and candidate.acquisitionId == entry.acquisitionId
			and candidate.revision > entry.lease.revision
	end

	local function new(deps: Deps): Handle
		local sessionDeps = {
			store = deps.store,
			leaseKeyFor = deps.leaseKeyFor,
			zoneKeyFor = deps.zoneKeyFor,
			leaseZoneFamily = deps.leaseZoneFamily,
			clock = deps.clock,
		}
		local saveDelay = deps.saveDelaySeconds or config.defaultSaveDelay
		assert(Value.finite(saveDelay) and saveDelay >= 0, "invalid quest save delay")
		local entries: { [string]: Entry<Z> } = {}

		local handle = {}
		local function currentPhase(entry: Entry<Z>): string
			return entry.phase
		end

		local function holdLease(entry: Entry<Z>, lease: Lease)
			entry.lease = lease
			if lease.expiresAt > deps.clock() then
				entry.session.leaseExpiresAt = lease.expiresAt
				entry.session.leaseLost = false
			end
		end

		local function adoptOwnedLease(characterId: string, entry: Entry<Z>): boolean
			local captured: unknown = nil
			local read = pcall(deps.store.updateOutcome, deps.leaseKeyFor(characterId), function(current): unknown
				captured = current
				return nil
			end)
			if not read then
				return false
			end
			local current = LeaseRecord.copy(captured)
			if current == nil or not newerOwnedLease(current, entry) or current.expiresAt <= deps.clock() then
				return false
			end
			holdLease(entry, current)
			return true
		end

		local function reacquire(characterId: string, entry: Entry<Z>): boolean
			entry.reacquiring = true
			local outcome =
				Session.acquireAndHydrate(sessionDeps, entry.zoneId, characterId, entry.sessionId, entry.acquisitionId)
			entry.reacquiring = false
			if not outcome.ok then
				entry.phase = "fenced"
				entry.reason = outcome.reason or "lease_lost"
				return false
			end
			local previous = config.snapshot(entry.zoneSnapshot)
			local current = config.snapshot(outcome.zoneSnapshot)
			if previous.found ~= current.found or previous.revision ~= current.revision then
				LeaseRepository.release(
					deps.store,
					deps.leaseKeyFor,
					characterId,
					entry.sessionId,
					entry.acquisitionId,
					outcome.lease.revision
				)
				entry.phase = "fenced"
				entry.reason = "quest_record_diverged"
				return false
			end
			entry.session = outcome.session
			entry.lease = outcome.lease
			entry.zoneSnapshot = outcome.zoneSnapshot
			entry.failures = 0
			return true
		end

		local function leaseLapsed(characterId: string, entry: Entry<Z>): boolean
			if entry.lease.expiresAt > deps.clock() then
				return false
			end
			if entry.flushing or entry.reacquiring then
				return true
			end
			if adoptOwnedLease(characterId, entry) then
				return false
			end
			return not reacquire(characterId, entry)
		end

		local function retryFlush(characterId: string, entry: Entry<Z>, quests: Quests?)
			entry.dirty = entry.dirty or quests
			if not entry.flushScheduled then
				entry.flushScheduled = true
				deps.schedule(saveDelay, function()
					if entries[characterId] == entry then
						handle.flush(characterId)
					end
				end)
			end
		end

		local function keepLeaseAlive(characterId: string, entry: Entry<Z>)
			if entries[characterId] ~= entry or entry.phase ~= "active" then
				return
			end
			local delay = LEASE_RENEW_SECONDS
			if not entry.flushing then
				local renewed = LeaseRepository.renew(
					deps.store,
					deps.leaseKeyFor,
					characterId,
					entry.sessionId,
					entry.acquisitionId,
					entry.lease.revision,
					deps.clock(),
					ProfileSession.LEASE_SECONDS
				)
				if renewed.ok then
					holdLease(entry, renewed.value)
					entry.renewBackoff = nil
				elseif adoptOwnedLease(characterId, entry) then
					entry.renewBackoff = nil
				elseif entry.lease.expiresAt <= deps.clock() then
					if not reacquire(characterId, entry) then
						return
					end
					entry.renewBackoff = nil
				else
					local backoff = if entry.renewBackoff == nil
						then LEASE_RETRY_SECONDS
						else math.min(entry.renewBackoff * 2, LEASE_RENEW_SECONDS)
					entry.renewBackoff = backoff
					delay = backoff
				end
			end
			if deps.scheduleLeaseRenewal ~= nil then
				pcall(deps.scheduleLeaseRenewal, delay, function()
					keepLeaseAlive(characterId, entry)
				end)
			end
		end

		function handle.attach(
			zoneId: string,
			characterId: string,
			sessionId: string,
			acquisitionId: string
		): AttachOutcome
			local existing = entries[characterId]
			if existing ~= nil then
				return { ok = false, reason = "already_attached" }
			end
			local leaseKey = deps.leaseKeyFor(characterId)
			local staleIds: { string } = {}
			for otherId in entries do
				if otherId ~= characterId and deps.leaseKeyFor(otherId) == leaseKey then
					table.insert(staleIds, otherId)
				end
			end
			for _, staleId in staleIds do
				handle.detach(staleId)
			end
			local outcome = Session.acquireAndHydrate(sessionDeps, zoneId, characterId, sessionId, acquisitionId)
			if not outcome.ok then
				return { ok = false, reason = outcome.reason }
			end
			entries[characterId] = {
				zoneId = zoneId,
				sessionId = sessionId,
				acquisitionId = acquisitionId,
				session = outcome.session,
				lease = outcome.lease,
				zoneSnapshot = outcome.zoneSnapshot,
				failures = 0,
				phase = "active",
			}
			local record, recordReason =
				ZoneQuestRecord.fromStorageQuests(zoneId, characterId, config.snapshot(outcome.zoneSnapshot).quests)
			if record == nil then
				handle.detach(characterId)
				return { ok = false, reason = recordReason or "quest_record_invalid" }
			end
			entries[characterId].record = record
			local attached = entries[characterId]
			if deps.scheduleLeaseRenewal ~= nil then
				pcall(deps.scheduleLeaseRenewal, LEASE_RENEW_SECONDS, function()
					keepLeaseAlive(characterId, attached)
				end)
			end
			return {
				ok = true,
				found = config.snapshot(outcome.zoneSnapshot).found,
				quests = record.quests,
				semanticEventIds = record.semanticEventIds,
				record = record,
			}
		end

		function handle.flush(characterId: string): { ok: boolean, reason: string?, skipped: boolean? }
			local entry = entries[characterId]
			if entry == nil then
				return { ok = false, reason = "not_attached" }
			end
			if entry.phase == "release" or entry.phase == "fenced" then
				return { ok = false, reason = entry.reason or "writes_stopped" }
			end
			if entry.flushing then
				return { ok = false, reason = "save_in_progress" }
			end
			local quests = entry.dirty
			entry.flushScheduled = false
			if quests == nil then
				return { ok = true, skipped = true }
			end
			if entry.reacquiring then
				retryFlush(characterId, entry, nil)
				return { ok = false, reason = "lease_reacquiring" }
			end
			entry.dirty = nil
			entry.flushing = true
			local saved = Session.saveZoneQuests(sessionDeps, entry.session, entry.lease, entry.zoneSnapshot, quests)
			entry.flushing = false
			local adoptedLease = if newerOwnedLease(saved.lease, entry) then saved.lease else nil
			if adoptedLease then
				entry.lease = adoptedLease
			end
			if saved.ok then
				if not adoptedLease then
					entry.lease = saved.lease
				end
				entry.zoneSnapshot = saved.zoneSnapshot
				entry.failures = 0
				entry.record = entry.dirtyRecord or entry.record
				entry.dirtyRecord = nil
				return { ok = true }
			end
			local leaseLoss = FENCE_LOSS_REASONS[saved.reason or ""] or saved.reason == "readback_mismatch"
			if
				not adoptedLease
				and entry.phase == "active"
				and leaseLoss
				and (
					adoptOwnedLease(characterId, entry)
					or (entry.lease.expiresAt <= deps.clock() and reacquire(characterId, entry))
				)
			then
				retryFlush(characterId, entry, quests)
				return { ok = false, reason = saved.reason }
			end
			if currentPhase(entry) == "fenced" then
				return { ok = false, reason = entry.reason or saved.reason }
			end
			if FENCE_LOSS_REASONS[saved.reason or ""] and not (saved.reason == "lease_stale" and adoptedLease) then
				entry.dirty = quests
				entry.phase = "fenced"
				entry.reason = saved.reason
				return { ok = false, reason = saved.reason }
			end
			entry.failures += 1
			if entry.failures >= MAX_CONSECUTIVE_SAVE_FAILURES then
				entry.dirty = entry.dirty or quests
				entry.phase = "stopping"
				entry.reason = saved.reason
				return { ok = false, reason = saved.reason }
			end
			retryFlush(characterId, entry, quests)
			return { ok = false, reason = saved.reason }
		end

		local function prepareDirty(characterId: string, rawRecord: unknown): PreparedDirty<Z>?
			local entry = entries[characterId]
			if entry == nil or entry.phase ~= "active" or leaseLapsed(characterId, entry) then
				return nil
			end
			if type(rawRecord) ~= "table" or getmetatable(rawRecord) ~= nil then
				return nil
			end
			local decoded: QuestRecord? = nil
			local record = Value.raw(rawRecord)
			if record ~= nil then
				decoded = if record.version ~= nil
					then ZoneQuestRecord.decode(rawRecord)
					else ZoneQuestRecord.create(entry.zoneId, characterId, record.quests, record.semanticEventIds)
			end
			local stored = if decoded ~= nil then ZoneQuestRecord.storageQuests(decoded) else nil
			if
				decoded == nil
				or stored == nil
				or decoded.characterId ~= characterId
				or decoded.zoneId ~= entry.zoneId
			then
				return nil
			end
			return {
				characterId = characterId,
				entry = entry,
				stored = stored,
				record = decoded,
			}
		end

		local function applyDirty(prepared: PreparedDirty<Z>)
			prepared.entry.dirty = prepared.stored
			prepared.entry.dirtyRecord = prepared.record
			if not prepared.entry.flushScheduled then
				prepared.entry.flushScheduled = true
				local characterId = prepared.characterId
				local scheduled = pcall(deps.schedule, saveDelay, function()
					if entries[characterId] == prepared.entry then
						handle.flush(characterId)
					end
				end)
				if not scheduled then
					prepared.entry.flushScheduled = false
				end
			end
		end

		function handle.markDirty(characterId: string, record: unknown): boolean
			local prepared = prepareDirty(characterId, record)
			if prepared == nil then
				return false
			end
			applyDirty(prepared)
			return true
		end

		function handle.markDirtyBatch(updates: { unknown }): boolean
			local prepared = {}
			local seen: { [string]: boolean } = {}
			for _, rawUpdate in updates do
				if type(rawUpdate) ~= "table" or getmetatable(rawUpdate) ~= nil then
					return false
				end
				local update = Value.raw(rawUpdate)
				if update == nil then
					return false
				end
				if type(update.characterId) ~= "string" or seen[update.characterId] then
					return false
				end
				seen[update.characterId] = true
				local nextDirty = prepareDirty(update.characterId, update.record)
				if nextDirty == nil then
					return false
				end
				table.insert(prepared, nextDirty)
			end
			for _, nextDirty in prepared do
				applyDirty(nextDirty)
			end
			return true
		end

		function handle.stopWrites(characterId: string): boolean
			local entry = entries[characterId]
			if entry == nil then
				return false
			end
			if entry.phase == "active" then
				entry.phase = "stopping"
			end
			return entry.phase == "stopping" or entry.phase == "release"
		end

		function handle.overwriteRecord(
			characterId: string,
			record: unknown
		): { ok: boolean, reason: string?, skipped: boolean? }
			local entry = entries[characterId]
			if entry == nil or entry.phase ~= "active" then
				return { ok = false, reason = "not_attached" }
			end
			local decoded = ZoneQuestRecord.decode(record)
			local stored = if decoded ~= nil then ZoneQuestRecord.storageQuests(decoded) else nil
			if
				decoded == nil
				or stored == nil
				or decoded.characterId ~= characterId
				or decoded.zoneId ~= entry.zoneId
			then
				return { ok = false, reason = "not_attached" }
			end
			local priorDirty = entry.dirty
			local priorDirtyRecord = entry.dirtyRecord
			local priorScheduled = entry.flushScheduled
			entry.dirty = stored
			entry.dirtyRecord = decoded
			entry.flushScheduled = false
			local result = handle.flush(characterId)
			if not result.ok then
				entry.dirty = priorDirty
				entry.dirtyRecord = priorDirtyRecord
				entry.flushScheduled = priorScheduled
			end
			return result
		end

		function handle.detach(characterId: string): { ok: boolean, reason: string? }
			local entry = entries[characterId]
			if entry == nil then
				return { ok = false, reason = "not_attached" }
			end
			if entry.phase == "fenced" then
				return { ok = false, reason = entry.reason }
			end
			if entry.phase == "active" then
				entry.phase = "stopping"
			end
			local flushed: Result = if entry.phase == "release"
				then { ok = true, skipped = true }
				else handle.flush(characterId)
			if not flushed.ok and flushed.skipped ~= true then
				return { ok = false, reason = flushed.reason }
			end
			entry.phase = "release"
			local released = LeaseRepository.release(
				deps.store,
				deps.leaseKeyFor,
				characterId,
				entry.sessionId,
				entry.acquisitionId,
				entry.lease.revision
			)
			if not released.ok then
				entry.reason = released.reason
				return { ok = false, reason = released.reason }
			end
			entries[characterId] = nil
			return { ok = true }
		end

		function handle.drain(): { [string]: { ok: boolean, reason: string? } }
			local outcomes: { [string]: { ok: boolean, reason: string? } } = {}
			for characterId in entries do
				outcomes[characterId] = handle.detach(characterId)
			end
			return outcomes
		end

		function handle.isAttached(characterId: string): boolean
			local entry = entries[characterId]
			return entry ~= nil and entry.phase == "active"
		end

		function handle.canWrite(characterId: string): boolean
			local entry = entries[characterId]
			return entry ~= nil and entry.phase == "active" and entry.lease.expiresAt > deps.clock()
		end

		function handle.phase(characterId: string): string?
			local entry = entries[characterId]
			return if entry ~= nil then entry.phase else nil
		end

		return table.freeze(handle)
	end

	return table.freeze({ new = new })
end

return table.freeze({ configure = configure })
