--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./season")
local Shape = require("../social/shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local config: Module.Config = {
	weekSec = 604800,
	contributionBucketUnits = 33,
	doorCycleUnits = 10,
	receiptWindow = 128,
	maxSeasons = 16,
	maxRewards = 64,
	minWeeks = 8,
	maxWeeks = 12,
	maxObjectiveShare = 0.3,
	maxId = 128,
	maxTime = 1000000000000,
	maxXp = 1000000000,
	rewardKinds = { title = true, cosmetic = true, chronicle_mark = true },
	contributionKinds = { contribution = true, contribution_work = true },
	scopedKind = "contribution_work",
	allowanceGroups = { craft = "craft", gather = "craft", contribution = "work", contribution_work = "work" },
	milestoneKinds = { contribution_work = "contribution" },
	craftGroup = "craft",
	workGroup = "work",
	allowanceUnits = 150,
	allowanceSec = 3600,
	accountingPrefix = "chapter:",
	protectedSeasons = { ["track-a"] = true },
	maxSources = 32,
	maxObjectives = 256,
	maxSourceXp = 10000,
	maxSourceUnits = 100,
	maxTarget = 1000,
	maxBonusXp = 10000,
	maxLabel = 80,
	maxEventUnits = 1000,
}
local Core = Module.season(config)
local SeasonTrack: Module.AuthoredDefinition = {
	permanent = true,
	seasonId = "track-a",
	startsAtUnix = 1000000,
	weeks = 10,
	playSources = {
		{ kind = "quest_complete", xpPerUnit = 40, maxUnitsPerEvent = 1 },
		{ kind = "named_kill", xpPerUnit = 35, maxUnitsPerEvent = 1 },
		{ kind = "contribution", xpPerUnit = 3, maxUnitsPerEvent = 10 },
		{ kind = "contribution_work", xpPerUnit = 3, maxUnitsPerEvent = 10 },
		{ kind = "craft", xpPerUnit = 15, maxUnitsPerEvent = 3 },
		{ kind = "gather", xpPerUnit = 5, maxUnitsPerEvent = 5 },
	},
	objectives = {},
	rewards = {},
}
for week = 1, 10 do
	for i, kind in { "quest_complete", "contribution", "craft" } do
		table.insert(SeasonTrack.objectives, {
			objectiveId = ("m.%02d.%d"):format(week, i),
			week = week,
			kind = kind,
			target = if i == 1 then 5 elseif i == 2 then 30 else 2,
			bonusXp = 100,
			label = "Milestone",
		})
	end
end
for tier = 1, 20 do
	SeasonTrack.rewards[tier] = {
		tier = tier,
		threshold = tier * 500,
		kind = if tier % 5 == 0 then "title" elseif tier % 2 == 0 then "cosmetic" else "chronicle_mark",
		rewardId = "reward-" .. tier,
		label = "Reward " .. tier,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	local WEEK = Core.WEEK_SEC
	local DAY = 24 * 60 * 60
	type State = Module.State
	type Definition = Module.Definition
	type Projection = Module.Projection
	type Tracks = { [string]: State }

	local function track(): Definition
		local definition, reason = Core.definition(SeasonTrack)
		assert(definition ~= nil, reason)
		return definition
	end

	local function apply(state: State?, eventId: string, kind: string, units: number, atSec: number)
		local event: Module.Event = { eventId = eventId, kind = kind, units = units, atSec = atSec }
		if kind == "contribution" or kind == "contribution_work" then
			event.contested = true
		end
		return Core.apply(state, track(), event)
	end

	local START = SeasonTrack.startsAtUnix

	local function record(seasonId: string, endsAtSec: number, earnedTier: number, claimed: { number }): State
		local claimedTiers: { [string]: boolean } = {}
		for _, tier in claimed do
			claimedTiers[tostring(tier)] = true
		end
		return {
			schemaVersion = Core.SCHEMA_VERSION,
			seasonId = seasonId,
			xp = earnedTier * 500,
			objectiveProgress = {},
			completedObjectives = {},
			claimedTiers = claimedTiers,
			receiptOrder = {},
			endsAtSec = endsAtSec,
			earnedTier = earnedTier,
			contributionUnitsByWeek = {},
			doorCycle = "",
			doorUnits = 0,
		}
	end

	type FixtureState = typeof(record("", 0, 0, {}))

	local function playWeek(state: State, week: number, prefix: string, days: { number }): State
		local sequence = 0
		local weekStart = START + (week - 1) * WEEK
		local plan = {
			{ kind = "quest_complete", units = 1, count = 6 },
			{ kind = "contribution", units = 10, count = 3 },
			{ kind = "craft", units = 1, count = 2 },
			{ kind = "gather", units = 5, count = 4 },
		}
		for _, row in plan do
			for _ = 1, row.count do
				sequence += 1
				local at = weekStart + days[1] * DAY + sequence * 3601
				state =
					assert(apply(state, ("%s:w%d:%d"):format(prefix, week, sequence), row.kind, row.units, at).state)
			end
		end
		return state
	end

	describe("SeasonTrackCore authored track", function()
		it("rejects calendar-gated track definitions", function()
			local timed = table.clone(SeasonTrack)
			timed.permanent = false
			local definition, reason = Core.definition(timed)
			expect(definition):toBeNil()
			expect(reason):toBe("track_invalid")
			local missing: { [string]: unknown } = {}
			for key, value in assert(Shape.raw(SeasonTrack)) do
				if type(key) == "string" and key ~= "permanent" then
					missing[key] = value
				end
			end
			expect((Core.definition(missing))):toBeNil()
		end)

		it("rejects missing current allowance fields without synthesizing counters", function()
			local current = record("track-a", START, 5, { 1 })
			expect((Core.projectState(current)) ~= nil):toBe(true)
			for _, field in { "contributionUnitsByWeek", "doorCycle", "doorUnits" } do
				local incomplete: { [string]: unknown } = {}
				for key, value in assert(Shape.raw(current)) do
					if type(key) == "string" and key ~= field then
						incomplete[key] = value
					end
				end
				expect(Core.projectState(incomplete)):toBeNil()
			end
		end)
		it(
			"accepts the first season's track: ten weeks, cosmetic and recognition rewards, objectives within 30%",
			function()
				local definition = track()
				expect(definition.weeks):toBe(10)
				expect(#definition.rewards):toBe(20)
				local bonus = 0
				for _, objective in definition.objectives do
					bonus += objective.bonusXp
				end
				expect(bonus <= definition.topThreshold * 0.3):toBe(true)
				for _, reward in definition.rewards do
					expect(reward.kind == "title" or reward.kind == "cosmetic" or reward.kind == "chronicle_mark"):toBe(
						true
					)
				end
			end
		)

		it(
			"refuses a power reward, an objective share above 30%, a season outside 8 to 12 weeks, or an unknown objective kind",
			function()
				local function variant(mutate: (Module.AuthoredDefinition) -> ()): string?
					local copy = table.clone(SeasonTrack)
					copy.rewards = table.clone(SeasonTrack.rewards)
					copy.objectives = table.clone(SeasonTrack.objectives)
					mutate(copy)
					local _, reason = Core.definition(copy)
					return reason
				end
				expect(variant(function(copy)
					copy.rewards[1] = table.clone(copy.rewards[1])
					copy.rewards[1].kind = "stat_bonus"
				end)):toBe("reward_invalid")
				expect(variant(function(copy)
					local objective = table.clone(copy.objectives[1])
					objective.bonusXp = 5000
					copy.objectives[1] = objective
				end)):toBe("objective_share_exceeded")
				expect(variant(function(copy)
					copy.weeks = 7
				end)):toBe("track_invalid")
				expect(variant(function(copy)
					local objective = table.clone(copy.objectives[1])
					objective.kind = "daily_login"
					copy.objectives[1] = objective
				end)):toBe("objective_invalid")
			end
		)
	end)

	describe("SeasonTrackCore earns from ordinary play without dailies", function()
		it("awards capped play xp per event and completes a week's objective once", function()
			local state = assert(Core.emptyState(track()))
			local first = apply(state, "e1", "contribution", 10, START + 10)
			expect(first.awarded):toBe(10 * 3)
			expect(assert(first.state).completedObjectives["m.01.2"]):toBeNil()
			local progressed = assert(apply(first.state, "e2", "contribution", 10, START + 11).state)
			progressed = assert(apply(progressed, "e3", "contribution", 10, START + 12).state)
			expect(progressed.completedObjectives["m.01.2"]):toBe(true)
			for index = 1, 5 do
				progressed =
					assert(apply(progressed, "q" .. tostring(index), "quest_complete", 1, START + 20 + index).state)
			end
			expect(progressed.completedObjectives["m.01.1"]):toBe(true)
			expect(progressed.xp):toBe(3 * 10 * 3 + 100 + 5 * 40 + 100)
			local again = apply(progressed, "q6", "quest_complete", 1, START + 30)
			expect(again.awarded):toBe(40)
		end)

		it("pays a named kill once without making it a daily objective", function()
			local state = assert(Core.emptyState(track()))
			local first = apply(state, "named:guardian", "named_kill", 1, START + 10)
			expect(first.awarded):toBe(35)
			local again = apply(first.state, "named:guardian", "named_kill", 1, START + DAY)
			expect(again.replayed):toBe(true)
			expect(assert(again.state).xp):toBe(35)
		end)

		it("advances one sequential craft milestone without a calendar unlock", function()
			local early = assert(apply(Core.emptyState(track()), "c1", "craft", 2, START + 5).state)
			expect(early.completedObjectives["m.01.3"]):toBe(true)
			expect(early.completedObjectives["m.02.3"]):toBeNil()
			local later = assert(apply(early, "c2", "craft", 2, START + 8 * WEEK).state)
			expect(later.completedObjectives["m.02.3"]):toBe(true)
			expect(later.completedObjectives["m.09.3"]):toBeNil()
			for week = 3, 9 do
				later = assert(apply(later, "c" .. tostring(week), "craft", 2, START + 8 * WEEK + week * 3601).state)
			end
			expect(later.completedObjectives["m.09.3"]):toBe(true)
			expect(later.completedObjectives["m.10.3"]):toBeNil()
		end)

		it("gives a player absent three days a week the same season as one present every day", function()
			local everyDay = assert(Core.emptyState(track()))
			local fourDays = assert(Core.emptyState(track()))
			for week = 1, 10 do
				everyDay = playWeek(everyDay, week, "a", { 0, 1, 2, 3, 4, 5, 6 })
				fourDays = playWeek(fourDays, week, "b", { 0, 2, 4, 6 })
			end
			expect(fourDays.xp):toBe(everyDay.xp)
			expect(everyDay.xp >= SeasonTrack.rewards[#SeasonTrack.rewards].threshold * 0.7):toBe(true)
		end)

		it("costs a player who misses a whole week no more than that week's play", function()
			local steady = assert(Core.emptyState(track()))
			local away = assert(Core.emptyState(track()))
			local weekPlay = 0
			for week = 1, 10 do
				local before = steady.xp
				steady = playWeek(steady, week, "s", { 0, 1, 2, 3, 4, 5, 6 })
				if week == 3 then
					weekPlay = steady.xp - before
				else
					away = playWeek(away, week, "m", { 0, 1, 2, 3, 4, 5, 6 })
				end
			end
			expect(steady.xp - away.xp <= weekPlay):toBe(true)
			expect(steady.xp - away.xp > 0):toBe(true)
		end)
	end)

	describe("SeasonTrackCore idempotence, season window, and claims", function()
		it("applies a kept event id once and accepts a new id whatever its time", function()
			local state = assert(Core.emptyState(track()))
			state = assert(apply(state, "e1", "gather", 5, START + 1).state)
			local replay = apply(state, "e1", "gather", 5, START + 1)
			expect(replay.replayed):toBe(true)
			expect(assert(replay.state).xp):toBe(state.xp)
			for index = 1, Core.RECEIPT_WINDOW do
				state = assert(apply(state, "g" .. tostring(index), "gather", 1, START + 10 + index * 3601).state)
			end
			expect(#state.receiptOrder):toBe(Core.RECEIPT_WINDOW)
			local late = apply(state, "late", "gather", 1, START + 1)
			expect(late.ok):toBe(true)
			expect(late.replayed):toBe(false)
			expect(assert(late.state).xp):toBe(state.xp + 5)
			expect(apply(late.state, "late", "gather", 1, START + 2).replayed):toBe(true)
		end)

		it("earns before the old start and long after the old end without attendance events", function()
			local state = assert(Core.emptyState(track()))
			expect(apply(state, "e1", "gather", 1, START - 1).awarded):toBe(5)
			expect(apply(state, "e2", "gather", 1, START + 1000 * WEEK).awarded):toBe(5)
			expect(apply(state, "e3", "daily_login", 1, START + 1).reason):toBe("kind_unknown")
			expect(Core.apply(Core.emptyState({ seasonId = "season-2", endsAtSec = START }), track(), {
				eventId = "e4",
				kind = "gather",
				units = 1,
				atSec = START + 1,
			}).reason):toBe("season_mismatch")
		end)

		it("claims an earned tier once, refuses an unearned one, and keeps it claimable after the season", function()
			local state = assert(Core.emptyState(track()))
			for index = 1, 13 do
				state = assert(apply(state, "q" .. tostring(index), "quest_complete", 1, START + index).state)
			end
			expect(state.xp >= 500):toBe(true)
			expect(Core.claim(state, track(), 2).reason):toBe("tier_unearned")
			local claimed = Core.claim(state, track(), 1)
			expect(claimed.ok):toBe(true)
			expect(Core.claim(claimed.state, track(), 1).replayed):toBe(true)
			local view = assert(Core.projection(state, track(), START + 20 * WEEK))
			expect(view.open):toBe(true)
			expect(view.claimable):toEqual({ 1 })
			expect(Core.claim(state, track(), 1).ok):toBe(true)
		end)

		it("projects all permanent milestones and the next tier", function()
			local view = assert(Core.projection(Core.emptyState(track()), track(), START + WEEK + 5))
			expect(view.week):toBe(2)
			expect(#view.objectives):toBe(30)
			expect(view.nextThreshold):toBe(500)
			expect(view.nextRewardLabel):toBe(SeasonTrack.rewards[1].label)
			expect(view.tier):toBe(0)
		end)

		it("keeps one record per season in a bounded profile map and changes nothing on replay or refusal", function()
			expect(Core.projectTracks({ ["track-a"] = record("season-2", START, 0, {}) })):toBeNil()
			expect(Core.projectTracks(nil)):toBeNil()
			local full: { [string]: FixtureState | State } = {}
			for index = 1, Core.MAX_SEASONS do
				full["old-" .. tostring(index)] = record("old-" .. tostring(index), START + 10 * WEEK, 0, {})
			end
			expect((Core.projectTracks(full)) ~= nil):toBe(true)
			local event = { eventId = "q1", kind = "quest_complete", units = 1, atSec = START + 1 }
			local refusedFull, fullResult = Core.recordIn(full, track(), event)
			expect(refusedFull):toBeNil()
			expect(fullResult.reason):toBe("seasons_full")
			local over = table.clone(full)
			over["track-a"] = assert(Core.emptyState(track()))
			expect(Core.projectTracks(over)):toBeNil()
			local recorded = assert((Core.recordIn({}, track(), event)))
			expect(recorded["track-a"].xp):toBe(40)
			local replayed, replay = Core.recordIn(recorded, track(), event)
			expect(replayed):toBeNil()
			expect(replay.replayed):toBe(true)
			local closed, closedResult = Core.recordIn(recorded, track(), {
				eventId = "q2",
				kind = "quest_complete",
				units = 1,
				atSec = START + 20 * WEEK,
			})
			expect(assert(closed)["track-a"].xp):toBe(80)
			expect(closedResult.ok):toBe(true)
			expect((Core.claimIn(recorded, track(), 1))):toBeNil()
			expect(assert(Core.projectionIn(recorded, track(), START + 5)).xp):toBe(40)
			expect(assert(Core.projectionIn({}, track(), START + 5)).rewards[1].earned):toBe(false)
		end)

		it("makes room for a new season by evicting a closed season, fully claimed first, then the oldest", function()
			local event = { eventId = "q1", kind = "quest_complete", units = 1, atSec = START + 1 }
			local closedEarly: { [string]: FixtureState } = {}
			for index = 1, Core.MAX_SEASONS do
				closedEarly["old-" .. tostring(index)] = record("old-" .. tostring(index), START - index, 1, {})
			end
			closedEarly["old-16"] = record("old-16", START + WEEK, 1, {})
			closedEarly["old-3"] = record("old-3", START - 3, 2, { 1, 2 })
			local claimedFirst = assert((Core.recordIn(closedEarly, track(), event)))
			expect(claimedFirst["track-a"].xp):toBe(40)
			expect(claimedFirst["old-3"]):toBeNil()
			expect(claimedFirst["old-15"] ~= nil):toBe(true)
			closedEarly["old-3"] = record("old-3", START - 3, 2, { 1 })
			local oldestNext = assert((Core.recordIn(closedEarly, track(), event)))
			expect(oldestNext["old-15"]):toBeNil()
			expect(oldestNext["old-3"] ~= nil):toBe(true)
			expect(oldestNext["old-16"] ~= nil):toBe(true)
			local count = 0
			for _ in oldestNext do
				count += 1
			end
			expect(count):toBe(Core.MAX_SEASONS)
			local earned = assert((Core.recordIn({}, track(), event)))
			for index = 2, 13 do
				earned = Core.recordIn(earned, track(), {
					eventId = "q" .. tostring(index),
					kind = "quest_complete",
					units = 1,
					atSec = START + index,
				})
				earned = assert(earned)
			end
			expect(assert(earned)["track-a"].earnedTier):toBe(1)
			expect(assert(earned)["track-a"].endsAtSec):toBe(track().endsAtSec)
		end)
		it(
			"caps both farm groups by awarded progress, preserves contested healing and bounds rolling accounting over long play",
			function()
				local definition = track()
				local state = assert(Core.emptyState(definition))
				local first =
					Core.apply(state, definition, { eventId = "craft:1", kind = "craft", units = 2, atSec = START })
				expect(first.awarded):toBe(130)
				state = assert(first.state)
				local gathered =
					Core.apply(state, definition, { eventId = "gather:1", kind = "gather", units = 10, atSec = START })
				expect(gathered.awarded):toBe(20)
				state = assert(gathered.state)
				expect(assert(Core.projection(state, definition, START)).craftGatherRemaining):toBe(0)
				expect(
					Core.apply(
						state,
						definition,
						{ eventId = "gather:2", kind = "gather", units = 1, atSec = START + 3599 }
					).reason
				):toBe("progress_allowance_exhausted")
				local work = Core.apply(
					state,
					definition,
					{ eventId = "work:1", kind = "contribution_work", units = 10, atSec = START, contested = false }
				)
				state = assert(work.state)
				for index = 2, 20 do
					local result = Core.apply(state, definition, {
						eventId = "work:" .. index,
						kind = "contribution",
						units = 10,
						atSec = START,
						contested = false,
					})
					if result.ok then
						state = assert(result.state)
					end
				end
				expect(assert(Core.projection(state, definition, START)).unopposedWorkRemaining):toBe(63)
				local healed = Core.apply(state, definition, {
					eventId = "heal:contested",
					kind = "contribution_work",
					units = 10,
					atSec = START,
					contested = true,
				})
				expect(healed.awarded):toBe(130)
				expect(assert(Core.projection(healed.state, definition, START)).unopposedWorkRemaining):toBe(63)
				state = assert(healed.state)
				for hour = 1, 1000 do
					local nextResult = Core.apply(
						state,
						definition,
						{ eventId = "long:gather:" .. hour, kind = "gather", units = 10, atSec = START + hour * 3600 }
					)
					state = assert(nextResult.state)
					local count = 0
					for _ in state.contributionUnitsByWeek do
						count += 1
					end
					expect(count <= 6):toBe(true)
				end
				local back = Core.apply(
					state,
					definition,
					{ eventId = "late:clock", kind = "gather", units = 10, atSec = START }
				)
				expect(back.awarded):toBe(25)
				expect(assert(Core.projection(back.state, definition, START)).craftGatherRemaining):toBe(100)
			end
		)
		it("never evicts the Chapter 1 record to make room for another track", function()
			local chapter =
				record("track-a", 1, 20, { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20 })
			local tracks: { [string]: FixtureState } = { ["track-a"] = chapter }
			for index = 1, 15 do
				tracks["old-" .. index] = record("old-" .. index, index + 1, 0, {})
			end
			local other = table.clone(track())
			other.seasonId = "other-track"
			local nextTracks =
				Core.recordIn(tracks, other, { eventId = "other:q", kind = "quest_complete", units = 1, atSec = START })
			expect(assert(nextTracks)["track-a"].xp):toBe(10000)
			expect(assert(nextTracks)["track-a"].claimedTiers["20"]):toBe(true)
			expect(assert(nextTracks)["old-1"]):toBeNil()
		end)
	end)
	it("enforces each supplied definition bound", function()
		local tests: { { change: (Module.Config) -> (), reason: string } } = {
			{
				change = function(c)
					c.minWeeks = 11
				end,
				reason = "track_invalid",
			},
			{
				change = function(c)
					c.maxWeeks = 9
				end,
				reason = "track_invalid",
			},
			{
				change = function(c)
					c.maxSources = 1
				end,
				reason = "track_invalid",
			},
			{
				change = function(c)
					c.maxObjectives = 1
				end,
				reason = "track_invalid",
			},
			{
				change = function(c)
					c.maxRewards = 1
				end,
				reason = "track_invalid",
			},
			{
				change = function(c)
					c.maxId = 2
				end,
				reason = "track_invalid",
			},
			{
				change = function(c)
					c.maxTime = 10
				end,
				reason = "track_invalid",
			},
			{
				change = function(c)
					c.maxSourceXp = 1
				end,
				reason = "play_source_invalid",
			},
			{
				change = function(c)
					c.maxSourceUnits = 1
				end,
				reason = "play_source_invalid",
			},
			{
				change = function(c)
					c.maxTarget = 1
				end,
				reason = "objective_invalid",
			},
			{
				change = function(c)
					c.maxBonusXp = 1
				end,
				reason = "objective_invalid",
			},
			{
				change = function(c)
					c.maxLabel = 1
				end,
				reason = "objective_invalid",
			},
			{
				change = function(c)
					c.maxXp = 999
				end,
				reason = "reward_invalid",
			},
			{
				change = function(c)
					c.rewardKinds = {}
				end,
				reason = "reward_invalid",
			},
			{
				change = function(c)
					c.maxObjectiveShare = 0
				end,
				reason = "objective_share_exceeded",
			},
		}
		for _, test in tests do
			local c = table.clone(config)
			test.change(c)
			local _, reason = Module.season(c).definition(SeasonTrack)
			expect(reason):toBe(test.reason)
		end
	end)
	it("configures event families, rolling accounting and receipt limits", function()
		local c = table.clone(config)
		c.weekSec = 10
		c.receiptWindow = 1
		c.doorCycleUnits = 2
		c.contributionBucketUnits = 2
		c.allowanceUnits = 20
		c.allowanceSec = 5
		c.accountingPrefix = "budget:"
		c.contributionKinds = { custom = true }
		c.scopedKind = "custom"
		c.allowanceGroups = { custom = "help_2", gather = "making-1" }
		c.workGroup = "help_2"
		c.craftGroup = "making-1"
		c.milestoneKinds = { custom = "contribution" }
		local law = Module.season(c)
		local authored = table.clone(SeasonTrack)
		authored.playSources = table.clone(SeasonTrack.playSources)
		table.insert(authored.playSources, { kind = "custom", xpPerUnit = 3, maxUnitsPerEvent = 10 })
		local definition = assert(law.definition(authored))
		local state = assert(law.emptyState(definition))
		local first = law.apply(
			state,
			definition,
			{ eventId = "one", kind = "custom", units = 10, scope = "scope", atSec = START }
		)
		expect(first.awarded):toBe(6)
		expect(assert(law.projection(first.state, definition, START)).unopposedWorkRemaining):toBe(14)
		expect(assert(first.state).doorUnits):toBe(2)
		local capped = law.apply(
			first.state,
			definition,
			{ eventId = "two", kind = "custom", units = 1, scope = "scope", atSec = START, contested = true }
		)
		expect(capped.replayed):toBe(true)
		local nextResult = law.apply(
			first.state,
			definition,
			{ eventId = "two", kind = "custom", units = 10, scope = "next", atSec = START + 1 }
		)
		expect(nextResult.awarded):toBe(6)
		expect(#assert(nextResult.state).receiptOrder):toBe(1)
		local view = assert(law.projection(nextResult.state, definition, START + 10))
		expect(view.week):toBe(2)
		expect(view.unopposedWorkRemaining):toBe(20)
		local bad = table.clone(c)
		bad.maxEventUnits = 1
		expect(
			Module.season(bad)
				.apply(state, definition, { eventId = "bad", kind = "custom", units = 2, atSec = START }).reason
		):toBe("event_invalid")
		for key, count in assert(nextResult.state).contributionUnitsByWeek do
			expect(string.sub(key, 1, 7)):toBe("budget:")
			expect(count <= 2):toBe(true)
		end
	end)
	it("honors configured capacity and protected records", function()
		local c = table.clone(config)
		c.maxSeasons = 1
		c.protectedSeasons = { ["protected"] = true }
		local law = Module.season(c)
		local records = { protected = record("protected", 1, 0, {}) }
		local tracks, result =
			law.recordIn(records, track(), { eventId = "new", kind = "quest_complete", units = 1, atSec = START })
		expect(tracks):toBeNil()
		expect(result.reason):toBe("seasons_full")
		c = table.clone(c)
		c.protectedSeasons = {}
		local stored = Module.season(c)
			.recordIn(records, track(), { eventId = "new", kind = "quest_complete", units = 1, atSec = START })
		expect(assert(stored).protected):toBeNil()
	end)
end
