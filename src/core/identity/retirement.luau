--!strict

local Shape = require("../internal/shape")
local Value = require("../internal/value")

export type Deletion = { characterId: string, phase: string, fence: number }
export type Retirement = { operationId: string, fingerprint: string, fence: number }
export type View = {
	characterId: string,
	rosterHolds: boolean,
	deletion: Deletion | false,
	retirement: Retirement | false,
}
export type Decision = { action: string, reason: string }

export type Config = {
	read maxFence: number,
	read characterIdLimit: number,
	read operationIdLimit: number,
	read fingerprintLimit: number,
	read phaseLimit: number,
	read retiringPhases: { [string]: boolean },
	read restoringPhases: { [string]: boolean },
}

export type API = {
	read MAX_FENCE: number,
	read view: (raw: unknown) -> (View?, string?),
	read decide: (raw: unknown) -> Decision,
}

local function create(config: Config): API
	config = table.freeze(table.clone(config))
	for _, value in
		{
			config.maxFence,
			config.characterIdLimit,
			config.operationIdLimit,
			config.fingerprintLimit,
			config.phaseLimit,
		}
	do
		assert(Value.whole(value, 1, 9007199254740991) ~= nil, "invalid retirement limit")
	end
	local Plan = { MAX_FENCE = config.maxFence }
	local VIEW_FIELDS: { [string]: boolean } = {
		characterId = true,
		rosterHolds = true,
		deletion = true,
		retirement = true,
	}

	local DELETION_FIELDS: { [string]: boolean } = { characterId = true, phase = true, fence = true }
	local RETIREMENT_FIELDS: { [string]: boolean } = { operationId = true, fingerprint = true, fence = true }

	local RETIRING_PHASES = table.freeze(table.clone(config.retiringPhases))
	local RESTORING_PHASES = table.freeze(table.clone(config.restoringPhases))
	for phase, enabled in RETIRING_PHASES do
		assert(Value.opaque(phase, config.phaseLimit) ~= nil, "invalid retirement phase")
		assert(not enabled or not RESTORING_PHASES[phase], "ambiguous retirement phase")
	end
	for phase in RESTORING_PHASES do
		assert(Value.opaque(phase, config.phaseLimit) ~= nil, "invalid restoration phase")
	end

	local function exact(raw: unknown, fields: { [string]: boolean }): Shape.Raw?
		if type(raw) ~= "table" or getmetatable(raw) ~= nil then
			return nil
		end
		local row = Shape.raw(raw)
		if row == nil then
			return nil
		end
		for key in row do
			if type(key) ~= "string" or fields[key] ~= true then
				return nil
			end
		end
		for key in fields do
			if row[key] == nil then
				return nil
			end
		end
		return row
	end

	local function text(value: unknown, maximum: number): string?
		if type(value) == "string" and #value > 0 and #value <= maximum then
			return value
		end
		return nil
	end

	local function fence(value: unknown): number?
		if
			type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value % 1 == 0
			and value >= 1
			and value <= Plan.MAX_FENCE
		then
			return value
		end
		return nil
	end

	local function decision(action: string, reason: string): Decision
		local result: Decision = { action = action, reason = reason }
		return Shape.freezeDeep(result)
	end

	function Plan.view(raw: unknown): (View?, string?)
		local row = exact(raw, VIEW_FIELDS)
		if row == nil then
			return nil, "view_invalid"
		end
		local characterId = text(row.characterId, config.characterIdLimit)
		local rosterHolds = row.rosterHolds
		if characterId == nil or type(rosterHolds) ~= "boolean" then
			return nil, "view_invalid"
		end
		local deletion: Deletion | false = false
		if row.deletion ~= false then
			local candidate = exact(row.deletion, DELETION_FIELDS)
			if candidate == nil then
				return nil, "deletion_invalid"
			end
			local deletionCharacterId = text(candidate.characterId, config.characterIdLimit)
			local phase = text(candidate.phase, config.phaseLimit)
			local deletionFence = fence(candidate.fence)
			if deletionCharacterId == nil or phase == nil or deletionFence == nil then
				return nil, "deletion_invalid"
			end
			deletion = {
				characterId = deletionCharacterId,
				phase = phase,
				fence = deletionFence,
			}
		end
		local retirement: Retirement | false = false
		if row.retirement ~= false then
			local candidate = exact(row.retirement, RETIREMENT_FIELDS)
			if candidate == nil then
				return nil, "retirement_invalid"
			end
			local operationId = text(candidate.operationId, config.operationIdLimit)
			local fingerprint = text(candidate.fingerprint, config.fingerprintLimit)
			local retirementFence = fence(candidate.fence)
			if operationId == nil or fingerprint == nil or retirementFence == nil then
				return nil, "retirement_invalid"
			end
			retirement = {
				operationId = operationId,
				fingerprint = fingerprint,
				fence = retirementFence,
			}
		end
		local view: View = {
			characterId = characterId,
			rosterHolds = rosterHolds,
			deletion = deletion,
			retirement = retirement,
		}
		return Shape.freezeDeep(view), nil
	end

	function Plan.decide(raw: unknown): Decision
		local view, reason = Plan.view(raw)
		if view == nil then
			return decision("invalid", reason or "view_invalid")
		end
		local deletion: Deletion? = if view.deletion == false then nil else view.deletion
		if deletion ~= nil and deletion.characterId == view.characterId then
			if RETIRING_PHASES[deletion.phase] then
				return decision("retire", "deletion_in_progress")
			end
			if RESTORING_PHASES[deletion.phase] then
				return decision("restore", "deletion_compensating")
			end
			return decision("invalid", "phase_unknown")
		end
		if view.rosterHolds then
			if view.retirement ~= false then
				return decision("restore", "retirement_orphaned")
			end
			return decision("settled", "character_live")
		end
		if view.retirement == false then
			return decision("orphan", "roster_absent")
		end
		return decision("settled", "character_retired")
	end

	return table.freeze(Plan)
end

return table.freeze({ create = create })
