--!strict
export type Refresh<C> = { previous: C?, character: C?, invalid: boolean? }
export type Observation<C> = {
	character: C?,
	engineCharacter: C?,
	liveBody: boolean,
	actorPresent: boolean,
	alive: boolean,
	hp: number?,
	zoneId: string,
}
export type Dependencies<P, C, H, O, S> = {
	owner: O,
	child: (O) -> O,
	dispose: (O) -> (),
	own: (O, () -> ()) -> (),
	clock: () -> number,
	schedule: (number, () -> ()) -> () -> (),
	spawn: (() -> ()) -> () -> (),
	pollSec: number,
	observe: (O, P, (Observation<C>) -> ()) -> (),
	sample: (P) -> Observation<C>,
	stamp: (P, string) -> boolean,
	record: (P, string) -> (),
	error: (P, unknown) -> (),
	characterChanged: (P) -> (),
	rememberBody: (P) -> (),
	nextPending: (boolean?, boolean, number?, number, boolean) -> number?,
	recordDeath: (P) -> (),
	onCancel: (P, string) -> (),
	onUntrack: (P) -> (),
	canSchedule: (P) -> boolean,
	delaySec: () -> number,
	automatic: (P) -> boolean,
	respawn: (P) -> boolean,
	ready: (P) -> (),
	isNative: (P) -> boolean,
	currentCharacter: (P) -> C?,
	observeCharacter: (O, P, (C?) -> ()) -> (),
	findHumanoid: (C) -> H?,
	waitHumanoid: (C) -> H?,
	prepareHumanoid: (H) -> (),
	observeDeath: (O, H, () -> ()) -> (),
	isDead: (H) -> boolean,
	engineDeath: (P) -> (),
	context: (P) -> S?,
	present: (P) -> boolean,
	refreshPending: (P, boolean) -> (),
}
local Respawn = {}
export type Host<P, C, O> = {
	pendingAt: { [P]: number },
	watchers: { [P]: O },
	plannedRefresh: { [P]: boolean },
	refreshes: { [P]: Refresh<C> },
	cancelPending: (P, string) -> (),
	schedulePending: (P) -> (),
	reschedule: () -> (),
	track: (P) -> (),
	untrack: (P) -> (),
	refresh: <F>(
		P,
		(() -> boolean) -> (unknown, string?, F?),
		() -> boolean,
		() -> (),
		(F?, () -> boolean) -> ()
	) -> boolean,
	dispose: () -> (),
}
function Respawn.completeSpawn<F>(
	spawn: () -> (unknown, string?, F?),
	valid: () -> boolean,
	current: () -> boolean,
	pause: () -> (),
	restore: (F?) -> ()
): (boolean, string?)
	local reason = "spawn_invalid"
	for attempt = 1, 3 do
		if not current() then
			return false, "spawn_cancelled"
		end
		local ok, accepted, failure, destination = pcall(spawn)
		if ok and accepted == true and valid() and current() then
			if not valid() then
				return false, "body_invalid"
			end
			local restored, refusal = pcall(restore, destination)
			if not restored then
				return false, "restore_error:" .. tostring(refusal)
			end
			return true, nil
		end
		reason = if not ok then "spawn_error" else failure or "body_invalid"
		if attempt < 3 then
			pause()
		end
	end
	return false, reason
end
function Respawn.create<P, C, H, O, S>(deps: Dependencies<P, C, H, O, S>): Host<P, C, O>
	local pendingAt: { [P]: number } = {}
	local scheduled: { [P]: { cancel: () -> () } } = {}
	local watchers: { [P]: O } = {}
	local lastAlive: { [P]: boolean } = {}
	local plannedRefresh: { [P]: boolean } = {}
	local refreshes: { [P]: Refresh<C> } = {}
	local function cancelPending(player: P, why: string)
		local entry = scheduled[player]
		local held = entry ~= nil or pendingAt[player] ~= nil
		if entry ~= nil then
			scheduled[player] = nil
			entry.cancel()
		end
		pendingAt[player] = nil
		deps.onCancel(player, why)
		if held then
			deps.record(player, "cancelled:" .. why)
		end
	end
	local function schedulePending(player: P)
		local startedAt = pendingAt[player]
		if startedAt == nil or scheduled[player] ~= nil or not deps.canSchedule(player) then
			return
		end
		local entry = { cancel = function() end }
		scheduled[player] = entry
		entry.cancel = deps.schedule(math.max(0, startedAt + deps.delaySec() - deps.clock()), function()
			if scheduled[player] ~= entry or pendingAt[player] ~= startedAt then
				return
			end
			scheduled[player] = nil
			if deps.automatic(player) then
				pendingAt[player] = nil
				deps.respawn(player)
			else
				deps.ready(player)
				deps.record(player, "awaiting_recovery")
			end
		end)
		deps.record(player, "scheduled")
	end
	local function reschedule()
		for player in pendingAt do
			local entry = scheduled[player]
			if entry ~= nil then
				scheduled[player] = nil
				entry.cancel()
			end
			schedulePending(player)
		end
	end
	local function watchCharacter(player: P, trackedOwner: O)
		if not deps.isNative(player) then
			return
		end
		local generation = 0
		local characterOwner: O? = nil
		local function clear()
			if characterOwner ~= nil then
				deps.dispose(characterOwner)
				characterOwner = nil
			end
		end
		local function bindHumanoid(owner: O, humanoid: H)
			deps.prepareHumanoid(humanoid)
			deps.observeDeath(owner, humanoid, function()
				deps.engineDeath(player)
			end)
			if deps.isDead(humanoid) then
				deps.engineDeath(player)
			end
		end
		local function bindCharacter(character: C?)
			local refresh = refreshes[player]
			if refresh ~= nil and character ~= refresh.previous then
				if refresh.character == nil and character ~= nil then
					refresh.character = character
				elseif character ~= refresh.character then
					refresh.invalid = true
				end
			end
			generation += 1
			local currentGeneration = generation
			clear()
			plannedRefresh[player] = nil
			if character == nil then
				return
			end
			local activeOwner = deps.child(trackedOwner)
			characterOwner = activeOwner
			local humanoid = deps.findHumanoid(character)
			if humanoid ~= nil then
				bindHumanoid(activeOwner, humanoid)
				return
			end
			local cancel = deps.spawn(function()
				local waited = deps.waitHumanoid(character)
				if generation == currentGeneration and waited ~= nil then
					bindHumanoid(activeOwner, waited)
				end
			end)
			deps.own(activeOwner, cancel)
		end
		deps.observeCharacter(trackedOwner, player, bindCharacter)
		bindCharacter(deps.currentCharacter(player))
		deps.own(trackedOwner, function()
			generation += 1
			clear()
		end)
	end
	local function untrack(player: P)
		local owner = watchers[player]
		if owner ~= nil then
			deps.dispose(owner)
			watchers[player] = nil
		end
		lastAlive[player] = nil
		cancelPending(player, "untracked")
		if refreshes[player] ~= nil and deps.isNative(player) then
			deps.refreshPending(player, false)
		end
		refreshes[player], plannedRefresh[player] = nil, nil
		deps.onUntrack(player)
	end
	local function track(player: P)
		if watchers[player] ~= nil then
			return
		end
		local owner = deps.child(deps.owner)
		watchers[player] = owner
		local stamped: string? = nil
		local function stamp(detail: string)
			if detail ~= stamped then
				stamped = if deps.stamp(player, string.sub(detail, 1, 50)) then detail else nil
			end
		end
		stamp("tracked")
		local observedCharacter: C? = nil
		local observedLive = false
		local function evaluate(observation: Observation<C>)
			if observation.character == nil then
				stamp("character_nil")
				cancelPending(player, "character_nil")
				lastAlive[player] = nil
				return
			end
			if observation.engineCharacter ~= observedCharacter then
				observedCharacter, observedLive = observation.engineCharacter, false
				deps.characterChanged(player)
			end
			if observation.liveBody then
				deps.rememberBody(player)
				observedLive = true
			elseif observedLive and observation.engineCharacter ~= nil and not plannedRefresh[player] then
				observedLive = false
				deps.engineDeath(player)
			end
			local previous = lastAlive[player]
			lastAlive[player] = observation.alive
			stamp(
				("hp=%s,alive=%s,prev=%s,zone=%s"):format(
					if observation.hp ~= nil then tostring(observation.hp) else "absent",
					tostring(observation.alive),
					tostring(previous),
					observation.zoneId
				)
			)
			local prior = pendingAt[player]
			if not observation.actorPresent then
				cancelPending(player, "policy_none")
				return
			end
			local nextAt = deps.nextPending(
				previous,
				observation.alive,
				prior,
				deps.clock(),
				observation.hp ~= nil and observation.hp <= 0
			)
			if nextAt == nil then
				cancelPending(player, if observation.alive then "alive" else "policy_none")
			else
				if nextAt ~= prior then
					pendingAt[player] = nextAt
					deps.record(player, "pending")
				end
				deps.recordDeath(player)
			end
		end
		local polling = true
		local function poll()
			if not polling or watchers[player] ~= owner then
				return
			end
			local ok, reason = pcall(function()
				evaluate(deps.sample(player))
			end)
			if not ok then
				deps.error(player, reason)
			end
			deps.schedule(deps.pollSec, poll)
		end
		deps.own(owner, function()
			polling = false
		end)
		local ok, reason = pcall(function()
			deps.observe(owner, player, evaluate)
			deps.schedule(deps.pollSec, poll)
			watchCharacter(player, owner)
		end)
		if not ok then
			watchers[player] = nil
			deps.dispose(owner)
			error(reason, 0)
		end
	end
	local function refresh<F>(
		player: P,
		spawn: (() -> boolean) -> (unknown, string?, F?),
		valid: () -> boolean,
		pause: () -> (),
		restore: (F?, () -> boolean) -> ()
	): boolean
		local owner, context = watchers[player], deps.context(player)
		if owner == nil or context == nil then
			return false
		end
		local native = deps.isNative(player)
		local entry: Refresh<C> = { previous = deps.currentCharacter(player) }
		refreshes[player] = entry
		local function current(): boolean
			return refreshes[player] == entry
				and watchers[player] == owner
				and deps.context(player) == context
				and entry.invalid ~= true
				and (not native or deps.present(player))
		end
		if native then
			deps.refreshPending(player, true)
		end
		local ok, reason = Respawn.completeSpawn(
			function(): (unknown, string?, F?)
				if not native then
					return true, nil, nil
				end
				entry.previous, entry.character = deps.currentCharacter(player), nil
				plannedRefresh[player] = true
				return spawn(current)
			end,
			valid,
			current,
			pause,
			function(destination: F?)
				restore(destination, current)
			end
		)
		if refreshes[player] == entry then
			plannedRefresh[player] = nil
			refreshes[player] = nil
			if native then
				deps.refreshPending(player, false)
			end
			deps.record(player, if ok then "respawned" else "cancelled:" .. (reason or "spawner_failed"))
		end
		return ok
	end
	local function dispose()
		for player in scheduled do
			cancelPending(player, "disposed")
		end
		for player in watchers do
			untrack(player)
		end
		table.clear(watchers)
		table.clear(lastAlive)
		table.clear(pendingAt)
		table.clear(plannedRefresh)
		table.clear(refreshes)
	end
	local result: Host<P, C, O> = {
		pendingAt = pendingAt,
		watchers = watchers,
		plannedRefresh = plannedRefresh,
		refreshes = refreshes,
		cancelPending = cancelPending,
		schedulePending = schedulePending,
		reschedule = reschedule,
		track = track,
		untrack = untrack,
		refresh = refresh,
		dispose = dispose,
	}
	return result
end
return table.freeze(Respawn)
