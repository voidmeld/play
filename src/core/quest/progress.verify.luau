--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Progress = require("./progress")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type Objective = { key: string, amount: number, enemy: string? }
type Definition = {
	key: string,
	steps: { Objective },
	domain: string?,
	before: { string }?,
	either: { string }?,
	group: string?,
	path: string?,
}
type Actor = { archetype: string?, rank: number?, domain: string?, log: { [string]: Progress.QuestProgress } }
type Content = {
	definitions: { Definition }?,
	gates: { [string]: Progress.Rule }?,
	paths: { [string]: Progress.Branch }?,
	options: { [string]: { [string]: boolean } }?,
}
local realms: { [string]: boolean } = { domain_a = true, domain_b = true }
local core = Progress.progress({
	content = function(content: Content): Progress.ContentView<Definition>
		return {
			quests = content.definitions,
			questRules = content.gates,
			exclusiveQuestBranches = content.paths,
			exclusiveQuestGroups = content.options,
		}
	end,
	quest = function(quest: Definition): Progress.QuestView<Objective>
		return {
			id = quest.key,
			objectives = quest.steps,
			realm = quest.domain,
			prereqQuestIds = quest.before,
			prereqAnyQuestIds = quest.either,
			exclusiveQuestGroupId = quest.group,
			exclusiveQuestArmId = quest.path,
		}
	end,
	objective = function(objective: Objective): Progress.ObjectiveView
		return { id = objective.key, target = objective.amount, mobId = objective.enemy }
	end,
	actor = function(actor: Actor): Progress.ActorView
		return { quests = actor.log, classId = actor.archetype, level = actor.rank, realm = actor.domain }
	end,
	canonicalRealm = function(value: unknown): boolean
		return type(value) == "string" and realms[value] == true
	end,
	statuses = {
		inProgress = "active",
		completed = "done",
		turnedIn = "claimed",
		replayInProgress = "repeat_active",
		replayCompleted = "repeat_done",
		replayTurnedIn = "repeat_claimed",
	},
})
local function rig()
	local quest: Definition = {
		key = "q",
		domain = "domain_a",
		steps = { { key = "first", amount = 1, enemy = "creature" }, { key = "second", amount = 2 } },
	}
	local content: Content =
		{ definitions = { quest }, gates = { q = { classId = "class_a", minLevel = 3, ordered = true } } }
	local actor: Actor = { archetype = "class_a", rank = 3, domain = "domain_a", log = {} }
	return { quest = quest, content = content, actor = actor }
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("opaque quest progress", function()
		it("returns original definitions and objectives through schema projections", function()
			local r = rig()
			expect(core.questById(r.content, "q")):toBe(r.quest)
			local found, index = core.questForMob(r.content, "creature")
			expect(found):toBe(r.quest)
			expect(index):toBe(1)
			expect(core.questForObjective(r.content, "second")):toBe(r.quest)
			expect(#core.questRows(nil)):toBe(0)
			expect(core.objectiveTarget({ key = "invalid", amount = 0 })):toBe(1)
		end)
		it("requires current domain class and level and refuses repeated admission", function()
			local r = rig()
			expect(core.canAcceptQuest(r.content, r.actor, r.quest)):toBe(true)
			r.actor.rank = 2
			expect(core.canAcceptQuest(r.content, r.actor, r.quest)):toBe(false)
			r.actor.rank = 3
			r.actor.archetype = "class_b"
			expect(core.canAcceptQuest(r.content, r.actor, r.quest)):toBe(false)
			r.actor.archetype = "class_a"
			r.actor.domain = "domain_b"
			expect(core.canAcceptQuest(r.content, r.actor, r.quest)):toBe(false)
			r.actor.domain = "domain_a"
			r.actor.log.q = { status = "active", step = 0 }
			expect(core.canAcceptQuest(r.content, r.actor, r.quest)):toBe(false)
			expect(core.canAcceptQuest(r.content, nil, r.quest)):toBe(false)
		end)
		it("requires all prerequisites and one alternative with replay claims admitted", function()
			local r = rig()
			r.quest.before = { "before" }
			r.quest.either = { "left", "right" }
			expect(core.prereqsMet(r.quest, r.actor)):toBe(false)
			r.actor.log.before = { status = "repeat_claimed", step = 0 }
			r.actor.log.left = { status = "done", step = 0 }
			expect(core.prereqsMet(r.quest, r.actor)):toBe(false)
			r.actor.log.right = { status = "claimed", step = 0 }
			expect(core.prereqsMet(r.quest, r.actor)):toBe(true)
			expect(core.actorIsReplaying(r.actor)):toBe(true)
		end)
		it("reconciles only the completed ordered prefix on a caller-owned draft", function()
			local r = rig()
			local progress: Progress.QuestProgress =
				{ status = "repeat_active", step = 0, counts = { first = 1, second = 1 } }
			r.actor.log.q = progress
			core.reconcileOrdered(r.content, r.actor)
			expect(progress.step):toBe(1)
			expect(core.completedCount(r.quest, progress)):toBe(1)
			expect(core.claimableObjective(r.content, r.quest, progress, "first")):toBeNil()
			expect(core.claimableObjective(r.content, r.quest, progress, nil)):toBe(r.quest.steps[2])
			assert(progress.counts ~= nil)
			progress.counts.second = 2
			core.reconcileOrdered(r.content, r.actor)
			expect(progress.step):toBe(2)
			expect(progress.status):toBe("repeat_done")
			expect(core.claimableObjective(r.content, r.quest, progress, nil)):toBeNil()
		end)
		it("refuses malformed or conflicting exclusive paths without reserving state", function()
			local r = rig()
			r.quest.group = "group"
			expect(core.allowedExclusiveBranch(r.content, r.quest, r.actor)):toBe(false)
			r.quest.path = "a"
			r.content.paths = { q = { groupId = "group", armId = "a" }, other = { groupId = "group", armId = "b" } }
			r.content.options = { group = { a = true, b = true } }
			expect(core.allowedExclusiveBranch(r.content, r.quest, r.actor)):toBe(true)
			r.actor.log.other = { status = "claimed", step = 0 }
			expect(core.allowedExclusiveBranch(r.content, r.quest, r.actor)):toBe(false)
			expect(core.progressFor(r.actor, "q")):toBeNil()
		end)
	end)
end
