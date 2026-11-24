--!strict

local Objectives = require("./objectives")
local Value = require("../../kernel/value")

export type Objective = Objectives.Objective
export type Binding = Objectives.Binding
export type Event = Objectives.Event
export type Quest = Objectives.Quest
export type Problem = Objectives.Problem
export type Config = {
	catalog: Objectives.Catalog,
	targetFields: { string },
	eventField: string,
	targetsField: string,
	bespokeFields: { string },
	stillnessKinds: { [string]: boolean },
}

local System = {}
function System.lifecycle(config: Config)
	local catalog = config.catalog
	local function projectObjective(value: unknown): Objective?
		local raw = Value.raw(value)
		if raw == nil or type(raw.id) ~= "string" or type(raw.kind) ~= "string" then
			return nil
		end
		local targets: Objectives.Targets = {}
		local explicit = Value.raw(raw[config.targetsField])
		if explicit ~= nil then
			for field, entry in explicit do
				if type(field) == "string" and type(entry) == "string" and entry ~= "" then
					targets[field] = entry
				end
			end
		end
		for _, field in config.targetFields do
			local entry = raw[field]
			if type(entry) == "string" and entry ~= "" then
				targets[field] = entry
			end
		end
		local event = raw[config.eventField]
		return {
			id = raw.id,
			kind = raw.kind,
			targets = targets,
			targetId = if type(raw.targetId) == "string" and raw.targetId ~= "" then raw.targetId else nil,
			event = if type(event) == "string" and event ~= "" then event else nil,
		}
	end
	local function stillnessValid(value: unknown, kind: string, target: unknown): boolean
		local policy = Value.raw(value)
		if policy == nil or config.stillnessKinds[kind] ~= true or target ~= 1 then
			return false
		end
		local position = Value.raw(policy.position)
		if position == nil then
			return false
		end
		for _, field in { "durationSec", "radiusStuds", "maxDriftStuds" } do
			local entry = policy[field]
			if type(entry) ~= "number" or entry <= 0 or entry >= math.huge or entry ~= entry then
				return false
			end
		end
		for _, field in { "x", "y", "z" } do
			local entry = position[field]
			if type(entry) ~= "number" or entry <= -math.huge or entry >= math.huge or entry ~= entry then
				return false
			end
		end
		local drift, radius = policy.maxDriftStuds, policy.radiusStuds
		return type(drift) == "number" and type(radius) == "number" and drift <= radius
	end
	local function validateObjective(value: unknown): { Problem }
		local raw = Value.raw(value)
		local objective = projectObjective(value)
		if raw == nil or objective == nil then
			return { { kind = "bad_value", field = "kind", detail = "objective must have string id and kind" } }
		end
		local problems = catalog.validate(objective)
		if not catalog.known(objective.kind) then
			return problems
		end
		local function problem(kind: string, field: string, detail: string)
			table.insert(problems, { kind = kind, field = field, detail = detail })
		end
		if raw.stillness ~= nil and not stillnessValid(raw.stillness, objective.kind, raw.target) then
			table.insert(problems, 1, {
				kind = "bad_value",
				field = "stillness",
				detail = "stillness needs finite positive duration/radius/drift and a finite canonical position",
			})
		end
		if catalog.eventOf(objective) == nil then
			problem("untrackable_objective", config.eventField, "objective has no event kind")
		end
		local explicit = raw[config.targetsField]
		if explicit ~= nil then
			local fields = Value.raw(explicit)
			if fields == nil then
				problem("bad_value", config.targetsField, "eventTargets must be a string-keyed table")
			else
				for field, entry in fields do
					if type(field) ~= "string" or field == "" or type(entry) ~= "string" or entry == "" then
						problem("bad_value", config.targetsField, "eventTargets must contain non-empty strings")
					end
				end
			end
		end
		if raw.groupSize ~= nil then
			local size = raw.groupSize
			if type(size) ~= "number" or size <= 1 or size ~= math.floor(size) then
				problem("bad_value", "groupSize", "groupSize must be an integer greater than 1")
			end
		end
		for _, field in config.bespokeFields do
			if raw[field] ~= nil then
				problem("bespoke_script", field, "objective progress requires declarative data")
			end
		end
		return problems
	end
	local function bindingForObjective(questId: string, value: unknown): Binding?
		local objective = projectObjective(value)
		return if objective ~= nil then catalog.binding(questId, objective) else nil
	end
	return {
		projectObjective = projectObjective,
		validateObjective = validateObjective,
		bindingForObjective = bindingForObjective,
		catalog = catalog,
	}
end
return System
