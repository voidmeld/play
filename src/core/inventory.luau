--!strict

local Cargo = require("./inventory/cargo")
local Equipment = require("./inventory/equipment")
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
export type EquipmentRequirements = Equipment.Requirements
export type EquipmentItemDef = Equipment.ItemDef
export type EquipmentItemLookup = Equipment.ItemLookup
export type EquipmentEquipment = Equipment.Equipment
export type EquipmentInventory = Equipment.Inventory
export type EquipmentWear = Equipment.Wear
export type EquipmentDecision = Equipment.Decision
export type EquipmentInventoryPort = Equipment.InventoryPort
export type EquipmentConfig = Equipment.Config
export type EquipmentPlan = Equipment.Plan
export type EquipmentAPI = Equipment.API

export type API = {
	read cargo: typeof(Cargo),
	read equipment: typeof(Equipment),
	read stacks: typeof(Stacks),
}

local api: API = {
	cargo = Cargo,
	equipment = Equipment,
	stacks = Stacks,
}

return table.freeze(api)
