--!strict

local Catalog = require("./catalog")
export type Event = Catalog.Event
export type Catalog = Catalog.Catalog
export type Context = {
	nowUnix: number,
	shardId: string?,
	playerId: number?,
	liveConfig: { flags: { [string]: Catalog.Flag }, killSwitches: { [string]: boolean } }?,
}
export type Effect = {
	rewards: { [string]: number },
	flags: { [string]: Catalog.Flag },
	contentScale: { [string]: { string } },
}
export type Resolution = { events: { Event }, effect: Effect }
export type Config = {
	catalog: Catalog,
	schemaVersion: number,
	maxRewardMultiplier: number,
	multiplierKeys: { string },
	bonusKeys: { string },
	contentKeys: { string },
	killSwitch: string,
	enabledFlag: string,
}
local finite = Catalog.finite
local function stableBucket(key: string): number
	local hash = 17
	for i = 1, #key do
		hash = (hash * 31 + string.byte(key, i)) % 10000
	end
	return hash % 100
end
local System = {}
function System.schedule(config: Config)
	local catalog = Catalog.catalog({ schemaVersion = config.schemaVersion, contentKeys = config.contentKeys })
	local function emptyEffect(): Effect
		local rewards: { [string]: number } = {}
		for _, key in config.multiplierKeys do
			rewards[key] = 1
		end
		for _, key in config.bonusKeys do
			rewards[key] = 0
		end
		local contentScale: { [string]: { string } } = {}
		for _, key in config.contentKeys do
			contentScale[key] = {}
		end
		return { rewards = rewards, flags = {}, contentScale = contentScale }
	end
	local function rolloutAllows(event: Event, context: Context): boolean
		local rollout = event.rollout
		if rollout == nil or rollout.mode == "all" then
			return true
		end
		if rollout.mode ~= "bucket" then
			return false
		end
		local percent = math.clamp(finite(rollout.percent) or 0, 0, 100)
		if percent >= 100 then
			return true
		elseif percent <= 0 then
			return false
		end
		local target = if context.playerId ~= nil then tostring(context.playerId) else context.shardId
		if target == nil or target == "" then
			return false
		end
		local salt = if rollout.salt ~= nil and rollout.salt ~= "" then rollout.salt else event.id
		return stableBucket(salt .. ":" .. target) < percent
	end
	local function buildEffect(events: { Event }): Effect
		local effect = emptyEffect()
		local seen: { [string]: { [string]: boolean } } = {}
		for _, key in config.contentKeys do
			seen[key] = {}
		end
		for _, event in events do
			local rewards = event.rewards or {}
			for _, key in config.multiplierKeys do
				local value = finite(rewards[key])
				if value ~= nil then
					effect.rewards[key] *= math.clamp(value, 0, config.maxRewardMultiplier)
				end
			end
			for _, key in config.bonusKeys do
				local value = finite(rewards[key])
				if value ~= nil then
					effect.rewards[key] += math.floor(value)
				end
			end
			for key, value in event.flags or {} do
				if key ~= "" then
					effect.flags[key] = value
				end
			end
			for _, key in config.contentKeys do
				for _, value in event.contentScale[key] or {} do
					if value ~= "" and not seen[key][value] then
						seen[key][value] = true
						table.insert(effect.contentScale[key], value)
					end
				end
			end
		end
		for _, key in config.multiplierKeys do
			effect.rewards[key] = math.clamp(effect.rewards[key], 0, config.maxRewardMultiplier)
		end
		return effect
	end
	local function resolve(supplied: Catalog?, context: Context): Resolution
		local live = context.liveConfig
		if
			live ~= nil and (live.killSwitches[config.killSwitch] == true or live.flags[config.enabledFlag] == false)
		then
			return { events = {}, effect = emptyEffect() }
		end
		local src = supplied or config.catalog
		local nowUnix = math.floor(finite(context.nowUnix) or 0)
		local active: { Event } = {}
		for _, entry in src.events do
			local event = catalog.projectEvent(entry)
			if
				event ~= nil
				and nowUnix >= event.schedule.startUnix
				and nowUnix < event.schedule.endUnix
				and rolloutAllows(event, context)
			then
				table.insert(active, event)
			end
		end
		table.sort(active, function(a: Event, b: Event)
			local ap, bp = finite(a.priority) or 0, finite(b.priority) or 0
			if ap ~= bp then
				return ap > bp
			end
			if a.schedule.startUnix ~= b.schedule.startUnix then
				return a.schedule.startUnix < b.schedule.startUnix
			end
			return a.id < b.id
		end)
		return { events = active, effect = buildEffect(active) }
	end
	local function validateCatalog(value: Catalog?): (boolean, { string })
		return catalog.validateCatalog(value or config.catalog)
	end
	return {
		resolve = resolve,
		validateCatalog = validateCatalog,
		stableBucket = stableBucket,
		MAX_REWARD_MULTIPLIER = config.maxRewardMultiplier,
		SCHEMA_VERSION = config.schemaVersion,
	}
end
return System
