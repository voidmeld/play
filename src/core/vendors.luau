--!strict

local Exchange = require("./vendors/exchange")

export type ExchangeInventory = Exchange.Inventory
export type ExchangeAccount = Exchange.Account
export type ExchangeWare = Exchange.Ware
export type ExchangeVendor = Exchange.Vendor
export type ExchangeDecision = Exchange.Decision
export type ExchangeReceipt = Exchange.Receipt
export type ExchangeState = Exchange.State
export type ExchangeConfig = Exchange.Config

export type API = {
	read exchange: typeof(Exchange),
}

local api: API = {
	exchange = Exchange,
}

return table.freeze(api)
