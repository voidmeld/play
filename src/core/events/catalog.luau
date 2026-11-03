--!strict

local Value = require("../../kernel/value")

export type Flag = string | boolean | number
export type Rollout = { mode: string, percent: number?, salt: string? }
export type Schedule = { startUnix: number, endUnix: number }
export type Event = {
	id: string,
	title: string,
	realm: string,
	priority: number?,
	schedule: Schedule,
	rollout: Rollout?,
	rewards: { [string]: number }?,
	contentScale: { [string]: { string } },
	flags: { [string]: Flag }?,
}
export type Catalog = { schemaVersion: number, events: { Event } }
export type Config = { schemaVersion: number, contentKeys: { string } }

local function finite(value: unknown): number?
	return if type(value) == "number" and value == value and math.abs(value) ~= math.huge then value else nil
end

local function rolloutValue(value: Rollout): Rollout
	return value
end
local System = {}
function System.catalog(config: Config)
	local function projectEvent(value: unknown): (Event?, string?)
		local raw = Value.raw(value)
		if raw == nil then
			return nil, "event must be a table"
		end
		local id = raw.id
		if type(id) ~= "string" or id == "" then
			return nil, "event id is required"
		end
		local title, realm = raw.title, raw.realm
		if type(title) ~= "string" or title == "" then
			return nil, ("event %s title is required"):format(id)
		end
		if type(realm) ~= "string" or realm == "" then
			return nil, ("event %s realm is required"):format(id)
		end
		local schedule = Value.raw(raw.schedule)
		if schedule == nil then
			return nil, ("event %s schedule is required"):format(id)
		end
		local startUnix, endUnix = finite(schedule.startUnix), finite(schedule.endUnix)
		if startUnix == nil or endUnix == nil then
			return nil, ("event %s schedule must use finite unix seconds"):format(id)
		end
		if startUnix >= endUnix then
			return nil, ("event %s schedule must end after it starts"):format(id)
		end
		local rollout: Rollout? = nil
		if raw.rollout ~= nil then
			local fields = Value.raw(raw.rollout)
			if fields == nil then
				return nil, ("event %s rollout must be a table"):format(id)
			end
			local mode = fields.mode
			if mode ~= "all" and mode ~= "bucket" then
				return nil, ("event %s rollout mode is unsupported"):format(id)
			end
			local percent = finite(fields.percent)
			if mode == "bucket" then
				if percent == nil then
					return nil, ("event %s rollout percent is required"):format(id)
				end
				if percent < 0 or percent > 100 then
					return nil, ("event %s rollout percent must be 0..100"):format(id)
				end
			end
			rollout = rolloutValue({
				mode = mode,
				percent = percent,
				salt = if type(fields.salt) == "string" then fields.salt else nil,
			})
		end
		local contentScale: { [string]: { string } } = {}
		local content = Value.raw(raw.contentScale)
		local found = false
		if content ~= nil then
			for _, key in config.contentKeys do
				local list = content[key]
				if type(list) == "table" then
					local entries: { string } = {}
					if #list > 0 then
						found = true
					end
					for _, entry in list do
						if type(entry) == "string" then
							table.insert(entries, entry)
						end
					end
					contentScale[key] = entries
				end
			end
		end
		if not found then
			return nil, ("event %s must declare at least one contentScale hook"):format(id)
		end
		local rewards: { [string]: number } = {}
		local rewardFields = Value.raw(raw.rewards)
		if rewardFields ~= nil then
			for key, v in rewardFields do
				if type(key) == "string" and finite(v) ~= nil and type(v) == "number" then
					rewards[key] = v
				end
			end
		end
		local flags: { [string]: Flag } = {}
		local flagFields = Value.raw(raw.flags)
		if flagFields ~= nil then
			for key, v in flagFields do
				if
					type(key) == "string"
					and key ~= ""
					and (type(v) == "string" or type(v) == "boolean" or type(v) == "number")
				then
					flags[key] = v
				end
			end
		end
		return {
			id = id,
			title = title,
			realm = realm,
			priority = finite(raw.priority),
			schedule = { startUnix = startUnix, endUnix = endUnix },
			rollout = rollout,
			rewards = rewards,
			contentScale = contentScale,
			flags = flags,
		},
			nil
	end
	local function validateCatalog(value: unknown): (boolean, { string })
		local raw = Value.raw(value)
		if raw == nil then
			return false, { "catalog must be a table" }
		end
		local errors: { string } = {}
		if raw.schemaVersion ~= config.schemaVersion then
			table.insert(
				errors,
				("schema mismatch: got v%s expected v%d"):format(tostring(raw.schemaVersion), config.schemaVersion)
			)
		end
		local events = Value.raw(raw.events)
		if events == nil then
			table.insert(errors, "catalog events must be a table")
			return false, errors
		end
		local ids: { [string]: boolean } = {}
		for _, entry in events do
			local event, reason = projectEvent(entry)
			if event == nil then
				table.insert(errors, assert(reason))
			elseif ids[event.id] then
				table.insert(errors, "duplicate event id: " .. event.id)
			else
				ids[event.id] = true
			end
		end
		return #errors == 0, errors
	end
	return { projectEvent = projectEvent, validateCatalog = validateCatalog, SCHEMA_VERSION = config.schemaVersion }
end
System.finite = finite
return System
