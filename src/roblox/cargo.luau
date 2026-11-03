--!strict
local CoreTypes = require("../core/inventory/cargo")
local EqualData = require("../core/internal/equal-data")
local LedgerTypes = require("./material-ledger")
local Value = require("../kernel/value")
export type State = CoreTypes.State
type CoreResult = CoreTypes.Result
export type Intent = CoreTypes.Intent
type Envelope = {
	zoneId: string,
	nowSec: number,
	spaceKind: unknown,
	claimId: unknown,
	actorId: unknown,
	materialId: unknown,
	count: unknown,
	dropId: unknown,
	cause: unknown,
	expiresAtSec: unknown,
	realmId: unknown,
	campId: unknown,
	position: unknown,
	extractionId: unknown,
}

type ReadValue = {
	found: boolean,
	census: { CoreTypes.CensusRow },
	carried: { CoreTypes.Total },
	openDrops: { CoreTypes.Drop },
}
export type StoreOutcome = LedgerTypes.StoreOutcome
export type Store = LedgerTypes.Store

export type Position = { x: number, y: number, z: number }

export type Camp = {
	read campId: string,
	read realmId: string,
	read center: Position,
	read radiusStuds: number,
}

export type Dependencies = {
	loadCamps: () -> unknown,
	store: Store,
	keyForHaul: (string) -> string,
	keyForLedger: (string) -> string,
}

export type Outcome = {
	read ok: boolean,
	read reason: string?,
	read replayed: boolean,
	read carriedCount: number,
	read droppedCount: number,
	read recoveredCount: number,
	read expiredCount: number,
	read bankedCount: number,
	read ledgerReplayed: boolean,
	read dropId: string?,
	read extractionId: string?,
	read intents: { Intent },
	read boundary: string,
}

export type ReadOutcome = {
	read ok: boolean,
	read reason: string?,
	read found: boolean,
	read census: { CoreTypes.CensusRow },
	read carried: { CoreTypes.Total },
	read openDrops: { CoreTypes.Drop },
	read boundary: string,
}

export type Service = {
	read campIds: { string },
	read campFor: (campId: string) -> Camp?,
	read emptyState: () -> State,
	read admitsExtraction: (campId: string, realmId: string, position: unknown) -> (boolean, string?),
	read carry: (request: unknown) -> Outcome,
	read release: (request: unknown) -> Outcome,
	read recover: (request: unknown) -> Outcome,
	read expire: (request: unknown) -> Outcome,
	read extract: (request: unknown) -> Outcome,
	read read: (zoneId: string, actorId: string, nowSec: number) -> ReadOutcome,
}

export type MountResult = {
	read ok: boolean,
	read service: Service?,
	read reason: string?,
}

export type CorePort = {
	read emptyState: () -> State,
	read projectState: (unknown) -> (State?, string?),
	read step: (unknown, unknown, unknown) -> (CoreTypes.Result?, string?),
	read carriedOf: (unknown, unknown) -> ({ CoreTypes.Total }?, string?),
	read census: (unknown) -> ({ CoreTypes.CensusRow }?, string?),
	read openDrops: (unknown, unknown) -> ({ CoreTypes.Drop }?, string?),
}
export type Config = {
	read core: CorePort,
	read ledger: LedgerTypes.API,
	read schemaVersion: number,
	read maxText: number,
	read maxAt: number,
	read carriedSpaceKind: string,
	read bankedSpaceKind: string,
	read bankedSpaceReason: string,
	read dropExpirySeconds: number,
	read realms: { [string]: boolean },
	read boundary: string,
}
export type API = {
	read mount: (Dependencies?) -> MountResult,
	read mountFromContent: (Dependencies?) -> MountResult,
	read SCHEMA_VERSION: number,
	read CARRIED_SPACE_KIND: string,
	read BANKED_SPACE_KIND: string,
	read DROP_EXPIRY_SECONDS: number,
	read REALMS: { [string]: boolean },
	read BOUNDARY: string,
	read REASONS: { string },
}
local function configure(config: Config): API
	config = table.freeze(table.clone(config))
	for _, bound in { config.schemaVersion, config.maxText } do
		assert(Value.whole(bound, 1, 9007199254740991) ~= nil, "invalid cargo bound")
	end
	assert(Value.finite(config.maxAt) and config.maxAt > 0, "invalid cargo clock limit")
	assert(Value.finite(config.dropExpirySeconds) and config.dropExpirySeconds > 0, "invalid cargo expiry")
	assert(
		#config.carriedSpaceKind > 0
			and #config.bankedSpaceKind > 0
			and config.carriedSpaceKind ~= config.bankedSpaceKind,
		"invalid cargo spaces"
	)
	assert(#config.bankedSpaceReason > 0, "missing banked-space refusal")
	local Core = config.core
	local Ledger = config.ledger
	local SCHEMA_VERSION = config.schemaVersion
	local MAX_TEXT = config.maxText
	local MAX_AT = config.maxAt
	local CARRIED_SPACE_KIND = config.carriedSpaceKind
	local BANKED_SPACE_KIND = config.bankedSpaceKind
	local BANKED_SPACE_REASON = config.bankedSpaceReason
	local DROP_EXPIRY_SECONDS = config.dropExpirySeconds
	local REALMS = table.freeze(table.clone(config.realms))
	local BOUNDARY = config.boundary
	local REASONS: { string } = {
		"sources_malformed",
		"store_unwired",
		"dependencies_malformed",
		"camps_load_failed",
		"camps_refused",
		"request_shape_invalid",
		"zone_invalid",
		"clock_invalid",
		"actor_invalid",
		"realm_unknown",
		"space_kind_invalid",
		BANKED_SPACE_REASON,
		"unknown_camp",
		"camp_realm_mismatch",
		"position_invalid",
		"outside_camp_radius",
		"record_invalid",
		"schema_unknown",
		"zone_mismatch",
		"core_refused",
		"store_failure",
		"ledger_refused",
		"readback_mismatch",
		"read_wrote",
	}

	local RECORD_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		zoneId = true,
		haul = true,
	}

	local CARRY_FIELDS: { [string]: boolean } = {
		zoneId = true,
		nowSec = true,
		claimId = true,
		actorId = true,
		materialId = true,
		count = true,
		spaceKind = true,
	}

	local RELEASE_FIELDS: { [string]: boolean } = {
		zoneId = true,
		nowSec = true,
		dropId = true,
		actorId = true,
		cause = true,
		expiresAtSec = true,
	}

	local RECOVER_FIELDS: { [string]: boolean } = {
		zoneId = true,
		nowSec = true,
		dropId = true,
		actorId = true,
	}

	local EXPIRE_FIELDS: { [string]: boolean } = {
		zoneId = true,
		nowSec = true,
		dropId = true,
	}

	local EXTRACT_FIELDS: { [string]: boolean } = {
		zoneId = true,
		nowSec = true,
		extractionId = true,
		actorId = true,
		realmId = true,
		campId = true,
		position = true,
	}

	local CAMP_FIELDS: { [string]: boolean } = {
		campId = true,
		realmId = true,
		center = true,
		radiusStuds = true,
	}

	local POSITION_FIELDS: { [string]: boolean } = {
		x = true,
		y = true,
		z = true,
	}

	local finite = Value.finite

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_TEXT
	end

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
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

	local function denseLength(value: unknown): number?
		local fields = Value.raw(value)
		if fields == nil then
			return nil
		end
		local count = 0
		for key in fields do
			if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
				return nil
			end
			count += 1
		end
		for index = 1, count do
			if fields[index] == nil then
				return nil
			end
		end
		return count
	end

	local function projectPosition(value: unknown): Position?
		if not hasOnlyFields(value, POSITION_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		local x, y, z = source.x, source.y, source.z
		if
			type(x) ~= "number"
			or type(y) ~= "number"
			or type(z) ~= "number"
			or not finite(x)
			or not finite(y)
			or not finite(z)
		then
			return nil
		end
		return { x = x, y = y, z = z }
	end

	local function distanceSquared(a: Position, b: Position): number
		local dx = a.x - b.x
		local dy = a.y - b.y
		local dz = a.z - b.z
		return dx * dx + dy * dy + dz * dz
	end

	local function refusedMount(reason: string): MountResult
		return table.freeze({ ok = false, service = nil, reason = reason })
	end

	local function refused(reason: string?): Outcome
		local intents: { Intent } = {}
		table.freeze(intents)
		local result: Outcome = {
			ok = false,
			reason = reason,
			replayed = false,
			carriedCount = 0,
			droppedCount = 0,
			recoveredCount = 0,
			expiredCount = 0,
			bankedCount = 0,
			ledgerReplayed = false,
			dropId = nil,
			extractionId = nil,
			intents = intents,
			boundary = BOUNDARY,
		}
		return table.freeze(result)
	end

	local function refusedRead(reason: string): ReadOutcome
		local census: { CoreTypes.CensusRow } = {}
		local carried: { CoreTypes.Total } = {}
		local openDrops: { CoreTypes.Drop } = {}
		table.freeze(census)
		table.freeze(carried)
		table.freeze(openDrops)
		local result: ReadOutcome = {
			ok = false,
			reason = reason,
			found = false,
			census = census,
			carried = carried,
			openDrops = openDrops,
			boundary = BOUNDARY,
		}
		return table.freeze(result)
	end

	local function accepted(result: CoreResult, ledgerReplayed: boolean): Outcome
		return table.freeze({
			ok = true,
			reason = nil,
			replayed = result.replayed,
			carriedCount = result.carriedCount,
			droppedCount = result.droppedCount,
			recoveredCount = result.recoveredCount,
			expiredCount = result.expiredCount,
			bankedCount = result.bankedCount,
			ledgerReplayed = ledgerReplayed,
			dropId = result.dropId,
			extractionId = result.extractionId,
			intents = result.intents,
			boundary = BOUNDARY,
		})
	end

	local function stagedKey(ledgerId: string): string
		return ledgerId
	end

	local function stagedStore(seed: unknown): (Store, () -> unknown)
		local staged = seed
		local store: Store = {
			update = function(_key, transform): StoreOutcome
				local nextValue = transform(staged)
				if nextValue == nil then
					return { ok = false, value = nil, reason = "callback_cancelled" }
				end
				staged = nextValue
				return { ok = true, value = staged, reason = nil }
			end,
		}
		return store, function()
			return staged
		end
	end

	local function readRecord(value: unknown, zoneId: string): (State?, string?)
		if not hasOnlyFields(value, RECORD_FIELDS) then
			return nil, "record_invalid"
		end
		local record = assert(Value.raw(value))
		if type(record.schemaVersion) ~= "number" then
			return nil, "record_invalid"
		end
		if record.schemaVersion ~= SCHEMA_VERSION then
			return nil, "schema_unknown"
		end
		if record.zoneId ~= zoneId then
			return nil, "zone_mismatch"
		end
		local state, stateReason = Core.projectState(record.haul)
		if state == nil then
			return nil, stateReason or "record_invalid"
		end
		return state, nil
	end

	local function envelope(requestValue: unknown, fields: { [string]: boolean }): (Envelope?, string?)
		if not hasOnlyFields(requestValue, fields) then
			return nil, "request_shape_invalid"
		end
		local source = assert(Value.raw(requestValue))
		local zoneId, nowSec = source.zoneId, source.nowSec
		if type(zoneId) ~= "string" or not text(zoneId) then
			return nil, "zone_invalid"
		end
		if type(nowSec) ~= "number" or not finite(nowSec) or nowSec < 0 or nowSec > MAX_AT then
			return nil, "clock_invalid"
		end
		return {
			zoneId = zoneId,
			nowSec = nowSec,
			spaceKind = source.spaceKind,
			claimId = source.claimId,
			actorId = source.actorId,
			materialId = source.materialId,
			count = source.count,
			dropId = source.dropId,
			cause = source.cause,
			expiresAtSec = source.expiresAtSec,
			realmId = source.realmId,
			campId = source.campId,
			position = source.position,
			extractionId = source.extractionId,
		},
			nil
	end

	local HaulService = {}

	function HaulService.mount(dependencies: Dependencies?): MountResult
		local raw = dependencies
		if
			type(raw) ~= "table"
			or type(raw.loadCamps) ~= "function"
			or type(raw.store) ~= "table"
			or type((raw.store).update) ~= "function"
			or type(raw.keyForHaul) ~= "function"
			or type(raw.keyForLedger) ~= "function"
		then
			return refusedMount("dependencies_malformed")
		end
		local deps = raw

		local loaded = table.pack(pcall(deps.loadCamps))
		if loaded.n ~= 2 or loaded[1] ~= true then
			return refusedMount("camps_load_failed")
		end
		local loadedRows = Value.raw(loaded[2])
		local rowCount = denseLength(loadedRows)
		if loadedRows == nil or rowCount == nil or rowCount < 1 then
			return refusedMount("camps_refused")
		end

		local campIds: { string } = {}
		local campById: { [string]: Camp } = {}
		for index = 1, rowCount do
			local row = Value.raw(loadedRows[index])
			if row == nil or not hasOnlyFields(row, CAMP_FIELDS) then
				return refusedMount("camps_refused")
			end
			if type(row.campId) ~= "string" or not text(row.campId) or campById[row.campId] ~= nil then
				return refusedMount("camps_refused")
			end
			if type(row.realmId) ~= "string" or REALMS[row.realmId] ~= true then
				return refusedMount("camps_refused")
			end
			if type(row.radiusStuds) ~= "number" or not finite(row.radiusStuds) or row.radiusStuds <= 0 then
				return refusedMount("camps_refused")
			end
			local center = projectPosition(row.center)
			if center == nil then
				return refusedMount("camps_refused")
			end
			local camp: Camp = {
				campId = row.campId,
				realmId = row.realmId,
				center = center,
				radiusStuds = row.radiusStuds,
			}
			table.freeze(center)
			table.freeze(camp)
			campById[camp.campId] = camp
			table.insert(campIds, camp.campId)
		end

		local function campFor(campId: string): Camp?
			return campById[campId]
		end

		local function admitsExtraction(campId: string, realmId: string, positionValue: unknown): (boolean, string?)
			local camp = campById[campId]
			if camp == nil then
				return false, "unknown_camp"
			end
			if REALMS[realmId] ~= true then
				return false, "realm_unknown"
			end
			if camp.realmId ~= realmId then
				return false, "camp_realm_mismatch"
			end
			local position = projectPosition(positionValue)
			if position == nil then
				return false, "position_invalid"
			end
			if distanceSquared(position, camp.center) > camp.radiusStuds * camp.radiusStuds then
				return false, "outside_camp_radius"
			end
			return true, nil
		end

		local function commit(zoneId: string, nowSec: number, command: unknown): (CoreResult?, string?)
			local transformFail: string? = nil
			local produced: CoreResult? = nil
			local result = deps.store.update(deps.keyForHaul(zoneId), function(current)
				transformFail = nil
				produced = nil
				local stateValue: State
				if current == nil then
					stateValue = Core.emptyState()
				else
					local state, recordReason = readRecord(current, zoneId)
					if state == nil then
						transformFail = recordReason
						return nil
					end
					stateValue = state
				end
				local outcome, outcomeReason = Core.step(stateValue, command, nowSec)
				if outcome == nil then
					transformFail = "core_refused: " .. tostring(outcomeReason)
					return nil
				end
				produced = outcome
				if outcome.replayed and current ~= nil then
					return nil
				end
				return {
					schemaVersion = SCHEMA_VERSION,
					zoneId = zoneId,
					haul = outcome.state,
				}
			end)

			if not result.ok then
				if result.reason ~= "callback_cancelled" then
					return nil, result.reason or "store_failure"
				end
				if transformFail ~= nil then
					return nil, transformFail
				end
				if produced == nil then
					return nil, "store_failure"
				end
				return produced, nil
			end
			local readback, readbackReason = readRecord(result.value, zoneId)
			if readback == nil then
				return nil, readbackReason or "readback_mismatch"
			end
			if produced == nil or not EqualData(readback, produced.state) then
				return nil, "readback_mismatch"
			end
			return produced, nil
		end

		local function settle(actorId: string, intents: { Intent }): (boolean, string?)
			local transformFail: string? = nil
			local wroteAny = false
			local desired: unknown = nil
			local result = deps.store.update(deps.keyForLedger(actorId), function(current)
				transformFail = nil
				wroteAny = false
				desired = nil
				local staged, readStaged = stagedStore(current)
				for _, intent in intents do
					local appended = Ledger.append(staged, stagedKey, actorId, intent)
					if not appended.ok then
						transformFail = "ledger_refused: " .. tostring(appended.reason)
						return nil
					end
					if not appended.value.replayed then
						wroteAny = true
					end
				end
				if not wroteAny then
					return nil
				end
				desired = readStaged()
				return desired
			end)
			if not result.ok then
				if result.reason ~= "callback_cancelled" then
					return false, result.reason or "store_failure"
				end
				if transformFail ~= nil then
					return false, transformFail
				end
				return false, nil
			end
			if not wroteAny or desired == nil or not EqualData(result.value, desired) then
				return false, "readback_mismatch"
			end
			return true, nil
		end

		local function carry(requestValue: unknown): Outcome
			local request, envelopeReason = envelope(requestValue, CARRY_FIELDS)
			if request == nil then
				return refused(envelopeReason)
			end
			if request.spaceKind ~= CARRIED_SPACE_KIND then
				if request.spaceKind == BANKED_SPACE_KIND then
					return refused(BANKED_SPACE_REASON)
				end
				return refused("space_kind_invalid")
			end
			local produced, reason = commit(request.zoneId, request.nowSec, {
				kind = "carry",
				claimId = request.claimId,
				actorId = request.actorId,
				materialId = request.materialId,
				count = request.count,
			})
			if produced == nil then
				return refused(reason)
			end
			return accepted(produced, false)
		end

		local function release(requestValue: unknown): Outcome
			local request, envelopeReason = envelope(requestValue, RELEASE_FIELDS)
			if request == nil then
				return refused(envelopeReason)
			end
			local expiresAtSec = request.expiresAtSec
			if expiresAtSec == nil then
				expiresAtSec = request.nowSec + DROP_EXPIRY_SECONDS
			end
			local produced, reason = commit(request.zoneId, request.nowSec, {
				kind = "release",
				dropId = request.dropId,
				actorId = request.actorId,
				cause = request.cause,
				expiresAtSec = expiresAtSec,
			})
			if produced == nil then
				return refused(reason)
			end
			return accepted(produced, false)
		end

		local function recover(requestValue: unknown): Outcome
			local request, envelopeReason = envelope(requestValue, RECOVER_FIELDS)
			if request == nil then
				return refused(envelopeReason)
			end
			local produced, reason = commit(request.zoneId, request.nowSec, {
				kind = "recover",
				dropId = request.dropId,
				actorId = request.actorId,
			})
			if produced == nil then
				return refused(reason)
			end
			return accepted(produced, false)
		end

		local function expire(requestValue: unknown): Outcome
			local request, envelopeReason = envelope(requestValue, EXPIRE_FIELDS)
			if request == nil then
				return refused(envelopeReason)
			end
			local produced, reason = commit(request.zoneId, request.nowSec, {
				kind = "expire",
				dropId = request.dropId,
			})
			if produced == nil then
				return refused(reason)
			end
			return accepted(produced, false)
		end

		local function extract(requestValue: unknown): Outcome
			local request, envelopeReason = envelope(requestValue, EXTRACT_FIELDS)
			if request == nil then
				return refused(envelopeReason)
			end
			if type(request.actorId) ~= "string" or not text(request.actorId) then
				return refused("actor_invalid")
			end
			if type(request.realmId) ~= "string" or REALMS[request.realmId] ~= true then
				return refused("realm_unknown")
			end
			if type(request.campId) ~= "string" or not text(request.campId) then
				return refused("unknown_camp")
			end
			local admitted, refusal = admitsExtraction(request.campId, request.realmId, request.position)
			if not admitted then
				return refused(refusal)
			end
			local produced, reason = commit(request.zoneId, request.nowSec, {
				kind = "extract",
				extractionId = request.extractionId,
				actorId = request.actorId,
				campId = request.campId,
			})
			if produced == nil then
				return refused(reason)
			end
			local wrote, settleReason = settle(request.actorId, produced.intents)
			if settleReason ~= nil then
				return refused(settleReason)
			end
			return accepted(produced, not wrote)
		end

		local function read(zoneId: string, actorId: string, nowSec: number): ReadOutcome
			if not text(zoneId) then
				return refusedRead("zone_invalid")
			end
			if not text(actorId) then
				return refusedRead("actor_invalid")
			end
			if not finite(nowSec) or nowSec < 0 or nowSec > MAX_AT then
				return refusedRead("clock_invalid")
			end
			local captured: ReadValue? = nil
			local transformFail: string? = nil
			local result = deps.store.update(deps.keyForHaul(zoneId), function(current)
				captured = nil
				transformFail = nil
				if current == nil then
					local empty = refusedRead("empty")
					captured =
						{ found = false, census = empty.census, carried = empty.carried, openDrops = empty.openDrops }
					return nil
				end
				local state, recordReason = readRecord(current, zoneId)
				if state == nil then
					transformFail = recordReason
					return nil
				end
				captured = {
					found = true,
					census = assert(Core.census(state)),
					carried = assert(Core.carriedOf(state, actorId)),
					openDrops = assert(Core.openDrops(state, nowSec)),
				}
				return nil
			end)
			if result.ok then
				return refusedRead("read_wrote")
			end
			if result.reason ~= "callback_cancelled" then
				return refusedRead(result.reason or "store_failure")
			end
			if captured == nil then
				return refusedRead(transformFail or "store_failure")
			end
			return table.freeze({
				ok = true,
				reason = nil,
				found = captured.found,
				census = captured.census,
				carried = captured.carried,
				openDrops = captured.openDrops,
				boundary = BOUNDARY,
			})
		end

		local service: Service = table.freeze({
			campIds = table.freeze(campIds),
			campFor = campFor,
			emptyState = Core.emptyState,
			admitsExtraction = admitsExtraction,
			carry = carry,
			release = release,
			recover = recover,
			expire = expire,
			extract = extract,
			read = read,
		})
		return table.freeze({ ok = true, service = service, reason = nil })
	end

	function HaulService.mountFromContent(sources: Dependencies?): MountResult
		if type(sources) ~= "table" then
			return refusedMount("sources_malformed")
		end
		if (sources).store == nil then
			return refusedMount("store_unwired")
		end
		return HaulService.mount(sources)
	end

	HaulService.SCHEMA_VERSION = SCHEMA_VERSION
	HaulService.CARRIED_SPACE_KIND = CARRIED_SPACE_KIND
	HaulService.BANKED_SPACE_KIND = BANKED_SPACE_KIND
	HaulService.DROP_EXPIRY_SECONDS = DROP_EXPIRY_SECONDS
	HaulService.REALMS = REALMS
	HaulService.BOUNDARY = BOUNDARY
	HaulService.REASONS = table.freeze(REASONS)

	return table.freeze(HaulService)
end
return table.freeze({ configure = configure })
