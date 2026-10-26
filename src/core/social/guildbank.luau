--!strict

local SocialShape = require("./shape")
local Vault = require("../bank/vault")

export type Receipt = { receiptId: string, ownerId: number, materialId: string, count: number, issuedAtSec: number }
export type Operation = { fingerprint: string, atSec: number, actorId: number, keepUntilSec: number }
export type Entry = { atSec: number, actorId: number, kind: string, materialId: string, count: number }
export type Withdrawal = { actorId: number, atSec: number, count: number }
export type Command = {
	kind: string,
	opId: string,
	actorId: number,
	role: string,
	materialId: string,
	count: number,
	receiptIds: { string },
	memberIds: { number },
}
export type State = {
	schemaVersion: number,
	fellowshipId: string,
	stock: { [string]: number },
	receipts: { Receipt },
	withdrawals: { Withdrawal },
	log: { Entry },
	operations: { [string]: Operation },
	operationOrder: { string },
	lastClockSec: number,
}
export type Result = {
	ok: boolean,
	state: State?,
	replayed: boolean,
	reason: string?,
	receipts: { Receipt }?,
	fence: string?,
}

export type Config = {
	maxKinds: number,
	maxStack: number,
	maxReceipts: number,
	maxReceiptsPerOwner: number,
	maxLog: number,
	maxWithdrawals: number,
	daySec: number,
	memberDailyWithdrawal: number,
	healRetentionSec: number,
	receiptTtlSec: number,
	maxOperations: number,
	maxOperationsPerActor: number,
	maxId: number,
	maxTime: number,
	maxMembers: number,
	roles: { [string]: boolean },
	privilegedRoles: { [string]: boolean },
}

local System = {}

function System.guildbank(config: Config)
	local function readReceipt(value: unknown): Receipt?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(
				value,
				{ receiptId = true, ownerId = true, materialId = true, count = true, issuedAtSec = true }
			)
		then
			return nil
		end
		local receiptId = SocialShape.string(raw.receiptId)
		if receiptId == nil then
			return nil
		end
		local ownerId = SocialShape.number(raw.ownerId)
		if ownerId == nil then
			return nil
		end
		local materialId = SocialShape.string(raw.materialId)
		if materialId == nil then
			return nil
		end
		local count = SocialShape.number(raw.count)
		if count == nil then
			return nil
		end
		local issuedAtSec = SocialShape.number(raw.issuedAtSec)
		if issuedAtSec == nil then
			return nil
		end
		return {
			receiptId = receiptId,
			ownerId = ownerId,
			materialId = materialId,
			count = count,
			issuedAtSec = issuedAtSec,
		}
	end

	local function readWithdrawal(value: unknown): Withdrawal?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { actorId = true, atSec = true, count = true }) then
			return nil
		end
		local actorId = SocialShape.number(raw.actorId)
		if actorId == nil then
			return nil
		end
		local atSec = SocialShape.number(raw.atSec)
		if atSec == nil then
			return nil
		end
		local count = SocialShape.number(raw.count)
		if count == nil then
			return nil
		end
		return { actorId = actorId, atSec = atSec, count = count }
	end

	local function readEntry(value: unknown): Entry?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(
				value,
				{ atSec = true, actorId = true, kind = true, materialId = true, count = true }
			)
		then
			return nil
		end
		local atSec = SocialShape.number(raw.atSec)
		if atSec == nil then
			return nil
		end
		local actorId = SocialShape.number(raw.actorId)
		if actorId == nil then
			return nil
		end
		local kind = SocialShape.string(raw.kind)
		if kind == nil then
			return nil
		end
		local materialId = SocialShape.string(raw.materialId)
		if materialId == nil then
			return nil
		end
		local count = SocialShape.number(raw.count)
		if count == nil then
			return nil
		end
		return { atSec = atSec, actorId = actorId, kind = kind, materialId = materialId, count = count }
	end

	local function readOperation(value: unknown): Operation?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, { fingerprint = true, atSec = true, actorId = true, keepUntilSec = true })
		then
			return nil
		end
		local fingerprint = SocialShape.string(raw.fingerprint)
		if fingerprint == nil then
			return nil
		end
		local atSec = SocialShape.number(raw.atSec)
		if atSec == nil then
			return nil
		end
		local actorId = SocialShape.number(raw.actorId)
		if actorId == nil then
			return nil
		end
		local keepUntilSec = SocialShape.number(raw.keepUntilSec)
		if keepUntilSec == nil then
			return nil
		end
		return { fingerprint = fingerprint, atSec = atSec, actorId = actorId, keepUntilSec = keepUntilSec }
	end

	local function readState(value: unknown): State?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				schemaVersion = true,
				fellowshipId = true,
				stock = true,
				receipts = true,
				withdrawals = true,
				log = true,
				operations = true,
				operationOrder = true,
				lastClockSec = true,
			})
		then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local fellowshipId = SocialShape.string(raw.fellowshipId)
		if fellowshipId == nil then
			return nil
		end
		local stock = SocialShape.map(raw.stock, SocialShape.string, SocialShape.number)
		if stock == nil then
			return nil
		end
		local receipts = SocialShape.array(raw.receipts, readReceipt)
		if receipts == nil then
			return nil
		end
		local withdrawals = SocialShape.array(raw.withdrawals, readWithdrawal)
		if withdrawals == nil then
			return nil
		end
		local log = SocialShape.array(raw.log, readEntry)
		if log == nil then
			return nil
		end
		local operations = SocialShape.map(raw.operations, SocialShape.string, readOperation)
		if operations == nil then
			return nil
		end
		local operationOrder = SocialShape.array(raw.operationOrder, SocialShape.string)
		if operationOrder == nil then
			return nil
		end
		local lastClockSec = SocialShape.number(raw.lastClockSec)
		if lastClockSec == nil then
			return nil
		end
		return {
			schemaVersion = schemaVersion,
			fellowshipId = fellowshipId,
			stock = stock,
			receipts = receipts,
			withdrawals = withdrawals,
			log = log,
			operations = operations,
			operationOrder = operationOrder,
			lastClockSec = lastClockSec,
		}
	end

	local SCHEMA_VERSION = 1
	local MAX_KINDS = config.maxKinds
	local MAX_STACK = config.maxStack
	local MAX_RECEIPTS = config.maxReceipts
	local MAX_RECEIPTS_PER_OWNER = config.maxReceiptsPerOwner
	local MAX_LOG = config.maxLog
	local MAX_WITHDRAWALS = config.maxWithdrawals
	local DAY_SEC = config.daySec
	local MEMBER_DAILY_WITHDRAWAL = config.memberDailyWithdrawal
	local HEAL_RETENTION_SEC = config.healRetentionSec
	local RECEIPT_TTL_SEC = config.receiptTtlSec
	local MAX_OPERATIONS = config.maxOperations
	local MAX_OPERATIONS_PER_ACTOR = config.maxOperationsPerActor
	local MAX_ID = config.maxId
	local MAX_TIME = config.maxTime
	local VOID_MARK = "voidvoidvoidvoid"
	local ROLES = config.roles

	local whole = SocialShape.whole
	local opaque = SocialShape.opaque
	local exact = SocialShape.exact
	local dense = SocialShape.dense
	local freezeDeep = SocialShape.freezeDeep

	local STATE_FIELDS = SocialShape.freezeDeep({
		schemaVersion = true,
		fellowshipId = true,
		stock = true,
		receipts = true,
		withdrawals = true,
		log = true,
		operations = true,
		operationOrder = true,
		lastClockSec = true,
	})
	local RECEIPT_FIELDS = SocialShape.freezeDeep({
		receiptId = true,
		ownerId = true,
		materialId = true,
		count = true,
		issuedAtSec = true,
	})
	local OPERATION_FIELDS =
		SocialShape.freezeDeep({ fingerprint = true, atSec = true, actorId = true, keepUntilSec = true })
	local WITHDRAWAL_FIELDS = SocialShape.freezeDeep({ actorId = true, atSec = true, count = true })
	local ENTRY_FIELDS =
		SocialShape.freezeDeep({ atSec = true, actorId = true, kind = true, materialId = true, count = true })
	local ENTRY_KINDS = SocialShape.freezeDeep({ deposit = true, withdraw = true, ["return"] = true })
	local MOVE_FIELDS = SocialShape.freezeDeep({
		kind = true,
		opId = true,
		actorId = true,
		role = true,
		materialId = true,
		count = true,
	})
	local COMMAND_FIELDS: { [string]: { [string]: boolean } } = SocialShape.freezeDeep({
		deposit = MOVE_FIELDS,
		withdraw = MOVE_FIELDS,
		ack = SocialShape.freezeDeep({ kind = true, opId = true, actorId = true, receiptIds = true }),
		void = SocialShape.freezeDeep({ kind = true, opId = true }),
		expire = SocialShape.freezeDeep({ kind = true, opId = true, memberIds = true }),
	})

	local GuildBankCore = {}

	local function copyList<T>(value: { T }, maximum: number, fields: { [string]: boolean }, check: (T) -> boolean): { T }?
		if dense(value, maximum) == nil then
			return nil
		end
		local out: { T } = {}
		for _, item in value do
			if not exact(item, fields) or not check(item) then
				return nil
			end
			out[#out + 1] = item
		end
		return out
	end

	local function copyState(value: unknown): State?
		if not exact(value, STATE_FIELDS) then
			return nil
		end
		local raw = readState(value)
		if raw == nil then
			return nil
		end
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or not opaque(raw.fellowshipId, MAX_ID)
			or not whole(raw.lastClockSec, 0, MAX_TIME)
			or type(raw.stock) ~= "table"
			or type(raw.operations) ~= "table"
		then
			return nil
		end
		local stock: { [string]: number } = {}
		local kinds = 0
		for materialId, count in raw.stock do
			if not opaque(materialId, MAX_ID) or not whole(count, 1, MAX_STACK) then
				return nil
			end
			stock[materialId] = count
			kinds += 1
		end
		local receipts = copyList(raw.receipts, MAX_RECEIPTS, RECEIPT_FIELDS, function(item: Receipt): boolean
			return opaque(item.receiptId, MAX_ID)
				and whole(item.ownerId, 1, MAX_TIME)
				and opaque(item.materialId, MAX_ID)
				and whole(item.count, 1, MAX_STACK)
				and whole(item.issuedAtSec, 0, MAX_TIME)
		end)
		local withdrawals = copyList(
			raw.withdrawals,
			MAX_WITHDRAWALS,
			WITHDRAWAL_FIELDS,
			function(item: Withdrawal): boolean
				return whole(item.actorId, 1, MAX_TIME)
					and whole(item.atSec, 0, MAX_TIME)
					and whole(item.count, 1, MAX_STACK)
			end
		)
		local log = copyList(raw.log, MAX_LOG, ENTRY_FIELDS, function(item: Entry): boolean
			return whole(item.atSec, 0, MAX_TIME)
				and whole(item.actorId, 1, MAX_TIME)
				and ENTRY_KINDS[item.kind] == true
				and opaque(item.materialId, MAX_ID)
				and whole(item.count, 1, MAX_STACK)
		end)
		local order = dense(raw.operationOrder, MAX_OPERATIONS)
		if kinds > MAX_KINDS or receipts == nil or withdrawals == nil or log == nil or order == nil then
			return nil
		end
		local operations: { [string]: Operation } = {}
		local operationOrder: { string } = {}
		for _, opId in raw.operationOrder do
			local operation = raw.operations[opId]
			if
				not opaque(opId, MAX_ID)
				or operations[opId] ~= nil
				or not exact(operation, OPERATION_FIELDS)
				or not opaque(operation.fingerprint, 16)
				or not whole(operation.atSec, 0, MAX_TIME)
				or not whole(operation.keepUntilSec, 0, MAX_TIME + HEAL_RETENTION_SEC)
				or not whole(operation.actorId, 0, MAX_TIME)
			then
				return nil
			end
			operations[opId] = table.clone(operation)
			operationOrder[#operationOrder + 1] = opId
		end
		for opId in raw.operations do
			if operations[opId] == nil then
				return nil
			end
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			fellowshipId = raw.fellowshipId,
			stock = stock,
			receipts = receipts,
			withdrawals = withdrawals,
			log = log,
			operations = operations,
			operationOrder = operationOrder,
			lastClockSec = raw.lastClockSec,
		}
	end

	local function outcome(value: Result): Result
		return freezeDeep(value)
	end

	local function refused(reason: string): Result
		return outcome({ ok = false, state = nil, replayed = false, reason = reason, receipts = nil, fence = nil })
	end

	local function hashText(text: string): string
		local first = 2166136261
		local second = 5381
		for index = 1, #text do
			local byte = string.byte(text, index)
			first = bit32.bxor(first, byte)
			first = (first * 16777619) % 4294967296
			second = (second * 33 + byte) % 4294967296
		end
		return string.format("%08x%08x", first, second)
	end

	local function fingerprint(command: SocialShape.Raw): string
		local keys: { string } = {}
		for key in command do
			assert(type(key) == "string")
			keys[#keys + 1] = key
		end
		table.sort(keys)
		local parts: { string } = {}
		for _, key in keys do
			local value = command[key]
			if type(value) == "table" then
				local items = assert(SocialShape.array(value, function(item: unknown): (string | number)?
					return if type(item) == "string" or type(item) == "number" then item else nil
				end))
				table.sort(items)
				value = table.concat(items, ",")
			end
			parts[#parts + 1] = key .. "=" .. tostring(value)
		end
		return hashText(table.concat(parts, "|"))
	end

	local function remember(
		state: State,
		opId: string,
		mark: string,
		nowSec: number,
		actorId: number,
		keepSec: number
	): string?
		local kept: { string } = {}
		for _, keptId in state.operationOrder do
			if state.operations[keptId].keepUntilSec > nowSec then
				kept[#kept + 1] = keptId
			else
				state.operations[keptId] = nil
			end
		end
		state.operationOrder = kept
		if actorId ~= 0 then
			local recent = 0
			for _, operation in state.operations do
				if operation.actorId == actorId and nowSec - operation.atSec < DAY_SEC then
					recent += 1
				end
			end
			if recent >= MAX_OPERATIONS_PER_ACTOR then
				return "actor_saturated"
			end
		end
		if #state.operationOrder >= MAX_OPERATIONS then
			return "bank_saturated"
		end
		state.operations[opId] =
			{ fingerprint = mark, atSec = nowSec, actorId = actorId, keepUntilSec = nowSec + keepSec }
		state.operationOrder[#state.operationOrder + 1] = opId
		return nil
	end

	local function withdrawnToday(state: State, actorId: number, nowSec: number): number
		local total = 0
		for _, withdrawal in state.withdrawals do
			if withdrawal.actorId == actorId and nowSec - withdrawal.atSec < DAY_SEC then
				total += withdrawal.count
			end
		end
		return total
	end

	local function record(state: State, entry: Entry)
		state.log[#state.log + 1] = entry
		if #state.log > MAX_LOG then
			table.remove(state.log, 1)
		end
	end

	function GuildBankCore.emptyState(fellowshipId: unknown): State?
		if not opaque(fellowshipId, MAX_ID) then
			return nil
		end
		return freezeDeep({
			schemaVersion = SCHEMA_VERSION,
			fellowshipId = assert(SocialShape.string(fellowshipId)),
			stock = {},
			receipts = {},
			withdrawals = {},
			log = {},
			operations = {},
			operationOrder = {},
			lastClockSec = 0,
		})
	end

	function GuildBankCore.projectState(value: unknown): State?
		local state = copyState(value)
		return if state == nil then nil else freezeDeep(state)
	end

	function GuildBankCore.knowsOperation(value: unknown, opId: unknown): boolean
		local state = copyState(value)
		return state ~= nil and type(opId) == "string" and state.operations[opId] ~= nil
	end

	function GuildBankCore.receiptsFor(value: unknown, ownerId: unknown): { Receipt }?
		local state = copyState(value)
		if state == nil then
			return nil
		end
		local rows: { Receipt } = {}
		for _, receipt in state.receipts do
			if receipt.ownerId == ownerId then
				rows[#rows + 1] = receipt
			end
		end
		return freezeDeep(rows)
	end

	function GuildBankCore.apply(previous: unknown, commandValue: unknown, nowSecValue: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		local command = SocialShape.raw(commandValue)
		if command == nil or type(command.kind) ~= "string" then
			return refused("command_invalid")
		end
		local kind = command.kind
		local fields = COMMAND_FIELDS[kind]
		local opId = SocialShape.string(command.opId)
		if fields == nil or not exact(commandValue, fields) or opId == nil or not opaque(opId, MAX_ID) then
			return refused("command_invalid")
		end
		if not whole(nowSecValue, 0, MAX_TIME) then
			return refused("clock_invalid")
		end
		local nowSec = assert(SocialShape.number(nowSecValue))
		local mark = fingerprint(command)
		local prior = state.operations[opId]
		if command.kind == "void" then
			if prior ~= nil then
				return outcome({
					ok = true,
					state = state,
					replayed = true,
					reason = nil,
					receipts = {},
					fence = if prior.fingerprint == VOID_MARK then "voided" else "known",
				})
			end
		elseif prior ~= nil then
			if prior.fingerprint == mark then
				return outcome({ ok = true, state = state, replayed = true, reason = nil, receipts = {}, fence = nil })
			end
			return refused(if prior.fingerprint == VOID_MARK then "operation_void" else "operation_conflict")
		end
		if nowSec < state.lastClockSec then
			return refused("clock_regressed")
		end
		local issued: { Receipt } = {}
		local actorId = 0
		if command.kind == "deposit" or command.kind == "withdraw" then
			if
				not whole(command.actorId, 1, MAX_TIME)
				or ROLES[if type(command.role) == "string" then command.role else ""] ~= true
				or not opaque(command.materialId, MAX_ID)
				or not whole(command.count, 1, MAX_STACK)
			then
				return refused("command_invalid")
			end
			local materialId, count =
				assert(SocialShape.string(command.materialId)), assert(SocialShape.number(command.count))
			actorId = assert(SocialShape.number(command.actorId))
			local held = state.stock[materialId] or 0
			if command.kind == "deposit" then
				if held == 0 then
					local kinds = 0
					for _ in state.stock do
						kinds += 1
					end
					if kinds >= MAX_KINDS then
						return refused("bank_full")
					end
				end
				if held + count > MAX_STACK then
					return refused("bank_full")
				end
				state.stock = assert(Vault.adjust(state.stock, materialId, count, MAX_STACK, MAX_KINDS))
			else
				if held < count then
					return refused("stock_insufficient")
				end
				if
					config.privilegedRoles[if type(command.role) == "string" then command.role else ""] ~= true
					and withdrawnToday(state, actorId, nowSec) + count > MEMBER_DAILY_WITHDRAWAL
				then
					return refused("withdrawal_limit")
				end
				if #state.receipts >= MAX_RECEIPTS then
					return refused("receipts_full")
				end
				local owned = 0
				for _, receipt in state.receipts do
					if receipt.ownerId == actorId then
						owned += 1
					end
				end
				if owned >= MAX_RECEIPTS_PER_OWNER then
					return refused("receipts_unclaimed")
				end
				state.stock = assert(Vault.adjust(state.stock, materialId, -count, MAX_STACK, math.huge))
				local kept = {}
				for _, withdrawal in state.withdrawals do
					if nowSec - withdrawal.atSec < DAY_SEC then
						kept[#kept + 1] = withdrawal
					end
				end
				if #kept >= MAX_WITHDRAWALS then
					return refused("bank_saturated")
				end
				kept[#kept + 1] = { actorId = actorId, atSec = nowSec, count = count }
				state.withdrawals = kept
				local receipt = {
					receiptId = opId,
					ownerId = actorId,
					materialId = materialId,
					count = count,
					issuedAtSec = nowSec,
				}
				state.receipts[#state.receipts + 1] = receipt
				issued[1] = receipt
			end
			record(state, {
				atSec = nowSec,
				actorId = actorId,
				kind = command.kind,
				materialId = materialId,
				count = count,
			})
		elseif command.kind == "ack" then
			if not whole(command.actorId, 1, MAX_TIME) or dense(command.receiptIds, MAX_RECEIPTS) == nil then
				return refused("command_invalid")
			end
			local acked: { [string]: boolean } = {}
			for _, value in assert(SocialShape.raw(command.receiptIds)) do
				local receiptId = SocialShape.string(value)
				if receiptId == nil or not opaque(receiptId, MAX_ID) then
					return refused("command_invalid")
				end
				acked[receiptId] = true
			end
			local kept: { Receipt } = {}
			for _, receipt in state.receipts do
				if not (receipt.ownerId == command.actorId and acked[receipt.receiptId]) then
					kept[#kept + 1] = receipt
				end
			end
			state.receipts = kept
			state.lastClockSec = nowSec
			return outcome({ ok = true, state = state, replayed = false, reason = nil, receipts = {}, fence = nil })
		elseif command.kind == "expire" then
			if dense(command.memberIds, config.maxMembers) == nil then
				return refused("command_invalid")
			end
			local members: { [number]: boolean } = {}
			for _, value in assert(SocialShape.raw(command.memberIds)) do
				local memberId = SocialShape.number(value)
				if memberId == nil or not whole(memberId, 1, MAX_TIME) then
					return refused("command_invalid")
				end
				members[memberId] = true
			end
			local kept: { Receipt } = {}
			local returned = 0
			for _, receipt in state.receipts do
				local held = state.stock[receipt.materialId] or 0
				if
					not members[receipt.ownerId]
					and nowSec - receipt.issuedAtSec >= RECEIPT_TTL_SEC
					and held + receipt.count <= MAX_STACK
				then
					state.stock[receipt.materialId] = held + receipt.count
					record(state, {
						atSec = nowSec,
						actorId = receipt.ownerId,
						kind = "return",
						materialId = receipt.materialId,
						count = receipt.count,
					})
					returned += 1
				else
					kept[#kept + 1] = receipt
				end
			end
			if returned == 0 then
				return refused("nothing_expired")
			end
			state.receipts = kept
		end
		local saturated = remember(
			state,
			opId,
			if command.kind == "void" then VOID_MARK else mark,
			nowSec,
			actorId,
			if command.kind == "deposit" or command.kind == "void" then HEAL_RETENTION_SEC else DAY_SEC
		)
		if saturated ~= nil then
			return refused(saturated)
		end
		state.lastClockSec = nowSec
		return outcome({
			ok = true,
			state = state,
			replayed = false,
			reason = nil,
			receipts = issued,
			fence = if command.kind == "void" then "voided" else nil,
		})
	end

	GuildBankCore.SCHEMA_VERSION = SCHEMA_VERSION
	GuildBankCore.MEMBER_DAILY_WITHDRAWAL = MEMBER_DAILY_WITHDRAWAL
	GuildBankCore.MAX_KINDS = MAX_KINDS
	GuildBankCore.MAX_STACK = MAX_STACK
	GuildBankCore.MAX_RECEIPTS_PER_OWNER = MAX_RECEIPTS_PER_OWNER
	GuildBankCore.HEAL_RETENTION_SEC = HEAL_RETENTION_SEC
	GuildBankCore.RECEIPT_TTL_SEC = RECEIPT_TTL_SEC
	GuildBankCore.DAY_SEC = DAY_SEC

	return SocialShape.freezeDeep(GuildBankCore)
end

return System
