--!strict

local Cargo = require("./inventory/cargo")
local Stacks = require("./inventory/stacks")

export type CargoStatus = Cargo.Status
export type CargoCause = Cargo.Cause
export type CargoClaim = Cargo.Claim
export type CargoDrop = Cargo.Drop
export type CargoTotal = Cargo.Total
export type CargoExtraction = Cargo.Extraction
export type CargoState = Cargo.State
export type CargoIntent = Cargo.Intent
export type CargoCommandKind = Cargo.CommandKind
export type CargoCommand = Cargo.Command
export type CargoResult = Cargo.Result
export type CargoCensusRow = Cargo.CensusRow
export type CargoConfig = Cargo.Config
export type StacksInventory = Stacks.Inventory
export type StacksHoldings = Stacks.Holdings
export type StacksConfig = Stacks.Config

export type API = {
	read cargo: typeof(Cargo),
	read stacks: typeof(Stacks),
}

local api: API = {
	cargo = Cargo,
	stacks = Stacks,
}

return table.freeze(api)
