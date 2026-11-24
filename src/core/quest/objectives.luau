--!strict

export type Targets = { [string]: string }

export type KindSpec = {
	event: string,
	required: { string },
	optional: { string }?,
	targetIdField: string?,
}

export type Objective = {
	id: string,
	kind: string,
	event: string?,
	targetId: string?,
	targets: Targets,
}

export type Quest = { id: string, objectives: { Objective } }

export type Event = {
	kind: string,
	questId: string?,
	objectiveId: string?,
	targets: Targets,
}

export type Binding = {
	questId: string,
	objectiveId: string,
	objectiveKind: string,
	event: string,
	targets: Targets,
}

export type Problem = { kind: string, field: string, detail: string }

export type EventContract = { kind: string, required: { string }, allowed: { [string]: boolean } }

export type Aliases = { [string]: { [string]: { [string]: { [string]: boolean } } } }

export type Config = {
	order: { string },
	kinds: { [string]: KindSpec },
	aliases: Aliases?,
}

export type Catalog = {
	kinds: () -> { string },
	events: () -> { string },
	known: (kind: string) -> boolean,
	contract: (event: string) -> EventContract?,
	eventOf: (objective: Objective) -> string?,
	targetsOf: (objective: Objective) -> Targets,
	validate: (objective: Objective) -> { Problem },
	binding: (questId: string, objective: Objective) -> Binding?,
	bindings: (quest: Quest) -> { Binding },
	matches: (event: Event, binding: Binding) -> boolean,
	bindingsFor: (quests: { Quest }, event: Event) -> { Binding },
}

local Objectives = {}

function Objectives.catalog(config: Config): Catalog
	local order = table.clone(config.order)
	local kinds = config.kinds
	local aliases: Aliases = config.aliases or {}
	for _, kind in order do
		assert(kinds[kind] ~= nil, "objective kind " .. kind .. " has no specification")
	end

	local function eventOf(objective: Objective): string?
		if objective.event ~= nil and objective.event ~= "" then
			return objective.event
		end
		local spec = kinds[objective.kind]
		return if spec ~= nil then spec.event else nil
	end

	local function targetsOf(objective: Objective): Targets
		local targets: Targets = {}
		for field, value in objective.targets do
			if field ~= "" and value ~= "" then
				targets[field] = value
			end
		end
		local targetId = objective.targetId
		if targetId ~= nil and targetId ~= "" then
			local spec = kinds[objective.kind]
			local field = if spec ~= nil and spec.targetIdField ~= nil then spec.targetIdField else "targetId"
			if targets[field] == nil then
				targets[field] = targetId
			end
		end
		return targets
	end

	local function binding(questId: string, objective: Objective): Binding?
		local event = eventOf(objective)
		if event == nil then
			return nil
		end
		return {
			questId = questId,
			objectiveId = objective.id,
			objectiveKind = objective.kind,
			event = event,
			targets = targetsOf(objective),
		}
	end

	local function bindings(quest: Quest): { Binding }
		local out: { Binding } = {}
		for _, objective in quest.objectives do
			local found = binding(quest.id, objective)
			if found ~= nil then
				table.insert(out, found)
			end
		end
		return out
	end

	local function targetMatches(event: Event, field: string, expected: string): boolean
		local actual = event.targets[field]
		if actual == expected then
			return true
		end
		local byField = aliases[event.kind]
		local byExpected = if byField ~= nil then byField[field] else nil
		local accepted = if byExpected ~= nil then byExpected[expected] else nil
		return accepted ~= nil and actual ~= nil and accepted[actual] == true
	end

	local function matches(event: Event, candidate: Binding): boolean
		if event.kind ~= candidate.event then
			return false
		end
		if event.questId ~= nil and event.questId ~= candidate.questId then
			return false
		end
		if event.objectiveId ~= nil and event.objectiveId ~= candidate.objectiveId then
			return false
		end
		for field, expected in candidate.targets do
			if not targetMatches(event, field, expected) then
				return false
			end
		end
		return true
	end

	return {
		kinds = function(): { string }
			return table.clone(order)
		end,
		events = function(): { string }
			local out: { string } = {}
			local seen: { [string]: boolean } = {}
			for _, kind in order do
				local event = kinds[kind].event
				if not seen[event] then
					seen[event] = true
					table.insert(out, event)
				end
			end
			return out
		end,
		known = function(kind: string): boolean
			return kinds[kind] ~= nil
		end,
		contract = function(event: string): EventContract?
			local required: { string } = {}
			local allowed: { [string]: boolean } = {}
			local found = false
			for _, kind in order do
				local spec = kinds[kind]
				if spec.event == event then
					found = true
					for _, field in spec.required do
						if not allowed[field] then
							table.insert(required, field)
						end
						allowed[field] = true
					end
					for _, field in spec.optional or {} do
						allowed[field] = true
					end
				end
			end
			return if found then { kind = event, required = required, allowed = allowed } else nil
		end,
		eventOf = eventOf,
		targetsOf = targetsOf,
		validate = function(objective: Objective): { Problem }
			local problems: { Problem } = {}
			local spec = kinds[objective.kind]
			if spec == nil then
				table.insert(problems, {
					kind = "bad_value",
					field = "kind",
					detail = "unknown objective kind: " .. objective.kind,
				})
				return problems
			end
			local targets = targetsOf(objective)
			for _, field in spec.required do
				if targets[field] == nil then
					table.insert(problems, {
						kind = "missing_target",
						field = field,
						detail = ("objective kind '%s' requires %s or a targetId alias"):format(objective.kind, field),
					})
				end
			end
			return problems
		end,
		binding = binding,
		bindings = bindings,
		matches = matches,
		bindingsFor = function(quests: { Quest }, event: Event): { Binding }
			local out: { Binding } = {}
			for _, quest in quests do
				for _, candidate in bindings(quest) do
					if matches(event, candidate) then
						table.insert(out, candidate)
					end
				end
			end
			return out
		end,
	}
end

return Objectives
