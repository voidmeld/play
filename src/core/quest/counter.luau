--!strict

export type Band = {
	questId: string,
	minLevel: number,
}

export type Counts = {
	eligible: number,
	completed: number,
}

export type Config = { markerPrefix: string, completedStatus: string, labelFormat: string }
local System = {}
function System.counter(config: Config)
	local QuestCompletionCounter = {}

	QuestCompletionCounter.MARKER_PREFIX = config.markerPrefix

	function QuestCompletionCounter.questIdFromMarkerName(markerName: string): string?
		local prefix = QuestCompletionCounter.MARKER_PREFIX
		if string.sub(markerName, 1, #prefix) ~= prefix then
			return nil
		end
		local id = string.sub(markerName, #prefix + 1)
		return if id ~= "" then id else nil
	end

	function QuestCompletionCounter.count(
		bands: { Band }?,
		statusByQuestId: { [string]: string },
		level: number
	): Counts?
		if bands == nil or #bands == 0 then
			return nil
		end
		local eligible = 0
		local completed = 0
		for _, band in bands do
			if band.minLevel <= level then
				eligible += 1
				if statusByQuestId[band.questId] == config.completedStatus then
					completed += 1
				end
			end
		end
		return { eligible = eligible, completed = completed }
	end

	function QuestCompletionCounter.label(counts: Counts?): string
		if counts == nil or counts.eligible == 0 then
			return ""
		end
		return string.format(config.labelFormat, counts.completed, counts.eligible)
	end

	return QuestCompletionCounter
end
return System
