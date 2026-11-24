--!strict

local SocialShape = require("./shape")

export type Pending = { fellowshipId: string, materialId: string, count: number, startedAtSec: number }
export type Ledger = {
	schemaVersion: number,
	pending: { [string]: Pending },
	unacked: { [string]: string },
}
export type Limits = { maxItemCount: number, maxInventoryEntries: number }

local Vault = require("../bank/vault")

export type Receipt = { receiptId: string, ownerId: number, materialId: string, count: number, issuedAtSec: number? }
type Raw = { [unknown]: unknown }
export type ProfileInput = { inventory: unknown, guildBank: unknown }

export type Config<T> = {
	readProfile: (T) -> ProfileInput,
	writeProfile: (T, Vault.Inventory?, Ledger) -> T,
	maxUnacked: number,
	withdrawRoom: number,
	maxPending: number,
	maxId: number,
	maxCount: number,
	maxTime: number,
	healRetentionSec: number,
}

local System = {}

function System.guildledger<T>(config: Config<T>)
	local function readPending(value: unknown): Pending?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(
				value,
				{ fellowshipId = true, materialId = true, count = true, startedAtSec = true }
			)
		then
			return nil
		end
		local fellowshipId = SocialShape.string(raw.fellowshipId)
		if fellowshipId == nil then
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
		local startedAtSec = SocialShape.number(raw.startedAtSec)
		if startedAtSec == nil then
			return nil
		end
		return { fellowshipId = fellowshipId, materialId = materialId, count = count, startedAtSec = startedAtSec }
	end

	local function readLedger(value: unknown): Ledger?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { schemaVersion = true, pending = true, unacked = true }) then
			return nil
		end
		local schemaVersion = SocialShape.number(raw.schemaVersion)
		if schemaVersion == nil then
			return nil
		end
		local pending = SocialShape.map(raw.pending, SocialShape.string, readPending)
		if pending == nil then
			return nil
		end
		local unacked = SocialShape.map(raw.unacked, SocialShape.string, SocialShape.string)
		if unacked == nil then
			return nil
		end
		return { schemaVersion = schemaVersion, pending = pending, unacked = unacked }
	end

	local SCHEMA_VERSION = 1
	local MAX_UNACKED = config.maxUnacked
	local WITHDRAW_ROOM = config.withdrawRoom
	local MAX_PENDING = config.maxPending
	local MAX_ID = config.maxId
	local MAX_COUNT = config.maxCount
	local MAX_TIME = config.maxTime
	local HEAL_RETENTION_SEC = config.healRetentionSec

	local whole = SocialShape.whole
	local opaque = SocialShape.opaque
	local exact = SocialShape.exact
	local freezeDeep = SocialShape.freezeDeep

	local LEDGER_FIELDS = SocialShape.freezeDeep({ schemaVersion = true, pending = true, unacked = true })
	local PENDING_FIELDS =
		SocialShape.freezeDeep({ fellowshipId = true, materialId = true, count = true, startedAtSec = true })

	local GuildBankLedgerCore = {}

	local function copyLedger(value: unknown): (Ledger?, number, number)
		if not exact(value, LEDGER_FIELDS) then
			return nil, 0, 0
		end
		local raw = readLedger(value)
		if raw == nil then
			return nil, 0, 0
		end
		if raw.schemaVersion ~= SCHEMA_VERSION or type(raw.pending) ~= "table" or type(raw.unacked) ~= "table" then
			return nil, 0, 0
		end
		local pending: { [string]: Pending } = {}
		local pendingTotal = 0
		local pendingCount = 0
		for opId, entry in raw.pending do
			if
				not opaque(opId, MAX_ID)
				or not exact(entry, PENDING_FIELDS)
				or not opaque(entry.fellowshipId, MAX_ID)
				or not opaque(entry.materialId, MAX_ID)
				or not whole(entry.count, 1, MAX_COUNT)
				or not whole(entry.startedAtSec, 0, MAX_TIME)
			then
				return nil, 0, 0
			end
			pendingCount += if pending[opId] == nil then 1 else 0
			pending[opId] = table.clone(entry)
			pendingTotal += 1
		end
		local unacked: { [string]: string } = {}
		local unackedTotal = 0
		local unackedCount = 0
		for receiptId, fellowshipId in raw.unacked do
			if not opaque(receiptId, MAX_ID) or not opaque(fellowshipId, MAX_ID) then
				return nil, 0, 0
			end
			unackedCount += if unacked[receiptId] == nil then 1 else 0
			unacked[receiptId] = fellowshipId
			unackedTotal += 1
		end
		if pendingTotal > MAX_PENDING or unackedTotal > MAX_UNACKED then
			return nil, 0, 0
		end
		return { schemaVersion = SCHEMA_VERSION, pending = pending, unacked = unacked }, pendingCount, unackedCount
	end

	function GuildBankLedgerCore.emptyLedger(): Ledger
		return freezeDeep({ schemaVersion = SCHEMA_VERSION, pending = {}, unacked = {} })
	end

	function GuildBankLedgerCore.projectLedger(value: unknown): Ledger?
		local ledger = copyLedger(value)
		return if ledger == nil then nil else freezeDeep(ledger)
	end

	local function withGoods(
		value: unknown,
		materialId: string,
		delta: number,
		limits: Limits
	): (Vault.Inventory?, string?)
		local inventory = SocialShape.map(value, SocialShape.string, SocialShape.number)
		if inventory == nil then
			return nil, "profile_invalid"
		end
		return Vault.adjust(inventory, materialId, delta, limits.maxItemCount, limits.maxInventoryEntries)
	end

	local function updated(profile: T, inventory: Vault.Inventory?, ledger: Ledger): T
		return config.writeProfile(profile, inventory, freezeDeep(ledger))
	end

	function GuildBankLedgerCore.beginDeposit(
		profile: T,
		opId: string,
		fellowshipId: string,
		materialId: string,
		count: number,
		nowSec: number,
		limits: Limits
	): (T?, string?)
		local source = config.readProfile(profile)
		local ledger, pendingCount = copyLedger(source.guildBank)
		if
			ledger == nil
			or not opaque(opId, MAX_ID)
			or not opaque(fellowshipId, MAX_ID)
			or not opaque(materialId, MAX_ID)
			or not whole(count, 1, MAX_COUNT)
			or not whole(nowSec, 0, MAX_TIME)
		then
			return nil, "request_invalid"
		end
		if ledger.pending[opId] ~= nil then
			return nil, "operation_conflict"
		end
		if pendingCount >= MAX_PENDING then
			return nil, "pending_full"
		end
		local inventory, reason = withGoods(source.inventory, materialId, -count, limits)
		if inventory == nil then
			return nil, reason
		end
		ledger.pending[opId] =
			{ fellowshipId = fellowshipId, materialId = materialId, count = count, startedAtSec = nowSec }
		return updated(profile, inventory, ledger), nil
	end

	function GuildBankLedgerCore.settle(profile: T, opId: string): (T?, string?)
		local ledger = copyLedger((config.readProfile(profile)).guildBank)
		if ledger == nil then
			return nil, "ledger_invalid"
		end
		if ledger.pending[opId] == nil then
			return profile, nil
		end
		ledger.pending[opId] = nil
		return updated(profile, nil, ledger), nil
	end

	function GuildBankLedgerCore.refund(profile: T, opId: string, limits: Limits): (T?, string?)
		local source = config.readProfile(profile)
		local ledger = copyLedger(source.guildBank)
		if ledger == nil then
			return nil, "ledger_invalid"
		end
		local pending = ledger.pending[opId]
		if pending == nil then
			return profile, nil
		end
		local inventory, reason = withGoods(source.inventory, pending.materialId, pending.count, limits)
		if inventory == nil then
			return nil, reason
		end
		ledger.pending[opId] = nil
		return updated(profile, inventory, ledger), nil
	end

	function GuildBankLedgerCore.claim(
		profile: T,
		receipt: unknown,
		ownerId: number,
		fellowshipId: string,
		limits: Limits
	): (T?, string?)
		local source = config.readProfile(profile)
		local ledger, _, unackedCount = copyLedger(source.guildBank)
		if ledger == nil then
			return nil, "ledger_invalid"
		end
		local row = SocialShape.raw(receipt)
		if row == nil then
			return nil, "receipt_invalid"
		end
		if
			type(receipt) ~= "table"
			or row.ownerId ~= ownerId
			or not opaque(row.receiptId, MAX_ID)
			or not opaque(row.materialId, MAX_ID)
			or not whole(row.count, 1, MAX_COUNT)
			or not opaque(fellowshipId, MAX_ID)
		then
			return nil, "receipt_invalid"
		end
		local receiptId, materialId, count =
			assert(SocialShape.string(row.receiptId)),
			assert(SocialShape.string(row.materialId)),
			assert(SocialShape.number(row.count))
		if ledger.unacked[receiptId] ~= nil then
			return profile, nil
		end
		if unackedCount >= MAX_UNACKED then
			return nil, "receipts_unacked"
		end
		local inventory, reason = withGoods(source.inventory, materialId, count, limits)
		if inventory == nil then
			return nil, reason
		end
		ledger.unacked[receiptId] = fellowshipId
		return updated(profile, inventory, ledger), nil
	end

	function GuildBankLedgerCore.acked(profile: T, receiptIds: { string }): (T?, string?)
		local ledger = copyLedger((config.readProfile(profile)).guildBank)
		if ledger == nil then
			return nil, "ledger_invalid"
		end
		local changed = false
		for _, receiptId in receiptIds do
			if ledger.unacked[receiptId] ~= nil then
				ledger.unacked[receiptId] = nil
				changed = true
			end
		end
		return if changed then updated(profile, nil, ledger) else profile, nil
	end

	function GuildBankLedgerCore.claimed(profile: T, receiptId: string): boolean
		local ledger = copyLedger(config.readProfile(profile).guildBank)
		return ledger ~= nil and ledger.unacked[receiptId] ~= nil
	end

	function GuildBankLedgerCore.canWithdraw(profile: T): boolean
		local ledger, _, unackedCount = copyLedger(config.readProfile(profile).guildBank)
		return ledger ~= nil and unackedCount < WITHDRAW_ROOM
	end

	GuildBankLedgerCore.SCHEMA_VERSION = SCHEMA_VERSION
	GuildBankLedgerCore.MAX_UNACKED = MAX_UNACKED
	GuildBankLedgerCore.WITHDRAW_ROOM = WITHDRAW_ROOM
	GuildBankLedgerCore.MAX_PENDING = MAX_PENDING
	GuildBankLedgerCore.HEAL_RETENTION_SEC = HEAL_RETENTION_SEC

	return SocialShape.freezeDeep(GuildBankLedgerCore)
end

return System
