--!strict

local Value = require("../value")

export type CollectionSet = { [string]: boolean }
export type Outcome = "committed" | "replayed" | "rejected"

export type Result<T> = {
	state: T,
	outcome: Outcome,
	reason: string?,
}

export type Config<T> = {
	ledgerPrefix: string,
	orderPrefix: string,
	maxTransactionId: number,
	maxRecords: number,
	copy: (T) -> T,
	collections: (T) -> CollectionSet?,
	withCollections: (T, CollectionSet) -> T,
	pinned: (T, string) -> boolean,
}
local System = {}
function System.transactions<T>(config: Config<T>)
	local LEDGER_PREFIX = config.ledgerPrefix
	local ORDER_PREFIX = config.orderPrefix
	local MAX_TRANSACTION_ID = config.maxTransactionId
	local MAX_RECORDS = config.maxRecords
	local Reason = {
		malformedTransactionId = "malformed_transaction_id",
		profileNotLedgered = "profile_not_ledgered",
		effectRejected = "effect_rejected",
		ledgerDropped = "ledger_dropped",
		ledgerFull = "ledger_full",
	}

	local function ledgerKey(transactionId: unknown): string?
		if type(transactionId) ~= "string" then
			return nil
		end
		if #transactionId == 0 or #transactionId > MAX_TRANSACTION_ID then
			return nil
		end
		if string.match(transactionId, "^[%w%.%-_:]+$") == nil then
			return nil
		end
		return LEDGER_PREFIX .. transactionId
	end

	local function isRecorded(collections: unknown, transactionId: unknown): boolean
		local key = ledgerKey(transactionId)
		if key == nil or type(collections) ~= "table" then
			return false
		end
		return assert(Value.raw(collections))[key] == true
	end

	local function recordedKeys(collections: CollectionSet): { string }
		local keys: { string } = {}
		for id, held in collections do
			if
				held == true
				and type(id) == "string"
				and string.sub(id, 1, #LEDGER_PREFIX) == LEDGER_PREFIX
				and string.sub(id, 1, #ORDER_PREFIX) ~= ORDER_PREFIX
			then
				keys[#keys + 1] = id
			end
		end
		return keys
	end

	local function orderedKeys(collections: CollectionSet, carried: { string }): ({ string }, { string })
		local markers = {}
		for key, held in collections do
			if type(key) == "string" and string.sub(key, 1, #ORDER_PREFIX) == ORDER_PREFIX and held == true then
				markers[#markers + 1] = key
			end
		end
		table.sort(markers)
		local ordered = {}
		local seen = {}
		for _, marker in markers do
			for key in string.gmatch(string.sub(marker, #ORDER_PREFIX + 1), "[^|]+") do
				if collections[key] == true and string.sub(key, 1, #ORDER_PREFIX) ~= ORDER_PREFIX and not seen[key] then
					seen[key] = true
					ordered[#ordered + 1] = key
				end
			end
		end
		local missing = {}
		for _, key in carried do
			if not seen[key] then
				missing[#missing + 1] = key
			end
		end
		table.sort(missing)
		for _, key in missing do
			ordered[#ordered + 1] = key
		end
		return ordered, markers
	end

	local function commit(profile: T, transactionId: unknown, effect: (T) -> (T?, string?)): Result<T>
		local key = ledgerKey(transactionId)
		if key == nil then
			return { state = profile, outcome = "rejected", reason = Reason.malformedTransactionId }
		end
		local source = profile
		local collections = config.collections(source)
		if collections == nil or type(effect) ~= "function" then
			return { state = profile, outcome = "rejected", reason = Reason.profileNotLedgered }
		end
		local carried = recordedKeys(assert(collections))
		local order, oldMarkers = orderedKeys(assert(collections), carried)
		if collections[key] == true then
			local currentMarker = ORDER_PREFIX .. table.concat(order, "|")
			if #oldMarkers == 1 and oldMarkers[1] == currentMarker then
				return { state = profile, outcome = "replayed", reason = nil }
			end
			local repairedCollections = table.clone(assert(collections))
			for _, marker in oldMarkers do
				repairedCollections[marker] = nil
			end
			repairedCollections[currentMarker] = true
			return { state = config.withCollections(source, repairedCollections), outcome = "replayed", reason = nil }
		end
		local produced, rejection = effect(config.copy(profile))
		if produced == nil then
			return { state = profile, outcome = "rejected", reason = rejection or Reason.effectRejected }
		end
		local applied = produced
		local appliedCollections = config.collections(applied)
		if appliedCollections == nil then
			return { state = profile, outcome = "rejected", reason = Reason.ledgerDropped }
		end
		for _, held in carried do
			if assert(appliedCollections)[held] ~= true then
				return { state = profile, outcome = "rejected", reason = Reason.ledgerDropped }
			end
		end
		if #recordedKeys(assert(appliedCollections)) ~= #carried then
			return { state = profile, outcome = "rejected", reason = Reason.ledgerDropped }
		end

		local markedCollections = table.clone(assert(appliedCollections))
		markedCollections[key] = true
		local marked = config.withCollections(applied, markedCollections)
		order[#order + 1] = key
		while #order > MAX_RECORDS do
			local removable: number? = nil
			for index, candidate in order do
				if not config.pinned(marked, candidate) then
					removable = index
					break
				end
			end
			if removable == nil then
				return { state = profile, outcome = "rejected", reason = Reason.ledgerFull }
			end
			markedCollections[assert(table.remove(order, removable))] = nil
		end
		for _, marker in oldMarkers do
			markedCollections[marker] = nil
		end
		markedCollections[ORDER_PREFIX .. table.concat(order, "|")] = true
		return { state = config.withCollections(applied, markedCollections), outcome = "committed", reason = nil }
	end

	return {
		LEDGER_PREFIX = LEDGER_PREFIX,
		MAX_TRANSACTION_ID = MAX_TRANSACTION_ID,
		MAX_RECORDS = MAX_RECORDS,
		Reason = Reason,
		ledgerKey = ledgerKey,
		isRecorded = isRecorded,
		recordedKeys = recordedKeys,
		commit = commit,
	}
end
return System
