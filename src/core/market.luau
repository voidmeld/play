--!strict

local Book = require("./market/book")
local Conservation = require("./market/conservation")
local Goods = require("./market/goods")
local Wallet = require("./market/wallet")

export type BookListing = Book.Listing
export type BookReceiptKind = Book.ReceiptKind
export type BookReceipt = Book.Receipt
export type BookOperation = Book.Operation
export type BookState = Book.State
export type BookResult = Book.Result
export type BookCommand = Book.Command
export type BookSearch = Book.Search
export type BookConfig = Book.Config
export type ConservationTotals = Conservation.Totals
export type ConservationAudit = Conservation.Audit
export type ConservationConfig = Conservation.Config
export type GoodsItemFacts = Goods.ItemFacts
export type GoodsClass = Goods.Class
export type GoodsConfig<T> = Goods.Config<T>
export type GoodsFilters = Goods.Filters
export type WalletPending = Wallet.Pending
export type WalletState = Wallet.State
export type WalletLedger = Wallet.Ledger
export type WalletResult = Wallet.Result
export type WalletConfig = Wallet.Config

export type API = {
	read book: typeof(Book),
	read conservation: typeof(Conservation),
	read goods: typeof(Goods),
	read wallet: typeof(Wallet),
}

local api: API = {
	book = Book,
	conservation = Conservation,
	goods = Goods,
	wallet = Wallet,
}

return table.freeze(api)
