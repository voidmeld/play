--!strict

local SocialShape = require("../social/shape")

export type Event = { eventId: string, kind: string, units: number, atSec: number, scope: string?, contested: boolean? }

export type State = {
	schemaVersion: number,
	seasonId: string,
	xp: number,
	objectiveProgress: { [string]: number },
	completedObjectives: { [string]: boolean },
	claimedTiers: { [string]: boolean },
	receiptOrder: { { eventId: string, atSec: number } },
	endsAtSec: number,
	earnedTier: number,
	contributionUnitsByWeek: { [string]: number },
	doorCycle: string,
	doorUnits: number,
}

export type Result = { ok: boolean, state: State?, replayed: boolean, reason: string?, awarded: number? }
export type PlaySource = { kind: string, xpPerUnit: number, maxUnitsPerEvent: number }
export type Objective = {
	objectiveId: string,
	week: number,
	kind: string,
	target: number,
	bonusXp: number,
	label: string,
}
export type Reward = { tier: number, threshold: number, kind: string, rewardId: string, label: string }
export type AuthoredDefinition = {
	seasonId: string,
	startsAtUnix: number,
	weeks: number,
	permanent: boolean,
	playSources: { PlaySource },
	objectives: { Objective },
	rewards: { Reward },
}
export type Definition = {
	permanent: boolean,
	seasonId: string,
	startsAtSec: number,
	endsAtSec: number,
	weeks: number,
	sources: { [string]: PlaySource },
	objectives: { Objective },
	rewards: { Reward },
	topThreshold: number,
}
export type ProjectionObjective = {
	objectiveId: string,
	week: number,
	active: boolean,
	label: string,
	target: number,
	progress: number,
	complete: boolean,
}
export type Projection = {
	seasonId: string,
	xp: number,
	tier: number,
	nextThreshold: number | false,
	nextRewardLabel: string | false,
	week: number,
	open: boolean,
	permanent: boolean,
	craftGatherRemaining: number | false,
	unopposedWorkRemaining: number | false,
	objectives: { ProjectionObjective },
	claimable: { number },
	rewards: { Reward & { earned: boolean, claimed: boolean } },
}

export type Config = {
	weekSec: number,
	contributionBucketUnits: number,
	doorCycleUnits: number,
	receiptWindow: number,
	maxSeasons: number,
	maxRewards: number,
	minWeeks: number,
	maxWeeks: number,
	maxObjectiveShare: number,
	maxId: number,
	maxTime: number,
	maxXp: number,
	rewardKinds: { [string]: boolean },
	contributionKinds: { [string]: boolean },
	scopedKind: string,
	allowanceGroups: { [string]: string },
	milestoneKinds: { [string]: string },
	craftGroup: string,
	workGroup: string,
	allowanceUnits: number,
	allowanceSec: number,
	accountingPrefix: string,
	protectedSeasons: { [string]: boolean },
	maxSources: number,
	maxObjectives: number,
	maxSourceXp: number,
	maxSourceUnits: number,
	maxTarget: number,
	maxBonusXp: number,
	maxLabel: number,
	maxEventUnits: number,
}

type Receipt = { eventId: string, atSec: number }
local function readReceipt(value: unknown): Receipt?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if not SocialShape.onlyFields(value, { eventId = true, atSec = true }) then
		return nil
	end
	local eventId = SocialShape.string(raw.eventId)
	local atSec = SocialShape.number(raw.atSec)
	if eventId == nil or atSec == nil then
		return nil
	end
	return { eventId = eventId, atSec = atSec }
end

local function readState(value: unknown): State?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if
		not SocialShape.onlyFields(value, {
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
	then
		return nil
	end
	local schemaVersion = SocialShape.number(raw.schemaVersion)
	local seasonId = SocialShape.string(raw.seasonId)
	local xp = SocialShape.number(raw.xp)
	if schemaVersion == nil or seasonId == nil or xp == nil then
		return nil
	end
	local objectiveProgress = SocialShape.map(raw.objectiveProgress, SocialShape.string, SocialShape.number)
	if objectiveProgress == nil then
		return nil
	end
	local completedObjectives = SocialShape.map(raw.completedObjectives, SocialShape.string, SocialShape.boolean)
	if completedObjectives == nil then
		return nil
	end
	local claimedTiers = SocialShape.map(raw.claimedTiers, SocialShape.string, SocialShape.boolean)
	if claimedTiers == nil then
		return nil
	end
	local receiptOrder = SocialShape.array(raw.receiptOrder, readReceipt)
	if receiptOrder == nil then
		return nil
	end
	local endsAtSec = SocialShape.number(raw.endsAtSec)
	local earnedTier = SocialShape.number(raw.earnedTier)
	if endsAtSec == nil or earnedTier == nil then
		return nil
	end
	local contributionUnitsByWeek = SocialShape.map(raw.contributionUnitsByWeek, SocialShape.string, SocialShape.number)
	if contributionUnitsByWeek == nil then
		return nil
	end
	local doorCycle = SocialShape.string(raw.doorCycle)
	local doorUnits = SocialShape.number(raw.doorUnits)
	if doorCycle == nil or doorUnits == nil then
		return nil
	end
	return {
		schemaVersion = schemaVersion,
		seasonId = seasonId,
		xp = xp,
		objectiveProgress = objectiveProgress,
		completedObjectives = completedObjectives,
		claimedTiers = claimedTiers,
		receiptOrder = receiptOrder,
		endsAtSec = endsAtSec,
		earnedTier = earnedTier,
		contributionUnitsByWeek = contributionUnitsByWeek,
		doorCycle = doorCycle,
		doorUnits = doorUnits,
	}
end

local function readPlaySource(value: unknown): PlaySource?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	local kind = SocialShape.string(raw.kind)
	local xpPerUnit = SocialShape.number(raw.xpPerUnit)
	local maxUnitsPerEvent = SocialShape.number(raw.maxUnitsPerEvent)
	if kind == nil or xpPerUnit == nil or maxUnitsPerEvent == nil then
		return nil
	end
	return { kind = kind, xpPerUnit = xpPerUnit, maxUnitsPerEvent = maxUnitsPerEvent }
end

local function readObjective(value: unknown): Objective?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	local objectiveId = SocialShape.string(raw.objectiveId)
	local week = SocialShape.number(raw.week)
	local kind = SocialShape.string(raw.kind)
	local target = SocialShape.number(raw.target)
	local bonusXp = SocialShape.number(raw.bonusXp)
	local label = SocialShape.string(raw.label)
	if objectiveId == nil or week == nil or kind == nil or target == nil or bonusXp == nil or label == nil then
		return nil
	end
	return { objectiveId = objectiveId, week = week, kind = kind, target = target, bonusXp = bonusXp, label = label }
end

local function readReward(value: unknown): Reward?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	local tier = SocialShape.number(raw.tier)
	local threshold = SocialShape.number(raw.threshold)
	local kind = SocialShape.string(raw.kind)
	local rewardId = SocialShape.string(raw.rewardId)
	local label = SocialShape.string(raw.label)
	if tier == nil or threshold == nil or kind == nil or rewardId == nil or label == nil then
		return nil
	end
	return { tier = tier, threshold = threshold, kind = kind, rewardId = rewardId, label = label }
end

local function readAuthoredDefinition(value: unknown): AuthoredDefinition?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	local seasonId = SocialShape.string(raw.seasonId)
	local startsAtUnix = SocialShape.number(raw.startsAtUnix)
	local weeks = SocialShape.number(raw.weeks)
	local permanent = SocialShape.boolean(raw.permanent)
	if seasonId == nil or startsAtUnix == nil or weeks == nil or permanent == nil then
		return nil
	end
	local playSources = SocialShape.array(raw.playSources, readPlaySource)
	if playSources == nil then
		return nil
	end
	local objectives = SocialShape.array(raw.objectives, readObjective)
	if objectives == nil then
		return nil
	end
	local rewards = SocialShape.array(raw.rewards, readReward)
	if rewards == nil then
		return nil
	end
	return {
		seasonId = seasonId,
		startsAtUnix = startsAtUnix,
		weeks = weeks,
		permanent = permanent,
		playSources = playSources,
		objectives = objectives,
		rewards = rewards,
	}
end

local function readEvent(value: unknown): Event?
	local raw = SocialShape.raw(value)
	if raw == nil then
		return nil
	end
	if
		not SocialShape.onlyFields(
			value,
			{ eventId = true, kind = true, units = true, atSec = true, scope = true, contested = true }
		)
	then
		return nil
	end
	local eventId = SocialShape.string(raw.eventId)
	local kind = SocialShape.string(raw.kind)
	local units = SocialShape.number(raw.units)
	local atSec = SocialShape.number(raw.atSec)
	if eventId == nil or kind == nil or units == nil or atSec == nil then
		return nil
	end
	local scope = SocialShape.string(raw.scope)
	if raw.scope ~= nil and scope == nil then
		return nil
	end
	local contested = SocialShape.boolean(raw.contested)
	if raw.contested ~= nil and contested == nil then
		return nil
	end
	return { eventId = eventId, kind = kind, units = units, atSec = atSec, scope = scope, contested = contested }
end

return {
	readState = readState,
	readAuthoredDefinition = readAuthoredDefinition,
	readEvent = readEvent,
}
