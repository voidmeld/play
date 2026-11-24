--!strict

local Patron = require("./orders/patron")
local Work = require("./orders/work")

export type PatronOrder = Patron.Order
export type PatronCatalog = Patron.Catalog
export type PatronState = Patron.State
export type PatronResult = Patron.Result
export type PatronConfig = Patron.Config
export type WorkPhase = Work.Phase
export type WorkWorkOrderStep = Work.WorkOrderStep
export type WorkWorkOrder = Work.WorkOrder
export type WorkState = Work.State
export type WorkCommandKind = Work.CommandKind
export type WorkCommand = Work.Command
export type WorkResult = Work.Result

export type API = {
	read patron: typeof(Patron),
	read work: typeof(Work),
}

local api: API = {
	patron = Patron,
	work = Work,
}

return table.freeze(api)
