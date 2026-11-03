--!strict

local Book = require("../core/market/book")
local Records = require("./social-records")
local Value = require("../core/internal/value")
local Wallet = require("../core/market/wallet")

export type BookResult = Records.Settled<Book.State, Book.Receipt>
export type BookService = {
	read read: (string, string) -> BookResult,
	read apply: (string, string, unknown) -> BookResult,
}
export type WalletAccess = {
	read read: () -> Wallet.State?,
	read write: (Wallet.State) -> boolean,
	read room: ((string) -> number)?,
}
export type Dependencies = { book: BookService, wallet: WalletAccess, clock: () -> number, newOpId: () -> string }
export type Outcome = { ok: boolean, reason: string?, opId: string?, pending: boolean }
export type Service = {
	read consign: (string, string, number, number, string?) -> Outcome,
	read buy: (string, string, number, number, string?) -> Outcome,
	read cancel: (string, string, string) -> Outcome,
	read claimAll: (string, string) -> Outcome,
	read heal: () -> Outcome,
}
export type WalletOps = {
	read beginConsign: (unknown, unknown, unknown, unknown, unknown, unknown, unknown?) -> Wallet.Result,
	read beginBuy: (unknown, unknown, unknown, unknown, unknown, unknown, unknown?) -> Wallet.Result,
	read refund: (unknown, unknown) -> Wallet.Result,
	read settleConsign: (unknown, unknown) -> Wallet.Result,
	read claim: (unknown, unknown, unknown) -> Wallet.Result,
	read heal: (unknown, unknown, unknown, unknown) -> Wallet.Result,
}
export type Config = {
	read wallet: WalletOps,
	read receiptsFor: (unknown, unknown) -> { Book.Receipt }?,
	read healRetentionSec: number,
}
export type Host = { read create: (Dependencies?) -> (Service?, string?) }

local function configure(config: Config): Host
	config = table.freeze(table.clone(config))
	assert(Value.finite(config.healRetentionSec) and config.healRetentionSec > 0, "invalid market recovery retention")
	type Receipt = Book.Receipt
	type WalletResult = Wallet.Result
	local MarketWalletCore = config.wallet
	local MarketBookCore = { receiptsFor = config.receiptsFor }

	local MarketSettlement = {}

	local function outcome(ok: boolean, reason: string?, opId: string?, pending: boolean): Outcome
		return { ok = ok, reason = reason, opId = opId, pending = pending }
	end

	function MarketSettlement.create(raw: Dependencies?): (Service?, string?)
		if
			type(raw) ~= "table"
			or type((raw).book) ~= "table"
			or type((raw).wallet) ~= "table"
			or type(((raw).wallet).read) ~= "function"
			or type(((raw).wallet).write) ~= "function"
			or type((raw).clock) ~= "function"
			or type((raw).newOpId) ~= "function"
		then
			return nil, "dependencies_invalid"
		end
		local deps = raw
		local busy = false

		local function serially(body: () -> Outcome): Outcome
			if busy then
				return outcome(false, "market_busy", nil, false)
			end
			busy = true
			local ran, result = pcall(body)
			busy = false
			if not ran then
				error(result, 0)
			end
			return result
		end

		local function commitWallet(result: WalletResult): boolean
			return result.ok and (result.replayed or deps.wallet.write(result.state))
		end

		local function claimReceipts(realmId: string, materialId: string, receipts: { Receipt }): string?
			local state = deps.wallet.read()
			if state == nil then
				return "wallet_unavailable"
			end
			local userId = state.userId
			local acknowledged: { string } = {}
			local changed = false
			local rooms: { [string]: number } = {}
			for _, receipt in receipts do
				local goodsId = receipt.itemId or materialId
				if rooms[goodsId] == nil then
					rooms[goodsId] = if deps.wallet.room ~= nil then deps.wallet.room(goodsId) else math.huge
				end
				local fits = receipt.goods <= rooms[goodsId] or table.find(state.claimedOrder, receipt.receiptId) ~= nil
				if receipt.ownerId == userId and fits then
					local claimed = MarketWalletCore.claim(state, receipt, goodsId)
					if claimed.ok and not claimed.replayed then
						rooms[goodsId] -= receipt.goods
					end
					if claimed.ok then
						acknowledged[#acknowledged + 1] = receipt.receiptId
						if not claimed.replayed then
							state = claimed.state
							changed = true
						end
					end
				end
			end
			if #acknowledged == 0 then
				return nil
			end
			if changed and not deps.wallet.write(state) then
				return "wallet_not_durable"
			end
			local acked = deps.book.apply(realmId, materialId, {
				kind = "ack",
				opId = deps.newOpId(),
				actorId = userId,
				receiptIds = acknowledged,
			})
			return if acked.ok then nil else acked.reason
		end

		local function resolve(opId: string, applied: BookResult): Outcome
			if applied.ok then
				return outcome(true, nil, opId, false)
			end
			if applied.ambiguous then
				return outcome(false, applied.reason, opId, true)
			end
			local wallet = deps.wallet.read()
			if wallet == nil then
				return outcome(false, "wallet_unavailable", opId, true)
			end
			local refunded = MarketWalletCore.refund(wallet, opId)
			if not commitWallet(refunded) then
				return outcome(false, "wallet_not_durable", opId, true)
			end
			return outcome(false, applied.reason, opId, false)
		end

		local function consign(
			realmId: string,
			materialId: string,
			count: number,
			unitPrice: number,
			itemId: string?
		): Outcome
			return serially(function(): Outcome
				local wallet = deps.wallet.read()
				if wallet == nil then
					return outcome(false, "wallet_unavailable", nil, false)
				end
				local opId = deps.newOpId()
				local begun = MarketWalletCore.beginConsign(
					wallet,
					opId,
					realmId,
					if itemId ~= nil then itemId else materialId,
					count,
					deps.clock(),
					if itemId ~= nil then materialId else nil
				)
				if not commitWallet(begun) then
					return outcome(false, begun.reason or "wallet_not_durable", opId, false)
				end
				local applied = deps.book.apply(realmId, materialId, {
					kind = "list",
					opId = opId,
					actorId = wallet.userId,
					actorRealmId = realmId,
					count = count,
					unitPrice = unitPrice,
					itemId = itemId,
				})
				if applied.ok then
					local current = deps.wallet.read()
					if current == nil then
						return outcome(false, "wallet_unavailable", opId, true)
					end
					local settled = MarketWalletCore.settleConsign(current, opId)
					if not commitWallet(settled) then
						return outcome(false, "wallet_not_durable", opId, true)
					end
				end
				return resolve(opId, applied)
			end)
		end

		local function buy(
			realmId: string,
			materialId: string,
			quantity: number,
			ceilingUnitPrice: number,
			itemId: string?
		): Outcome
			return serially(function(): Outcome
				local wallet = deps.wallet.read()
				if wallet == nil then
					return outcome(false, "wallet_unavailable", nil, false)
				end
				local opId = deps.newOpId()
				local hold = quantity * ceilingUnitPrice
				local begun = MarketWalletCore.beginBuy(
					wallet,
					opId,
					realmId,
					if itemId ~= nil then itemId else materialId,
					hold,
					deps.clock(),
					if itemId ~= nil then materialId else nil
				)
				if not commitWallet(begun) then
					return outcome(false, begun.reason or "wallet_not_durable", opId, false)
				end
				local applied = deps.book.apply(realmId, materialId, {
					kind = "fill",
					opId = opId,
					actorId = wallet.userId,
					actorRealmId = realmId,
					quantity = quantity,
					ceilingUnitPrice = ceilingUnitPrice,
					holdCoin = hold,
					itemId = itemId,
				})
				local resolved = resolve(opId, applied)
				if applied.ok then
					local problem = claimReceipts(realmId, materialId, applied.receipts or {})
					if problem ~= nil then
						return outcome(false, problem, opId, true)
					end
				end
				return resolved
			end)
		end

		local function cancel(realmId: string, materialId: string, listingId: string): Outcome
			return serially(function(): Outcome
				local wallet = deps.wallet.read()
				if wallet == nil then
					return outcome(false, "wallet_unavailable", nil, false)
				end
				local opId = deps.newOpId()
				local applied = deps.book.apply(realmId, materialId, {
					kind = "cancel",
					opId = opId,
					actorId = wallet.userId,
					listingId = listingId,
				})
				if not applied.ok then
					return outcome(false, applied.reason, opId, applied.ambiguous)
				end
				local problem = claimReceipts(realmId, materialId, applied.receipts or {})
				return outcome(problem == nil, problem, opId, problem ~= nil)
			end)
		end

		local function claimAll(realmId: string, materialId: string): Outcome
			return serially(function(): Outcome
				local read = deps.book.read(realmId, materialId)
				if not read.ok then
					return outcome(false, read.reason, nil, true)
				end
				local state = read.state
				if state == nil then
					return outcome(false, "book_unavailable", nil, true)
				end
				local nowSec = deps.clock()
				for _, listing in state.listings do
					if listing.expiresAtSec <= nowSec then
						local swept = deps.book.apply(realmId, materialId, { kind = "sweep", opId = deps.newOpId() })
						if swept.ok and swept.state ~= nil then
							state = swept.state
						end
						break
					end
				end
				local wallet = deps.wallet.read()
				if wallet == nil then
					return outcome(false, "wallet_unavailable", nil, true)
				end
				local receipts = MarketBookCore.receiptsFor(state, wallet.userId) or {}
				local problem = claimReceipts(realmId, materialId, receipts)
				return outcome(problem == nil, problem, nil, problem ~= nil)
			end)
		end

		local function heal(): Outcome
			return serially(function(): Outcome
				local wallet = deps.wallet.read()
				if wallet == nil then
					return outcome(false, "wallet_unavailable", nil, true)
				end
				local problem: string? = nil
				for opId, pending in wallet.pending do
					if deps.clock() - pending.startedAtSec >= config.healRetentionSec then
						continue
					end
					local fenced = deps.book.apply(
						pending.realmId,
						pending.bookId or pending.materialId,
						{ kind = "void", opId = opId }
					)
					if not fenced.ok or (fenced.fence ~= "known" and fenced.fence ~= "voided") then
						problem = fenced.reason or "fence_unconfirmed"
						continue
					end
					local current = deps.wallet.read()
					if current == nil then
						return outcome(false, "wallet_unavailable", opId, true)
					end
					local healed = MarketWalletCore.heal(current, opId, fenced.fence == "known", deps.clock())
					if not commitWallet(healed) then
						problem = healed.reason or "wallet_not_durable"
					end
				end
				return outcome(problem == nil, problem, nil, problem ~= nil)
			end)
		end

		return table.freeze({ consign = consign, buy = buy, cancel = cancel, claimAll = claimAll, heal = heal }), nil
	end

	return table.freeze(MarketSettlement)
end

return table.freeze({ configure = configure })
