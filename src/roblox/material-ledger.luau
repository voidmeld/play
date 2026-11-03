--!strict
local CoreTypes = require("../core/ledger/ledger")
local EqualData = require("../core/internal/equal-data")
local Shape = require("../core/social/shape")
local Value = require("../core/internal/value")
export type State = CoreTypes.State
export type Event = CoreTypes.Event
type StoredRecord = { schemaVersion: number, events: { Event }, recentEventIds: { string }, windowFloorAt: number }
type MigratedRecord = { state: State, windowIds: { [string]: boolean }, windowFloorAt: number }

export type AppendValue = { replayed: boolean, settled: boolean, groupId: string? }
export type SnapshotValue = {
	found: boolean,
	balances: { [string]: { [string]: number } },
	tornGroups: { CoreTypes.TornGroup },
	eventCount: number,
	windowFloorAt: number,
	boundary: string,
}
export type Failure = { ok: false, value: nil, reason: string? }
export type StoreOutcome = { ok: boolean, value: unknown, reason: string? }
export type Store = { update: (string, (unknown) -> unknown) -> StoreOutcome }
export type Outcome<T> = Failure | { ok: true, value: T, reason: nil }

export type CorePort = {
	read emptyState: () -> State,
	read projectEvent: (unknown) -> (Event?, string?),
	read projectState: (unknown) -> (State?, string?),
	read apply: (unknown, unknown) -> (CoreTypes.ApplyResult?, string?),
	read balances: (unknown) -> ({ [string]: { [string]: number } }?, string?),
	read tornGroups: (unknown) -> ({ CoreTypes.TornGroup }?, string?),
}
export type Config = {
	read core: CorePort,
	read schemaVersion: number,
	read windowLimit: number,
	read maxText: number,
	read boundary: string,
}
export type API = {
	read append: (Store, (string) -> string, string, unknown) -> Outcome<AppendValue>,
	read snapshot: (Store, (string) -> string, string) -> Outcome<SnapshotValue>,
	read SCHEMA_VERSION: number,
	read WINDOW_LIMIT: number,
	read NO_FLOOR: number,
	read BOUNDARY: string,
	read REASONS: { string },
}
local function configure(config: Config): API
	config = table.freeze(table.clone(config))
	for _, limit in { config.schemaVersion, config.windowLimit, config.maxText } do
		assert(Value.whole(limit, 1, 9007199254740991) ~= nil, "invalid material ledger bound")
	end
	local Core = config.core
	local SCHEMA_VERSION = config.schemaVersion
	local WINDOW_LIMIT = config.windowLimit
	local MAX_TEXT = config.maxText
	local NO_FLOOR = -1
	local BOUNDARY = config.boundary
	local Service = {}
	local REASONS: { string } = {
		"ledger_key_invalid",
		"record_invalid",
		"schema_unknown",
		"window_mismatch",
		"replay_unverifiable",
		"store_failure",
		"readback_mismatch",
		"snapshot_wrote",
	}

	local RECORD_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		events = true,
		recentEventIds = true,
		windowFloorAt = true,
	}

	local function failed(reason: string): Failure
		return { ok = false, value = nil, reason = reason }
	end

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_TEXT
	end

	local hasOnlyFields = Shape.onlyFields

	local denseLength = Shape.denseLength

	local function migrate(value: unknown): (MigratedRecord?, string?)
		if not hasOnlyFields(value, RECORD_FIELDS) then
			return nil, "record_invalid"
		end
		local raw = Shape.raw(value)
		if raw == nil then
			return nil, "record_invalid"
		end
		if type(raw.schemaVersion) ~= "number" then
			return nil, "record_invalid"
		end
		if raw.schemaVersion ~= SCHEMA_VERSION then
			return nil, "schema_unknown"
		end
		if type(raw.windowFloorAt) ~= "number" then
			return nil, "record_invalid"
		end
		local state, stateReason = Core.projectState({ events = raw.events })
		if state == nil then
			return nil, stateReason or "record_invalid"
		end
		local eventCount = #state.events
		local start = math.max(1, eventCount - WINDOW_LIMIT + 1)
		local expectedFloor = if eventCount > WINDOW_LIMIT then state.events[eventCount - WINDOW_LIMIT].at else NO_FLOOR
		local idCount = denseLength(raw.recentEventIds)
		local ids = Shape.raw(raw.recentEventIds)
		if idCount == nil or ids == nil then
			return nil, "record_invalid"
		end
		if idCount ~= eventCount - start + 1 then
			return nil, "window_mismatch"
		end
		local windowIds: { [string]: boolean } = {}
		for offset = 1, idCount do
			local expected = state.events[start + offset - 1].eventId
			if (ids)[offset] ~= expected then
				return nil, "window_mismatch"
			end
			windowIds[expected] = true
		end
		if raw.windowFloorAt ~= expectedFloor then
			return nil, "window_mismatch"
		end
		return {
			state = state,
			windowIds = windowIds,
			windowFloorAt = expectedFloor,
		}, nil
	end

	local function buildRecord(state: State): StoredRecord
		local rows: { Event } = {}
		for index, event in state.events do
			rows[index] = {
				eventId = event.eventId,
				kind = event.kind,
				materialId = event.materialId,
				count = event.count,
				actorId = event.actorId,
				at = event.at,
				groupId = event.groupId,
				groupSize = event.groupSize,
			}
		end
		local eventCount = #rows
		local start = math.max(1, eventCount - WINDOW_LIMIT + 1)
		local recentEventIds = {}
		for index = start, eventCount do
			table.insert(recentEventIds, rows[index].eventId)
		end
		local windowFloorAt = if eventCount > WINDOW_LIMIT then rows[eventCount - WINDOW_LIMIT].at else NO_FLOOR
		return {
			schemaVersion = SCHEMA_VERSION,
			events = rows,
			recentEventIds = recentEventIds,
			windowFloorAt = windowFloorAt,
		}
	end

	function Service.append(
		store: Store,
		keyForLedger: (string) -> string,
		ledgerId: string,
		eventValue: unknown
	): Outcome<AppendValue>
		if type(keyForLedger) ~= "function" or not text(ledgerId) then
			return failed("ledger_key_invalid")
		end
		local row, eventReason = Core.projectEvent(eventValue)
		if row == nil then
			return failed(eventReason or "store_failure")
		end
		local replaySatisfied: AppendValue? = nil
		local transformFail: string? = nil
		local appliedValue: AppendValue? = nil
		local desired: StoredRecord? = nil
		local result = store.update(keyForLedger(ledgerId), function(current)
			replaySatisfied = nil
			transformFail = nil
			appliedValue = nil
			desired = nil
			local state: State
			local windowIds: { [string]: boolean }
			local windowFloorAt: number
			if current == nil then
				state = Core.emptyState()
				windowIds = {}
				windowFloorAt = NO_FLOOR
			else
				local record, migrateReason = migrate(current)
				if record == nil then
					transformFail = migrateReason
					return nil
				end
				state = record.state
				windowIds = record.windowIds
				windowFloorAt = record.windowFloorAt
			end
			if windowIds[row.eventId] == nil and row.at <= windowFloorAt then
				transformFail = "replay_unverifiable"
				return nil
			end
			local applied, applyReason = Core.apply(state, row)
			if applied == nil then
				transformFail = applyReason
				return nil
			end
			if applied.replayed then
				replaySatisfied = { replayed = true, settled = applied.settled, groupId = applied.groupId }
				return nil
			end
			appliedValue = { replayed = false, settled = applied.settled, groupId = applied.groupId }
			desired = buildRecord(applied.state)
			return desired
		end)
		if not result.ok then
			if result.reason ~= "callback_cancelled" then
				return failed(result.reason or "store_failure")
			end
			if replaySatisfied ~= nil then
				return { ok = true, value = replaySatisfied, reason = nil }
			end
			return failed(transformFail or "store_failure")
		end
		local readback = migrate(result.value)
		if readback == nil then
			return failed("readback_mismatch")
		end
		if readback.windowIds[row.eventId] == nil then
			return failed("readback_mismatch")
		end
		if appliedValue == nil or desired == nil or not EqualData(result.value, desired) then
			return failed("readback_mismatch")
		end
		return { ok = true, value = appliedValue, reason = nil }
	end

	function Service.snapshot(store: Store, keyForLedger: (string) -> string, ledgerId: string): Outcome<SnapshotValue>
		if type(keyForLedger) ~= "function" or not text(ledgerId) then
			return failed("ledger_key_invalid")
		end
		local captured: SnapshotValue? = nil
		local transformFail: string? = nil
		local result = store.update(keyForLedger(ledgerId), function(current)
			captured = nil
			transformFail = nil
			if current == nil then
				local balances: { [string]: { [string]: number } } = {}
				local tornGroups: { CoreTypes.TornGroup } = {}
				captured = {
					found = false,
					balances = table.freeze(balances),
					tornGroups = table.freeze(tornGroups),
					eventCount = 0,
					windowFloorAt = NO_FLOOR,
					boundary = BOUNDARY,
				}
				return nil
			end
			local record, migrateReason = migrate(current)
			if record == nil then
				transformFail = migrateReason
				return nil
			end
			local balances = Core.balances(record.state)
			local tornGroups = Core.tornGroups(record.state)
			if balances == nil or tornGroups == nil then
				transformFail = "record_invalid"
				return nil
			end
			captured = {
				found = true,
				balances = balances,
				tornGroups = tornGroups,
				eventCount = #record.state.events,
				windowFloorAt = record.windowFloorAt,
				boundary = BOUNDARY,
			}
			return nil
		end)
		if result.ok then
			return failed("snapshot_wrote")
		end
		if result.reason ~= "callback_cancelled" then
			return failed(result.reason or "store_failure")
		end
		if captured ~= nil then
			return { ok = true, value = captured, reason = nil }
		end
		return failed(transformFail or "store_failure")
	end

	Service.SCHEMA_VERSION = SCHEMA_VERSION
	Service.WINDOW_LIMIT = WINDOW_LIMIT
	Service.NO_FLOOR = NO_FLOOR
	Service.BOUNDARY = BOUNDARY
	Service.REASONS = table.freeze(REASONS)

	return table.freeze(Service)
end
return table.freeze({ configure = configure })
