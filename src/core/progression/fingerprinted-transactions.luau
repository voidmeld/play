--!strict

local Value = require("../../kernel/value")

export type Bounds = { maxDepth: number, maxEntries: number, maxBytes: number }
export type Receipts = { [string]: string }
export type Result<T> = { state: T, outcome: "committed" | "replayed" | "rejected", reason: string? }
export type ReceiptCodec<R> = { fingerprint: (R) -> string?, create: (string) -> R }
export type ReceiptConfig<T, R> = {
	maxTransactionId: number?,
	maxRecords: number?,
	bounds: Bounds?,
	fingerprint: ((unknown) -> (string?, string?))?,
	copy: (T) -> T,
	receipts: (T) -> { [string]: R },
	withReceipts: (T, { [string]: R }) -> T,
}
export type Config<T> = ReceiptConfig<T, string>

local function fingerprint(payload: unknown, bounds: Bounds): (string?, string?)
	assert(Value.whole(bounds.maxDepth, 0, 128) ~= nil, "invalid depth bound")
	assert(Value.whole(bounds.maxEntries, 1, 1000000) ~= nil, "invalid entry bound")
	assert(Value.whole(bounds.maxBytes, 1, 10000000) ~= nil, "invalid byte bound")
	local parts: { string } = {}
	local bytes, entries = 0, 0
	local active: { [unknown]: boolean } = {}
	local function emit(part: string): boolean
		bytes += #part
		if bytes > bounds.maxBytes then
			return false
		end
		table.insert(parts, part)
		return true
	end
	local function encode(value: unknown, depth: number): boolean
		if value == nil then
			return emit("z")
		elseif type(value) == "boolean" then
			return emit(if value then "t" else "f")
		elseif type(value) == "string" then
			return #value <= bounds.maxBytes - bytes and emit("s" .. #value .. ":") and emit(value)
		elseif type(value) == "number" then
			return Value.finite(value)
				and emit("n" .. (if value == 0 then "0" else string.format("%.17g", value)) .. ";")
		end
		if type(value) ~= "table" or getmetatable(value) ~= nil or active[value] or depth >= bounds.maxDepth then
			return false
		end
		local keys: { string | number } = {}
		local raw: Value.Raw = {}
		for key, child in value do
			entries += 1
			if entries > bounds.maxEntries or (type(key) ~= "string" and type(key) ~= "number") then
				return false
			end
			if type(key) == "number" and not Value.finite(key) then
				return false
			end
			if type(key) == "string" and #key > bounds.maxBytes then
				return false
			end
			table.insert(keys, key)
			raw[key] = child
		end
		table.sort(keys, function(a, b)
			if type(a) == "number" and type(b) == "number" then
				return a < b
			elseif type(a) == "string" and type(b) == "string" then
				return a < b
			end
			return type(a) == "number"
		end)
		active[value] = true
		if not emit("{") then
			return false
		end
		for _, key in keys do
			if not encode(key, depth + 1) or not encode(raw[key], depth + 1) then
				return false
			end
		end
		active[value] = nil
		return emit("}")
	end
	if not encode(payload, 0) then
		return nil, "payload_invalid"
	end
	return table.concat(parts), nil
end

local function createWithReceipts<T, R>(config: ReceiptConfig<T, R>, codec: ReceiptCodec<R>)
	assert(
		config.maxTransactionId == nil or Value.whole(config.maxTransactionId, 1, 1000000) ~= nil,
		"invalid id bound"
	)
	assert(config.maxRecords == nil or Value.whole(config.maxRecords, 1, 1000000) ~= nil, "invalid receipt bound")
	local bounds = if config.bounds ~= nil then table.clone(config.bounds) else nil
	assert(config.fingerprint ~= nil or bounds ~= nil, "payload encoder required")
	local function encode(payload: unknown): (string?, string?)
		if config.fingerprint ~= nil then
			local ok, stamp, reason = pcall(config.fingerprint, payload)
			if not ok then
				return nil, "payload_invalid"
			end
			return stamp, reason
		end
		assert(bounds ~= nil)
		return fingerprint(payload, bounds)
	end
	local function commit(profile: T, transactionId: string, payload: unknown, effect: (T) -> (T?, string?)): Result<T>
		local function reject(reason: string): Result<T>
			return { state = profile, outcome = "rejected", reason = reason }
		end
		if #transactionId == 0 or (config.maxTransactionId ~= nil and #transactionId > config.maxTransactionId) then
			return reject("transaction_id_invalid")
		end
		local stamp, problem = encode(payload)
		if stamp == nil or #stamp == 0 then
			return reject(problem or "payload_invalid")
		end
		local receipts = config.receipts(profile)
		local previous = receipts[transactionId]
		if previous ~= nil then
			return if codec.fingerprint(previous) == stamp
				then { state = profile, outcome = "replayed" }
				else reject("transaction_conflict")
		end
		local count = 0
		for _ in receipts do
			count += 1
		end
		if config.maxRecords ~= nil and count >= config.maxRecords then
			return reject("receipts_full")
		end
		local owned = table.clone(receipts)
		local candidate, reason = effect(config.copy(profile))
		if candidate == nil then
			return reject(reason or "effect_rejected")
		end
		owned[transactionId] = codec.create(stamp)
		return { state = config.withReceipts(candidate, owned), outcome = "committed" }
	end
	return table.freeze({ commit = commit })
end

local function create<T>(config: Config<T>)
	return createWithReceipts(config, {
		fingerprint = function(receipt: string): string
			return receipt
		end,
		create = function(stamp: string): string
			return stamp
		end,
	})
end

return table.freeze({ fingerprint = fingerprint, create = create, createWithReceipts = createWithReceipts })
