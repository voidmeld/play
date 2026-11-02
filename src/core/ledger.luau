--!strict

local Ledger = require("./ledger/ledger")

export type LedgerEventKind = Ledger.EventKind
export type LedgerEvent = Ledger.Event
export type LedgerState = Ledger.State
export type LedgerApplyResult = Ledger.ApplyResult
export type LedgerTornGroup = Ledger.TornGroup
export type LedgerConfig = Ledger.Config
export type LedgerJournal = Ledger.Journal

export type API = {
	read ledger: typeof(Ledger),
}

local api: API = {
	ledger = Ledger,
}

return table.freeze(api)
