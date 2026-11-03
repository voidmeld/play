--!strict

local BankTypes = require("../core/social/guildbank")
local LedgerTypes = require("../core/social/guildledger")
local Records = require("./social-records")
local Transfer = require("./profile-transfer")
local Value = require("../kernel/value")

export type Bank = Records.Ledger<string, BankTypes.State, BankTypes.Receipt>
export type BankResult = Records.Settled<BankTypes.State, BankTypes.Receipt>
type BankState = BankTypes.State
type Receipt = BankTypes.Receipt
export type Material = { read id: string, read label: string }
export type MaterialRow = { read materialId: string, read label: string, read held: number, read stock: number }
export type LogRow = { read kind: string, read actorId: number, read materialId: string, read count: number }
export type Projection = {
	read available: boolean,
	read role: "member" | "steward",
	read dailyLimit: number,
	read materials: { MaterialRow },
	read log: { LogRow },
}
export type ProfileAccess<P> = { read read: () -> P?, read update: ((P) -> P) -> (), read save: () -> boolean }
export type Membership = { fellowshipId: string, role: "member" | "steward", memberIds: { number } }
export type Dependencies<P> = {
	bank: Bank,
	materials: { Material },
	profileFor: (number) -> ProfileAccess<P>?,
	membershipFor: (number, boolean) -> (Membership?, string?),
	clock: () -> number,
	newOpId: () -> string,
}
export type Outcome = { ok: boolean, reason: string?, pending: boolean }
export type Handle = {
	read join: (number) -> Outcome,
	read deposit: (number, unknown, unknown) -> Outcome,
	read withdraw: (number, unknown, unknown) -> Outcome,
	read projection: (number) -> Projection | false,
	read refresh: (number) -> Outcome,
	read forget: (number) -> (),
}
export type ProfileLedger<P> = {
	read projectLedger: (unknown) -> LedgerTypes.Ledger?,
	read beginDeposit: (P, string, string, string, number, number, LedgerTypes.Limits) -> (P?, string?),
	read settle: (P, string) -> (P?, string?),
	read refund: (P, string, LedgerTypes.Limits) -> (P?, string?),
	read claim: (P, unknown, number, string, LedgerTypes.Limits) -> (P?, string?),
	read acked: (P, { string }) -> (P?, string?),
	read claimed: (P, string) -> boolean,
	read canWithdraw: (P) -> boolean,
}
export type Config<P> = {
	read ledger: ProfileLedger<P>,
	read copy: (P) -> P,
	read profileLedger: (P) -> unknown,
	read inventory: (P) -> { [string]: number },
	read capacity: (P?) -> number,
	read receiptsFor: (unknown, unknown) -> { BankTypes.Receipt }?,
	read maxItemCount: number,
	read maxMove: number,
	read joinRetrySec: number,
	read healRetentionSec: number,
	read receiptTtlSec: number,
	read memberDailyWithdrawal: number,
	read logRows: number,
}
export type API<P> = { read mount: (Dependencies<P>) -> (Handle?, string?) }
local function configure<P>(config: Config<P>): API<P>
	config = table.freeze(table.clone(config))
	for _, value in { config.maxItemCount, config.maxMove, config.logRows } do
		assert(Value.whole(value, 1, 9007199254740991) ~= nil, "invalid guild-bank bound")
	end
	for _, value in { config.healRetentionSec, config.receiptTtlSec } do
		assert(Value.finite(value) and value > 0, "invalid guild-bank retention")
	end
	assert(Value.finite(config.joinRetrySec) and config.joinRetrySec >= 0, "invalid guild-bank retry")
	assert(Value.whole(config.memberDailyWithdrawal, 0, 9007199254740991) ~= nil, "invalid guild-bank allowance")
	type Profile = P
	local Ledger = config.ledger

	local JOIN_RETRY_SEC = config.joinRetrySec
	local MAX_MOVE = config.maxMove

	local function limits(profile: Profile?): LedgerTypes.Limits
		return {
			maxItemCount = config.maxItemCount,
			maxInventoryEntries = config.capacity(profile),
		}
	end

	local GuildBankService = {}

	local function outcome(ok: boolean, reason: string?, pending: boolean): Outcome
		return { ok = ok, reason = reason, pending = pending }
	end

	local function whole(value: unknown, minimum: number, maximum: number): boolean
		return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
	end

	function GuildBankService.mount(deps: Dependencies<P>): (Handle?, string?)
		if
			type(deps) ~= "table"
			or type(deps.bank) ~= "table"
			or type(deps.materials) ~= "table"
			or type(deps.profileFor) ~= "function"
			or type(deps.membershipFor) ~= "function"
			or type(deps.clock) ~= "function"
			or type(deps.newOpId) ~= "function"
		then
			return nil, "dependencies_invalid"
		end
		local materialById: { [string]: Material } = {}
		for _, material in deps.materials do
			materialById[material.id] = material
		end
		local busy: { [number]: boolean } = {}
		local joined: { [number]: boolean } = {}
		local joinTriedAt: { [number]: number } = {}
		local bankCache: { [string]: BankState } = {}

		local function serially(userId: number, body: () -> Outcome): Outcome
			return Transfer.exclusive(busy, userId, outcome(false, "guild_bank_busy", false), body)
		end

		local function step(access: ProfileAccess<P>, change: (Profile) -> (Profile?, string?)): string?
			local refusal: string? = nil
			local accepted = false
			access.update(function(profile): Profile
				refusal = nil
				accepted = false
				local nextProfile, reason = change(config.copy(profile))
				if nextProfile == nil then
					refusal = reason
					return profile
				end
				accepted = true
				return nextProfile
			end)
			if not accepted then
				return refusal or "guild_bank_unavailable"
			end
			return if access.save() then nil else "guild_bank_not_durable"
		end

		local function remember(fellowshipId: string, result: BankResult)
			if result.ok and result.state ~= nil then
				bankCache[fellowshipId] = result.state
			end
		end

		local function claimFrom(
			userId: number,
			access: ProfileAccess<P>,
			fellowshipId: string,
			receipts: { Receipt }
		): string?
			local acknowledged: { string } = {}
			for _, receipt in receipts do
				if receipt.ownerId == userId then
					local problem = step(access, function(profile): (Profile?, string?)
						return Ledger.claim(profile, receipt, userId, fellowshipId, limits(profile))
					end)
					if problem == nil then
						acknowledged[#acknowledged + 1] = receipt.receiptId
					elseif problem == "guild_bank_not_durable" then
						return problem
					end
				end
			end
			if #acknowledged == 0 then
				return nil
			end
			local acked = deps.bank.apply(fellowshipId, {
				kind = "ack",
				opId = deps.newOpId(),
				actorId = userId,
				receiptIds = acknowledged,
			})
			remember(fellowshipId, acked)
			if not acked.ok then
				return acked.reason
			end
			return step(access, function(profile): (Profile?, string?)
				return Ledger.acked(profile, acknowledged)
			end)
		end

		local function settleBank(
			userId: number,
			access: ProfileAccess<P>,
			fellowshipId: string,
			current: boolean
		): string?
			local read = deps.bank.read(fellowshipId)
			if not read.ok or read.state == nil then
				return read.reason or "guild_bank_unavailable"
			end
			remember(fellowshipId, read)
			local receipts: { BankTypes.Receipt } = config.receiptsFor(read.state, userId) or {}
			local present: { [string]: boolean } = {}
			for _, receipt in receipts do
				present[receipt.receiptId] = true
			end
			local profile = access.read()
			if profile == nil then
				return "guild_bank_unavailable"
			end
			local ledger = Ledger.projectLedger(config.profileLedger(profile))
			local gone: { string } = {}
			for receiptId, bankId in (if ledger ~= nil then ledger.unacked else {}) do
				if bankId == fellowshipId and not present[receiptId] then
					gone[#gone + 1] = receiptId
				end
			end
			if #gone > 0 then
				local problem = step(access, function(profile): (Profile?, string?)
					return Ledger.acked(profile, gone)
				end)
				if problem ~= nil then
					return problem
				end
			end
			local owed: { Receipt } = {}
			for _, receipt in receipts do
				local latest = access.read()
				if current or (latest ~= nil and Ledger.claimed(latest, receipt.receiptId)) then
					owed[#owed + 1] = receipt
				end
			end
			return claimFrom(userId, access, fellowshipId, owed)
		end

		local function expireStale(membership: Membership)
			local bank = bankCache[membership.fellowshipId]
			if bank == nil then
				return
			end
			local members: { [number]: boolean } = {}
			for _, memberId in membership.memberIds do
				members[memberId] = true
			end
			for _, receipt in bank.receipts do
				if not members[receipt.ownerId] and deps.clock() - receipt.issuedAtSec >= config.receiptTtlSec then
					remember(
						membership.fellowshipId,
						deps.bank.apply(
							membership.fellowshipId,
							{ kind = "expire", opId = deps.newOpId(), memberIds = membership.memberIds }
						)
					)
					return
				end
			end
		end

		local function heal(userId: number, access: ProfileAccess<P>): string?
			local profile = access.read()
			local ledger = if profile ~= nil then Ledger.projectLedger(config.profileLedger(profile)) else nil
			if ledger == nil then
				return "ledger_invalid"
			end
			local problem: string? = nil
			for opId, pending in ledger.pending do
				if deps.clock() - pending.startedAtSec >= config.healRetentionSec then
					continue
				end
				local fenced = deps.bank.apply(pending.fellowshipId, { kind = "void", opId = opId })
				if not fenced.ok or (fenced.fence ~= "known" and fenced.fence ~= "voided") then
					problem = fenced.reason or "fence_unconfirmed"
					continue
				end
				local healProblem = step(access, function(current): (Profile?, string?)
					if fenced.fence == "known" then
						return Ledger.settle(current, opId)
					end
					return Ledger.refund(current, opId, limits(current))
				end)
				if healProblem ~= nil then
					problem = healProblem
				end
			end
			return problem
		end

		local function join(userId: number): Outcome
			if joined[userId] then
				return outcome(true, nil, false)
			end
			local triedAt = joinTriedAt[userId]
			if triedAt ~= nil and deps.clock() - triedAt < JOIN_RETRY_SEC then
				return outcome(false, "guild_bank_settling", true)
			end
			local access = deps.profileFor(userId)
			if access == nil or access.read() == nil then
				return outcome(false, "guild_bank_unavailable", false)
			end
			joinTriedAt[userId] = deps.clock()
			return serially(userId, function(): Outcome
				local problem = heal(userId, access)
				local membership = deps.membershipFor(userId, false)
				local banks: { [string]: boolean } = {}
				local profile = access.read()
				if profile == nil then
					return outcome(false, "guild_bank_unavailable", false)
				end
				local ledger = Ledger.projectLedger(config.profileLedger(profile))
				for _, fellowshipId in (if ledger ~= nil then ledger.unacked else {}) do
					banks[fellowshipId] = true
				end
				if membership ~= nil then
					banks[membership.fellowshipId] = true
				end
				for fellowshipId in banks do
					local current = membership ~= nil and membership.fellowshipId == fellowshipId
					local bankProblem = settleBank(userId, access, fellowshipId, current)
					if bankProblem ~= nil then
						problem = bankProblem
					end
				end
				if membership ~= nil then
					expireStale(membership)
				end
				if type(problem) == "string" then
					return outcome(false, problem, true)
				end
				joined[userId] = true
				joinTriedAt[userId] = nil
				return outcome(true, nil, false)
			end)
		end

		local function context(
			userId: number,
			materialId: unknown,
			count: unknown,
			fresh: boolean
		): (ProfileAccess<P>?, Membership?, string?)
			if type(materialId) ~= "string" or materialById[materialId] == nil then
				return nil, nil, "material_unknown"
			end
			if not whole(count, 1, MAX_MOVE) then
				return nil, nil, "guild_bank_request_invalid"
			end
			local membership, membershipProblem = deps.membershipFor(userId, fresh)
			if membership == nil then
				return nil, nil, if membershipProblem ~= nil then membershipProblem else "fellowship_unknown"
			end
			local access = deps.profileFor(userId)
			if access == nil then
				return nil, nil, "guild_bank_unavailable"
			end
			if not joined[userId] and not join(userId).ok then
				return nil, nil, "guild_bank_settling"
			end
			return access, membership, nil
		end

		local function deposit(userId: number, materialId: unknown, count: unknown): Outcome
			local access, membership, refusal = context(userId, materialId, count, true)
			if access == nil or membership == nil then
				return outcome(false, refusal, false)
			end
			if type(materialId) ~= "string" or type(count) ~= "number" then
				return outcome(false, "guild_bank_request_invalid", false)
			end
			return serially(userId, function(): Outcome
				local opId = deps.newOpId()
				local begun = step(access, function(profile): (Profile?, string?)
					return Ledger.beginDeposit(
						profile,
						opId,
						membership.fellowshipId,
						materialId,
						count,
						deps.clock(),
						limits(profile)
					)
				end)
				if begun ~= nil then
					return outcome(false, begun, begun == "guild_bank_not_durable")
				end
				local applied = deps.bank.apply(membership.fellowshipId, {
					kind = "deposit",
					opId = opId,
					actorId = userId,
					role = membership.role,
					materialId = materialId,
					count = count,
				})
				remember(membership.fellowshipId, applied)
				if applied.ok then
					local settled = step(access, function(profile): (Profile?, string?)
						return Ledger.settle(profile, opId)
					end)
					return outcome(settled == nil, settled, settled ~= nil)
				end
				if applied.ambiguous then
					return outcome(false, applied.reason, true)
				end
				local refunded = step(access, function(profile): (Profile?, string?)
					return Ledger.refund(profile, opId, limits(profile))
				end)
				return outcome(false, if refunded ~= nil then refunded else applied.reason, refunded ~= nil)
			end)
		end

		local function withdraw(userId: number, materialId: unknown, count: unknown): Outcome
			local access, membership, refusal = context(userId, materialId, count, true)
			if access == nil or membership == nil then
				return outcome(false, refusal, false)
			end
			return serially(userId, function(): Outcome
				local profile = access.read()
				if profile == nil then
					return outcome(false, "guild_bank_unavailable", true)
				end
				if not Ledger.canWithdraw(profile) then
					return outcome(false, "receipts_unacked", false)
				end
				local roomy = Ledger.claim(
					profile,
					{ receiptId = "room-check", ownerId = userId, materialId = materialId, count = count },
					userId,
					membership.fellowshipId,
					limits(profile)
				)
				if roomy == nil then
					return outcome(false, "inventory_full", false)
				end
				local applied = deps.bank.apply(membership.fellowshipId, {
					kind = "withdraw",
					opId = deps.newOpId(),
					actorId = userId,
					role = membership.role,
					materialId = materialId,
					count = count,
				})
				remember(membership.fellowshipId, applied)
				if not applied.ok then
					return outcome(false, applied.reason, applied.ambiguous == true)
				end
				local problem = claimFrom(userId, access, membership.fellowshipId, applied.receipts or {})
				return outcome(problem == nil, problem, problem ~= nil)
			end)
		end

		local function projection(userId: number): Projection | false
			local membership = deps.membershipFor(userId, false)
			local access = deps.profileFor(userId)
			local profile = if access ~= nil then access.read() else nil
			if membership == nil or profile == nil then
				return false
			end
			local bank = bankCache[membership.fellowshipId]
			local rows: { MaterialRow } = {}
			for _, material in deps.materials do
				local held = config.inventory(profile)[material.id]
				rows[#rows + 1] = table.freeze({
					materialId = material.id,
					label = material.label,
					held = if type(held) == "number" then held else 0,
					stock = if bank ~= nil then bank.stock[material.id] or 0 else 0,
				})
			end
			local log: { LogRow } = {}
			if bank ~= nil then
				for index = #bank.log, math.max(1, #bank.log - config.logRows + 1), -1 do
					local entry = bank.log[index]
					log[#log + 1] = table.freeze({
						kind = entry.kind,
						actorId = entry.actorId,
						materialId = entry.materialId,
						count = entry.count,
					})
				end
			end
			return table.freeze({
				available = bank ~= nil,
				role = membership.role,
				dailyLimit = config.memberDailyWithdrawal,
				materials = table.freeze(rows),
				log = table.freeze(log),
			})
		end

		local function refresh(userId: number): Outcome
			joined[userId] = nil
			joinTriedAt[userId] = nil
			return join(userId)
		end

		local function forget(userId: number)
			joined[userId] = nil
			joinTriedAt[userId] = nil
		end

		return table.freeze({
			join = join,
			deposit = deposit,
			withdraw = withdraw,
			projection = projection,
			refresh = refresh,
			forget = forget,
		}),
			nil
	end

	GuildBankService.BOUNDARY = table.concat({
		"deposit=the-goods-leave-the-profile-into-a-pending-entry-that-is-saved-before-the-bank-write;the-bank-write-settles-it,a-definitive-refusal-refunds-it,and-an-ambiguous-outcome-stays-pending-for-heal",
		"heal=at-join,each-pending-deposit-writes-a-void-fence-on-its-own-guild's-bank;known-settles,voided-refunds,anything-else-waits;an-entry-older-than-40-days-is-left-for-audit",
		"withdraw=membership-and-role-are-reread-fresh-from-the-guild-record-first,failing-closed;the-profile-must-have-room;the-bank-write-issues-a-receipt-that-is-claimed-into-the-profile,saved,then-acked,and-the-ledger-drops-its-id-only-after-the-ack",
		"join=every-bank-the-ledger-still-owes-an-ack-is-read,even-a-former-guild's;a-claimed-receipt-replays-and-is-acked,an-id-the-bank-no-longer-holds-is-dropped,and-only-the-current-guild's-unclaimed-receipts-are-claimed",
		"expire=a-join-asks-the-current-guild's-bank-to-return-receipts-of-non-members-older-than-30-days;a-member-who-claimed-one-but-never-acked-it-and-stayed-away-30-days-after-leaving-is-the-one-case-that-can-duplicate-a-receipt",
		"deposit-membership=a-deposit-rereads-membership-fresh-from-the-guild-record;only-catalogued-base-materials-move,at-most-100-per-action",
		"serial=one-bank-call-at-a-time-per-player;a-concurrent-call-refuses-as-guild_bank_busy",
	}, ";")

	return table.freeze(GuildBankService)
end

return table.freeze({ configure = configure })
