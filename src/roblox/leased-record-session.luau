--!strict
local LeaseRecords = require("../core/identity/character-lease")
local LeaseStores = require("../core/identity/character-lease-store")
local Records = require("../core/persistence/record-store")
local Sessions = require("../core/persistence/profile-session")
local Value = require("../core/internal/value")

export type Lease = LeaseRecords.Record
export type SessionState = Sessions.State
export type StoreOutcome = Records.StoreOutcome
export type OutcomeStore = Records.Store
export type Dependencies = {
	store: OutcomeStore,
	leaseKeyFor: (string) -> string,
	zoneKeyFor: (string, string) -> string,
	leaseZoneFamily: { string }?,
	clock: () -> number,
}
export type Accepted<R> = {
	ok: true,
	reason: string?,
	releaseReason: string?,
	session: SessionState,
	lease: Lease,
	zoneSnapshot: Records.Accepted<R>,
}
export type Refused =
	{ ok: false, reason: string?, releaseReason: string?, session: nil, lease: nil, zoneSnapshot: nil }
export type Outcome<R> = Accepted<R> | Refused
export type SaveAccepted<R> = { ok: true, reason: string?, lease: Lease, zoneSnapshot: Records.Accepted<R> }
export type SaveRefused = { ok: false, reason: string?, lease: Lease?, zoneSnapshot: nil }
export type SaveOutcome<R> = SaveAccepted<R> | SaveRefused
export type SessionPort = {
	read openAcquired: (number, number) -> (SessionState?, string?),
	read dirty: (SessionState, number, string) -> Sessions.Outcome,
	read begin: (SessionState, number) -> Sessions.Outcome,
	read finish: (SessionState, number, boolean) -> Sessions.Outcome,
}
export type Config<R> = {
	read leaseRecord: LeaseRecords.API,
	read leaseStore: LeaseStores.API,
	read session: SessionPort,
	read records: Records.API<R>,
	read copyRecord: (unknown) -> (R?, string?),
	read withPayload: (R, unknown) -> (R?, string?),
	read characterId: (R) -> string,
	read leaseSeconds: number,
	read dirtyReason: string,
}
export type API<R> = {
	read acquireAndHydrate: (Dependencies, string, string, string, string) -> Outcome<R>,
	read savePayload: (Dependencies, SessionState, unknown, unknown, unknown) -> SaveOutcome<R>,
}

local function configure<R>(config: Config<R>): API<R>
	config = table.freeze(table.clone(config))
	assert(Value.finite(config.leaseSeconds) and config.leaseSeconds > 0, "invalid session lease duration")
	assert(#config.dirtyReason > 0, "missing session dirty reason")
	local LeaseRecord = config.leaseRecord
	local LeaseRepository = config.leaseStore
	local ProfileSession = config.session
	local ZoneRecord = { copy = config.copyRecord }
	local ZoneRepository = config.records
	local Coordinator = {}

	local function denied(reason: string, releaseReason: string?): Refused
		return {
			ok = false,
			reason = reason,
			releaseReason = releaseReason,
			session = nil,
			lease = nil,
			zoneSnapshot = nil,
		}
	end

	local function fenceTakeover(
		dependencies: Dependencies,
		characterId: string,
		sessionId: string,
		acquisitionId: string,
		acquired: Lease,
		prior: Lease?
	): string?
		if prior == nil then
			return nil
		end
		if
			acquired.characterId ~= characterId
			or acquired.sessionId ~= sessionId
			or acquired.acquisitionId ~= acquisitionId
			or acquired.revision ~= prior.revision + 1
			or prior.sessionId == nil
			or prior.retirement ~= false
		then
			return "lease_takeover_binding_invalid"
		end
		local zones: { string } = dependencies.leaseZoneFamily or {}
		if prior.zoneId ~= nil then
			zones = { prior.zoneId }
		end
		if #zones == 0 then
			return "lease_zone_family_missing"
		end
		for _, zoneId in zones do
			local snapshot = ZoneRepository.read(dependencies.store, dependencies.zoneKeyFor, zoneId, characterId)
			if not snapshot.ok then
				return snapshot.reason or "zone_read_failed"
			end
			local fenced = ZoneRepository.update(dependencies.store, dependencies.zoneKeyFor, snapshot, snapshot.value)
			if not fenced.ok then
				return fenced.reason or "zone_fence_failed"
			end
		end
		return nil
	end

	function Coordinator.acquireAndHydrate(
		dependencies: Dependencies,
		zoneId: string,
		characterId: string,
		sessionId: string,
		acquisitionId: string
	): Outcome<R>
		local now = dependencies.clock()
		local acquired = LeaseRepository.acquire(
			dependencies.store,
			dependencies.leaseKeyFor,
			characterId,
			sessionId,
			acquisitionId,
			now,
			config.leaseSeconds,
			nil,
			nil,
			zoneId
		)
		if not acquired.ok then
			return denied(acquired.reason or "lease_acquire_failed", nil)
		end
		local lease = acquired.value
		local function releaseAfterFailure(reason: string): Refused
			local released = LeaseRepository.release(
				dependencies.store,
				dependencies.leaseKeyFor,
				characterId,
				sessionId,
				acquisitionId,
				lease.revision
			)
			return denied(reason, if released.ok then nil else released.reason or "release_failed")
		end
		local fenceReason =
			fenceTakeover(dependencies, characterId, sessionId, acquisitionId, lease, acquired.takeoverPrior)
		if fenceReason ~= nil then
			return releaseAfterFailure(fenceReason)
		end
		local zoneSnapshot = ZoneRepository.read(dependencies.store, dependencies.zoneKeyFor, zoneId, characterId)
		if not zoneSnapshot.ok then
			return releaseAfterFailure(zoneSnapshot.reason or "zone_read_failed")
		end
		local session, sessionReason = ProfileSession.openAcquired(dependencies.clock(), lease.expiresAt)
		if session == nil then
			return releaseAfterFailure(sessionReason or "session_open_failed")
		end
		return {
			ok = true,
			reason = nil,
			releaseReason = nil,
			session = session,
			lease = lease,
			zoneSnapshot = zoneSnapshot,
		}
	end

	local function saveDenied(reason: string, lease: Lease?): SaveRefused
		return {
			ok = false,
			reason = reason,
			lease = lease,
			zoneSnapshot = nil,
		}
	end

	function Coordinator.savePayload(
		dependencies: Dependencies,
		session: SessionState,
		leaseRaw: unknown,
		zoneSnapshot: unknown,
		questsRaw: unknown
	): SaveOutcome<R>
		local now = dependencies.clock()
		local marked = ProfileSession.dirty(session, now, config.dirtyReason)
		if not marked.ok then
			return saveDenied(marked.reason or "session_dirty_failed", nil)
		end
		local begun = ProfileSession.begin(session, now)
		if not begun.ok then
			return saveDenied(begun.reason or "session_begin_failed", nil)
		end
		local lease = LeaseRecord.copy(leaseRaw)
		if lease == nil or lease.sessionId == nil or lease.acquisitionId == nil then
			ProfileSession.finish(session, dependencies.clock(), false)
			return saveDenied("lease_invalid", nil)
		end
		local renewed = LeaseRepository.renew(
			dependencies.store,
			dependencies.leaseKeyFor,
			lease.characterId,
			lease.sessionId,
			lease.acquisitionId,
			lease.revision,
			now,
			config.leaseSeconds
		)
		if not renewed.ok then
			ProfileSession.finish(session, dependencies.clock(), false)
			return saveDenied(renewed.reason or "lease_renew_failed", nil)
		end
		session.leaseExpiresAt = renewed.value.expiresAt
		if dependencies.clock() >= renewed.value.expiresAt then
			local expired = ProfileSession.finish(session, dependencies.clock(), false)
			return saveDenied(expired.reason or "lease_lost", renewed.value)
		end
		local snapshot = Value.raw(zoneSnapshot)
		if snapshot == nil then
			ProfileSession.finish(session, dependencies.clock(), false)
			return saveDenied("snapshot_invalid", renewed.value)
		end
		local desired = ZoneRecord.copy(snapshot.value)
		if desired == nil then
			ProfileSession.finish(session, dependencies.clock(), false)
			return saveDenied("snapshot_invalid", renewed.value)
		end
		local validated, validationReason = config.withPayload(desired, questsRaw)
		if validated == nil then
			ProfileSession.finish(session, dependencies.clock(), false)
			return saveDenied(validationReason or "quests_invalid", renewed.value)
		end
		if config.characterId(validated) ~= lease.characterId then
			ProfileSession.finish(session, dependencies.clock(), false)
			return saveDenied("identity_mismatch", renewed.value)
		end
		local persisted = ZoneRepository.update(dependencies.store, dependencies.zoneKeyFor, zoneSnapshot, validated)
		local finished = ProfileSession.finish(session, dependencies.clock(), persisted.ok)
		session.leaseExpiresAt = renewed.value.expiresAt
		if not persisted.ok then
			return saveDenied(persisted.reason or "zone_update_failed", renewed.value)
		end
		if not finished.ok then
			return saveDenied(finished.reason or "session_finish_failed", renewed.value)
		end
		return {
			ok = true,
			reason = nil,
			lease = renewed.value,
			zoneSnapshot = {
				ok = true,
				value = persisted.value,
				reason = nil,
				found = true,
			},
		}
	end

	return table.freeze(Coordinator)
end

return table.freeze({ configure = configure })
