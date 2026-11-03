--!strict

type Raw = { [unknown]: unknown }

local Tables = require("../internal/value")
export type QuestProgress = { status: string, step: number, counts: { [string]: number }? }

export type Record = {
	version: number,
	zoneId: string,
	characterId: string,
	quests: { [string]: QuestProgress },
	semanticEventIds: { [string]: boolean },
}

export type Config = {
	read version: number,
	read maxIdLength: number,
	read maxCharacterIdLength: number,
	read maxEventIdLength: number,
	read maxEvents: number,
	read maxQuests: number,
	read maxCounts: number,
	read maxStep: number,
	read maxCount: number,
	read eventPrefix: string,
	read statuses: { [string]: boolean },
	read claimableStatuses: { [string]: boolean },
	read receiptStatus: string,
	read eventIdAllowed: (string) -> boolean,
}
export type API = {
	read CURRENT_VERSION: number,
	read STATUSES: { [string]: boolean },
	read MAX_EVENT_ID_LENGTH: number,
	read MAX_EVENTS: number,
	read create: (unknown, unknown, unknown, unknown?) -> (Record?, string?),
	read decode: (unknown) -> (Record?, string?),
	read copyQuests: (unknown) -> ({ [string]: QuestProgress }?, string?),
	read copySemanticEventIds: (unknown) -> ({ [string]: boolean }?, string?),
	read storageQuests: (unknown) -> ({ [string]: QuestProgress }?, string?),
	read fromStorageQuests: (unknown, unknown, unknown, { [string]: boolean }?) -> (Record?, string?),
	read key: (string, string) -> string,
}
local function journal(config: Config): API
	config = table.freeze(table.clone(config))
	for _, limit in
		{
			config.version,
			config.maxIdLength,
			config.maxCharacterIdLength,
			config.maxEventIdLength,
			config.maxEvents,
			config.maxQuests,
			config.maxCounts,
		}
	do
		assert(limit >= 1 and limit < math.huge and limit % 1 == 0, "invalid journal bound")
	end
	for _, limit in { config.maxStep, config.maxCount } do
		assert(limit >= 0 and limit < math.huge and limit % 1 == 0, "invalid journal progress bound")
	end
	assert(config.eventPrefix ~= "" and config.statuses[config.receiptStatus] == true, "invalid journal receipt policy")
	local CURRENT_VERSION = config.version
	local MAX_ID_LENGTH = config.maxIdLength
	local MAX_EVENT_ID_LENGTH = config.maxEventIdLength
	local MAX_EVENTS = config.maxEvents
	local EVENT_PREFIX = config.eventPrefix
	local MAX_CHARACTER_ID_LENGTH = config.maxCharacterIdLength
	local MAX_QUESTS = config.maxQuests
	local MAX_COUNTS = config.maxCounts
	local MAX_STEP = config.maxStep
	local MAX_COUNT = config.maxCount

	local STATUSES = table.freeze(table.clone(config.statuses))
	local EVENT_PATTERN = string.gsub(EVENT_PREFIX, "(%W)", "%%%1")

	local function whole(value: unknown, maximum: number): boolean
		return type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value >= 0
			and value <= maximum
			and value == math.floor(value)
	end

	local function validId(value: unknown, maximum: number): boolean
		return type(value) == "string" and #value > 0 and #value <= maximum
	end

	local function copyQuests(raw: unknown): ({ [string]: QuestProgress }?, string?)
		local source = Tables.raw(raw)
		if source == nil then
			return nil, "quests_not_a_table"
		end
		local quests: { [string]: QuestProgress } = {}
		local questCount = 0
		for questId, entry in source do
			questCount += 1
			if questCount > MAX_QUESTS then
				return nil, "too_many_quests"
			end
			if type(questId) ~= "string" or not validId(questId, MAX_ID_LENGTH) then
				return nil, "invalid_quest_id"
			end
			local progress = Tables.raw(entry)
			if progress == nil then
				return nil, "invalid_quest_progress:" .. questId
			end
			local status, step = progress.status, progress.step
			if
				type(status) ~= "string"
				or not STATUSES[status]
				or type(step) ~= "number"
				or not whole(step, MAX_STEP)
			then
				return nil, "invalid_quest_progress:" .. questId
			end
			local counts: { [string]: number }? = nil
			if progress.counts ~= nil then
				local sourceCounts = Tables.raw(progress.counts)
				if sourceCounts == nil then
					return nil, "counts_not_a_table:" .. questId
				end
				counts = {}
				local countEntries = 0
				for objectiveId, count in sourceCounts do
					countEntries += 1
					if countEntries > MAX_COUNTS then
						return nil, "too_many_counts:" .. questId
					end
					if
						type(objectiveId) ~= "string"
						or not validId(objectiveId, MAX_ID_LENGTH)
						or type(count) ~= "number"
						or not whole(count, MAX_COUNT)
					then
						return nil, "invalid_objective_count:" .. questId
					end
					(counts)[objectiveId] = count
				end
			end
			quests[questId] = {
				status = status,
				step = step,
				counts = counts,
			}
		end
		return quests, nil
	end

	local function copySemanticEventIds(raw: unknown): ({ [string]: boolean }?, string?)
		if raw == nil then
			return {}, nil
		end
		local source = Tables.raw(raw)
		if source == nil then
			return nil, "semantic_events_not_a_table"
		end
		local copied: { [string]: boolean } = {}
		local count = 0
		for eventId, answered in source do
			count += 1
			if
				count > MAX_EVENTS
				or type(eventId) ~= "string"
				or not validId(eventId, MAX_EVENT_ID_LENGTH)
				or not config.eventIdAllowed(eventId)
				or answered ~= true
			then
				return nil, "invalid_semantic_event_id"
			end
			copied[eventId] = true
		end
		return copied, nil
	end

	local function create(
		zoneId: unknown,
		characterId: unknown,
		quests: unknown,
		semanticEventIds: unknown?
	): (Record?, string?)
		if type(zoneId) ~= "string" or not validId(zoneId, MAX_ID_LENGTH) then
			return nil, "invalid_zone_id"
		end
		if type(characterId) ~= "string" or not validId(characterId, MAX_CHARACTER_ID_LENGTH) then
			return nil, "invalid_character_id"
		end
		local copied, reason = copyQuests(quests)
		if copied == nil then
			return nil, reason
		end
		local copiedEvents, eventReason = copySemanticEventIds(semanticEventIds)
		if copiedEvents == nil then
			return nil, eventReason
		end
		local total = 0
		for _ in copied do
			total += 1
		end
		for _ in copiedEvents do
			total += 1
		end
		if total > MAX_QUESTS then
			return nil, "too_many_quest_records"
		end
		return {
			version = CURRENT_VERSION,
			zoneId = zoneId,
			characterId = characterId,
			quests = copied,
			semanticEventIds = copiedEvents,
		},
			nil
	end

	local function decode(raw: unknown): (Record?, string?)
		local fields = Tables.raw(raw)
		if fields == nil then
			return nil, "record_not_a_table"
		end
		if fields.version ~= CURRENT_VERSION then
			return nil, "unsupported_version:" .. tostring(fields.version)
		end
		return create(fields.zoneId, fields.characterId, fields.quests, fields.semanticEventIds)
	end

	local function storageQuests(recordRaw: unknown): ({ [string]: QuestProgress }?, string?)
		local record, reason = decode(recordRaw)
		if record == nil then
			return nil, reason
		end
		local stored = table.clone(record.quests)
		for eventId in record.semanticEventIds do
			stored[EVENT_PREFIX .. eventId] = { status = config.receiptStatus, step = 0 }
		end
		return stored, nil
	end

	local CLAIMABLE_STATUSES = table.freeze(table.clone(config.claimableStatuses))

	local function fromStorageQuests(
		zoneId: unknown,
		characterId: unknown,
		raw: unknown,
		knownQuestIds: { [string]: boolean }?
	): (Record?, string?)
		local source = Tables.raw(raw)
		if source == nil then
			return nil, "quests_not_a_table"
		end
		local quests: Raw = {}
		local semanticEventIds: { [string]: boolean } = {}
		for id, value in source do
			local progress = Tables.raw(value)
			local eventId = if type(id) == "string" then string.match(id, "^" .. EVENT_PATTERN .. "(.+)$") else nil
			if eventId == nil then
				quests[id] = value
			elseif
				progress == nil
				or progress.status ~= config.receiptStatus
				or progress.step ~= 0
				or progress.counts ~= nil
			then
				return nil, "invalid_stored_semantic_event"
			else
				semanticEventIds[eventId] = true
			end
		end
		local record, reason = create(zoneId, characterId, quests, semanticEventIds)
		if record == nil then
			return nil, reason
		end
		for questId, progress in record.quests do
			if knownQuestIds ~= nil and knownQuestIds[questId] ~= true then
				return nil, "unknown_quest_id:" .. questId
			end
			if
				progress.step > 0
				and CLAIMABLE_STATUSES[progress.status]
				and (progress.counts == nil or next(progress.counts) == nil)
			then
				return nil, "quest_progress_counts_missing:" .. questId
			end
		end
		return record, nil
	end

	local function key(zoneId: string, characterId: string): string
		return tostring(#zoneId) .. ":" .. zoneId .. characterId
	end

	return table.freeze({
		CURRENT_VERSION = CURRENT_VERSION,
		STATUSES = table.freeze(table.clone(STATUSES)),
		create = create,
		decode = decode,
		copyQuests = copyQuests,
		copySemanticEventIds = copySemanticEventIds,
		storageQuests = storageQuests,
		fromStorageQuests = fromStorageQuests,
		MAX_EVENT_ID_LENGTH = MAX_EVENT_ID_LENGTH,
		MAX_EVENTS = MAX_EVENTS,
		key = key,
	})
end

return table.freeze({ journal = journal })
