--!strict
local Journal = require("./journal")
export type QuestProgress = Journal.QuestProgress
export type Rule = { classId: string?, minLevel: number?, ordered: boolean? }
export type Branch = { groupId: string, armId: string }
export type Statuses = {
	inProgress: string,
	completed: string,
	turnedIn: string,
	replayInProgress: string,
	replayCompleted: string,
	replayTurnedIn: string,
}
export type Config<C, A, Q, O> = {
	read questRows: (C) -> { Q }?,
	read questId: (Q) -> string,
	read objectives: (Q) -> { O },
	read objectiveId: (O) -> string,
	read objectiveMobId: (O) -> string?,
	read objectiveTarget: (O) -> number?,
	read progress: (A) -> { [string]: QuestProgress }?,
	read classId: (A) -> string?,
	read level: (A) -> number?,
	read actorRealm: (A) -> unknown,
	read questRealm: (Q) -> unknown,
	read canonicalRealm: (unknown) -> boolean,
	read prerequisites: (Q) -> { string }?,
	read anyPrerequisites: (Q) -> { string }?,
	read exclusiveGroupId: (Q) -> unknown,
	read exclusiveArmId: (Q) -> unknown,
	read rules: (C) -> { [string]: Rule }?,
	read branches: (C) -> { [string]: Branch }?,
	read groups: (C) -> { [string]: { [string]: boolean } }?,
	read statuses: Statuses,
}
export type API<C, A, Q, O> = {
	read questRows: (C?) -> { Q },
	read questById: (C?, string) -> Q?,
	read objectiveIndexForMob: (Q, string) -> number?,
	read questForMob: (C?, string) -> (Q?, number),
	read questForObjective: (C?, string) -> Q?,
	read objectiveTarget: (O) -> number,
	read progressFor: (A, string) -> QuestProgress?,
	read seededQuests: ({ [string]: string }?) -> { [string]: QuestProgress }?,
	read questInProgress: (string?) -> boolean,
	read isReplayStatus: (string?) -> boolean,
	read actorIsReplaying: (A) -> boolean,
	read completedQuestStatus: (string?) -> string,
	read questRule: (C?, string) -> Rule?,
	read allowedClass: (C?, Q, A) -> boolean,
	read allowedLevel: (C?, Q, A) -> boolean,
	read canonicalRealm: (unknown) -> boolean,
	read allowedRealm: (Q, A) -> boolean,
	read isOrdered: (C?, string) -> boolean,
	read objectiveComplete: (QuestProgress, O) -> boolean,
	read completedCount: (Q, QuestProgress) -> number,
	read prereqsMet: (Q, A) -> boolean,
	read allowedExclusiveBranch: (C?, Q, A) -> boolean,
	read canAcceptQuest: (C?, A?, Q?) -> boolean,
	read completedPrefix: (Q, QuestProgress) -> number,
	read reconcileOrdered: (C?, A) -> (),
	read claimableObjective: (C?, Q, QuestProgress, string?) -> O?,
	read EMPTY_QUESTS: { Q },
	read NO_QUESTS: { [string]: QuestProgress },
}
local function progress<C, A, Q, O>(config: Config<C, A, Q, O>): API<C, A, Q, O>
	config = table.freeze(table.clone(config))
	local vocabulary = table.freeze(table.clone(config.statuses))
	local statuses: { [string]: boolean } = {}
	for _, status in
		{
			vocabulary.inProgress,
			vocabulary.completed,
			vocabulary.turnedIn,
			vocabulary.replayInProgress,
			vocabulary.replayCompleted,
			vocabulary.replayTurnedIn,
		}
	do
		assert(status ~= "" and not statuses[status], "invalid quest status vocabulary")
		statuses[status] = true
	end
	local EMPTY_QUESTS: { Q } = {}

	local Quest = {}

	function Quest.questRows(content: C?): { Q }
		if content == nil then
			return EMPTY_QUESTS
		end
		return config.questRows(content) or EMPTY_QUESTS
	end

	function Quest.questById(content: C?, questId: string): Q?
		for _, quest in Quest.questRows(content) do
			if config.questId(quest) == questId then
				return quest
			end
		end
		return nil
	end

	function Quest.objectiveIndexForMob(quest: Q, mobId: string): number?
		for index, objective in config.objectives(quest) do
			if config.objectiveMobId(objective) == mobId then
				return index
			end
		end
		return nil
	end

	function Quest.questForMob(content: C?, mobId: string): (Q?, number)
		for _, quest in Quest.questRows(content) do
			local index = Quest.objectiveIndexForMob(quest, mobId)
			if index ~= nil then
				return quest, index
			end
		end
		return nil, 0
	end

	function Quest.questForObjective(content: C?, objectiveId: string): Q?
		for _, quest in Quest.questRows(content) do
			for _, objective in config.objectives(quest) do
				if config.objectiveId(objective) == objectiveId then
					return quest
				end
			end
		end
		return nil
	end

	function Quest.objectiveTarget(objective: O): number
		local target = config.objectiveTarget(objective)
		return if type(target) == "number" and target >= 1 then math.floor(target) else 1
	end

	local NO_QUESTS: { [string]: QuestProgress } = {}

	function Quest.progressFor(actor: A, questId: string): QuestProgress?
		local quests = config.progress(actor)
		return if quests == nil then nil else quests[questId]
	end

	function Quest.seededQuests(questStatus: { [string]: string }?): { [string]: QuestProgress }?
		if questStatus == nil then
			return nil
		end
		local out: { [string]: QuestProgress } = {}
		for questId, status in questStatus do
			out[questId] = { status = status, step = 0 }
		end
		return out
	end

	function Quest.questInProgress(status: string?): boolean
		return status == vocabulary.inProgress or status == vocabulary.replayInProgress
	end

	function Quest.isReplayStatus(status: string?): boolean
		return status == vocabulary.replayInProgress
			or status == vocabulary.replayCompleted
			or status == vocabulary.replayTurnedIn
	end

	function Quest.actorIsReplaying(actor: A): boolean
		for _, progress in config.progress(actor) or NO_QUESTS do
			if Quest.isReplayStatus(progress.status) then
				return true
			end
		end
		return false
	end

	function Quest.completedQuestStatus(status: string?): string
		return if status == vocabulary.replayInProgress then vocabulary.replayCompleted else vocabulary.completed
	end

	function Quest.questRule(content: C?, questId: string): Rule?
		local rules: { [string]: Rule }? = if content == nil then nil else config.rules(content)
		return if rules == nil then nil else rules[questId]
	end

	function Quest.allowedClass(content: C?, quest: Q, actor: A): boolean
		local rule = Quest.questRule(content, config.questId(quest))
		local required = if rule == nil then nil else rule.classId
		return required == nil or config.classId(actor) == required
	end

	function Quest.allowedLevel(content: C?, quest: Q, actor: A): boolean
		local rule = Quest.questRule(content, config.questId(quest))
		local required = if rule == nil then nil else rule.minLevel
		local level = config.level(actor)
		return required == nil or (type(level) == "number" and level >= required)
	end

	function Quest.canonicalRealm(realm: unknown): boolean
		return config.canonicalRealm(realm)
	end

	function Quest.allowedRealm(quest: Q, actor: A): boolean
		return Quest.canonicalRealm(config.questRealm(quest))
			and Quest.canonicalRealm(config.actorRealm(actor))
			and config.actorRealm(actor) == config.questRealm(quest)
	end

	function Quest.isOrdered(content: C?, questId: string): boolean
		local rule = Quest.questRule(content, questId)
		return rule ~= nil and rule.ordered == true
	end

	function Quest.objectiveComplete(progress: QuestProgress, objective: O): boolean
		local counts = progress.counts
		local reached = if counts == nil then 0 else counts[config.objectiveId(objective)] or 0
		return reached >= Quest.objectiveTarget(objective)
	end

	function Quest.completedCount(quest: Q, progress: QuestProgress): number
		local done = 0
		for _, objective in config.objectives(quest) do
			if Quest.objectiveComplete(progress, objective) then
				done += 1
			end
		end
		return done
	end

	function Quest.prereqsMet(quest: Q, actor: A): boolean
		local prereqIds: { string } = config.prerequisites(quest) or {}
		for _, prereqId in prereqIds do
			local progress = Quest.progressFor(actor, prereqId)
			if
				progress == nil
				or (progress.status ~= vocabulary.turnedIn and progress.status ~= vocabulary.replayTurnedIn)
			then
				return false
			end
		end
		local alternatives = config.anyPrerequisites(quest)
		if alternatives ~= nil then
			local anyMet = false
			for _, prereqId in alternatives do
				local progress = Quest.progressFor(actor, prereqId)
				if
					progress ~= nil
					and (progress.status == vocabulary.turnedIn or progress.status == vocabulary.replayTurnedIn)
				then
					anyMet = true
					break
				end
			end
			if not anyMet then
				return false
			end
		end
		return true
	end

	function Quest.allowedExclusiveBranch(content: C?, quest: Q, actor: A): boolean
		local authoredGroupId = config.exclusiveGroupId(quest)
		local authoredArmId = config.exclusiveArmId(quest)
		if (authoredGroupId == nil) ~= (authoredArmId == nil) then
			return false
		end
		if authoredGroupId == nil then
			return true
		end
		if
			type(authoredGroupId) ~= "string"
			or authoredGroupId == ""
			or type(authoredArmId) ~= "string"
			or authoredArmId == ""
		then
			return false
		end
		local branches: { [string]: Branch }? = if content == nil then nil else config.branches(content)
		local groups: { [string]: { [string]: boolean } }? = if content == nil then nil else config.groups(content)
		if branches == nil or groups == nil then
			return false
		end
		local selected = branches[config.questId(quest)]
		local knownArms = groups[authoredGroupId]
		if
			selected == nil
			or selected.groupId ~= authoredGroupId
			or selected.armId ~= authoredArmId
			or knownArms == nil
			or knownArms[authoredArmId] ~= true
		then
			return false
		end
		for acceptedQuestId in config.progress(actor) or NO_QUESTS do
			local accepted = branches[acceptedQuestId]
			if accepted ~= nil and accepted.groupId == authoredGroupId and accepted.armId ~= authoredArmId then
				return false
			end
		end
		return true
	end

	function Quest.canAcceptQuest(content: C?, actor: A?, quest: Q?): boolean
		return actor ~= nil
			and quest ~= nil
			and Quest.allowedClass(content, quest, actor)
			and Quest.allowedLevel(content, quest, actor)
			and Quest.allowedRealm(quest, actor)
			and Quest.allowedExclusiveBranch(content, quest, actor)
			and Quest.prereqsMet(quest, actor)
			and Quest.progressFor(actor, config.questId(quest)) == nil
	end

	function Quest.completedPrefix(quest: Q, progress: QuestProgress): number
		local count = 0
		for _, objective in config.objectives(quest) do
			if not Quest.objectiveComplete(progress, objective) then
				break
			end
			count += 1
		end
		return count
	end

	function Quest.reconcileOrdered(content: C?, actor: A)
		for _, quest in Quest.questRows(content) do
			local progress = Quest.progressFor(actor, config.questId(quest))
			if
				progress ~= nil
				and progress.counts ~= nil
				and Quest.questInProgress(progress.status)
				and Quest.isOrdered(content, config.questId(quest))
			then
				progress.step = Quest.completedPrefix(quest, progress)
				if progress.step == #config.objectives(quest) then
					progress.status = Quest.completedQuestStatus(progress.status)
				end
			end
		end
	end

	function Quest.claimableObjective(content: C?, quest: Q, progress: QuestProgress, objectiveId: string?): O?
		if not Quest.questInProgress(progress.status) then
			return nil
		end
		if Quest.isOrdered(content, config.questId(quest)) then
			local objective = config.objectives(quest)[progress.step + 1]
			if objective == nil or (objectiveId ~= nil and config.objectiveId(objective) ~= objectiveId) then
				return nil
			end
			return objective
		end
		for _, objective in config.objectives(quest) do
			if
				not Quest.objectiveComplete(progress, objective)
				and (objectiveId == nil or config.objectiveId(objective) == objectiveId)
			then
				return objective
			end
		end
		return nil
	end

	Quest.EMPTY_QUESTS = EMPTY_QUESTS
	Quest.NO_QUESTS = NO_QUESTS
	return table.freeze(Quest)
end
return table.freeze({ progress = progress })
