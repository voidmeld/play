--!strict
local Value = require("../value")

export type Buff = { read slot: "food" | "elixir", read durationSec: number, read stats: { [string]: number } }
export type Item = {
	read resource: "hp" | "mana" | "none",
	read verb: string,
	read durationSec: number,
	read fractionPerSec: number,
	read combat: boolean?,
	read buff: Buff?,
}
export type Channel = { itemId: string, startedAt: number, tickedAt: number, endsAt: number, x: number, z: number }
export type ActiveBuff = { itemId: string, endsAt: number, stats: { [string]: number } }
export type State = {
	serial: number,
	cue: string,
	hp: Channel?,
	mana: Channel?,
	hpGained: number?,
	manaGained: number?,
	food: ActiveBuff?,
	elixir: ActiveBuff?,
}
export type Actor = {
	id: string,
	classId: string?,
	hp: number,
	maxHp: number?,
	mana: number?,
	maxMana: number?,
	pos: { x: number, y: number?, z: number },
	sustenance: State?,
	sustenanceGeneration: number?,
	fights: { [string]: number }?,
	pendingControl: unknown?,
	gcdRemainingSec: number?,
	crowdControls: { [string]: { remainingSec: number, totalSec: number? } }?,
}
export type ActorView = {
	read id: string,
	read classId: string?,
	read hp: number,
	read maxHp: number?,
	read mana: number?,
	read maxMana: number?,
	read pos: { read x: number, read y: number?, read z: number },
	read sustenance: State?,
	read sustenanceGeneration: number?,
	read fights: { read [string]: number }?,
	read pendingControl: unknown?,
	read gcdRemainingSec: number?,
	read crowdControls: { read [string]: { read remainingSec: number, read totalSec: number? } }?,
}
export type Mob = { read hp: number, read targetActorId: string?, read threat: { read [string]: number }? }
export type Config = {
	maxBuffStat: number,
	maxBuffSeconds: number,
	movementToleranceSquared: number,
	drinksMana: (ActorView) -> boolean,
	consumedCue: string,
	channelCue: string,
	finishedCue: string,
	interruptedCue: (string) -> string,
}

local Consumables = {}
function Consumables.create(config: Config)
	local function channel(state: State, resource: string): Channel?
		return if resource == "hp" then state.hp else state.mana
	end
	local function setChannel(state: State, resource: string, value: Channel?)
		if resource == "hp" then
			state.hp = value
		else
			state.mana = value
		end
	end
	local function buffAt(state: State, slot: string): ActiveBuff?
		return if slot == "food" then state.food else state.elixir
	end
	local function setBuff(state: State, slot: string, value: ActiveBuff)
		if slot == "food" then
			state.food = value
		else
			state.elixir = value
		end
	end
	local function amount(actor: ActorView, resource: string): number?
		return if resource == "hp" then actor.hp else actor.mana
	end
	local function addGain(state: State, resource: string, gain: number)
		if resource == "hp" then
			state.hpGained = (state.hpGained or 0) + gain
		else
			state.manaGained = (state.manaGained or 0) + gain
		end
	end
	local Core = {}
	local ITEMS: { [string]: Item } = {}
	local MAX_BUFF_STAT = config.maxBuffStat
	local MAX_BUFF_SEC = config.maxBuffSeconds
	local RESOURCES: { "hp" | "mana" } = { "hp", "mana" }
	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and math.abs(value) < math.huge
	end

	local function readItem(input: unknown): Item?
		local raw = Value.raw(input)
		if raw == nil then
			return nil
		end
		local resource, verb = raw.resource, raw.verb
		local duration, fraction, combat = raw.durationSec, raw.fractionPerSec, raw.combat
		if
			(resource ~= "hp" and resource ~= "mana" and resource ~= "none")
			or type(verb) ~= "string"
			or type(duration) ~= "number"
			or not finite(duration)
			or duration < 0
			or type(fraction) ~= "number"
			or not finite(fraction)
			or (combat ~= nil and type(combat) ~= "boolean")
		then
			return nil
		end
		if resource ~= "none" and (duration <= 0 or fraction <= 0) then
			return nil
		end
		local buff: Buff? = nil
		if raw.buff ~= nil then
			local value = Value.raw(raw.buff)
			if value == nil then
				return nil
			end
			local slot, seconds = value.slot, value.durationSec
			if
				(slot ~= "food" and slot ~= "elixir")
				or type(seconds) ~= "number"
				or not finite(seconds)
				or seconds <= 0
				or seconds > MAX_BUFF_SEC
				or type(value.stats) ~= "table"
			then
				return nil
			end
			local stats: { [string]: number } = {}
			for key, amount in value.stats do
				if
					type(key) ~= "string"
					or type(amount) ~= "number"
					or not finite(amount)
					or amount <= 0
					or amount > MAX_BUFF_STAT
				then
					return nil
				end
				stats[key] = amount
			end
			local definition: Buff = { slot = slot, durationSec = seconds, stats = table.freeze(stats) }
			buff = table.freeze(definition)
		elseif resource == "none" then
			return nil
		end
		local definition: Item = {
			resource = resource,
			verb = verb,
			durationSec = duration,
			fractionPerSec = fraction,
			combat = combat,
			buff = buff,
		}
		return table.freeze(definition)
	end

	function Core.register(itemId: unknown, raw: unknown): boolean
		if type(itemId) ~= "string" or itemId == "" or ITEMS[itemId] ~= nil then
			return false
		end
		local item = readItem(raw)
		if item == nil then
			return false
		end
		ITEMS[itemId] = item
		return true
	end

	function Core.registerAll(map: unknown): number
		local added = 0
		if type(map) == "table" then
			for itemId, profile in map do
				if Core.register(itemId, profile) then
					added += 1
				end
			end
		end
		return added
	end

	local drinksMana = config.drinksMana

	function Core.item(itemId: unknown): Item?
		return if type(itemId) == "string" then ITEMS[itemId] else nil
	end

	function Core.copy(state: State?): State
		local out: State = if state == nil then { serial = 0, cue = "" } else table.clone(state)
		out.hp = if out.hp ~= nil then table.clone(out.hp) else nil
		out.mana = if out.mana ~= nil then table.clone(out.mana) else nil
		return out
	end

	local function activeItem(actor: ActorView): Item?
		local state = actor.sustenance
		if state == nil then
			return nil
		end
		for _, resource in RESOURCES do
			local channel = channel(state, resource)
			if channel ~= nil then
				return Core.item(channel.itemId)
			end
		end
		return nil
	end

	function Core.eligibility(actor: ActorView?, mobs: { read [string]: Mob }?, item: Item?): string?
		local selected = item or (if actor ~= nil then activeItem(actor) else nil)
		local allowCombat = selected ~= nil and selected.combat == true
		if actor == nil or not finite(actor.hp) or actor.hp <= 0 then
			return "recover_before_rest"
		end
		if not allowCombat then
			if actor.fights ~= nil then
				for _ in actor.fights do
					return "in_combat"
				end
			end
			if actor.pendingControl ~= nil or (actor.gcdRemainingSec or 0) > 0 then
				return "in_combat"
			end
			for _, mob in (mobs or {}) do
				if mob.hp > 0 and (mob.targetActorId == actor.id or ((mob.threat or {})[actor.id] or 0) > 0) then
					return "in_combat"
				end
			end
		end
		if actor.crowdControls ~= nil then
			for _, effect in actor.crowdControls do
				if effect.remainingSec > 0 then
					return "controlled"
				end
			end
		end
		return nil
	end

	function Core.begin(
		state: State?,
		actor: ActorView,
		mobs: { read [string]: Mob }?,
		itemId: unknown,
		rawSerial: unknown,
		rawNow: unknown
	): (State?, string?)
		local serial = rawSerial
		local now = rawNow
		local item = Core.item(itemId)
		if item == nil or type(itemId) ~= "string" then
			return nil, "not_food_or_drink"
		end
		if
			type(now) ~= "number"
			or not finite(now)
			or now < 0
			or type(serial) ~= "number"
			or not finite(serial)
			or serial % 1 ~= 0
			or serial > 9007199254740991
			or serial <= (if state then state.serial else 0)
		then
			return nil, "stale_use"
		end
		local reason = Core.eligibility(actor, mobs, item)
		if reason ~= nil then
			return nil, reason
		end
		local resource = item.resource
		if resource == "none" then
			local buff = assert(item.buff)
			local slot = buff.slot
			local held = if state ~= nil then buffAt(state, slot) else nil
			if held ~= nil and held.itemId == itemId and now < held.endsAt then
				return nil, "already_active"
			end
			local applied = Core.copy(state)
			applied.serial = serial
			setBuff(applied, slot, {
				itemId = itemId,
				endsAt = now + assert(item.buff).durationSec,
				stats = assert(item.buff).stats,
			})
			applied.cue = config.consumedCue
			return applied, nil
		end
		local maximum = (if resource == "hp" then actor.maxHp else actor.maxMana)
		if
			type(maximum) ~= "number"
			or not finite(maximum)
			or maximum <= 0
			or type(amount(actor, resource)) ~= "number"
			or not finite(amount(actor, resource))
		then
			return nil, "resource_full"
		end
		if (amount(actor, resource) or 0) >= maximum and item.buff == nil then
			return nil, "resource_full"
		end
		if resource == "mana" and item.buff == nil and not drinksMana(actor) then
			return nil, "no_mana_pool"
		end
		if state ~= nil and channel(state, resource) ~= nil then
			return nil, "already_resting"
		end
		local out = Core.copy(state)
		out.serial = serial
		if resource == "hp" then
			out.hpGained = 0
		else
			out.manaGained = 0
		end
		out.cue = config.channelCue
		setChannel(out, resource, {
			itemId = itemId,
			startedAt = now,
			tickedAt = now,
			endsAt = now + item.durationSec,
			x = actor.pos.x,
			z = actor.pos.z,
		})
		return out, nil
	end

	function Core.interrupt(state: State?, reason: string): State?
		if state == nil or (state.hp == nil and state.mana == nil) then
			return state
		end
		local out = Core.copy(state)
		out.hp, out.mana = nil, nil
		out.cue = config.interruptedCue(reason)
		return out
	end

	function Core.interruptActor(actor: { sustenanceGeneration: number?, sustenance: State? }, reason: string)
		actor.sustenanceGeneration = (actor.sustenanceGeneration or 0) + 1
		actor.sustenance = Core.interrupt(actor.sustenance, reason)
	end

	function Core.activeStats(state: State?, now: number): { [string]: number }
		local out: { [string]: number } = {}
		if state == nil then
			return out
		end
		for _, slot: "food" | "elixir" in { "food", "elixir" } do
			local buff = buffAt(state, slot)
			if buff ~= nil and now < buff.endsAt then
				for key, value in buff.stats do
					out[key] = (out[key] or 0) + value
				end
			end
		end
		return out
	end

	function Core.advance(
		state: State?,
		actor: ActorView,
		mobs: { read [string]: Mob }?,
		now: number
	): (State?, number, number)
		if state == nil then
			return nil, 0, 0
		end
		local reason = Core.eligibility(actor, mobs)
		if reason ~= nil then
			return Core.interrupt(state, reason), 0, 0
		end
		local out = Core.copy(state)
		local gains: { [string]: number } = { hp = 0, mana = 0 }
		for _, resource in RESOURCES do
			local channel = channel(out, resource)
			if channel ~= nil then
				local dx, dz = actor.pos.x - channel.x, actor.pos.z - channel.z
				if dx * dx + dz * dz > config.movementToleranceSquared then
					return Core.interrupt(state, "moved"), 0, 0
				end
				local item = assert(Core.item(channel.itemId))
				local maximum = assert(if resource == "hp" then actor.maxHp else actor.maxMana)
				local elapsed = math.max(0, math.min(now, channel.endsAt) - channel.tickedAt)
				if resource == "mana" and not drinksMana(actor) then
					gains[resource] = 0
				else
					gains[resource] = math.min(
						math.max(0, maximum - (amount(actor, resource) or 0)),
						maximum * item.fractionPerSec * elapsed
					)
				end
				addGain(out, resource, gains[resource])
				channel.tickedAt = math.max(channel.tickedAt, math.min(now, channel.endsAt))
				if
					now >= channel.endsAt
					or (item.buff == nil and (amount(actor, resource) or 0) + gains[resource] >= maximum)
				then
					if item.buff ~= nil then
						setBuff(out, item.buff.slot, {
							itemId = channel.itemId,
							endsAt = now + item.buff.durationSec,
							stats = item.buff.stats,
						})
					end
					setChannel(out, resource, nil)
				end
			end
		end
		if (state.hp ~= nil or state.mana ~= nil) and out.hp == nil and out.mana == nil then
			out.cue = config.finishedCue
		end
		return out, gains.hp, gains.mana
	end

	return table.freeze(Core)
end

return table.freeze(Consumables)
