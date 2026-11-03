--!strict

local Book = require("./book")
local Value = require("../../kernel/value")
local Wallet = require("./wallet")

export type Totals = { coin: number, goods: { [string]: number } }
export type Audit = { ok: boolean, coin: number, goods: { [string]: number }, reason: string? }

export type Config = {
	projectBook: (unknown) -> Book.State?,
	projectWallet: (unknown) -> Wallet.State?,
}

local Conservation = {}

function Conservation.conservation(config: Config)
	local Audit = {}

	local function claimedBy(wallets: { Wallet.State }): { [number]: { [string]: boolean } }
		local claimed: { [number]: { [string]: boolean } } = {}
		for _, wallet in wallets do
			local set: { [string]: boolean } = {}
			for _, receiptId in wallet.claimedOrder do
				set[receiptId] = true
			end
			claimed[wallet.userId] = set
		end
		return claimed
	end

	function Audit.measure(walletValues: unknown, bookValues: unknown): (Totals?, string?)
		if type(walletValues) ~= "table" or type(bookValues) ~= "table" then
			return nil, "input_invalid"
		end
		local wallets: { Wallet.State } = {}
		for _, value in assert(Value.raw(walletValues)) do
			local wallet = config.projectWallet(value)
			if wallet == nil then
				return nil, "wallet_invalid"
			end
			wallets[#wallets + 1] = wallet
		end
		local books: { Book.State } = {}
		local bookByMaterial: { [string]: { Book.State } } = {}
		for _, value in assert(Value.raw(bookValues)) do
			local book = config.projectBook(value)
			if book == nil then
				return nil, "book_invalid"
			end
			books[#books + 1] = book
			local list = bookByMaterial[book.materialId] or {}
			bookByMaterial[book.materialId] = list
			list[#list + 1] = book
		end
		local claimed = claimedBy(wallets)
		local coin = 0
		local goods: { [string]: number } = {}
		local function addGoods(materialId: string, count: number)
			goods[materialId] = (goods[materialId] or 0) + count
		end
		local function bookKnows(realmId: string, materialId: string, opId: string): boolean
			local candidates: { Book.State } = bookByMaterial[materialId] or {}
			for _, book in candidates do
				if book.realmId == realmId and book.operations[opId] ~= nil then
					return true
				end
			end
			return false
		end
		for _, wallet in wallets do
			coin += wallet.coin
			for materialId, count in wallet.goods do
				addGoods(materialId, count)
			end
			for opId, pending in wallet.pending do
				if pending.kind == "buy" then
					coin += pending.hold
				elseif not bookKnows(pending.realmId, pending.materialId, opId) then
					addGoods(pending.materialId, pending.count)
				end
			end
		end
		for _, book in books do
			coin += book.burnedCoin
			for _, listing in book.listings do
				addGoods(book.materialId, listing.count)
			end
			for _, receipt in book.receipts do
				local ownerClaims = claimed[receipt.ownerId]
				local alreadyClaimed = ownerClaims ~= nil and ownerClaims[receipt.receiptId] == true
				if receipt.kind == "purchase" then
					if not alreadyClaimed then
						coin -= receipt.coin
						addGoods(book.materialId, receipt.goods)
					end
				elseif not alreadyClaimed then
					coin += receipt.coin
					addGoods(book.materialId, receipt.goods)
				end
			end
		end
		return { coin = coin, goods = goods }, nil
	end

	function Audit.audit(walletValues: unknown, bookValues: unknown, expected: Totals): Audit
		local measured, reason = Audit.measure(walletValues, bookValues)
		if measured == nil then
			return { ok = false, coin = 0, goods = {}, reason = reason }
		end
		local totals = measured
		if totals.coin ~= expected.coin then
			return { ok = false, coin = totals.coin, goods = totals.goods, reason = "coin_unbalanced" }
		end
		local materials: { [string]: boolean } = {}
		for materialId in totals.goods do
			materials[materialId] = true
		end
		for materialId in expected.goods do
			materials[materialId] = true
		end
		for materialId in materials do
			if (totals.goods[materialId] or 0) ~= (expected.goods[materialId] or 0) then
				return {
					ok = false,
					coin = totals.coin,
					goods = totals.goods,
					reason = "goods_unbalanced:" .. materialId,
				}
			end
		end
		return { ok = true, coin = totals.coin, goods = totals.goods, reason = nil }
	end

	Audit.BOUNDARY = table.concat({
		"coin=wallet-coin+buy-holds-unclaimed-purchase-spend+unclaimed-proceeds+burned",
		"goods=wallet-goods+consigns-the-book-does-not-know+open-listings+unclaimed-returns+unclaimed-purchases",
		"a-receipt-counts-once:-in-the-book-until-its-owner-claims-it,-in-the-wallet-after",
	}, ";")

	return Audit
end

return Conservation
