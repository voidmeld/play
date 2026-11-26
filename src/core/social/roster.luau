--!strict

local Value = require("../../kernel/value")

export type Member = { accountId: string, characterId: string? }
export type Party = { partyId: string, realmId: string, disbandedAt: number?, members: { Member } }
export type Actor = { id: string, characterId: string?, realm: string?, partyId: string? }
export type Runtime<S> = { state: S, tick: number }
export type Result<S, A> = { parties: { [string]: Runtime<S> }, actors: { [string]: A } }
export type Config<S, A> = {
	project: (unknown) -> S?,
	party: (S) -> Party,
	lootCursor: (S) -> string?,
	withLootCursor: (S, string?) -> S,
	actor: (A) -> Actor,
	withParty: (A, string?) -> A,
	subject: (string) -> string,
}

export type Point = { read x: number, read y: number, read z: number }
export type Presence = { [string]: Point }
export type RewardParty = {
	read realmId: string,
	read disbandedAt: number?,
	read members: { read [number]: { read accountId: string, read absentSince: number? } },
}
export type XpEvent = { eventId: string, at: number, origin: Point, amount: number, groupBonus: number? }
export type ContributionEvent<K> = { eventId: string, at: number, origin: Point, kind: K, units: number }
export type Share = { read accountId: string, read amount: number }
export type Contribution<K> = {
	read eventId: string,
	read kind: K,
	read accountId: string,
	read realmId: string,
	read units: number,
	read at: number,
}
export type SharingConfig<K> = {
	read projectParty: (unknown) -> (RewardParty?, string?),
	read contributionKind: (string) -> (K & string)?,
	read eventIdFor: (eventId: string, accountId: string) -> string,
	read radius: number,
	read maxCoordinate: number,
	read maxText: number,
	read maxAt: number,
	read maxAmount: number,
	read maxUnits: number,
}
export type Sharing<K> = {
	read projectPresence: (unknown) -> (Presence?, string?),
	read eligible: (party: unknown, origin: unknown, presence: unknown) -> ({ string }?, string?),
	read shareXp: (party: unknown, event: unknown, presence: unknown) -> ({ Share }?, string?),
	read splitContribution: (party: unknown, event: unknown, presence: unknown) -> ({ Contribution<K> }?, string?),
}

local System = {}
function System.roster<S, A>(config: Config<S, A>)
	local function reduce(
		parties: { [string]: Runtime<S> },
		actors: { [string]: A },
		raw: unknown,
		tick: number
	): Result<S, A>?
		local projected = config.project(raw)
		if projected == nil then
			return nil
		end
		local view = config.party(projected)
		local prior = parties[view.partyId]
		local state = config.withLootCursor(projected, if prior ~= nil then config.lootCursor(prior.state) else nil)
		local nextParties = table.clone(parties)
		nextParties[view.partyId] = if view.disbandedAt ~= nil then nil else { state = state, tick = tick }
		local members: { [string]: string } = {}
		for _, member in view.members do
			members[member.accountId] = member.characterId
		end
		local nextActors = table.clone(actors)
		for key, source in actors do
			local actor = config.actor(source)
			local partyId = if view.disbandedAt == nil
					and actor.characterId ~= nil
					and string.lower(actor.realm or "") == view.realmId
					and members[config.subject(actor.id)] == actor.characterId
				then view.partyId
				elseif actor.partyId == view.partyId then nil
				else actor.partyId
			if partyId ~= actor.partyId then
				nextActors[key] = config.withParty(source, partyId)
			end
		end
		return { parties = nextParties, actors = nextActors }
	end
	return { reduce = reduce, subject = config.subject }
end

local POINT = { x = true, y = true, z = true }
local XP = { eventId = true, at = true, origin = true, amount = true, groupBonus = true }
local CONTRIBUTION = { eventId = true, at = true, origin = true, kind = true, units = true }
local MAX_INTEGER = 9007199254740991

local function share(total: number, count: number, index: number): number
	return total // count + (if index <= total % count then 1 else 0)
end

function System.sharing<K>(config: SharingConfig<K>): Sharing<K>
	config = table.clone(config)
	local radiusSquared = config.radius * config.radius
	assert(Value.finite(radiusSquared) and config.radius >= 0, "radius_invalid")
	assert(Value.finite(config.maxCoordinate) and config.maxCoordinate >= 0, "coordinate_limit_invalid")
	assert(Value.finite(config.maxAt) and config.maxAt >= 0, "time_limit_invalid")
	assert(Value.whole(config.maxText, 1, MAX_INTEGER), "text_limit_invalid")
	assert(Value.whole(config.maxAmount, 0, MAX_INTEGER), "amount_limit_invalid")
	assert(Value.whole(config.maxUnits, 1, MAX_INTEGER), "unit_limit_invalid")

	local function coordinate(value: unknown): number?
		return if type(value) == "number" and math.abs(value) <= config.maxCoordinate then value else nil
	end

	local function point(value: unknown): Point?
		local raw = Value.record(value, POINT, true, false)
		if raw == nil then
			return nil
		end
		local x, y, z = coordinate(raw.x), coordinate(raw.y), coordinate(raw.z)
		return if x ~= nil and y ~= nil and z ~= nil then table.freeze({ x = x, y = y, z = z }) else nil
	end

	local function projectPresence(value: unknown): (Presence?, string?)
		if type(value) ~= "table" then
			return nil, "presence_invalid"
		end
		local presence: Presence = {}
		for key, entry in value do
			local id = Value.opaque(key, config.maxText)
			if id == nil then
				return nil, "presence_invalid"
			end
			local position = point(entry)
			if position == nil then
				return nil, "presence_invalid"
			end
			presence[id] = position
		end
		return table.freeze(presence), nil
	end

	local function recipients(party: RewardParty, originValue: unknown, presenceValue: unknown): ({ string }?, string?)
		local origin = point(originValue)
		if origin == nil then
			return nil, "event_shape_invalid"
		end
		local presence, reason = projectPresence(presenceValue)
		if presence == nil then
			return nil, reason
		end
		local ids: { string } = {}
		for _, member in party.members do
			local position = presence[member.accountId]
			if position ~= nil and member.absentSince == nil then
				local dx, dy, dz = position.x - origin.x, position.y - origin.y, position.z - origin.z
				if dx * dx + dy * dy + dz * dz <= radiusSquared then
					table.insert(ids, member.accountId)
				end
			end
		end
		return table.freeze(ids), nil
	end

	local function eligible(partyValue: unknown, origin: unknown, presence: unknown): ({ string }?, string?)
		local party, reason = config.projectParty(partyValue)
		if party == nil then
			return nil, reason
		end
		return recipients(party, origin, presence)
	end

	type Event = { party: RewardParty, raw: Value.Raw, id: string }
	local function openEvent(partyValue: unknown, value: unknown, fields: { [string]: boolean }): (Event?, string?)
		local party, reason = config.projectParty(partyValue)
		if party == nil then
			return nil, reason
		elseif party.disbandedAt ~= nil then
			return nil, "party_disbanded"
		end
		local raw = Value.record(value, fields, false, false)
		if raw == nil then
			return nil, "event_shape_invalid"
		end
		local id = Value.opaque(raw.eventId, config.maxText)
		if id == nil then
			return nil, "event_id_invalid"
		end
		return { party = party, raw = raw, id = id }, nil
	end

	local function timestamp(value: unknown): number?
		return if type(value) == "number" and value >= 0 and value <= config.maxAt then value else nil
	end

	local function shareXp(party: unknown, value: unknown, presence: unknown): ({ Share }?, string?)
		local event, reason = openEvent(party, value, XP)
		if event == nil then
			return nil, reason
		end
		local pool = Value.whole(event.raw.amount, 0, config.maxAmount)
		if pool == nil then
			return nil, "amount_invalid"
		elseif timestamp(event.raw.at) == nil then
			return nil, "time_invalid"
		end
		local ids, invalid = recipients(event.party, event.raw.origin, presence)
		if ids == nil then
			return nil, invalid
		end
		local rows: { Share } = {}
		local bonus = event.raw.groupBonus
		if #ids > 0 and bonus ~= nil then
			if type(bonus) ~= "number" or not Value.finite(bonus) or bonus < 0 or bonus > 1 then
				return nil, "bonus_invalid"
			end
			local boosted = pool * (1 + bonus * (#ids - 1))
			if boosted > MAX_INTEGER then
				return nil, "amount_invalid"
			end
			pool = math.round(boosted)
		end
		for index, id in ids do
			table.insert(rows, table.freeze({ accountId = id, amount = share(pool, #ids, index) }))
		end
		return table.freeze(rows), nil
	end

	local function splitContribution(party: unknown, value: unknown, presence: unknown): ({ Contribution<K> }?, string?)
		local event, reason = openEvent(party, value, CONTRIBUTION)
		if event == nil then
			return nil, reason
		end
		local kind = if type(event.raw.kind) == "string" then config.contributionKind(event.raw.kind) else nil
		if kind == nil then
			return nil, "kind_invalid"
		end
		local total = Value.whole(event.raw.units, 1, config.maxUnits)
		if total == nil then
			return nil, "units_invalid"
		end
		local at = timestamp(event.raw.at)
		if at == nil then
			return nil, "time_invalid"
		end
		local ids, invalid = recipients(event.party, event.raw.origin, presence)
		if ids == nil then
			return nil, invalid
		end
		local rows: { Contribution<K> } = {}
		for index, id in ids do
			local units = share(total, #ids, index)
			if units == 0 then
				break
			end
			local receipt = Value.opaque(config.eventIdFor(event.id, id), config.maxText)
			if receipt == nil then
				return nil, "event_id_invalid"
			end
			table.insert(
				rows,
				table.freeze({
					eventId = receipt,
					accountId = id,
					realmId = event.party.realmId,
					kind = kind,
					units = units,
					at = at,
				})
			)
		end
		return table.freeze(rows), nil
	end

	return table.freeze({
		projectPresence = projectPresence,
		eligible = eligible,
		shareXp = shareXp,
		splitContribution = splitContribution,
	})
end
return System
