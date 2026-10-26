--!strict
local Value = require("../internal/value")
export type Config = { statuses: { [string]: boolean } }
local System = {}
function System.tracking(config: Config)
	local function canTrack(progress: unknown): boolean
		local raw = Value.raw(progress)
		return raw ~= nil and type(raw.status) == "string" and config.statuses[raw.status] == true
	end
	return { canTrack = canTrack }
end
return System
