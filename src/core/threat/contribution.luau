--!strict
export type Point = { x: number, y: number?, z: number }
export type DungeonAdmission = { dungeonId: string, cycleId: string, characterId: string }
export type Relation = "self" | "ally" | "enemy"

export type Observation = {
	kind: string,
	sourceActorId: string,
	targetActorId: string,
	targetRelation: Relation,
	contested: boolean,
	targetEligible: boolean,
	attemptedAmount: number,
	effectiveAmount: number,
	eligibleAmountCap: number,
}

export type Credit = {
	category: string,
	amount: number,
	sourceActorId: string,
	targetActorId: string,
}

export type ActorContribution = {
	activeSec: number,
	firstActionSec: number?,
	lastActionSec: number?,
	interruptSec: number?,
	lastSeenSec: number?,
}

export type EndActor = {
	characterId: string,
	pos: { x: number, y: number?, z: number },
	distance: number,
	alive: boolean,
	defeatedAtSec: number?,
	dungeonAdmission: DungeonAdmission?,
}

export type Encounter = {
	startedAtSec: number,
	endedAtSec: number?,
	actors: { [string]: ActorContribution },
	endActors: { [string]: EndActor }?,
}

export type Participant = {
	hp: number,
	pos: Point,
	characterId: string?,
	defeatedAtSec: number?,
	dungeonAdmission: DungeonAdmission?,
}

export type Config = {
	read categories: { read [string]: string },
	read eligibleRelation: (Observation) -> boolean,
	read participationRadius: number,
	read inactiveSeconds: number,
	read recentDefeatSeconds: number,
	read rewardRadius: number,
	read shortEncounterSeconds: number,
	read actionSpanSeconds: number,
	read interruptActiveSeconds: number,
	read interruptKind: string,
}

local System = {}
function System.create(config: Config)
	local CombatContribution = {}
	local CATEGORY_BY_KIND = config.categories
	local function finite(value: number): boolean
		return value == value and value ~= math.huge and value ~= -math.huge
	end

	local eligibleRelation = config.eligibleRelation

	local function creditFor(observation: Observation): Credit?
		local category = CATEGORY_BY_KIND[observation.kind]
		if
			category == nil
			or observation.sourceActorId == ""
			or observation.targetActorId == ""
			or not observation.contested
			or not observation.targetEligible
			or not eligibleRelation(observation)
		then
			return nil
		end
		if
			not finite(observation.attemptedAmount)
			or not finite(observation.effectiveAmount)
			or not finite(observation.eligibleAmountCap)
		then
			return nil
		end
		local amount = math.min(observation.attemptedAmount, observation.effectiveAmount, observation.eligibleAmountCap)
		if amount <= 0 then
			return nil
		end
		return {
			category = category,
			amount = amount,
			sourceActorId = observation.sourceActorId,
			targetActorId = observation.targetActorId,
		}
	end

	function CombatContribution.asParticipant(actor: Participant): Participant
		return actor
	end

	function CombatContribution.record(encounter: Encounter?, actorId: string, kind: string, nowSec: number): Encounter
		local nextRecord: Encounter = if encounter == nil
			then { startedAtSec = nowSec, endedAtSec = nil, actors = {} }
			else {
				startedAtSec = encounter.startedAtSec,
				endedAtSec = encounter.endedAtSec,
				actors = table.clone(encounter.actors),
			}
		local previous = nextRecord.actors[actorId]
		local row: ActorContribution = if previous == nil then { activeSec = 0 } else table.clone(previous)
		row.firstActionSec = row.firstActionSec or nowSec
		row.lastActionSec = nowSec
		if kind == config.interruptKind then
			row.interruptSec = nowSec
		end
		nextRecord.actors[actorId] = row
		return nextRecord
	end

	function CombatContribution.observe<Actor>(
		encounter: Encounter?,
		actors: { [string]: Actor },
		participant: (Actor) -> Participant,
		center: Point,
		nowSec: number,
		dt: number
	): Encounter?
		if encounter == nil or encounter.endedAtSec ~= nil then
			return encounter
		end
		local nextRecord: Encounter = { startedAtSec = encounter.startedAtSec, actors = table.clone(encounter.actors) }
		for actorId, source in actors do
			local actor = participant(source)
			if
				actor.hp <= 0
				or (actor.pos.x - center.x) ^ 2 + (actor.pos.z - center.z) ^ 2 > config.participationRadius ^ 2
			then
				continue
			end
			local existing = nextRecord.actors[actorId]
			local row: ActorContribution = if existing == nil then { activeSec = 0 } else table.clone(existing)
			row.activeSec += dt
			row.lastSeenSec = nowSec
			nextRecord.actors[actorId] = row
		end
		for actorId, row in nextRecord.actors do
			if nowSec - (row.lastSeenSec or row.lastActionSec or nowSec) > config.inactiveSeconds then
				nextRecord.actors[actorId] = nil
			end
		end
		return nextRecord
	end

	function CombatContribution.finish<Actor>(
		encounter: Encounter?,
		nowSec: number,
		actors: { [string]: Actor },
		participant: (Actor) -> Participant,
		center: Point
	): Encounter?
		if encounter == nil then
			return nil
		end
		if encounter.endedAtSec ~= nil then
			return encounter
		end
		local result: Encounter = table.clone(encounter)
		local endActors: { [string]: EndActor } = {}
		result.endedAtSec = nowSec
		result.endActors = endActors
		for actorId in encounter.actors do
			local source = actors[actorId]
			local actor = if source == nil then nil else participant(source)
			if actor ~= nil and actor.characterId ~= nil and actor.characterId ~= "" then
				local dx, dz = actor.pos.x - center.x, actor.pos.z - center.z
				local dy = if center.y == nil
					then 0
					else if actor.pos.y ~= nil then actor.pos.y - center.y else math.huge
				endActors[actorId] = {
					characterId = actor.characterId,
					pos = { x = actor.pos.x, y = actor.pos.y, z = actor.pos.z },
					distance = math.sqrt(dx * dx + dy * dy + dz * dz),
					alive = actor.hp > 0,
					defeatedAtSec = actor.defeatedAtSec,
					dungeonAdmission = if actor.dungeonAdmission == nil
						then nil
						else table.clone(actor.dungeonAdmission),
				}
			end
		end
		return result
	end

	function CombatContribution.eligibleAtEnd(encounter: Encounter?, actorId: string, characterId: string): boolean
		if encounter == nil or encounter.endActors == nil or encounter.endedAtSec == nil then
			return false
		end
		local row = encounter.endActors[actorId]
		if row == nil or row.characterId ~= characterId then
			return false
		end
		local defeatedAtSec = row.defeatedAtSec
		local recent = defeatedAtSec ~= nil
			and encounter.endedAtSec >= defeatedAtSec
			and encounter.endedAtSec - defeatedAtSec <= config.recentDefeatSeconds
		return CombatContribution.eligible(encounter, actorId, row.distance, row.alive or recent)
	end

	function CombatContribution.eligible(
		encounter: Encounter?,
		actorId: string,
		distance: number,
		aliveOrRecent: boolean
	): boolean
		if
			encounter == nil
			or encounter.endedAtSec == nil
			or distance ~= distance
			or distance > config.rewardRadius
			or distance < 0
			or not aliveOrRecent
		then
			return false
		end
		local row = encounter.actors[actorId]
		if row == nil or row.firstActionSec == nil or row.lastActionSec == nil then
			return false
		end
		if encounter.endedAtSec - encounter.startedAtSec <= config.shortEncounterSeconds then
			return true
		end
		return row.lastActionSec - row.firstActionSec >= config.actionSpanSeconds
			or (row.interruptSec ~= nil and row.activeSec >= config.interruptActiveSeconds)
	end

	CombatContribution.CATEGORY_BY_KIND = CATEGORY_BY_KIND
	CombatContribution.creditFor = creditFor

	return CombatContribution
end
return table.freeze(System)
