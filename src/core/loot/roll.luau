--!strict
local Value = require("../value")

export type Roll = {
	itemId: string,
	weight: number,
	minCount: number,
	maxCount: number,
}

export type Table = {
	id: string,
	zoneId: string?,
	mobIds: { string },
	rolls: { Roll },
	picks: number?,
}

export type Drop = {
	tableId: string,
	itemId: string,
	count: number,
}

export type Config = { receiptPrefix: string }
local System = {}
function System.roll(config: Config)
	local HASH_PRIME_A = 2654435761
	local HASH_PRIME_B = 40503
	local HASH_MODULUS = 2147483647
	local HASH_SPLIT = 65536

	local function multiplyModulo(left: number, right: number): number
		local high = math.floor(right / HASH_SPLIT)
		local low = right % HASH_SPLIT
		return ((left * high) % HASH_MODULUS * HASH_SPLIT + left * low) % HASH_MODULUS
	end

	local function wholeAtLeast(value: unknown, minimum: number): number?
		if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
			return nil
		end
		local floored = math.floor(value)
		if floored ~= value or floored < minimum then
			return nil
		end
		return floored
	end

	local function validRoll(raw: unknown): Roll?
		local value = Value.raw(raw)
		if value == nil or type(value.itemId) ~= "string" or value.itemId == "" then
			return nil
		end
		local weight = wholeAtLeast(value.weight, 1)
		local minCount = wholeAtLeast(value.minCount, 1)
		local maxCount = wholeAtLeast(value.maxCount, 1)
		if weight == nil or minCount == nil or maxCount == nil or maxCount < minCount then
			return nil
		end
		return { itemId = value.itemId, weight = weight, minCount = minCount, maxCount = maxCount }
	end

	local function mixString(accumulator: number, text: string): number
		local hash = accumulator
		for index = 1, #text do
			hash = (hash * 31 + string.byte(text, index)) % HASH_MODULUS
		end
		return hash
	end

	local function streamFor(tableId: string, mobId: string, actorId: string, tickIndex: number): number
		local hash = multiplyModulo(tickIndex % HASH_MODULUS, HASH_PRIME_B)
		hash = mixString(hash, tableId)
		hash = mixString(hash, mobId)
		hash = mixString(hash, actorId)
		return multiplyModulo(hash, HASH_PRIME_A % HASH_MODULUS)
	end

	local function namesMob(value: unknown, mobId: unknown): boolean
		local raw = Value.raw(value)
		if raw == nil or type(raw.id) ~= "string" or type(raw.mobIds) ~= "table" then
			return false
		end
		for _, candidate in raw.mobIds do
			if candidate == mobId then
				return true
			end
		end
		return false
	end
	local function tableForMob<T>(tables: { T }?, mobId: unknown): T?
		if tables == nil or type(mobId) ~= "string" or mobId == "" then
			return nil
		end
		for _, entry in tables do
			if namesMob(entry, mobId) then
				return entry
			end
		end
		return nil
	end
	local function projectedTableForMob(tablesValue: unknown, mobId: unknown): Table?
		local tables = Value.raw(tablesValue)
		if tables == nil or type(mobId) ~= "string" or mobId == "" then
			return nil
		end
		for _, entry in tables do
			if not namesMob(entry, mobId) then
				continue
			end
			local raw = assert(Value.raw(entry))
			local id = raw.id
			assert(type(id) == "string")
			local ids: { string } = {}
			for _, value in assert(Value.raw(raw.mobIds)) do
				if type(value) == "string" then
					table.insert(ids, value)
				end
			end
			local rolls: { Roll } = {}
			local entries = Value.raw(raw.rolls)
			if entries ~= nil then
				for _, value in entries do
					local roll = validRoll(value)
					if roll ~= nil then
						table.insert(rolls, roll)
					end
				end
			end
			return {
				id = id,
				zoneId = if type(raw.zoneId) == "string" then raw.zoneId else nil,
				mobIds = ids,
				rolls = rolls,
				picks = if type(raw.picks) == "number" then raw.picks else nil,
			}
		end
		return nil
	end

	local function rollMany(
		lootTable: Table,
		mobId: string,
		actorId: string,
		tickIndex: number,
		picks: number
	): { Drop }
		local drops: { Drop } = {}
		if type(lootTable.rolls) ~= "table" then
			return drops
		end
		local pool: { Roll } = {}
		for _, raw in lootTable.rolls do
			local roll = validRoll(raw)
			if roll ~= nil then
				table.insert(pool, roll)
			end
		end
		for pick = 1, picks do
			local total = 0
			for _, roll in pool do
				total += roll.weight
			end
			if total <= 0 then
				break
			end
			local seed = if pick == 1 then lootTable.id else ("%s#%d"):format(lootTable.id, pick)
			local stream = streamFor(seed, mobId, actorId, tickIndex)
			local target = stream % total
			local running = 0
			for index, roll in pool do
				running += roll.weight
				if target < running then
					local span = roll.maxCount - roll.minCount + 1
					local count = roll.minCount + (math.floor(stream / total) % span)
					table.insert(drops, { tableId = lootTable.id, itemId = roll.itemId, count = count })
					table.remove(pool, index)
					break
				end
			end
		end
		return drops
	end

	local function rollFor(lootTable: Table?, mobId: string, actorId: string, tickIndex: number): Drop?
		local drops = if lootTable == nil then {} else rollMany(lootTable, mobId, actorId, tickIndex, 1)
		return drops[1]
	end

	local function dropFor(tables: unknown, mobId: unknown, actorId: unknown, tickIndex: unknown): Drop?
		if type(actorId) ~= "string" or actorId == "" then
			return nil
		end
		local resolvedTick = wholeAtLeast(tickIndex, 0)
		if resolvedTick == nil then
			return nil
		end
		local lootTable = projectedTableForMob(tables, mobId)
		if lootTable == nil then
			return nil
		end
		return rollFor(lootTable, assert(Value.opaque(mobId, math.huge)), actorId, resolvedTick)
	end

	local function picksOf(lootTable: Table): number
		return wholeAtLeast(lootTable.picks, 1) or 1
	end

	local function dropsFor(tables: unknown, mobId: unknown, actorId: unknown, tickIndex: unknown): { Drop }
		if type(actorId) ~= "string" or actorId == "" then
			return {}
		end
		local resolvedTick = wholeAtLeast(tickIndex, 0)
		local lootTable = projectedTableForMob(tables, mobId)
		if resolvedTick == nil or lootTable == nil then
			return {}
		end
		return rollMany(lootTable, assert(Value.opaque(mobId, math.huge)), actorId, resolvedTick, picksOf(lootTable))
	end

	local function receiptFor(
		drop: Drop,
		mobId: string,
		actorId: string,
		tickIndex: number,
		epoch: number?,
		pick: number?
	): string
		local origin = if epoch ~= nil then ("epoch:%d:"):format(epoch) else ""
		local base = ("%s%s%s:%s:%s:%d"):format(config.receiptPrefix, origin, drop.tableId, mobId, actorId, tickIndex)
		if pick ~= nil and pick > 1 then
			return ("%s:p%d"):format(base, pick)
		end
		return base
	end

	return table.freeze({
		validRoll = validRoll,
		tableForMob = tableForMob,
		dropFor = dropFor,
		dropsFor = dropsFor,
		receiptFor = receiptFor,
	})
end
return System
