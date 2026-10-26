--!strict

local Read = require("../internal/season-read")
local SocialShape = require("../social/shape")

export type Event = Read.Event
export type State = Read.State
export type Result = Read.Result
export type PlaySource = Read.PlaySource
export type Objective = Read.Objective
export type Reward = Read.Reward
export type AuthoredDefinition = Read.AuthoredDefinition
export type Definition = Read.Definition
export type ProjectionObjective = Read.ProjectionObjective
export type Projection = Read.Projection
export type Config = Read.Config

local System = {}

function System.season(config: Config)
	local readState = Read.readState
	local readAuthoredDefinition = Read.readAuthoredDefinition
	local readEvent = Read.readEvent

	local SCHEMA_VERSION = 2
	local WEEK_SEC = config.weekSec
	local CONTRIBUTION_WEEK_UNITS = config.contributionBucketUnits
	local DOOR_CYCLE_UNITS = config.doorCycleUnits
	local RECEIPT_WINDOW = config.receiptWindow
	local MAX_SEASONS = config.maxSeasons
	local MAX_REWARDS = config.maxRewards
	local MIN_WEEKS = config.minWeeks
	local MAX_WEEKS = config.maxWeeks
	local MAX_OBJECTIVE_SHARE = config.maxObjectiveShare
	local MAX_ID = config.maxId
	local MAX_TIME = config.maxTime
	local MAX_XP = config.maxXp
	local REWARD_KINDS = config.rewardKinds
	local CONTRIBUTION_KINDS = config.contributionKinds

	local whole = SocialShape.whole
	local opaque = SocialShape.opaque
	local exact = SocialShape.exact
	local dense = SocialShape.dense
	local freezeDeep = SocialShape.freezeDeep

	local STATE_FIELDS: { [string]: boolean } = SocialShape.freezeDeep({
		schemaVersion = true,
		seasonId = true,
		xp = true,
		objectiveProgress = true,
		completedObjectives = true,
		claimedTiers = true,
		receiptOrder = true,
		endsAtSec = true,
		earnedTier = true,
		contributionUnitsByWeek = true,
		doorCycle = true,
		doorUnits = true,
	})
	local EVENT_FIELDS: { [string]: boolean } =
		SocialShape.freezeDeep({ eventId = true, kind = true, units = true, atSec = true })
	local SCOPED_EVENT_FIELDS: { [string]: boolean } =
		SocialShape.freezeDeep({ eventId = true, kind = true, units = true, atSec = true, scope = true })
	local CONTEST_EVENT_FIELDS: { [string]: boolean } =
		SocialShape.freezeDeep({ eventId = true, kind = true, units = true, atSec = true, contested = true })
	local CONTEXT_EVENT_FIELDS: { [string]: boolean } = SocialShape.freezeDeep({
		eventId = true,
		kind = true,
		units = true,
		atSec = true,
		scope = true,
		contested = true,
	})

	local function copyCounts(value: unknown, maximum: number): { [string]: number }?
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return nil
		end
		local out: { [string]: number } = {}
		for key, count in assert(SocialShape.raw(value)) do
			if not opaque(key, MAX_ID) or not whole(count, 1, maximum) then
				return nil
			end
			out[assert(SocialShape.string(key))] = assert(SocialShape.number(count))
		end
		return out
	end

	local function copyFlags(value: unknown): { [string]: boolean }?
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return nil
		end
		local out: { [string]: boolean } = {}
		for key, flag in assert(SocialShape.raw(value)) do
			if not opaque(key, MAX_ID) or flag ~= true then
				return nil
			end
			out[assert(SocialShape.string(key))] = true
		end
		return out
	end

	local function copyState(value: unknown): State?
		if type(value) ~= "table" then
			return nil
		end
		if not exact(value, STATE_FIELDS) then
			return nil
		end
		local raw = readState(value)
		if raw == nil then
			return nil
		end
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or not opaque(raw.seasonId, MAX_ID)
			or not whole(raw.xp, 0, MAX_XP)
			or not whole(raw.endsAtSec, 0, MAX_TIME)
			or not whole(raw.earnedTier, 0, MAX_REWARDS)
			or dense(raw.receiptOrder, RECEIPT_WINDOW) == nil
		then
			return nil
		end
		local progress = copyCounts(raw.objectiveProgress, MAX_XP)
		local completed = copyFlags(raw.completedObjectives)
		local claimed = copyFlags(raw.claimedTiers)
		local contributionUnits = copyCounts(raw.contributionUnitsByWeek, CONTRIBUTION_WEEK_UNITS)
		if
			progress == nil
			or completed == nil
			or claimed == nil
			or contributionUnits == nil
			or type(raw.doorCycle) ~= "string"
			or #raw.doorCycle > MAX_ID
			or not whole(raw.doorUnits, 0, DOOR_CYCLE_UNITS)
		then
			return nil
		end
		local receiptOrder: { { eventId: string, atSec: number } } = {}
		local seen: { [string]: boolean } = {}
		for _, receipt in raw.receiptOrder do
			if
				not exact(receipt, { eventId = true, atSec = true })
				or not opaque(receipt.eventId, MAX_ID)
				or not whole(receipt.atSec, 0, MAX_TIME)
				or seen[receipt.eventId]
			then
				return nil
			end
			seen[receipt.eventId] = true
			receiptOrder[#receiptOrder + 1] = { eventId = receipt.eventId, atSec = receipt.atSec }
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			seasonId = raw.seasonId,
			xp = raw.xp,
			objectiveProgress = progress,
			completedObjectives = completed,
			claimedTiers = claimed,
			receiptOrder = receiptOrder,
			endsAtSec = raw.endsAtSec,
			earnedTier = raw.earnedTier,
			contributionUnitsByWeek = contributionUnits,
			doorCycle = raw.doorCycle,
			doorUnits = raw.doorUnits,
		}
	end

	local outcome: (Result) -> Result = freezeDeep
	local projectionResult: (Projection) -> Projection = freezeDeep
	local stateResult: (State) -> State = freezeDeep
	local function refused(reason: string): Result
		return outcome({ ok = false, state = nil, replayed = false, reason = reason, awarded = nil })
	end

	local SeasonTrackCore = {}

	function SeasonTrackCore.definition(value: unknown): (Definition?, string?)
		if type(value) ~= "table" then
			return nil, "track_invalid"
		end
		local raw = readAuthoredDefinition(value)
		if raw == nil then
			return nil, "track_invalid"
		end
		if
			raw.permanent ~= true
			or not opaque(raw.seasonId, MAX_ID)
			or not whole(raw.startsAtUnix, 0, MAX_TIME)
			or not whole(raw.weeks, MIN_WEEKS, MAX_WEEKS)
			or dense(raw.playSources, config.maxSources) == nil
			or dense(raw.objectives, config.maxObjectives) == nil
			or dense(raw.rewards, MAX_REWARDS) == nil
			or #raw.rewards == 0
		then
			return nil, "track_invalid"
		end
		local sources: { [string]: PlaySource } = {}
		for _, source in raw.playSources do
			if
				not opaque(source.kind, MAX_ID)
				or sources[source.kind] ~= nil
				or not whole(source.xpPerUnit, 1, config.maxSourceXp)
				or not whole(source.maxUnitsPerEvent, 1, config.maxSourceUnits)
			then
				return nil, "play_source_invalid"
			end
			sources[source.kind] = SocialShape.freezeDeep(table.clone(source))
		end
		local objectives: { Objective } = {}
		local objectiveIds: { [string]: boolean } = {}
		local bonusTotal = 0
		for _, objective in raw.objectives do
			if
				not opaque(objective.objectiveId, MAX_ID)
				or objectiveIds[objective.objectiveId]
				or not whole(objective.week, 1, raw.weeks)
				or sources[objective.kind] == nil
				or not whole(objective.target, 1, config.maxTarget)
				or not whole(objective.bonusXp, 1, config.maxBonusXp)
				or not opaque(objective.label, config.maxLabel)
			then
				return nil, "objective_invalid"
			end
			objectiveIds[objective.objectiveId] = true
			bonusTotal += objective.bonusXp
			objectives[#objectives + 1] = SocialShape.freezeDeep(table.clone(objective))
		end
		local rewards: { Reward } = {}
		local previous = 0
		for index, reward in raw.rewards do
			if
				reward.tier ~= index
				or not whole(reward.threshold, previous + 1, MAX_XP)
				or REWARD_KINDS[reward.kind] ~= true
				or not opaque(reward.rewardId, MAX_ID)
				or not opaque(reward.label, config.maxLabel)
			then
				return nil, "reward_invalid"
			end
			previous = reward.threshold
			rewards[#rewards + 1] = SocialShape.freezeDeep(table.clone(reward))
		end
		if bonusTotal > previous * MAX_OBJECTIVE_SHARE then
			return nil, "objective_share_exceeded"
		end
		return SocialShape.freezeDeep({
			permanent = true,
			seasonId = raw.seasonId,
			startsAtSec = raw.startsAtUnix,
			endsAtSec = MAX_TIME,
			weeks = raw.weeks,
			sources = SocialShape.freezeDeep(sources),
			objectives = SocialShape.freezeDeep(objectives),
			rewards = SocialShape.freezeDeep(rewards),
			topThreshold = previous,
		}),
			nil
	end

	function SeasonTrackCore.emptyState(track: { seasonId: string, endsAtSec: number }): State?
		if type(track) ~= "table" or not opaque(track.seasonId, MAX_ID) or not whole(track.endsAtSec, 0, MAX_TIME) then
			return nil
		end
		return stateResult({
			schemaVersion = SCHEMA_VERSION,
			seasonId = track.seasonId,
			xp = 0,
			objectiveProgress = {},
			completedObjectives = {},
			claimedTiers = {},
			receiptOrder = {},
			endsAtSec = track.endsAtSec,
			earnedTier = 0,
			contributionUnitsByWeek = {},
			doorCycle = "",
			doorUnits = 0,
		})
	end

	function SeasonTrackCore.projectState(value: unknown): State?
		local state = copyState(value)
		return if state == nil then nil else freezeDeep(state)
	end

	local function farmClock(state: State, atSec: number): number
		local current = atSec
		for key in state.contributionUnitsByWeek do
			local stamp = tonumber(
				(string.match(key, "^" .. string.gsub(config.accountingPrefix, "(%W)", "%%%1") .. "clock:(%d+)$"))
			)
			if stamp ~= nil then
				current = math.max(current, stamp)
			end
		end
		return current
	end

	local function farmRemaining(state: State, group: string, atSec: number): number
		local current = farmClock(state, atSec)
		local spent = 0
		for key, count in state.contributionUnitsByWeek do
			local kind, stamp =
				string.match(key, "^" .. string.gsub(config.accountingPrefix, "(%W)", "%%%1") .. "([^:]+):(%d+):%d+$")
			local time = tonumber(stamp)
			if kind == group and time ~= nil and time > current - config.allowanceSec then
				spent += count
			end
		end
		return math.max(0, config.allowanceUnits - spent)
	end

	local function farmCredit(state: State, group: string, atSec: number, awarded: number)
		local current = farmClock(state, atSec)
		for key in state.contributionUnitsByWeek do
			local stamp = tonumber(
				(string.match(key, "^" .. string.gsub(config.accountingPrefix, "(%W)", "%%%1") .. "[^:]+:(%d+):%d+$"))
			)
			if
				string.match(key, "^" .. string.gsub(config.accountingPrefix, "(%W)", "%%%1") .. "clock:%d+$")
				or (stamp ~= nil and stamp <= current - config.allowanceSec)
			then
				state.contributionUnitsByWeek[key] = nil
			end
		end
		state.contributionUnitsByWeek[config.accountingPrefix .. "clock:" .. current] = 1
		local slot = 1
		while awarded > 0 do
			local key = config.accountingPrefix .. group .. ":" .. current .. ":" .. slot
			local held = state.contributionUnitsByWeek[key] or 0
			local credit = math.min(CONTRIBUTION_WEEK_UNITS - held, awarded)
			if credit > 0 then
				state.contributionUnitsByWeek[key] = held + credit
				awarded -= credit
			end
			slot += 1
		end
	end

	function SeasonTrackCore.apply(previous: unknown, track: Definition, eventValue: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		if type(track) ~= "table" or state.seasonId ~= track.seasonId then
			return refused("season_mismatch")
		end
		if
			not exact(
				eventValue,
				if type(eventValue) == "table" and assert(SocialShape.raw(eventValue)).contested ~= nil
					then if assert(SocialShape.raw(eventValue)).scope ~= nil
						then CONTEXT_EVENT_FIELDS
						else CONTEST_EVENT_FIELDS
					elseif
						type(eventValue) == "table" and assert(SocialShape.raw(eventValue)).scope ~= nil
					then SCOPED_EVENT_FIELDS
					else EVENT_FIELDS
			)
			or not opaque(assert(SocialShape.raw(eventValue)).eventId, MAX_ID)
			or type(assert(SocialShape.raw(eventValue)).kind) ~= "string"
			or not whole(assert(SocialShape.raw(eventValue)).units, 1, config.maxEventUnits)
			or not whole(assert(SocialShape.raw(eventValue)).atSec, 0, MAX_TIME)
		then
			return refused("event_invalid")
		end
		local event = readEvent(eventValue)
		if event == nil then
			return refused("event_invalid")
		end
		local kind: string = event.kind
		if event.scope ~= nil and (not opaque(event.scope, MAX_ID) or kind ~= config.scopedKind) then
			return refused("event_invalid")
		end
		if event.contested ~= nil and (type(event.contested) ~= "boolean" or CONTRIBUTION_KINDS[kind] ~= true) then
			return refused("event_invalid")
		end
		local source = track.sources[kind]
		if source == nil then
			return refused("kind_unknown")
		end
		for _, receipt in state.receiptOrder do
			if receipt.eventId == event.eventId then
				return outcome({ ok = true, state = state, replayed = true, reason = nil, awarded = 0 })
			end
		end
		local units = math.min(event.units, source.maxUnitsPerEvent)
		if CONTRIBUTION_KINDS[kind] == true then
			if event.scope ~= nil then
				if state.doorCycle ~= event.scope then
					state.doorCycle = event.scope
					state.doorUnits = 0
				end
				units = math.min(units, DOOR_CYCLE_UNITS - state.doorUnits)
				state.doorUnits += units
			end
		end

		local budgetKind: string = tostring(kind)
		local allowanceGroup = if CONTRIBUTION_KINDS[kind] == true and event.contested == true
			then nil
			else config.allowanceGroups[budgetKind]
		local milestoneKind = config.milestoneKinds[kind] or kind
		if allowanceGroup ~= nil then
			local available = farmRemaining(state, allowanceGroup, event.atSec)
			while units > 0 do
				local trial = units * source.xpPerUnit
				local remaining = units
				for _, objective in track.objectives do
					if
						objective.kind == milestoneKind
						and not state.completedObjectives[objective.objectiveId]
						and remaining > 0
					then
						local missing = objective.target - (state.objectiveProgress[objective.objectiveId] or 0)
						local applied = math.min(remaining, missing)
						remaining -= applied
						if applied == missing then
							trial += objective.bonusXp
						end
					end
				end
				if trial <= available then
					break
				end
				units -= 1
			end
			if units == 0 then
				return refused("progress_allowance_exhausted")
			end
		end
		if units == 0 then
			return outcome({ ok = true, state = copyState(previous), replayed = true, reason = nil, awarded = 0 })
		end
		local awarded = units * source.xpPerUnit
		local objectiveUnits = units
		for _, objective in track.objectives do
			if
				objective.kind == milestoneKind
				and not state.completedObjectives[objective.objectiveId]
				and objectiveUnits > 0
			then
				local applied =
					math.min(objectiveUnits, objective.target - (state.objectiveProgress[objective.objectiveId] or 0))
				objectiveUnits -= applied
				local progress = (state.objectiveProgress[objective.objectiveId] or 0) + applied
				if progress >= objective.target then
					state.objectiveProgress[objective.objectiveId] = nil
					state.completedObjectives[objective.objectiveId] = true
					awarded += objective.bonusXp
				else
					state.objectiveProgress[objective.objectiveId] = progress
				end
			end
		end
		if allowanceGroup ~= nil then
			if awarded > farmRemaining(state, allowanceGroup, event.atSec) then
				return refused("progress_allowance_exhausted")
			end
			farmCredit(state, allowanceGroup, event.atSec, awarded)
		end
		state.endsAtSec = track.endsAtSec
		state.xp = math.min(MAX_XP, state.xp + awarded)
		for _, reward in track.rewards do
			if state.xp >= reward.threshold then
				state.earnedTier = math.max(state.earnedTier, reward.tier)
			end
		end
		state.receiptOrder[#state.receiptOrder + 1] = { eventId = event.eventId, atSec = event.atSec }
		if #state.receiptOrder > RECEIPT_WINDOW then
			table.remove(state.receiptOrder, 1)
		end
		return outcome({ ok = true, state = state, replayed = false, reason = nil, awarded = awarded })
	end

	function SeasonTrackCore.claim(previous: unknown, track: Definition, tierValue: unknown): Result
		local state = copyState(previous)
		if state == nil then
			return refused("state_invalid")
		end
		if type(track) ~= "table" or state.seasonId ~= track.seasonId then
			return refused("season_mismatch")
		end
		state.endsAtSec = track.endsAtSec
		local reward = if whole(tierValue, 1, #track.rewards)
			then track.rewards[assert(SocialShape.number(tierValue))]
			else nil
		if reward == nil then
			return refused("tier_unknown")
		end
		local key = tostring(reward.tier)
		if state.claimedTiers[key] then
			return outcome({ ok = true, state = state, replayed = true, reason = nil, awarded = 0 })
		end
		if state.xp < reward.threshold then
			return refused("tier_unearned")
		end
		state.claimedTiers[key] = true
		return outcome({ ok = true, state = state, replayed = false, reason = nil, awarded = 0 })
	end

	function SeasonTrackCore.projection(value: unknown, track: Definition, nowSec: number): Projection?
		local state = copyState(value)
		if state == nil or type(track) ~= "table" or state.seasonId ~= track.seasonId then
			return nil
		end
		local tier = 0
		local claimable: { number } = {}
		local rewards: { Reward & { earned: boolean, claimed: boolean } } = {}
		for _, reward in track.rewards do
			rewards[#rewards + 1] = SocialShape.freezeDeep({
				tier = reward.tier,
				threshold = reward.threshold,
				kind = reward.kind,
				rewardId = reward.rewardId,
				label = reward.label,
				earned = state.xp >= reward.threshold,
				claimed = state.claimedTiers[tostring(reward.tier)] == true,
			})
			if state.xp >= reward.threshold then
				tier = reward.tier
				if not state.claimedTiers[tostring(reward.tier)] then
					claimable[#claimable + 1] = reward.tier
				end
			end
		end
		local week = if nowSec < track.startsAtSec
			then 0
			else math.min(track.weeks, math.floor((nowSec - track.startsAtSec) / WEEK_SEC) + 1)
		local objectives: { ProjectionObjective } = {}
		local activeFamilies = {}
		for _, objective in track.objectives do
			local complete = state.completedObjectives[objective.objectiveId] == true
			local active = not complete and not activeFamilies[objective.kind]
			if active then
				activeFamilies[objective.kind] = true
			end
			objectives[#objectives + 1] = SocialShape.freezeDeep({
				objectiveId = objective.objectiveId,
				week = objective.week,
				active = active,
				label = objective.label,
				target = objective.target,
				progress = if state.completedObjectives[objective.objectiveId]
					then objective.target
					else state.objectiveProgress[objective.objectiveId] or 0,
				complete = state.completedObjectives[objective.objectiveId] == true,
			})
		end
		local nextReward = track.rewards[tier + 1]
		return projectionResult({
			seasonId = track.seasonId,
			xp = state.xp,
			tier = tier,
			nextThreshold = if nextReward ~= nil then nextReward.threshold else false,
			nextRewardLabel = if nextReward ~= nil then nextReward.label else false,
			week = week,
			open = true,
			permanent = true,
			craftGatherRemaining = farmRemaining(state, config.craftGroup, nowSec),
			unopposedWorkRemaining = farmRemaining(state, config.workGroup, nowSec),
			objectives = objectives,
			claimable = claimable,
			rewards = rewards,
		})
	end

	function SeasonTrackCore.projectTracks(value: unknown): { [string]: State }?
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return nil
		end
		local tracks: { [string]: State } = {}
		local count = 0
		for seasonId, entry in assert(SocialShape.raw(value)) do
			local state = SeasonTrackCore.projectState(entry)
			if state == nil or state.seasonId ~= seasonId then
				return nil
			end
			tracks[assert(SocialShape.string(seasonId))] = state
			count += 1
		end
		if count > MAX_SEASONS then
			return nil
		end
		return freezeDeep(tracks)
	end

	local function fullyClaimed(state: State): boolean
		for tier = 1, state.earnedTier do
			if not state.claimedTiers[tostring(tier)] then
				return false
			end
		end
		return true
	end

	local function evictsBefore(candidate: State, chosen: State): boolean
		local candidateClaimed, chosenClaimed = fullyClaimed(candidate), fullyClaimed(chosen)
		if candidateClaimed ~= chosenClaimed then
			return candidateClaimed
		end
		if candidate.endsAtSec ~= chosen.endsAtSec then
			return candidate.endsAtSec < chosen.endsAtSec
		end
		return candidate.seasonId < chosen.seasonId
	end

	local function evictable(tracks: { [string]: State }, nowSec: number): string?
		local chosen: State? = nil
		for _, state in tracks do
			if
				config.protectedSeasons[state.seasonId] ~= true
				and state.endsAtSec <= nowSec
				and (chosen == nil or evictsBefore(state, chosen))
			then
				chosen = state
			end
		end
		return if chosen == nil then nil else chosen.seasonId
	end

	function SeasonTrackCore.recordIn(
		tracksValue: unknown,
		track: Definition,
		event: unknown
	): ({ [string]: State }?, Result)
		local tracks = SeasonTrackCore.projectTracks(tracksValue)
		if tracks == nil or type(track) ~= "table" then
			return nil, refused("tracks_invalid")
		end
		local current = tracks[track.seasonId] or SeasonTrackCore.emptyState(track)
		local result = SeasonTrackCore.apply(current, track, event)
		if not result.ok or result.replayed then
			return nil, result
		end
		local nextTracks = table.clone(tracks)
		if tracks[track.seasonId] == nil then
			local count = 0
			for _ in tracks do
				count += 1
			end
			if count >= MAX_SEASONS then
				local victim = evictable(tracks, assert(readEvent(event)).atSec)
				if victim == nil then
					return nil, refused("seasons_full")
				end
				nextTracks[victim] = nil
			end
		end
		nextTracks[track.seasonId] = assert(result.state)
		return freezeDeep(nextTracks), result
	end

	function SeasonTrackCore.claimIn(
		tracksValue: unknown,
		track: Definition,
		tier: unknown
	): ({ [string]: State }?, Result)
		local tracks = SeasonTrackCore.projectTracks(tracksValue)
		if tracks == nil or type(track) ~= "table" then
			return nil, refused("tracks_invalid")
		end
		local result = SeasonTrackCore.claim(tracks[track.seasonId] or SeasonTrackCore.emptyState(track), track, tier)
		if not result.ok or result.replayed then
			return nil, result
		end
		local nextTracks = table.clone(tracks)
		nextTracks[track.seasonId] = assert(result.state)
		return freezeDeep(nextTracks), result
	end

	function SeasonTrackCore.projectionIn(tracksValue: unknown, track: Definition, nowSec: number): Projection?
		local tracks = SeasonTrackCore.projectTracks(tracksValue)
		if tracks == nil or type(track) ~= "table" then
			return nil
		end
		return SeasonTrackCore.projection(tracks[track.seasonId] or SeasonTrackCore.emptyState(track), track, nowSec)
	end

	SeasonTrackCore.SCHEMA_VERSION = SCHEMA_VERSION
	SeasonTrackCore.WEEK_SEC = WEEK_SEC
	SeasonTrackCore.RECEIPT_WINDOW = RECEIPT_WINDOW
	SeasonTrackCore.CONTRIBUTION_WEEK_UNITS = CONTRIBUTION_WEEK_UNITS
	SeasonTrackCore.DOOR_CYCLE_UNITS = DOOR_CYCLE_UNITS
	SeasonTrackCore.MAX_SEASONS = MAX_SEASONS
	return SocialShape.freezeDeep(SeasonTrackCore)
end
return System
