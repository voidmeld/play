--!strict

local Objectives = require("./objectives")
export type Config = { catalog: Objectives.Catalog, quests: { Objectives.Quest } }
export type TargetBinding = { questId: string, objectiveId: string, targetId: string }
local System = {}
function System.index(config: Config)
	local function objectiveBindings(): { Objectives.Binding }
		local out: { Objectives.Binding } = {}
		for _, quest in config.quests do
			for _, binding in config.catalog.bindings(quest) do
				table.insert(out, binding)
			end
		end
		return out
	end
	local function bindingsForEvent(event: Objectives.Event): { Objectives.Binding }
		local out: { Objectives.Binding } = {}
		for _, binding in objectiveBindings() do
			if config.catalog.matches(event, binding) then
				table.insert(out, binding)
			end
		end
		return out
	end
	local function byTarget(event: string, field: string): { [string]: { TargetBinding } }
		local out: { [string]: { TargetBinding } } = {}
		for _, binding in objectiveBindings() do
			local targetId = binding.targets[field]
			if binding.event == event and targetId ~= nil then
				local list = out[targetId]
				if list == nil then
					list = {}
					out[targetId] = list
				end
				table.insert(
					list,
					{ questId = binding.questId, objectiveId = binding.objectiveId, targetId = targetId }
				)
			end
		end
		return out
	end
	return { objectiveBindings = objectiveBindings, bindingsForEvent = bindingsForEvent, byTarget = byTarget }
end
return System
