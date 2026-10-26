--!strict
local SocialShape = require("../social/shape")

export type Phase = "dormant" | "active" | "succeeded" | "failed" | "recovery"

export type WorkPoint = { id: string, actionText: string, position: { x: number, y: number, z: number } }

export type Event = {
	workPoints: { WorkPoint },
	protectionPlacementIds: { string },
	id: string,
	realmId: string,
	zoneKey: string,
	surfacePoiId: string,
	surfaceName: string,
	questId: string,
	mobId: string,
	arrivalText: string,
	activeText: string,
	successText: string,
	failureText: string,
	rewardId: string,
	durationSec: number,
	recoverySec: number,
	maxParticipants: number,
}

export type State = {
	workDone: { [string]: boolean },
	protectionCount: number,
	lastClockSec: number,
	cycle: number,
	phase: Phase,
	startedAtSec: number?,
	endsAtSec: number?,
	recoversAtSec: number?,
	target: number,
	progress: number,
	participantCount: number,
	participants: { [string]: boolean },
	contributions: { [string]: number },
	contributionEvents: { [string]: string },
	claims: { [string]: string },
}

export type Result = {
	state: State,
	ok: boolean,
	reason: string?,
	replayed: boolean,
	rewardId: string?,
	rewardTicket: string?,
}
type Raw = { [unknown]: unknown }

export type Config = {
	realms: { [string]: boolean },
	workPointCount: number,
	minProtectionPlacements: number,
	protectionTarget: number,
	ticketPrefix: string,
	ordinaryTiers: { [string]: boolean },
}
local System = {}
function System.watch(config: Config)
	type Point = { x: number, y: number, z: number }
	local function readPoint(value: unknown): Point?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { x = true, y = true, z = true }) then
			return nil
		end
		local x = SocialShape.number(raw.x)
		if x == nil then
			return nil
		end
		local y = SocialShape.number(raw.y)
		if y == nil then
			return nil
		end
		local z = SocialShape.number(raw.z)
		if z == nil then
			return nil
		end
		return { x = x, y = y, z = z }
	end

	local function readWorkPoint(value: unknown): WorkPoint?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if not SocialShape.onlyFields(value, { id = true, actionText = true, position = true }) then
			return nil
		end
		local id = SocialShape.string(raw.id)
		if id == nil then
			return nil
		end
		local actionText = SocialShape.string(raw.actionText)
		if actionText == nil then
			return nil
		end
		local position = readPoint(raw.position)
		if position == nil then
			return nil
		end
		return { id = id, actionText = actionText, position = position }
	end

	local function readEvent(value: unknown): Event?
		local raw = SocialShape.raw(value)
		if raw == nil then
			return nil
		end
		if
			not SocialShape.onlyFields(value, {
				workPoints = true,
				protectionPlacementIds = true,
				id = true,
				realmId = true,
				zoneKey = true,
				surfacePoiId = true,
				surfaceName = true,
				questId = true,
				mobId = true,
				arrivalText = true,
				activeText = true,
				successText = true,
				failureText = true,
				rewardId = true,
				durationSec = true,
				recoverySec = true,
				maxParticipants = true,
			})
		then
			return nil
		end
		local workPoints = SocialShape.array(raw.workPoints, readWorkPoint)
		if workPoints == nil then
			return nil
		end
		local protectionPlacementIds = SocialShape.array(raw.protectionPlacementIds, SocialShape.string)
		if protectionPlacementIds == nil then
			return nil
		end
		local id = SocialShape.string(raw.id)
		if id == nil then
			return nil
		end
		local realmId = SocialShape.string(raw.realmId)
		if realmId == nil then
			return nil
		end
		local zoneKey = SocialShape.string(raw.zoneKey)
		if zoneKey == nil then
			return nil
		end
		local surfacePoiId = SocialShape.string(raw.surfacePoiId)
		if surfacePoiId == nil then
			return nil
		end
		local surfaceName = SocialShape.string(raw.surfaceName)
		if surfaceName == nil then
			return nil
		end
		local questId = SocialShape.string(raw.questId)
		if questId == nil then
			return nil
		end
		local mobId = SocialShape.string(raw.mobId)
		if mobId == nil then
			return nil
		end
		local arrivalText = SocialShape.string(raw.arrivalText)
		if arrivalText == nil then
			return nil
		end
		local activeText = SocialShape.string(raw.activeText)
		if activeText == nil then
			return nil
		end
		local successText = SocialShape.string(raw.successText)
		if successText == nil then
			return nil
		end
		local failureText = SocialShape.string(raw.failureText)
		if failureText == nil then
			return nil
		end
		local rewardId = SocialShape.string(raw.rewardId)
		if rewardId == nil then
			return nil
		end
		local durationSec = SocialShape.number(raw.durationSec)
		if durationSec == nil then
			return nil
		end
		local recoverySec = SocialShape.number(raw.recoverySec)
		if recoverySec == nil then
			return nil
		end
		local maxParticipants = SocialShape.number(raw.maxParticipants)
		if maxParticipants == nil then
			return nil
		end
		return {
			workPoints = workPoints,
			protectionPlacementIds = protectionPlacementIds,
			id = id,
			realmId = realmId,
			zoneKey = zoneKey,
			surfacePoiId = surfacePoiId,
			surfaceName = surfaceName,
			questId = questId,
			mobId = mobId,
			arrivalText = arrivalText,
			activeText = activeText,
			successText = successText,
			failureText = failureText,
			rewardId = rewardId,
			durationSec = durationSec,
			recoverySec = recoverySec,
			maxParticipants = maxParticipants,
		}
	end

	local EVENT_FIELDS: { [string]: boolean } = {
		workPoints = true,
		protectionPlacementIds = true,
		id = true,
		realmId = true,
		zoneKey = true,
		surfacePoiId = true,
		surfaceName = true,
		questId = true,
		mobId = true,
		arrivalText = true,
		activeText = true,
		successText = true,
		failureText = true,
		rewardId = true,
		durationSec = true,
		recoverySec = true,
		maxParticipants = true,
	}

	local REALMS = config.realms

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function integral(value: unknown): boolean
		return finite(value) and value == math.floor(assert(SocialShape.number(value)))
	end

	local function nonempty(value: unknown): boolean
		return type(value) == "string" and #value > 0
	end

	local function exactFields(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" then
			return false
		end
		for key in assert(SocialShape.raw(value)) do
			if type(key) ~= "string" or fields[key] ~= true then
				return false
			end
		end
		return true
	end

	local function copyState(state: State): State
		return {
			workDone = table.clone(state.workDone),
			protectionCount = state.protectionCount,
			lastClockSec = state.lastClockSec,
			cycle = state.cycle,
			phase = state.phase,
			startedAtSec = state.startedAtSec,
			endsAtSec = state.endsAtSec,
			recoversAtSec = state.recoversAtSec,
			target = state.target,
			progress = state.progress,
			participantCount = state.participantCount,
			participants = table.clone(state.participants),
			contributions = table.clone(state.contributions),
			contributionEvents = table.clone(state.contributionEvents),
			claims = table.clone(state.claims),
		}
	end

	local function result(state: State, ok: boolean, reason: string?, replayed: boolean): Result
		return { state = state, ok = ok, reason = reason, replayed = replayed, rewardId = nil, rewardTicket = nil }
	end

	local function startCycle(state: State, event: Event, nowSec: number, actorId: string): State
		local nextState = copyState(state)
		nextState.lastClockSec = nowSec
		nextState.cycle += 1
		nextState.phase = "active"
		nextState.startedAtSec = nowSec
		nextState.endsAtSec = nowSec + event.durationSec
		nextState.recoversAtSec = nil
		nextState.target = config.workPointCount + config.protectionTarget
		nextState.progress = 0
		nextState.workDone = {}
		nextState.protectionCount = 0
		nextState.participantCount = 1
		nextState.participants = { [actorId] = true }
		nextState.contributions = {}
		nextState.contributionEvents = {}
		nextState.claims = {}
		return nextState
	end

	local PublicWatchCore = {}

	function PublicWatchCore.projectEvent(value: unknown): Event?
		if not exactFields(value, EVENT_FIELDS) then
			return nil
		end
		local source = readEvent(value)
		if source == nil then
			return nil
		end
		for _, key in
			{
				"id",
				"realmId",
				"zoneKey",
				"surfacePoiId",
				"surfaceName",
				"questId",
				"mobId",
				"arrivalText",
				"activeText",
				"successText",
				"failureText",
				"rewardId",
			}
		do
			if not nonempty(assert(SocialShape.raw(source))[key]) then
				return nil
			end
		end
		if REALMS[assert(SocialShape.string(source.realmId))] ~= true then
			return nil
		end
		for _, key in { "durationSec", "recoverySec", "maxParticipants" } do
			if
				not integral(assert(SocialShape.raw(source))[key])
				or assert(SocialShape.number(assert(SocialShape.raw(source))[key])) < 1
			then
				return nil
			end
		end
		if assert(SocialShape.number(source.maxParticipants)) < 1 then
			return nil
		end
		if
			type(source.workPoints) ~= "table"
			or #source.workPoints ~= config.workPointCount
			or type(source.protectionPlacementIds) ~= "table"
			or #source.protectionPlacementIds < config.minProtectionPlacements
		then
			return nil
		end
		local seen: { [string]: boolean } = {}
		for _, point in source.workPoints do
			if
				not exactFields(point, { id = true, actionText = true, position = true })
				or not nonempty(point.id)
				or seen[point.id]
				or not nonempty(point.actionText)
				or not exactFields(point.position, { x = true, y = true, z = true })
			then
				return nil
			end
			for _, axis in { "x", "y", "z" } do
				if not finite(assert(SocialShape.raw(point.position))[axis]) then
					return nil
				end
			end
			seen[point.id] = true
		end
		for _, id in source.protectionPlacementIds do
			if not nonempty(id) or seen[id] then
				return nil
			end
			seen[id] = true
		end
		return SocialShape.freezeDeep(source)
	end

	function PublicWatchCore.protectionBindingsValid(event: Event, placements: unknown, mobs: unknown): boolean
		if type(placements) ~= "table" or type(mobs) ~= "table" then
			return false
		end
		local ordinary: { [string]: boolean } = {}
		for _, value in assert(SocialShape.raw(mobs)) do
			local row = SocialShape.raw(value)
			if
				row ~= nil
				and type(row.tier) == "string"
				and type(row.id) == "string"
				and config.ordinaryTiers[row.tier]
			then
				ordinary[row.id] = true
			end
		end
		local entries = assert(SocialShape.raw(placements))
		for _, id in event.protectionPlacementIds do
			local placement = SocialShape.raw(entries[id])
			if placement == nil or type(placement.mobId) ~= "string" or not ordinary[placement.mobId] then
				return false
			end
		end
		return #event.protectionPlacementIds >= config.minProtectionPlacements
	end

	function PublicWatchCore.emptyState(): State
		return {
			workDone = {},
			protectionCount = 0,
			lastClockSec = 0,
			cycle = 0,
			phase = "dormant",
			startedAtSec = nil,
			endsAtSec = nil,
			recoversAtSec = nil,
			target = 0,
			progress = 0,
			participantCount = 0,
			participants = {},
			contributions = {},
			contributionEvents = {},
			claims = {},
		}
	end

	function PublicWatchCore.sync(state: State, event: Event, nowSec: number): Result
		if not finite(nowSec) or nowSec < state.lastClockSec then
			return result(state, false, "sync_refused", false)
		end
		local nextState = copyState(state)
		nextState.lastClockSec = nowSec
		if nextState.phase == "active" and nowSec >= assert(SocialShape.number(nextState.endsAtSec)) then
			nextState.phase = if nextState.progress >= nextState.target then "succeeded" else "failed"
			nextState.recoversAtSec = nowSec + event.recoverySec
		end
		if
			(nextState.phase == "succeeded" or nextState.phase == "failed" or nextState.phase == "recovery")
			and nextState.recoversAtSec ~= nil
			and nowSec >= nextState.recoversAtSec
		then
			nextState.phase = "dormant"
			nextState.startedAtSec = nil
			nextState.endsAtSec = nil
			nextState.recoversAtSec = nil
			nextState.target = 0
			nextState.progress = 0
			nextState.workDone = {}
			nextState.protectionCount = 0
			nextState.participantCount = 0
			nextState.participants = {}
			nextState.contributions = {}
			nextState.contributionEvents = {}
			nextState.claims = {}
		end
		return result(nextState, true, nil, false)
	end

	function PublicWatchCore.join(
		state: State,
		event: Event,
		actorId: string,
		actorRealmId: string,
		nowSec: number
	): Result
		local synced = PublicWatchCore.sync(state, event, nowSec)
		if not synced.ok then
			return synced
		end
		if not nonempty(actorId) or actorRealmId ~= event.realmId then
			return result(synced.state, false, "participant_refused", false)
		end
		if synced.state.phase == "dormant" then
			return result(startCycle(synced.state, event, nowSec, actorId), true, nil, false)
		end
		if synced.state.phase ~= "active" then
			return result(synced.state, false, "event_not_active", false)
		end
		if synced.state.participants[actorId] then
			return result(synced.state, true, nil, true)
		end
		if synced.state.participantCount >= event.maxParticipants then
			return result(synced.state, false, "watch_full", false)
		end
		local nextState = copyState(synced.state)
		nextState.participants[actorId] = true
		nextState.participantCount += 1
		return result(nextState, true, nil, false)
	end

	local function finish(nextState: State, event: Event, nowSec: number): Result
		nextState.progress = nextState.protectionCount
		for _ in nextState.workDone do
			nextState.progress += 1
		end
		if nextState.progress == config.workPointCount + config.protectionTarget then
			nextState.phase = "succeeded"
			nextState.recoversAtSec = nowSec + event.recoverySec
		end
		return result(nextState, true, nil, false)
	end

	function PublicWatchCore.work(
		state: State,
		event: Event,
		actorId: string,
		realmId: string,
		pointId: string,
		nowSec: number
	): Result
		local synced = PublicWatchCore.sync(state, event, nowSec)
		if not synced.ok then
			return synced
		end
		local nextState = synced.state
		if realmId ~= event.realmId or not nextState.participants[actorId] then
			return result(nextState, false, "contributor_refused", false)
		end
		local authored = false
		for _, point in event.workPoints do
			if point.id == pointId then
				authored = true
			end
		end
		if not authored then
			return result(nextState, false, "work_refused", false)
		end
		if nextState.workDone[pointId] then
			return result(nextState, true, nil, true)
		end
		if nextState.phase ~= "active" then
			return result(nextState, false, "event_not_active", false)
		end
		nextState.workDone[pointId] = true
		nextState.contributions[actorId] = (nextState.contributions[actorId] or 0) + 1
		return finish(nextState, event, nowSec)
	end

	function PublicWatchCore.protect(
		state: State,
		event: Event,
		eventId: string,
		actorIds: { string },
		nowSec: number
	): Result
		local synced = PublicWatchCore.sync(state, event, nowSec)
		if not synced.ok then
			return synced
		end
		local nextState = synced.state
		if nextState.contributionEvents[eventId] ~= nil then
			return result(nextState, true, nil, true)
		end
		if nextState.phase ~= "active" or nextState.protectionCount >= config.protectionTarget then
			return result(nextState, false, "protection_complete", false)
		end
		local eligible: { [string]: boolean } = {}
		for _, actorId in actorIds do
			if nextState.participants[actorId] then
				eligible[actorId] = true
			end
		end
		if next(eligible) == nil or not nonempty(eventId) then
			return result(nextState, false, "contributor_refused", false)
		end
		for actorId in eligible do
			nextState.contributions[actorId] = (nextState.contributions[actorId] or 0) + 1
		end
		nextState.contributionEvents[eventId] = "protection"
		nextState.protectionCount += 1
		return finish(nextState, event, nowSec)
	end

	function PublicWatchCore.leave(state: State, event: Event, actorId: string, nowSec: number): Result
		local synced = PublicWatchCore.sync(state, event, nowSec)
		if not synced.ok then
			return synced
		end
		local nextState = synced.state
		if nextState.phase ~= "active" or not nextState.participants[actorId] then
			return result(nextState, true, nil, true)
		end
		nextState.participants[actorId] = nil
		nextState.participantCount -= 1
		return result(nextState, true, nil, false)
	end

	function PublicWatchCore.claim(
		state: State,
		event: Event,
		actorId: string,
		actorRealmId: string,
		nowSec: number
	): Result
		local synced = PublicWatchCore.sync(state, event, nowSec)
		if not synced.ok or synced.state.phase ~= "succeeded" then
			return result(synced.state, false, "claim_unavailable", false)
		end
		state = synced.state
		if not nonempty(actorId) or actorRealmId ~= event.realmId or (state.contributions[actorId] or 0) < 1 then
			return result(state, false, "no_eligible_contribution", false)
		end
		local ticket = table.concat({ config.ticketPrefix, event.id, tostring(state.cycle), actorId }, ":")
		local prior = state.claims[actorId]
		if prior ~= nil then
			local replay = result(state, true, nil, true)
			replay.rewardId = event.rewardId
			replay.rewardTicket = prior
			return replay
		end
		local nextState = copyState(state)
		nextState.lastClockSec = nowSec
		nextState.claims[actorId] = ticket
		local accepted = result(nextState, true, nil, false)
		accepted.rewardId = event.rewardId
		accepted.rewardTicket = ticket
		return accepted
	end

	return PublicWatchCore
end
return System
