--!strict

export type Config = { meleeTakeover: number, rangedTakeover: number, tauntLead: number }
export type State = { threat: { [string]: number }, targetActorId: string }
export type Candidate = { alive: boolean, eligible: boolean, insideLeash: boolean }
export type Pruned = { removed: { string }, outsideLeash: { string }, wasEngaged: boolean }

local Threat = {}

local function finite(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

function Threat.empty(): State
	return { threat = {}, targetActorId = "" }
end

function Threat.targetFor(threat: { [string]: number }): string
	local bestActorId, bestThreat = "", 0
	for actorId, value in threat do
		if value > bestThreat or (value == bestThreat and (bestActorId == "" or actorId < bestActorId)) then
			bestActorId, bestThreat = actorId, value
		end
	end
	return bestActorId
end

function Threat.remove(state: State, actorId: string): State
	local threat = table.clone(state.threat)
	threat[actorId] = nil
	return { threat = threat, targetActorId = Threat.targetFor(threat) }
end

function Threat.prune(state: State, candidates: { [string]: Candidate }): (State, Pruned)
	local removed: { string } = {}
	local outsideLeash: { string } = {}
	local threat = table.clone(state.threat)
	for actorId in threat do
		local actor = candidates[actorId]
		if actor == nil or not actor.alive or not actor.eligible or not actor.insideLeash then
			threat[actorId] = nil
			table.insert(removed, actorId)
			if actor ~= nil and actor.alive and not actor.insideLeash then
				table.insert(outsideLeash, actorId)
			end
		end
	end
	table.sort(removed)
	table.sort(outsideLeash)
	local result = {
		removed = removed,
		outsideLeash = outsideLeash,
		wasEngaged = state.targetActorId ~= "" or next(state.threat) ~= nil,
	}
	if #removed == 0 then
		return state, result
	end
	return { threat = threat, targetActorId = Threat.targetFor(threat) }, result
end

function Threat.rules(config: Config)
	assert(finite(config.meleeTakeover) and config.meleeTakeover >= 1, "invalid melee takeover")
	assert(finite(config.rangedTakeover) and config.rangedTakeover >= 1, "invalid ranged takeover")
	assert(finite(config.tauntLead) and config.tauntLead > 0, "invalid taunt lead")
	local melee, ranged, lead = config.meleeTakeover, config.rangedTakeover, config.tauntLead
	local function add(state: State, actorId: string, amount: number, inMelee: boolean): (State, boolean)
		assert(actorId ~= "" and finite(amount), "invalid threat addition")
		local threat = table.clone(state.threat)
		local total = (threat[actorId] or 0) + amount
		assert(finite(total), "threat overflow")
		threat[actorId] = total
		local holder = state.targetActorId
		local held = if holder ~= "" then threat[holder] else nil
		local target = holder
		if held == nil then
			target = Threat.targetFor(threat)
		elseif holder ~= actorId and total > held * (if inMelee then melee else ranged) then
			target = actorId
		end
		return { threat = threat, targetActorId = target }, held == nil
	end
	local function taunt(state: State, actorId: string): State
		assert(actorId ~= "", "invalid taunt actor")
		local top = 0
		for _, amount in state.threat do
			top = math.max(top, amount)
		end
		local total = top + lead
		assert(finite(total) and total > top, "taunt overflow")
		local threat = table.clone(state.threat)
		threat[actorId] = total
		return { threat = threat, targetActorId = Threat.targetFor(threat) }
	end
	return table.freeze({ add = add, taunt = taunt })
end

return table.freeze(Threat)
