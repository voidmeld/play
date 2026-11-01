--!strict
local Value = require("../internal/value")
export type EventKind = string

export type Event = {
	eventId: string,
	kind: EventKind,
	accountId: string,
	realmId: string,
	seasonId: string,
	units: number,
	at: number,
}

export type State = {
	events: { Event },
}

export type ApplyResult = {
	state: State,
	replayed: boolean,
	points: number,
}

export type Ladder = {
	seasonId: string,
	thresholds: { number },
	pointsPerUnit: { [string]: number },
	rankNames: { [string]: { string } },
}

export type Standing = {
	accountId: string,
	realmId: string,
	seasonId: string,
	points: number,
	rank: number,
	rankName: string?,
	nextRankAt: number?,
	pointsToNextRank: number?,
	lifetimePoints: number,
}

export type Config = {
	maxText: number,
	maxAt: number,
	maxUnits: number,
	maxPointsPerUnit: number,
	maxThreshold: number,
	kinds: { [string]: boolean },
	realms: { [string]: boolean },
	increasingIncrements: boolean,
	firstGrantReachesRank: boolean,
}
local Reputation = {}
function Reputation.create(config: Config)
	local MAX_TEXT = config.maxText
	local MAX_AT = config.maxAt
	local MAX_UNITS = config.maxUnits
	local MAX_POINTS_PER_UNIT = config.maxPointsPerUnit
	local MAX_THRESHOLD = config.maxThreshold
	type Raw = { [unknown]: unknown }

	local REASONS: { string } = {
		"state_invalid",
		"event_shape_invalid",
		"event_id_invalid",
		"event_kind_invalid",
		"account_invalid",
		"realm_unknown",
		"season_invalid",
		"units_invalid",
		"time_invalid",
		"event_id_conflict",
		"time_regressed",
		"ladder_shape_invalid",
		"thresholds_invalid",
		"curve_not_front_loaded",
		"rates_incomplete",
		"rate_invalid",
		"first_rung_unreachable",
		"rank_names_incomplete",
		"rank_names_length_mismatch",
		"rank_name_invalid",
	}

	local KINDS = config.kinds
	local REALMS = config.realms

	local EVENT_FIELDS: { [string]: boolean } = {
		eventId = true,
		kind = true,
		accountId = true,
		realmId = true,
		seasonId = true,
		units = true,
		at = true,
	}

	local STATE_FIELDS: { [string]: boolean } = {
		events = true,
	}

	local LADDER_FIELDS: { [string]: boolean } = {
		seasonId = true,
		thresholds = true,
		pointsPerUnit = true,
		rankNames = true,
	}

	type Context = {
		rows: { Event },
		ids: { [string]: number },
		lastAt: number,
	}

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function integral(value: unknown): boolean
		return finite(value) and value == math.floor(value)
	end

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_TEXT
	end

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" then
			return false
		end
		for key in value do
			if type(key) ~= "string" or fields[key] ~= true then
				return false
			end
		end
		return true
	end

	local function denseLength(value: unknown): number?
		if type(value) ~= "table" then
			return nil
		end
		local count = 0
		for key in value do
			if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
				return nil
			end
			count += 1
		end
		for index = 1, count do
			if (value)[index] == nil then
				return nil
			end
		end
		return count
	end

	local function projectEvent(value: unknown): (Event?, string?)
		if not hasOnlyFields(value, EVENT_FIELDS) then
			return nil, "event_shape_invalid"
		end
		local source = value
		if not text(source.eventId) then
			return nil, "event_id_invalid"
		end
		if type(source.kind) ~= "string" or KINDS[source.kind] ~= true then
			return nil, "event_kind_invalid"
		end
		if not text(source.accountId) then
			return nil, "account_invalid"
		end
		if type(source.realmId) ~= "string" or REALMS[source.realmId] ~= true then
			return nil, "realm_unknown"
		end
		if not text(source.seasonId) then
			return nil, "season_invalid"
		end
		if not integral(source.units) or source.units < 1 or source.units > MAX_UNITS then
			return nil, "units_invalid"
		end
		if not finite(source.at) or source.at < 0 or source.at > MAX_AT then
			return nil, "time_invalid"
		end
		return Value.freezeDeep({
			eventId = source.eventId,
			kind = source.kind,
			accountId = source.accountId,
			realmId = source.realmId,
			seasonId = source.seasonId,
			units = source.units,
			at = source.at,
		}),
			nil
	end

	local function eventsEqual(a: Event, b: Event): boolean
		return a.eventId == b.eventId
			and a.kind == b.kind
			and a.accountId == b.accountId
			and a.realmId == b.realmId
			and a.seasonId == b.seasonId
			and a.units == b.units
			and a.at == b.at
	end

	local function projectLadder(value: unknown): (Ladder?, string?)
		if not hasOnlyFields(value, LADDER_FIELDS) then
			return nil, "ladder_shape_invalid"
		end
		local source = value
		if not text(source.seasonId) then
			return nil, "season_invalid"
		end

		local thresholdCount = denseLength(source.thresholds)
		if thresholdCount == nil or thresholdCount < 1 then
			return nil, "thresholds_invalid"
		end
		local thresholds: { number } = {}
		local previousThreshold = 0
		local previousIncrement: number? = nil
		for index = 1, thresholdCount do
			local candidate = (source.thresholds)[index]
			if not integral(candidate) or candidate < 1 or candidate > MAX_THRESHOLD then
				return nil, "thresholds_invalid"
			end
			local threshold = candidate
			local increment = threshold - previousThreshold
			if increment < 1 then
				return nil, "thresholds_invalid"
			end
			if config.increasingIncrements and previousIncrement ~= nil and increment <= previousIncrement then
				return nil, "curve_not_front_loaded"
			end
			thresholds[index] = threshold
			previousThreshold = threshold
			previousIncrement = increment
		end

		if type(source.pointsPerUnit) ~= "table" then
			return nil, "rates_incomplete"
		end
		local pointsPerUnit: { [string]: number } = {}
		local cheapestGrant: number? = nil
		for key, candidate in source.pointsPerUnit do
			if type(key) ~= "string" or KINDS[key] ~= true then
				return nil, "rates_incomplete"
			end
			if not integral(candidate) or candidate < 1 or candidate > MAX_POINTS_PER_UNIT then
				return nil, "rate_invalid"
			end
			local rate = candidate
			pointsPerUnit[key] = rate
			if cheapestGrant == nil or rate < cheapestGrant then
				cheapestGrant = rate
			end
		end
		for kind in KINDS do
			if pointsPerUnit[kind] == nil then
				return nil, "rates_incomplete"
			end
		end
		if cheapestGrant == nil or (config.firstGrantReachesRank and thresholds[1] > cheapestGrant) then
			return nil, "first_rung_unreachable"
		end

		if type(source.rankNames) ~= "table" then
			return nil, "rank_names_incomplete"
		end
		local rankNames: { [string]: { string } } = {}
		for realmId, ladder in source.rankNames do
			if type(realmId) ~= "string" or REALMS[realmId] ~= true then
				return nil, "rank_names_incomplete"
			end
			local nameCount = denseLength(ladder)
			if nameCount == nil then
				return nil, "rank_name_invalid"
			end
			if nameCount ~= thresholdCount then
				return nil, "rank_names_length_mismatch"
			end
			local names: { string } = {}
			local seen: { [string]: boolean } = {}
			for index = 1, nameCount do
				local candidate = (ladder)[index]
				if not text(candidate) or seen[candidate] == true then
					return nil, "rank_name_invalid"
				end
				local name = candidate
				seen[name] = true
				names[index] = name
			end
			rankNames[realmId] = Value.freezeDeep(names)
		end
		for realmId in REALMS do
			if rankNames[realmId] == nil then
				return nil, "rank_names_incomplete"
			end
		end

		return Value.freezeDeep({
			seasonId = source.seasonId,
			thresholds = Value.freezeDeep(thresholds),
			pointsPerUnit = Value.freezeDeep(pointsPerUnit),
			rankNames = Value.freezeDeep(rankNames),
		}),
			nil
	end

	local function newContext(): Context
		return {
			rows = {},
			ids = {},
			lastAt = 0,
		}
	end

	local function admit(ctx: Context, row: Event): string?
		if row.at < ctx.lastAt then
			return "time_regressed"
		end
		table.insert(ctx.rows, row)
		ctx.ids[row.eventId] = #ctx.rows
		ctx.lastAt = row.at
		return nil
	end

	local function project(value: unknown): (Context?, string?)
		if not hasOnlyFields(value, STATE_FIELDS) then
			return nil, "state_invalid"
		end
		local count = denseLength((value).events)
		if count == nil then
			return nil, "state_invalid"
		end
		local ctx = newContext()
		for index = 1, count do
			local row = projectEvent(((value).events)[index])
			if row == nil then
				return nil, "state_invalid"
			end
			if ctx.ids[row.eventId] ~= nil then
				return nil, "state_invalid"
			end
			local reason = admit(ctx, row)
			if reason ~= nil then
				return nil, "state_invalid"
			end
		end
		return ctx, nil
	end

	local function snapshot(ctx: Context): State
		local rows = table.clone(ctx.rows)
		return Value.freezeDeep({
			events = Value.freezeDeep(rows),
		})
	end

	local function rankOf(thresholds: { number }, points: number): number
		local rank = 0
		for index, threshold in thresholds do
			if points >= threshold then
				rank = index
			else
				break
			end
		end
		return rank
	end

	local Ledger = {}

	function Ledger.emptyState(): State
		return Value.freezeDeep({
			events = Value.freezeDeep({}),
		})
	end

	function Ledger.projectEvent(value: unknown): (Event?, string?)
		return projectEvent(value)
	end

	function Ledger.projectState(value: unknown): (State?, string?)
		local ctx, reason = project(value)
		if ctx == nil then
			return nil, reason
		end
		return snapshot(ctx), nil
	end

	function Ledger.projectLadder(value: unknown): (Ladder?, string?)
		return projectLadder(value)
	end

	function Ledger.pointsFor(ladder: Ladder, kind: EventKind, units: number): number
		return ladder.pointsPerUnit[kind] * units
	end

	function Ledger.rankFor(ladderValue: unknown, pointsValue: unknown): (number?, string?)
		local ladder, ladderReason = projectLadder(ladderValue)
		if ladder == nil then
			return nil, ladderReason
		end
		if not integral(pointsValue) or pointsValue < 0 then
			return nil, "units_invalid"
		end
		return rankOf(ladder.thresholds, pointsValue), nil
	end

	function Ledger.apply(stateValue: unknown, eventValue: unknown, ladderValue: unknown): (ApplyResult?, string?)
		local ctx, stateReason = project(stateValue)
		if ctx == nil then
			return nil, stateReason
		end
		local ladder, ladderReason = projectLadder(ladderValue)
		if ladder == nil then
			return nil, ladderReason
		end
		local row, eventReason = projectEvent(eventValue)
		if row == nil then
			return nil, eventReason
		end
		local existingIndex = ctx.ids[row.eventId]
		if existingIndex ~= nil then
			if not eventsEqual(ctx.rows[existingIndex], row) then
				return nil, "event_id_conflict"
			end
			return Value.freezeDeep({
				state = snapshot(ctx),
				replayed = true,
				points = 0,
			}), nil
		end
		local reason = admit(ctx, row)
		if reason ~= nil then
			return nil, reason
		end
		return Value.freezeDeep({
			state = snapshot(ctx),
			replayed = false,
			points = ladder.pointsPerUnit[row.kind] * row.units,
		}),
			nil
	end

	function Ledger.standings(stateValue: unknown, ladderValue: unknown): ({ Standing }?, string?)
		local ctx, stateReason = project(stateValue)
		if ctx == nil then
			return nil, stateReason
		end
		local ladder, ladderReason = projectLadder(ladderValue)
		if ladder == nil then
			return nil, ladderReason
		end

		local keys: { string } = {}
		local pointsByKey: { [string]: number } = {}
		local accountByKey: { [string]: string } = {}
		local realmByKey: { [string]: string } = {}
		local seasonByKey: { [string]: string } = {}
		local lifetimeByRealmKey: { [string]: number } = {}
		for _, row in ctx.rows do
			local points = ladder.pointsPerUnit[row.kind] * row.units
			local realmKey = row.accountId .. "\0" .. row.realmId
			local key = realmKey .. "\0" .. row.seasonId
			if pointsByKey[key] == nil then
				pointsByKey[key] = 0
				accountByKey[key] = row.accountId
				realmByKey[key] = row.realmId
				seasonByKey[key] = row.seasonId
				table.insert(keys, key)
			end
			pointsByKey[key] += points
			lifetimeByRealmKey[realmKey] = (lifetimeByRealmKey[realmKey] or 0) + points
		end
		table.sort(keys)

		local rows: { Standing } = {}
		for index, key in keys do
			local points = pointsByKey[key]
			local rank = rankOf(ladder.thresholds, points)
			local realmId = realmByKey[key]
			local nextRankAt: number? = ladder.thresholds[rank + 1]
			local rankName: string? = nil
			if rank > 0 then
				rankName = ladder.rankNames[realmId][rank]
			end
			rows[index] = Value.freezeDeep({
				accountId = accountByKey[key],
				realmId = realmId,
				seasonId = seasonByKey[key],
				points = points,
				rank = rank,
				rankName = rankName,
				nextRankAt = nextRankAt,
				pointsToNextRank = if nextRankAt == nil then nil else nextRankAt - points,
				lifetimePoints = lifetimeByRealmKey[accountByKey[key] .. "\0" .. realmId],
			})
		end
		return Value.freezeDeep(rows), nil
	end

	Ledger.REASONS = Value.freezeDeep(REASONS)
	Ledger.KINDS = Value.freezeDeep(KINDS)
	Ledger.REALMS = Value.freezeDeep(REALMS)
	Ledger.MAX_TEXT = MAX_TEXT
	Ledger.MAX_AT = MAX_AT
	Ledger.MAX_UNITS = MAX_UNITS
	Ledger.MAX_POINTS_PER_UNIT = MAX_POINTS_PER_UNIT
	Ledger.MAX_THRESHOLD = MAX_THRESHOLD

	return Value.freezeDeep(Ledger)
end
return Value.freezeDeep(Reputation)
