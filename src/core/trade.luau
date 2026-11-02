--!strict

local Exchange = require("./trade/exchange")
local Receipt = require("./trade/receipt")

export type ExchangeStack = Exchange.Stack
export type ExchangeOffer = Exchange.Offer
export type ExchangePhase = Exchange.Phase
export type ExchangeState = Exchange.State
export type ExchangeConfig = Exchange.Config
export type ReceiptRecord<K> = Receipt.Record<K>
export type ReceiptProjected = Receipt.Projected
export type ReceiptWire = Receipt.Wire
export type ReceiptPointer = Receipt.Pointer
export type ReceiptConfig = Receipt.Config

export type API = {
	read exchange: typeof(Exchange),
	read receipt: typeof(Receipt),
}

local api: API = {
	exchange = Exchange,
	receipt = Receipt,
}

return table.freeze(api)
