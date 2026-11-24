--!strict

local RespawnHost = require("./character/respawn-host")

export type RespawnHostRefresh<C> = RespawnHost.Refresh<C>
export type RespawnHostObservation<C> = RespawnHost.Observation<C>
export type RespawnHostDependencies<P, C, H, O, S> = RespawnHost.Dependencies<P, C, H, O, S>
export type RespawnHostHost<P, C, O> = RespawnHost.Host<P, C, O>

export type API = {
	read respawn_host: typeof(RespawnHost),
}

local api: API = {
	respawn_host = RespawnHost,
}

return table.freeze(api)
