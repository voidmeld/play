--!strict
local Value = require("../internal/value")

export type Status = "carried" | "dropped" | "banked" | "lost"

export type Cause = "death" | "disconnect" | "teleport"

export type Claim = {
	claimId: string,
	materialId: string,
	count: number,
	originActorId: string,
	status: Status,
	holderId: string,
}

export type Drop = {
	dropId: string,
	actorId: string,
	cause: Cause,
	droppedAtSec: number,
	expiresAtSec: number,
	claimIds: { string },
	recoveredBy: string?,
	expired: boolean,
}

export type Total = {
	materialId: string,
	count: number,
}

export type Extraction = {
	extractionId: string,
	actorId: string,
	campId: string,
	atSec: number,
	claimIds: { string },
	totals: { Total },
}

export type State = {
	lastClockSec: number,
	claims: { Claim },
	drops: { Drop },
	extractions: { Extraction },
}

export type Intent = {
	eventId: string,
	kind: string,
	materialId: string,
	count: number,
	actorId: string,
	at: number,
}

export type CommandKind = "carry" | "release" | "recover" | "expire" | "extract"

export type Command = {
	claimIds: { string }?,
	kind: CommandKind,
	claimId: string?,
	actorId: string?,
	materialId: string?,
	count: number?,
	dropId: string?,
	cause: Cause?,
	expiresAtSec: number?,
	extractionId: string?,
	campId: string?,
}

type RawCommand = { [string]: unknown, kind: CommandKind }

export type Result = {
	state: State,
	replayed: boolean,
	carriedCount: number,
	droppedCount: number,
	recoveredCount: number,
	expiredCount: number,
	bankedCount: number,
	dropId: string?,
	extractionId: string?,
	intents: { Intent },
}

export type CensusRow = {
	materialId: string,
	carried: number,
	dropped: number,
	banked: number,
	lost: number,
}

export type Config = {
	maxText: number,
	maxCount: number,
	maxAt: number,
	ledgerEventKind: string,
	intentPrefix: string,
	intentSeparator: string,
}
local Cargo = {}
function Cargo.create(config: Config)
	local MAX_TEXT = config.maxText
	local MAX_COUNT = config.maxCount
	local MAX_AT = config.maxAt
	local LEDGER_EVENT_KIND = config.ledgerEventKind
	local INTENT_PREFIX = config.intentPrefix
	local INTENT_SEPARATOR = config.intentSeparator

	local REASONS: { string } = {
		"state_invalid",
		"command_shape_invalid",
		"command_kind_invalid",
		"clock_invalid",
		"clock_regressed",
		"actor_invalid",
		"claim_invalid",
		"material_invalid",
		"count_invalid",
		"drop_invalid",
		"cause_invalid",
		"expiry_invalid",
		"camp_invalid",
		"extraction_invalid",
		"intent_id_too_long",
		"claim_conflict",
		"drop_conflict",
		"extraction_conflict",
		"unknown_drop",
		"drop_taken",
		"drop_expired",
		"drop_live",
		"nothing_carried",
	}

	local STATUSES: { [string]: boolean } = {
		carried = true,
		dropped = true,
		banked = true,
		lost = true,
	}

	local CAUSES: { [string]: boolean } = {
		death = true,
		disconnect = true,
		teleport = true,
	}

	local COMMAND_KINDS: { [string]: boolean } = {
		carry = true,
		release = true,
		recover = true,
		expire = true,
		extract = true,
	}

	local STATE_FIELDS: { [string]: boolean } = {
		lastClockSec = true,
		claims = true,
		drops = true,
		extractions = true,
	}

	local CLAIM_FIELDS: { [string]: boolean } = {
		claimId = true,
		materialId = true,
		count = true,
		originActorId = true,
		status = true,
		holderId = true,
	}

	local DROP_FIELDS: { [string]: boolean } = {
		dropId = true,
		actorId = true,
		cause = true,
		droppedAtSec = true,
		expiresAtSec = true,
		claimIds = true,
		recoveredBy = true,
		expired = true,
	}

	local TOTAL_FIELDS: { [string]: boolean } = {
		materialId = true,
		count = true,
	}

	local EXTRACTION_FIELDS: { [string]: boolean } = {
		extractionId = true,
		actorId = true,
		campId = true,
		atSec = true,
		claimIds = true,
		totals = true,
	}

	local COMMAND_FIELDS: { [string]: boolean } = {
		claimIds = true,
		kind = true,
		claimId = true,
		actorId = true,
		materialId = true,
		count = true,
		dropId = true,
		cause = true,
		expiresAtSec = true,
		extractionId = true,
		campId = true,
	}

	local CARRY_FIELDS: { [string]: boolean } = {
		kind = true,
		claimId = true,
		actorId = true,
		materialId = true,
		count = true,
	}

	local RELEASE_FIELDS: { [string]: boolean } = {
		kind = true,
		dropId = true,
		actorId = true,
		cause = true,
		expiresAtSec = true,
	}

	local RECOVER_FIELDS: { [string]: boolean } = {
		kind = true,
		dropId = true,
		actorId = true,
	}

	local EXPIRE_FIELDS: { [string]: boolean } = {
		kind = true,
		dropId = true,
	}

	local EXTRACT_FIELDS: { [string]: boolean } = {
		claimIds = true,
		kind = true,
		extractionId = true,
		actorId = true,
		campId = true,
	}

	local FIELDS_BY_KIND: { [string]: { [string]: boolean } } = {
		carry = CARRY_FIELDS,
		release = RELEASE_FIELDS,
		recover = RECOVER_FIELDS,
		expire = EXPIRE_FIELDS,
		extract = EXTRACT_FIELDS,
	}

	type Context = {
		lastClockSec: number,
		claims: { Claim },
		claimIndex: { [string]: number },
		drops: { Drop },
		dropIndex: { [string]: number },
		extractions: { Extraction },
		extractionIndex: { [string]: number },
	}

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function integral(value: unknown): boolean
		return (type(value) == "number" and finite(value)) and value == math.floor(value)
	end

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_TEXT
	end

	local function clock(value: unknown): boolean
		return (type(value) == "number" and finite(value)) and value >= 0 and value <= MAX_AT
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
		local rows = Value.dense(value, math.huge, false)
		return if rows == nil then nil else #rows
	end

	local function projectClaim(value: unknown): Claim?
		if not hasOnlyFields(value, CLAIM_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		if
			not (type(source.claimId) == "string" and text(source.claimId))
			or not (type(source.materialId) == "string" and text(source.materialId))
			or not (type(source.originActorId) == "string" and text(source.originActorId))
			or not (type(source.holderId) == "string" and text(source.holderId))
		then
			return nil
		end
		if
			not (type(source.count) == "number" and integral(source.count))
			or source.count < 1
			or source.count > MAX_COUNT
		then
			return nil
		end
		if
			source.status ~= "carried"
			and source.status ~= "dropped"
			and source.status ~= "banked"
			and source.status ~= "lost"
		then
			return nil
		end
		return {
			claimId = source.claimId,
			materialId = source.materialId,
			count = source.count,
			originActorId = source.originActorId,
			status = source.status,
			holderId = source.holderId,
		}
	end

	local function projectIdList(value: unknown): { string }?
		local count = denseLength(value)
		if count == nil then
			return nil
		end
		local rows: { string } = {}
		local seen: { [string]: boolean } = {}
		for index = 1, count do
			local id = assert(Value.raw(value))[index]
			if not (type(id) == "string" and text(id)) or seen[id] == true then
				return nil
			end
			seen[id] = true
			rows[index] = id
		end
		return rows
	end

	local function projectDrop(value: unknown): Drop?
		if not hasOnlyFields(value, DROP_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		if
			not (type(source.dropId) == "string" and text(source.dropId))
			or not (type(source.actorId) == "string" and text(source.actorId))
		then
			return nil
		end
		if source.cause ~= "death" and source.cause ~= "disconnect" and source.cause ~= "teleport" then
			return nil
		end
		if
			not (type(source.droppedAtSec) == "number" and clock(source.droppedAtSec))
			or not (type(source.expiresAtSec) == "number" and clock(source.expiresAtSec))
		then
			return nil
		end
		if source.expiresAtSec <= source.droppedAtSec then
			return nil
		end
		if type(source.expired) ~= "boolean" then
			return nil
		end
		if source.recoveredBy ~= nil and not (type(source.recoveredBy) == "string" and text(source.recoveredBy)) then
			return nil
		end
		if source.recoveredBy ~= nil and source.expired then
			return nil
		end
		local claimIds = projectIdList(source.claimIds)
		if claimIds == nil then
			return nil
		end
		return {
			dropId = source.dropId,
			actorId = source.actorId,
			cause = source.cause,
			droppedAtSec = source.droppedAtSec,
			expiresAtSec = source.expiresAtSec,
			claimIds = claimIds,
			recoveredBy = source.recoveredBy,
			expired = source.expired,
		}
	end

	local function projectTotals(value: unknown): { Total }?
		local count = denseLength(value)
		if count == nil or count < 1 then
			return nil
		end
		local rows: { Total } = {}
		local previous: string? = nil
		for index = 1, count do
			local row = Value.raw(assert(Value.raw(value))[index])
			if row == nil or not hasOnlyFields(row, TOTAL_FIELDS) then
				return nil
			end
			if not (type(row.materialId) == "string" and text(row.materialId)) then
				return nil
			end
			if not (type(row.count) == "number" and integral(row.count)) or row.count < 1 or row.count > MAX_COUNT then
				return nil
			end
			if previous ~= nil and row.materialId <= previous then
				return nil
			end
			previous = row.materialId
			rows[index] = { materialId = row.materialId, count = row.count }
		end
		return rows
	end

	local function projectExtraction(value: unknown): Extraction?
		if not hasOnlyFields(value, EXTRACTION_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		if
			not (type(source.extractionId) == "string" and text(source.extractionId))
			or not (type(source.actorId) == "string" and text(source.actorId))
			or not (type(source.campId) == "string" and text(source.campId))
		then
			return nil
		end
		if not (type(source.atSec) == "number" and clock(source.atSec)) then
			return nil
		end
		local claimIds = projectIdList(source.claimIds)
		if claimIds == nil or #claimIds < 1 then
			return nil
		end
		local totals = projectTotals(source.totals)
		if totals == nil then
			return nil
		end
		return {
			extractionId = source.extractionId,
			actorId = source.actorId,
			campId = source.campId,
			atSec = source.atSec,
			claimIds = claimIds,
			totals = totals,
		}
	end

	local function coherent(ctx: Context): boolean
		for _, drop in ctx.drops do
			if drop.droppedAtSec > ctx.lastClockSec then
				return false
			end
			local open = drop.recoveredBy == nil and not drop.expired
			for _, claimId in drop.claimIds do
				local index = ctx.claimIndex[claimId]
				if index == nil then
					return false
				end
				local claim = ctx.claims[index]
				if open then
					if claim.status ~= "dropped" or claim.holderId ~= drop.dropId then
						return false
					end
				elseif drop.expired then
					if claim.status ~= "lost" or claim.holderId ~= drop.dropId then
						return false
					end
				elseif claim.holderId == drop.dropId then
					return false
				end
			end
		end

		for _, extraction in ctx.extractions do
			if extraction.atSec > ctx.lastClockSec then
				return false
			end
			local sums: { [string]: number } = {}
			for _, claimId in extraction.claimIds do
				local index = ctx.claimIndex[claimId]
				if index == nil then
					return false
				end
				local claim = ctx.claims[index]
				if claim.status ~= "banked" or claim.holderId ~= extraction.extractionId then
					return false
				end
				sums[claim.materialId] = (sums[claim.materialId] or 0) + claim.count
			end
			local declared = 0
			for _, total in extraction.totals do
				if sums[total.materialId] ~= total.count then
					return false
				end
				declared += 1
			end
			local distinct = 0
			for _ in sums do
				distinct += 1
			end
			if declared ~= distinct then
				return false
			end
		end

		local membership: { [string]: boolean } = {}
		for _, drop in ctx.drops do
			for _, claimId in drop.claimIds do
				local key = drop.dropId .. "\0" .. claimId
				membership[key] = true
			end
		end
		for _, extraction in ctx.extractions do
			for _, claimId in extraction.claimIds do
				local key = extraction.extractionId .. "\0" .. claimId
				membership[key] = true
			end
		end

		for _, claim in ctx.claims do
			if claim.status == "carried" then
				continue
			end
			if claim.status == "banked" then
				if ctx.extractionIndex[claim.holderId] == nil then
					return false
				end
			else
				local dropIndex = ctx.dropIndex[claim.holderId]
				if dropIndex == nil then
					return false
				end
				local drop = ctx.drops[dropIndex]
				if claim.status == "dropped" and (drop.expired or drop.recoveredBy ~= nil) then
					return false
				end
				if claim.status == "lost" and not drop.expired then
					return false
				end
			end
			if membership[claim.holderId .. "\0" .. claim.claimId] ~= true then
				return false
			end
		end

		return true
	end

	local function project(value: unknown): (Context?, string?)
		if not hasOnlyFields(value, STATE_FIELDS) then
			return nil, "state_invalid"
		end
		local source = assert(Value.raw(value))
		if not (type(source.lastClockSec) == "number" and clock(source.lastClockSec)) then
			return nil, "state_invalid"
		end

		local ctx: Context = {
			lastClockSec = source.lastClockSec,
			claims = {},
			claimIndex = {},
			drops = {},
			dropIndex = {},
			extractions = {},
			extractionIndex = {},
		}

		local claimCount = denseLength(source.claims)
		if claimCount == nil then
			return nil, "state_invalid"
		end
		for index = 1, claimCount do
			local claim = projectClaim(assert(Value.raw(source.claims))[index])
			if claim == nil or ctx.claimIndex[claim.claimId] ~= nil then
				return nil, "state_invalid"
			end
			ctx.claims[index] = claim
			ctx.claimIndex[claim.claimId] = index
		end

		local dropCount = denseLength(source.drops)
		if dropCount == nil then
			return nil, "state_invalid"
		end
		for index = 1, dropCount do
			local drop = projectDrop(assert(Value.raw(source.drops))[index])
			if drop == nil or ctx.dropIndex[drop.dropId] ~= nil then
				return nil, "state_invalid"
			end
			ctx.drops[index] = drop
			ctx.dropIndex[drop.dropId] = index
		end

		local extractionCount = denseLength(source.extractions)
		if extractionCount == nil then
			return nil, "state_invalid"
		end
		for index = 1, extractionCount do
			local extraction = projectExtraction(assert(Value.raw(source.extractions))[index])
			if extraction == nil or ctx.extractionIndex[extraction.extractionId] ~= nil then
				return nil, "state_invalid"
			end
			ctx.extractions[index] = extraction
			ctx.extractionIndex[extraction.extractionId] = index
		end

		if not coherent(ctx) then
			return nil, "state_invalid"
		end
		return ctx, nil
	end

	local function frozenClaim(claim: Claim): Claim
		return Value.freezeDeep({
			claimId = claim.claimId,
			materialId = claim.materialId,
			count = claim.count,
			originActorId = claim.originActorId,
			status = claim.status,
			holderId = claim.holderId,
		})
	end

	local function frozenDrop(drop: Drop): Drop
		return Value.freezeDeep({
			dropId = drop.dropId,
			actorId = drop.actorId,
			cause = drop.cause,
			droppedAtSec = drop.droppedAtSec,
			expiresAtSec = drop.expiresAtSec,
			claimIds = Value.freezeDeep(table.clone(drop.claimIds)),
			recoveredBy = drop.recoveredBy,
			expired = drop.expired,
		})
	end

	local function frozenExtraction(extraction: Extraction): Extraction
		local totals: { Total } = {}
		for index, total in extraction.totals do
			totals[index] = Value.freezeDeep({ materialId = total.materialId, count = total.count })
		end
		return Value.freezeDeep({
			extractionId = extraction.extractionId,
			actorId = extraction.actorId,
			campId = extraction.campId,
			atSec = extraction.atSec,
			claimIds = Value.freezeDeep(table.clone(extraction.claimIds)),
			totals = Value.freezeDeep(totals),
		})
	end

	local function snapshot(ctx: Context): State
		local claims: { Claim } = {}
		for index, claim in ctx.claims do
			claims[index] = frozenClaim(claim)
		end
		local drops: { Drop } = {}
		for index, drop in ctx.drops do
			drops[index] = frozenDrop(drop)
		end
		local extractions: { Extraction } = {}
		for index, extraction in ctx.extractions do
			extractions[index] = frozenExtraction(extraction)
		end
		return Value.freezeDeep({
			lastClockSec = ctx.lastClockSec,
			claims = Value.freezeDeep(claims),
			drops = Value.freezeDeep(drops),
			extractions = Value.freezeDeep(extractions),
		})
	end

	local function baseResult(ctx: Context): Result
		return {
			state = snapshot(ctx),
			replayed = false,
			carriedCount = 0,
			droppedCount = 0,
			recoveredCount = 0,
			expiredCount = 0,
			bankedCount = 0,
			dropId = nil,
			extractionId = nil,
			intents = Value.freezeDeep({}),
		}
	end

	local function carriedUnits(ctx: Context, actorId: string): number
		local total = 0
		for _, claim in ctx.claims do
			if claim.status == "carried" and claim.holderId == actorId then
				total += claim.count
			end
		end
		return total
	end

	local function carriedIndices(ctx: Context, actorId: string): { number }
		local rows: { number } = {}
		for index, claim in ctx.claims do
			if claim.status == "carried" and claim.holderId == actorId then
				table.insert(rows, index)
			end
		end
		return rows
	end

	local function validCommand(value: unknown): (RawCommand?, string?)
		local source = Value.raw(value)
		if source == nil or not hasOnlyFields(value, COMMAND_FIELDS) then
			return nil, "command_shape_invalid"
		end
		local kind = source.kind
		if kind ~= "carry" and kind ~= "release" and kind ~= "recover" and kind ~= "expire" and kind ~= "extract" then
			return nil, "command_kind_invalid"
		end
		if not hasOnlyFields(value, FIELDS_BY_KIND[kind]) then
			return nil, "command_shape_invalid"
		end
		local command: RawCommand = { kind = kind }
		for key, entry in source do
			if type(key) == "string" and key ~= "kind" then
				command[key] = entry
			end
		end
		return command, nil
	end

	local function intentsOf(extraction: Extraction): ({ Intent }?, string?)
		local rows: { Intent } = {}
		for index, total in extraction.totals do
			local eventId = table.concat({ INTENT_PREFIX, extraction.extractionId, total.materialId }, INTENT_SEPARATOR)
			if #eventId > MAX_TEXT then
				return nil, "intent_id_too_long"
			end
			rows[index] = Value.freezeDeep({
				eventId = eventId,
				kind = LEDGER_EVENT_KIND,
				materialId = total.materialId,
				count = total.count,
				actorId = extraction.actorId,
				at = extraction.atSec,
			})
		end
		return Value.freezeDeep(rows), nil
	end

	local function stepCarry(ctx: Context, command: RawCommand): (Result?, string?)
		if not (type(command.claimId) == "string" and text(command.claimId)) then
			return nil, "claim_invalid"
		end
		if not (type(command.actorId) == "string" and text(command.actorId)) then
			return nil, "actor_invalid"
		end
		if not (type(command.materialId) == "string" and text(command.materialId)) then
			return nil, "material_invalid"
		end
		if
			not (type(command.count) == "number" and integral(command.count))
			or command.count < 1
			or command.count > MAX_COUNT
		then
			return nil, "count_invalid"
		end
		local claimId = command.claimId
		local actorId = command.actorId
		local materialId = command.materialId
		local count = command.count

		local existingIndex = ctx.claimIndex[claimId]
		if existingIndex ~= nil then
			local existing = ctx.claims[existingIndex]
			if existing.materialId ~= materialId or existing.count ~= count or existing.originActorId ~= actorId then
				return nil, "claim_conflict"
			end
			local result = baseResult(ctx)
			result.replayed = true
			result.carriedCount = carriedUnits(ctx, actorId)
			return result, nil
		end

		local index = #ctx.claims + 1
		ctx.claims[index] = {
			claimId = claimId,
			materialId = materialId,
			count = count,
			originActorId = actorId,
			status = "carried",
			holderId = actorId,
		}
		ctx.claimIndex[claimId] = index

		local result = baseResult(ctx)
		result.carriedCount = carriedUnits(ctx, actorId)
		return result, nil
	end

	local function stepRelease(ctx: Context, command: RawCommand, nowSec: number): (Result?, string?)
		if not (type(command.dropId) == "string" and text(command.dropId)) then
			return nil, "drop_invalid"
		end
		if not (type(command.actorId) == "string" and text(command.actorId)) then
			return nil, "actor_invalid"
		end
		if command.cause ~= "death" and command.cause ~= "disconnect" and command.cause ~= "teleport" then
			return nil, "cause_invalid"
		end
		if
			not (type(command.expiresAtSec) == "number" and clock(command.expiresAtSec))
			or command.expiresAtSec <= nowSec
		then
			return nil, "expiry_invalid"
		end
		local dropId = command.dropId
		local actorId = command.actorId
		local cause: Cause = command.cause
		local expiresAtSec = command.expiresAtSec

		local existingIndex = ctx.dropIndex[dropId]
		if existingIndex ~= nil then
			local existing = ctx.drops[existingIndex]
			if existing.actorId ~= actorId or existing.cause ~= cause or existing.expiresAtSec ~= expiresAtSec then
				return nil, "drop_conflict"
			end
			local result = baseResult(ctx)
			result.replayed = true
			result.dropId = dropId
			result.carriedCount = carriedUnits(ctx, actorId)
			return result, nil
		end

		local indices = carriedIndices(ctx, actorId)
		local claimIds: { string } = {}
		local moved = 0
		for _, index in indices do
			local claim = ctx.claims[index]
			claim.status = "dropped"
			claim.holderId = dropId
			table.insert(claimIds, claim.claimId)
			moved += claim.count
		end

		local dropIndex = #ctx.drops + 1
		ctx.drops[dropIndex] = {
			dropId = dropId,
			actorId = actorId,
			cause = cause,
			droppedAtSec = nowSec,
			expiresAtSec = expiresAtSec,
			claimIds = claimIds,
			recoveredBy = nil,
			expired = false,
		}
		ctx.dropIndex[dropId] = dropIndex

		local result = baseResult(ctx)
		result.dropId = dropId
		result.droppedCount = moved
		result.carriedCount = carriedUnits(ctx, actorId)
		return result, nil
	end

	local function stepRecover(ctx: Context, command: RawCommand, nowSec: number): (Result?, string?)
		if not (type(command.dropId) == "string" and text(command.dropId)) then
			return nil, "drop_invalid"
		end
		if not (type(command.actorId) == "string" and text(command.actorId)) then
			return nil, "actor_invalid"
		end
		local dropId = command.dropId
		local actorId = command.actorId

		local dropIndex = ctx.dropIndex[dropId]
		if dropIndex == nil then
			return nil, "unknown_drop"
		end
		local drop = ctx.drops[dropIndex]
		if drop.expired then
			return nil, "drop_expired"
		end
		if drop.recoveredBy ~= nil then
			if drop.recoveredBy == actorId then
				local result = baseResult(ctx)
				result.replayed = true
				result.dropId = dropId
				result.carriedCount = carriedUnits(ctx, actorId)
				return result, nil
			end
			return nil, "drop_taken"
		end
		if nowSec >= drop.expiresAtSec then
			return nil, "drop_expired"
		end

		local moved = 0
		for _, claimId in drop.claimIds do
			local claim = ctx.claims[ctx.claimIndex[claimId]]
			claim.status = "carried"
			claim.holderId = actorId
			moved += claim.count
		end
		drop.recoveredBy = actorId

		local result = baseResult(ctx)
		result.dropId = dropId
		result.recoveredCount = moved
		result.carriedCount = carriedUnits(ctx, actorId)
		return result, nil
	end

	local function stepExpire(ctx: Context, command: RawCommand, nowSec: number): (Result?, string?)
		if not (type(command.dropId) == "string" and text(command.dropId)) then
			return nil, "drop_invalid"
		end
		local dropId = command.dropId

		local dropIndex = ctx.dropIndex[dropId]
		if dropIndex == nil then
			return nil, "unknown_drop"
		end
		local drop = ctx.drops[dropIndex]
		if drop.recoveredBy ~= nil then
			return nil, "drop_taken"
		end
		if drop.expired then
			local result = baseResult(ctx)
			result.replayed = true
			result.dropId = dropId
			return result, nil
		end
		if nowSec < drop.expiresAtSec then
			return nil, "drop_live"
		end

		local moved = 0
		for _, claimId in drop.claimIds do
			local claim = ctx.claims[ctx.claimIndex[claimId]]
			claim.status = "lost"
			moved += claim.count
		end
		drop.expired = true

		local result = baseResult(ctx)
		result.dropId = dropId
		result.expiredCount = moved
		return result, nil
	end

	local function stepExtract(ctx: Context, command: RawCommand, nowSec: number): (Result?, string?)
		if not (type(command.extractionId) == "string" and text(command.extractionId)) then
			return nil, "extraction_invalid"
		end
		if not (type(command.actorId) == "string" and text(command.actorId)) then
			return nil, "actor_invalid"
		end
		if not (type(command.campId) == "string" and text(command.campId)) then
			return nil, "camp_invalid"
		end
		local extractionId = command.extractionId
		local actorId = command.actorId
		local campId = command.campId

		local existingIndex = ctx.extractionIndex[extractionId]
		if existingIndex ~= nil then
			local existing = ctx.extractions[existingIndex]
			if existing.actorId ~= actorId or existing.campId ~= campId then
				return nil, "extraction_conflict"
			end
			local intents, intentReason = intentsOf(existing)
			if intents == nil then
				return nil, intentReason
			end
			local result = baseResult(ctx)
			result.replayed = true
			result.extractionId = extractionId
			result.intents = intents
			result.carriedCount = carriedUnits(ctx, actorId)
			for _, total in existing.totals do
				result.bankedCount += total.count
			end
			return result, nil
		end

		local indices = carriedIndices(ctx, actorId)
		if command.claimIds ~= nil then
			local selected = projectIdList(command.claimIds)
			if selected == nil or #selected == 0 then
				return nil, "claim_invalid"
			end
			local wanted = {}
			for _, claimId in selected do
				wanted[claimId] = true
			end
			local filtered = {}
			for _, index in indices do
				if wanted[ctx.claims[index].claimId] then
					table.insert(filtered, index)
				end
			end
			if #filtered ~= #selected then
				return nil, "claim_invalid"
			end
			indices = filtered
		end
		if #indices == 0 then
			return nil, "nothing_carried"
		end

		local claimIds: { string } = {}
		local sums: { [string]: number } = {}
		local materialIds: { string } = {}
		local banked = 0
		for _, index in indices do
			local claim = ctx.claims[index]
			if sums[claim.materialId] == nil then
				sums[claim.materialId] = 0
				table.insert(materialIds, claim.materialId)
			end
			sums[claim.materialId] += claim.count
			if sums[claim.materialId] > MAX_COUNT then
				return nil, "count_invalid"
			end
			banked += claim.count
			table.insert(claimIds, claim.claimId)
		end
		table.sort(materialIds)

		local totals: { Total } = {}
		for position, materialId in materialIds do
			totals[position] = { materialId = materialId, count = sums[materialId] }
		end

		local extraction: Extraction = {
			extractionId = extractionId,
			actorId = actorId,
			campId = campId,
			atSec = nowSec,
			claimIds = claimIds,
			totals = totals,
		}
		local intents, intentReason = intentsOf(extraction)
		if intents == nil then
			return nil, intentReason
		end

		for _, index in indices do
			local claim = ctx.claims[index]
			claim.status = "banked"
			claim.holderId = extractionId
		end
		local extractionIndex = #ctx.extractions + 1
		ctx.extractions[extractionIndex] = extraction
		ctx.extractionIndex[extractionId] = extractionIndex

		local result = baseResult(ctx)
		result.extractionId = extractionId
		result.bankedCount = banked
		result.intents = intents
		result.carriedCount = carriedUnits(ctx, actorId)
		return result, nil
	end

	local Claims = {}

	function Claims.emptyState(): State
		return Value.freezeDeep({
			lastClockSec = 0,
			claims = Value.freezeDeep({}),
			drops = Value.freezeDeep({}),
			extractions = Value.freezeDeep({}),
		})
	end

	function Claims.projectState(value: unknown): (State?, string?)
		local ctx, reason = project(value)
		if ctx == nil then
			return nil, reason
		end
		return snapshot(ctx), nil
	end

	function Claims.retireTransient(stateValue: unknown): (State?, string?)
		local ctx, reason = project(stateValue)
		if ctx == nil then
			return nil, reason
		end
		local claims = {}
		for _, claim in ctx.claims do
			if claim.status == "carried" or claim.status == "dropped" then
				table.insert(claims, frozenClaim(claim))
			end
		end
		local drops = {}
		for _, drop in ctx.drops do
			if not drop.expired and drop.recoveredBy == nil then
				table.insert(drops, frozenDrop(drop))
			end
		end
		return Value.freezeDeep({
			lastClockSec = ctx.lastClockSec,
			claims = Value.freezeDeep(claims),
			drops = Value.freezeDeep(drops),
			extractions = Value.freezeDeep({}),
		}),
			nil
	end

	function Claims.step(stateValue: unknown, commandValue: unknown, nowSecValue: unknown): (Result?, string?)
		local ctx, stateReason = project(stateValue)
		if ctx == nil then
			return nil, stateReason
		end
		local command, commandReason = validCommand(commandValue)
		if command == nil then
			return nil, commandReason
		end
		if not (type(nowSecValue) == "number" and clock(nowSecValue)) then
			return nil, "clock_invalid"
		end
		local nowSec = nowSecValue
		if nowSec < ctx.lastClockSec then
			return nil, "clock_regressed"
		end
		ctx.lastClockSec = nowSec

		if command.kind == "carry" then
			return stepCarry(ctx, command)
		elseif command.kind == "release" then
			return stepRelease(ctx, command, nowSec)
		elseif command.kind == "recover" then
			return stepRecover(ctx, command, nowSec)
		elseif command.kind == "expire" then
			return stepExpire(ctx, command, nowSec)
		end
		return stepExtract(ctx, command, nowSec)
	end

	function Claims.carriedOf(stateValue: unknown, actorIdValue: unknown): ({ Total }?, string?)
		local ctx, reason = project(stateValue)
		if ctx == nil then
			return nil, reason
		end
		if not (type(actorIdValue) == "string" and text(actorIdValue)) then
			return nil, "actor_invalid"
		end
		local actorId = actorIdValue
		local sums: { [string]: number } = {}
		local materialIds: { string } = {}
		for _, claim in ctx.claims do
			if claim.status == "carried" and claim.holderId == actorId then
				if sums[claim.materialId] == nil then
					sums[claim.materialId] = 0
					table.insert(materialIds, claim.materialId)
				end
				sums[claim.materialId] += claim.count
			end
		end
		table.sort(materialIds)
		local rows: { Total } = {}
		for index, materialId in materialIds do
			rows[index] = Value.freezeDeep({ materialId = materialId, count = sums[materialId] })
		end
		return Value.freezeDeep(rows), nil
	end

	function Claims.census(stateValue: unknown): ({ CensusRow }?, string?)
		local ctx, reason = project(stateValue)
		if ctx == nil then
			return nil, reason
		end
		local byMaterial: { [string]: CensusRow } = {}
		local materialIds: { string } = {}
		for _, claim in ctx.claims do
			local row = byMaterial[claim.materialId]
			if row == nil then
				row = { materialId = claim.materialId, carried = 0, dropped = 0, banked = 0, lost = 0 }
				byMaterial[claim.materialId] = row
				table.insert(materialIds, claim.materialId)
			end
			local live = row
			if claim.status == "carried" then
				live.carried += claim.count
			elseif claim.status == "dropped" then
				live.dropped += claim.count
			elseif claim.status == "banked" then
				live.banked += claim.count
			else
				live.lost += claim.count
			end
		end
		table.sort(materialIds)
		local rows: { CensusRow } = {}
		for index, materialId in materialIds do
			rows[index] = Value.freezeDeep(byMaterial[materialId])
		end
		return Value.freezeDeep(rows), nil
	end

	function Claims.openDrops(stateValue: unknown, nowSecValue: unknown): ({ Drop }?, string?)
		local ctx, reason = project(stateValue)
		if ctx == nil then
			return nil, reason
		end
		if not (type(nowSecValue) == "number" and clock(nowSecValue)) then
			return nil, "clock_invalid"
		end
		local nowSec = nowSecValue
		local rows: { Drop } = {}
		for _, drop in ctx.drops do
			if drop.recoveredBy == nil and not drop.expired and nowSec < drop.expiresAtSec then
				table.insert(rows, frozenDrop(drop))
			end
		end
		return Value.freezeDeep(rows), nil
	end

	Claims.REASONS = Value.freezeDeep(REASONS)
	Claims.STATUSES = Value.freezeDeep(STATUSES)
	Claims.CAUSES = Value.freezeDeep(CAUSES)
	Claims.COMMAND_KINDS = Value.freezeDeep(COMMAND_KINDS)
	Claims.LEDGER_EVENT_KIND = LEDGER_EVENT_KIND
	Claims.INTENT_PREFIX = INTENT_PREFIX
	Claims.MAX_TEXT = MAX_TEXT
	Claims.MAX_COUNT = MAX_COUNT
	Claims.MAX_AT = MAX_AT

	return Value.freezeDeep(Claims)
end
return Value.freezeDeep(Cargo)
