--!strict

local Catalog = require("./events/catalog")
local Schedule = require("./events/schedule")
local Watch = require("./events/watch")

export type CatalogFlag = Catalog.Flag
export type CatalogRollout = Catalog.Rollout
export type CatalogSchedule = Catalog.Schedule
export type CatalogEvent = Catalog.Event
export type CatalogCatalog = Catalog.Catalog
export type CatalogConfig = Catalog.Config
export type ScheduleEvent = Schedule.Event
export type ScheduleCatalog = Schedule.Catalog
export type ScheduleContext = Schedule.Context
export type ScheduleEffect = Schedule.Effect
export type ScheduleResolution = Schedule.Resolution
export type ScheduleConfig = Schedule.Config
export type WatchPhase = Watch.Phase
export type WatchWorkPoint = Watch.WorkPoint
export type WatchEvent = Watch.Event
export type WatchState = Watch.State
export type WatchResult = Watch.Result
export type WatchConfig = Watch.Config

export type API = {
	read catalog: typeof(Catalog),
	read schedule: typeof(Schedule),
	read watch: typeof(Watch),
}

local api: API = {
	catalog = Catalog,
	schedule = Schedule,
	watch = Watch,
}

return table.freeze(api)
