--!strict

export type QuestStatus = string

export type MarkerState = "turnIn" | "available" | "inProgress" | "notCurrentlyAcceptable"

export type QuestEntry = {
	status: QuestStatus,
	available: boolean,
}

export type Config = {
	aliases: { [string]: string },
	completedStatus: string,
	inProgressStatus: string,
	unstartedStatus: string,
}
local System = {}
function System.markers(config: Config)
	local function rank(state: MarkerState?): number
		if state == "turnIn" then
			return 4
		elseif state == "available" then
			return 3
		elseif state == "inProgress" then
			return 2
		elseif state == "notCurrentlyAcceptable" then
			return 1
		end
		return 0
	end

	local function normalizedStatus(status: QuestStatus): QuestStatus
		return config.aliases[status] or status
	end

	local function stateForEntry(entry: QuestEntry): MarkerState?
		local status = normalizedStatus(entry.status)
		if status == config.completedStatus then
			return "turnIn"
		elseif status == config.inProgressStatus then
			return "inProgress"
		elseif status == config.unstartedStatus then
			if entry.available then
				return "available"
			end
			return "notCurrentlyAcceptable"
		end
		return nil
	end

	local function stateForGiver(entries: { QuestEntry }): MarkerState?
		local bestRank = 0
		local best: MarkerState? = nil
		for _, entry in entries do
			local state: MarkerState? = stateForEntry(entry)
			local stateRank = rank(state)
			if stateRank > bestRank then
				bestRank = stateRank
				best = state
			end
		end
		return best
	end

	local function isActionable(state: MarkerState?): boolean
		return state == "turnIn" or state == "available"
	end

	local function shownState(state: MarkerState?, occluded: boolean, visibleAtDistance: boolean): MarkerState?
		if occluded or not visibleAtDistance then
			return nil
		end
		return state
	end

	local function colorForState<T>(
		palette: {
			questTurnIn: T,
			questAvailable: T,
			questInProgress: T,
			questLocked: T,
		},
		state: MarkerState?
	): T
		if state == "turnIn" then
			return palette.questTurnIn
		elseif state == "available" then
			return palette.questAvailable
		elseif state == "inProgress" then
			return palette.questInProgress
		end
		return palette.questLocked
	end

	return {
		stateForEntry = stateForEntry,
		stateForGiver = stateForGiver,
		isActionable = isActionable,
		shownState = shownState,
		colorForState = colorForState,
	}
end
return System
