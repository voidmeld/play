--!strict

local Timed = require("./effects/timed")

export type TimedEntry = Timed.Entry
export type TimedApplication = Timed.Application
export type TimedRefresh = Timed.Refresh

export type API = {
	read timed: typeof(Timed),
}

local api: API = {
	timed = Timed,
}

return table.freeze(api)
