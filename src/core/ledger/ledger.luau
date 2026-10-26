--!strict

export type EventKind = "grant" | "craft_consume" | "craft_yield" | "trade_out" | "trade_in"

export type Event = {
	eventId: string,
	kind: EventKind,
	materialId: string,
	count: number,
	actorId: string,
	at: number,
	groupId: string?,
	groupSize: number?,
}

export type State = {
	events: { Event },
}

export type ApplyResult = {
	state: State,
	replayed: boolean,
	settled: boolean,
	groupId: string?,
}

export type TornGroup = {
	groupId: string,
	groupSize: number,
	memberCount: number,
}

export type Config = {
	maxText: number,
	maxCount: number,
	maxAt: number,
	minGroupSize: number,
	maxGroupSize: number,
}

type Raw = { [unknown]: unknown }

local function raw(value: unknown): Raw?
	if type(value) ~= "table" then
		return nil
	end
	local out: Raw = {}
	for key, entry in value do
		out[key] = entry
	end
	return out
end

local function frozen<T>(value: T): T
	local probe: unknown = value
	if type(probe) == "table" and not table.isfrozen(probe) then
		table.freeze(probe)
	end
	return value
end

local REASONS: { string } = {
	"state_invalid",
	"event_shape_invalid",
	"event_id_invalid",
	"event_kind_invalid",
	"material_invalid",
	"count_invalid",
	"actor_invalid",
	"time_invalid",
	"group_forbidden",
	"group_id_invalid",
	"group_size_invalid",
	"event_id_conflict",
	"time_regressed",
	"group_sealed",
	"group_kind_mismatch",
	"group_size_mismatch",
	"group_actor_mismatch",
	"group_composition_invalid",
	"trade_unbalanced",
	"balance_insufficient",
}

local KINDS: { [string]: boolean } = {
	grant = true,
	craft_consume = true,
	craft_yield = true,
	trade_out = true,
	trade_in = true,
}

local GROUP_FAMILY: { [string]: string } = {
	craft_consume = "craft",
	craft_yield = "craft",
	trade_out = "trade",
	trade_in = "trade",
}

local SUBTRACTIVE: { [string]: boolean } = {
	craft_consume = true,
	trade_out = true,
}

local EVENT_FIELDS: { [string]: boolean } = {
	eventId = true,
	kind = true,
	materialId = true,
	count = true,
	actorId = true,
	at = true,
	groupId = true,
	groupSize = true,
}

local STATE_FIELDS: { [string]: boolean } = {
	events = true,
}

type Group = {
	family: string,
	size: number,
	actorId: string,
	members: { number },
	kindCounts: { [string]: number },
	outByMaterial: { [string]: number },
	inByMaterial: { [string]: number },
	complete: boolean,
}

type Context = {
	rows: { Event },
	ids: { [string]: number },
	lastAt: number,
	settled: { [string]: { [string]: number } },
	reserved: { [string]: { [string]: number } },
	groups: { [string]: Group },
}

export type Journal = {
	emptyState: () -> State,
	projectEvent: (unknown) -> (Event?, string?),
	projectState: (unknown) -> (State?, string?),
	apply: (unknown, unknown) -> (ApplyResult?, string?),
	balances: (unknown) -> ({ [string]: { [string]: number } }?, string?),
	available: (unknown, unknown, unknown) -> (number?, string?),
	tornGroups: (unknown) -> ({ TornGroup }?, string?),
	REASONS: { string },
	KINDS: { [string]: boolean },
}

local Ledger = {}

function Ledger.ledger(config: Config): Journal
	local function finite(value: unknown): number?
		if type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
			return value
		end
		return nil
	end

	local function integral(value: unknown): number?
		local number = finite(value)
		return if number ~= nil and number == math.floor(number) then number else nil
	end

	local function text(value: unknown): string?
		return if type(value) == "string" and #value > 0 and #value <= config.maxText then value else nil
	end

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): Raw?
		local source = raw(value)
		if source == nil then
			return nil
		end
		for key in source do
			if type(key) ~= "string" or fields[key] ~= true then
				return nil
			end
		end
		return source
	end

	local function denseLength(value: Raw): number?
		local count = 0
		for key in value do
			if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
				return nil
			end
			count += 1
		end
		for index = 1, count do
			if value[index] == nil then
				return nil
			end
		end
		return count
	end

	local function projectEvent(value: unknown): (Event?, string?)
		local source = hasOnlyFields(value, EVENT_FIELDS)
		if source == nil then
			return nil, "event_shape_invalid"
		end
		local eventId = text(source.eventId)
		if eventId == nil then
			return nil, "event_id_invalid"
		end
		local kind = source.kind
		if
			kind ~= "grant"
			and kind ~= "craft_consume"
			and kind ~= "craft_yield"
			and kind ~= "trade_out"
			and kind ~= "trade_in"
		then
			return nil, "event_kind_invalid"
		end
		local materialId = text(source.materialId)
		if materialId == nil then
			return nil, "material_invalid"
		end
		local count = integral(source.count)
		if count == nil or count < 1 or count > config.maxCount then
			return nil, "count_invalid"
		end
		local actorId = text(source.actorId)
		if actorId == nil then
			return nil, "actor_invalid"
		end
		local at = finite(source.at)
		if at == nil or at < 0 or at > config.maxAt then
			return nil, "time_invalid"
		end
		local groupId = text(source.groupId)
		local groupSize = integral(source.groupSize)
		if kind == "grant" then
			if source.groupId ~= nil or source.groupSize ~= nil then
				return nil, "group_forbidden"
			end
		else
			if groupId == nil then
				return nil, "group_id_invalid"
			end
			if groupSize == nil or groupSize < config.minGroupSize or groupSize > config.maxGroupSize then
				return nil, "group_size_invalid"
			end
		end
		local event: Event = {
			eventId = eventId,
			kind = kind,
			materialId = materialId,
			count = count,
			actorId = actorId,
			at = at,
			groupId = groupId,
			groupSize = groupSize,
		}
		return frozen(event), nil
	end

	local function eventsEqual(a: Event, b: Event): boolean
		return a.eventId == b.eventId
			and a.kind == b.kind
			and a.materialId == b.materialId
			and a.count == b.count
			and a.actorId == b.actorId
			and a.at == b.at
			and a.groupId == b.groupId
			and a.groupSize == b.groupSize
	end

	local function balanceOf(map: { [string]: { [string]: number } }, actorId: string, materialId: string): number
		local forActor = map[actorId]
		if forActor == nil then
			return 0
		end
		return forActor[materialId] or 0
	end

	local function addBalance(
		map: { [string]: { [string]: number } },
		actorId: string,
		materialId: string,
		delta: number
	)
		local forActor = map[actorId]
		if forActor == nil then
			forActor = {}
			map[actorId] = forActor
		end
		forActor[materialId] = (forActor[materialId] or 0) + delta
	end

	local function newContext(): Context
		return {
			rows = {},
			ids = {},
			lastAt = 0,
			settled = {},
			reserved = {},
			groups = {},
		}
	end

	local function admit(ctx: Context, row: Event): (string?, boolean, string?)
		if row.at < ctx.lastAt then
			return "time_regressed", false, nil
		end
		if row.kind == "grant" then
			addBalance(ctx.settled, row.actorId, row.materialId, row.count)
			table.insert(ctx.rows, row)
			ctx.ids[row.eventId] = #ctx.rows
			ctx.lastAt = row.at
			return nil, true, nil
		end
		local gid = assert(row.groupId)
		local size = assert(row.groupSize)
		local family = GROUP_FAMILY[row.kind]
		local group = ctx.groups[gid]
		if group ~= nil then
			if group.complete then
				return "group_sealed", false, gid
			end
			if group.family ~= family then
				return "group_kind_mismatch", false, gid
			end
			if group.size ~= size then
				return "group_size_mismatch", false, gid
			end
			if family == "craft" and group.actorId ~= row.actorId then
				return "group_actor_mismatch", false, gid
			end
		end
		local memberCount = if group ~= nil then #group.members + 1 else 1
		local completing = memberCount == size
		if completing then
			local kindCounts: { [string]: number } = {}
			if group ~= nil then
				for kind, total in group.kindCounts do
					kindCounts[kind] = total
				end
			end
			kindCounts[row.kind] = (kindCounts[row.kind] or 0) + 1
			if family == "craft" then
				if (kindCounts.craft_consume or 0) < 1 or (kindCounts.craft_yield or 0) < 1 then
					return "group_composition_invalid", false, gid
				end
			else
				if (kindCounts.trade_out or 0) < 1 or (kindCounts.trade_in or 0) < 1 then
					return "group_composition_invalid", false, gid
				end
				local outTotals: { [string]: number } = {}
				local inTotals: { [string]: number } = {}
				if group ~= nil then
					for materialId, total in group.outByMaterial do
						outTotals[materialId] = total
					end
					for materialId, total in group.inByMaterial do
						inTotals[materialId] = total
					end
				end
				if row.kind == "trade_out" then
					outTotals[row.materialId] = (outTotals[row.materialId] or 0) + row.count
				else
					inTotals[row.materialId] = (inTotals[row.materialId] or 0) + row.count
				end
				for materialId, total in outTotals do
					if inTotals[materialId] ~= total then
						return "trade_unbalanced", false, gid
					end
				end
				for materialId in inTotals do
					if outTotals[materialId] == nil then
						return "trade_unbalanced", false, gid
					end
				end
			end
		end
		if SUBTRACTIVE[row.kind] == true then
			local available = balanceOf(ctx.settled, row.actorId, row.materialId)
				- balanceOf(ctx.reserved, row.actorId, row.materialId)
			if available < row.count then
				return "balance_insufficient", false, gid
			end
		end
		if group == nil then
			group = {
				family = family,
				size = size,
				actorId = row.actorId,
				members = {},
				kindCounts = {},
				outByMaterial = {},
				inByMaterial = {},
				complete = false,
			}
			ctx.groups[gid] = group
		end
		local liveGroup = group
		table.insert(ctx.rows, row)
		ctx.ids[row.eventId] = #ctx.rows
		ctx.lastAt = row.at
		table.insert(liveGroup.members, #ctx.rows)
		liveGroup.kindCounts[row.kind] = (liveGroup.kindCounts[row.kind] or 0) + 1
		if row.kind == "trade_out" then
			liveGroup.outByMaterial[row.materialId] = (liveGroup.outByMaterial[row.materialId] or 0) + row.count
		elseif row.kind == "trade_in" then
			liveGroup.inByMaterial[row.materialId] = (liveGroup.inByMaterial[row.materialId] or 0) + row.count
		end
		if SUBTRACTIVE[row.kind] == true then
			addBalance(ctx.reserved, row.actorId, row.materialId, row.count)
		end
		if completing then
			liveGroup.complete = true
			for _, index in liveGroup.members do
				local member = ctx.rows[index]
				if SUBTRACTIVE[member.kind] == true then
					addBalance(ctx.settled, member.actorId, member.materialId, -member.count)
					addBalance(ctx.reserved, member.actorId, member.materialId, -member.count)
				else
					addBalance(ctx.settled, member.actorId, member.materialId, member.count)
				end
			end
			return nil, true, gid
		end
		return nil, false, gid
	end

	local function project(value: unknown): (Context?, string?)
		local source = hasOnlyFields(value, STATE_FIELDS)
		local events: Raw? = if source ~= nil then raw(source.events) else nil
		local count = if events ~= nil then denseLength(events) else nil
		if events == nil or count == nil then
			return nil, "state_invalid"
		end
		local ctx = newContext()
		for index = 1, count do
			local row = projectEvent(events[index])
			if row == nil or ctx.ids[row.eventId] ~= nil then
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
		return frozen({
			events = frozen(rows),
		})
	end

	local Journal = {}

	function Journal.emptyState(): State
		return frozen({
			events = frozen({}),
		})
	end

	function Journal.projectEvent(value: unknown): (Event?, string?)
		return projectEvent(value)
	end

	function Journal.projectState(value: unknown): (State?, string?)
		local ctx, reason = project(value)
		if ctx == nil then
			return nil, reason
		end
		return snapshot(ctx), nil
	end

	function Journal.apply(stateValue: unknown, eventValue: unknown): (ApplyResult?, string?)
		local ctx, stateReason = project(stateValue)
		if ctx == nil then
			return nil, stateReason
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
			local settled = true
			if row.groupId ~= nil then
				settled = ctx.groups[row.groupId].complete
			end
			return frozen({
				state = snapshot(ctx),
				replayed = true,
				settled = settled,
				groupId = row.groupId,
			}),
				nil
		end
		local reason, settled, groupId = admit(ctx, row)
		if reason ~= nil then
			return nil, reason
		end
		return frozen({
			state = snapshot(ctx),
			replayed = false,
			settled = settled,
			groupId = groupId,
		}),
			nil
	end

	function Journal.balances(stateValue: unknown): ({ [string]: { [string]: number } }?, string?)
		local ctx, reason = project(stateValue)
		if ctx == nil then
			return nil, reason
		end
		local totals: { [string]: { [string]: number } } = {}
		for actorId, forActor in ctx.settled do
			local rows: { [string]: number } = {}
			local hasRows = false
			for materialId, total in forActor do
				if total > 0 then
					rows[materialId] = total
					hasRows = true
				end
			end
			if hasRows then
				totals[actorId] = frozen(rows)
			end
		end
		return frozen(totals), nil
	end

	function Journal.available(stateValue: unknown, actorIdValue: unknown, materialIdValue: unknown): (number?, string?)
		local ctx, reason = project(stateValue)
		if ctx == nil then
			return nil, reason
		end
		local actorId = text(actorIdValue)
		if actorId == nil then
			return nil, "actor_invalid"
		end
		local materialId = text(materialIdValue)
		if materialId == nil then
			return nil, "material_invalid"
		end
		return balanceOf(ctx.settled, actorId, materialId) - balanceOf(ctx.reserved, actorId, materialId), nil
	end

	function Journal.tornGroups(stateValue: unknown): ({ TornGroup }?, string?)
		local ctx, reason = project(stateValue)
		if ctx == nil then
			return nil, reason
		end
		local groupIds: { string } = {}
		for groupId, group in ctx.groups do
			if not group.complete then
				table.insert(groupIds, groupId)
			end
		end
		table.sort(groupIds)
		local rows: { TornGroup } = {}
		for index, groupId in groupIds do
			local group = ctx.groups[groupId]
			rows[index] = frozen({
				groupId = groupId,
				groupSize = group.size,
				memberCount = #group.members,
			})
		end
		return frozen(rows), nil
	end

	Journal.REASONS = frozen(REASONS)
	Journal.KINDS = frozen(KINDS)
	return frozen(Journal)
end

return Ledger
