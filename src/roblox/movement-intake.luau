--!strict

local Value = require("../core/value")

local MovementIntake = {}

export type Point = { x: number, z: number }
export type State = {
	hp: number,
	facing: Point?,
	movement: Point?,
	movementEpoch: number?,
	movementSequence: number?,
}
export type Observation = { x: number, z: number, hp: number }
export type Normalized = { sequence: number, intent: Point, strafe: boolean?, epoch: number? }
export type Ack = { epoch: number, sequence: number, intent: Point, acceptedCount: number }
export type Dependencies<P, B> = {
	clock: () -> number,
	registerClose: (() -> ()) -> () -> (),
	remote: {
		connect: ((boolean, P, unknown) -> ()) -> () -> (),
		acknowledge: (P, Ack) -> (),
	},
	step: { connect: (() -> ()) -> () -> () },
	players: {
		validatePlayer: (P) -> boolean,
		isPresent: (P) -> boolean,
		identity: (P) -> number,
		currentBody: (P) -> B?,
	},
	normalize: (unknown) -> Normalized?,
	control: {
		apply: (B, Point, Point?) -> boolean,
		restore: (B, number, number) -> boolean,
	},
	snapshot: {
		state: (P) -> State?,
		reset: (P, number) -> (),
		move: (P, Point, boolean, number, number) -> boolean,
		observe: (B) -> Observation?,
		setPlayerSnapshot: (P, number, number, number, boolean?) -> boolean,
		travelRevision: (B) -> number,
	},
	mark: (string, string?) -> (),
}

export type StopResult = { phase: string }
export type Started<P> = {
	phase: "movement_authority_started",
	admitPlayer: (P) -> boolean,
	removePlayer: (P) -> boolean,
	stop: () -> StopResult,
	dispose: () -> StopResult,
}
export type Refused = { read phase: "movement_authority_refused", read reason: string }
type Live = { hp: number, facing: Point, movement: Point?, movementEpoch: number, movementSequence: number? }
type Entry<P, B> = {
	player: P,
	userId: number,
	body: B,
	epoch: number,
	sequence: number,
	acceptedCount: number,
	acknowledgedSequence: number,
	stopSequence: number?,
	invalidObservations: number,
	intent: Point,
	inert: boolean,
	lastAccepted: Point?,
	lastAcceptedAt: number?,
	windowStart: { x: number, z: number, at: number }?,
	travelRevision: number?,
}

local MAX_SAFE_INTEGER = 9007199254740991
local MAX_INVALID_OBSERVATIONS = 3
local MAX_STEP_DISPLACEMENT = 24
local MAX_SUSTAINED_SPEED = 48

local finite = Value.finite

local function connection(value: unknown): boolean
	return type(value) == "function"
end

local function userId(value: number): boolean
	return finite(value) and value == math.floor(value) and value > 0 and value <= MAX_SAFE_INTEGER
end

local function validEpoch(value: number?): boolean
	return value ~= nil and finite(value) and value > 0 and value <= MAX_SAFE_INTEGER and value % 1 == 0
end

local function unitFacing(point: Point): boolean
	return math.abs(point.x * point.x + point.z * point.z - 1) <= 1e-6
end

local function validIntent(value: Point): boolean
	if not finite(value.x) or not finite(value.z) then
		return false
	end
	return value.x >= -1
		and value.x <= 1
		and value.z >= -1
		and value.z <= 1
		and value.x * value.x + value.z * value.z <= 1 + 1e-6
end

local function validNormalized(value: Normalized?): boolean
	if value == nil or type(value.strafe) == "number" then
		return false
	end
	return (value.strafe == nil or type(value.strafe) == "boolean")
		and (value.epoch == nil or validEpoch(value.epoch))
		and finite(value.sequence)
		and value.sequence >= 0
		and value.sequence <= 2147483647
		and value.sequence % 1 == 0
		and validIntent(value.intent)
end

local function observationFault(value: Observation?): string?
	if value == nil then
		return "shape:nil"
	end
	if not finite(value.x) then
		return "x_nonfinite:" .. tostring(value.x)
	end
	if not finite(value.z) then
		return "z_nonfinite:" .. tostring(value.z)
	end
	if not finite(value.hp) then
		return "hp_nonfinite:" .. tostring(value.hp)
	end
	if value.hp == 0 then
		return "body_dead"
	end
	if value.hp < 0 then
		return "hp_not_positive:" .. tostring(value.hp)
	end
	return nil
end

local function refusal(reason: string): Refused
	local result: Refused = { phase = "movement_authority_refused", reason = reason }
	return result
end

function MovementIntake.start<P, B>(dependencies: Dependencies<P, B>): Started<P> | Refused
	local ports: Dependencies<P, B> = {
		clock = dependencies.clock,
		registerClose = dependencies.registerClose,
		remote = { connect = dependencies.remote.connect, acknowledge = dependencies.remote.acknowledge },
		step = { connect = dependencies.step.connect },
		players = {
			validatePlayer = dependencies.players.validatePlayer,
			isPresent = dependencies.players.isPresent,
			identity = dependencies.players.identity,
			currentBody = dependencies.players.currentBody,
		},
		normalize = dependencies.normalize,
		control = { apply = dependencies.control.apply, restore = dependencies.control.restore },
		snapshot = {
			state = dependencies.snapshot.state,
			reset = dependencies.snapshot.reset,
			move = dependencies.snapshot.move,
			observe = dependencies.snapshot.observe,
			setPlayerSnapshot = dependencies.snapshot.setPlayerSnapshot,
			travelRevision = dependencies.snapshot.travelRevision,
		},
		mark = dependencies.mark,
	}
	local entries: { [P]: Entry<P, B> } = {}
	local users: { [number]: Entry<P, B> } = {}
	local stopped = false
	local stoppedResult: StopResult? = nil
	local remoteConnection: (() -> ())? = nil
	local stepConnection: (() -> ())? = nil
	local closeDispose: (() -> ())? = nil
	local stop: (() -> StopResult)? = nil
	local marked: { [string]: boolean } = {}

	local function disconnect(handle: (() -> ())?): boolean
		return handle ~= nil and (pcall(handle))
	end

	local function mark(phase: string, detail: string?)
		if marked[phase] == true then
			return
		end
		local ok = pcall(ports.mark, phase, detail)
		if ok then
			marked[phase] = true
		end
	end

	local function present(player: P): boolean
		local validOk, valid = pcall(ports.players.validatePlayer, player)
		local presentOk, visible = pcall(ports.players.isPresent, player)
		return validOk and valid == true and presentOk and visible == true
	end

	local function current(entry: Entry<P, B>): boolean
		if stopped or entries[entry.player] ~= entry or users[entry.userId] ~= entry or not present(entry.player) then
			return false
		end
		local bodyOk, body = pcall(ports.players.currentBody, entry.player)
		return bodyOk and body ~= nil and body == entry.body
	end

	local function movementState(entry: Entry<P, B>): Live?
		local state = ports.snapshot.state(entry.player)
		if state == nil then
			return nil
		end
		local facing, epoch = state.facing, state.movementEpoch
		if
			facing == nil
			or epoch == nil
			or not finite(facing.x)
			or not finite(facing.z)
			or not unitFacing(facing)
			or not validEpoch(epoch)
		then
			return nil
		end
		return {
			hp = state.hp,
			facing = facing,
			movement = state.movement,
			movementEpoch = epoch,
			movementSequence = state.movementSequence,
		}
	end

	local function zero(entry: Entry<P, B>): boolean
		local state = movementState(entry)
		local appliedOk, applied =
			pcall(ports.control.apply, entry.body, { x = 0, z = 0 }, if state ~= nil then state.facing else nil)
		return appliedOk and applied == true
	end

	local function finalSnapshot(entry: Entry<P, B>): boolean
		local observedOk, observed = pcall(ports.snapshot.observe, entry.body)
		if not observedOk or observed == nil or observationFault(observed) ~= nil then
			return false
		end
		local writtenOk, written =
			pcall(ports.snapshot.setPlayerSnapshot, entry.player, observed.x, observed.z, observed.hp, nil)
		return writtenOk and written == true
	end

	local function revoke(entry: Entry<P, B>, reason: string?, detail: string?, skipSnapshot: boolean?): boolean
		if entries[entry.player] ~= entry then
			return false
		end
		if reason ~= nil then
			mark("movement_revoked_" .. reason, detail)
		end
		pcall(ports.snapshot.reset, entry.player, entry.epoch)
		entry.inert = true
		entries[entry.player] = nil
		if users[entry.userId] == entry then
			users[entry.userId] = nil
		end
		local zeroed = zero(entry)
		local snapshotted = if skipSnapshot then true else finalSnapshot(entry)
		return zeroed and snapshotted
	end

	local function admitPlayer(player: P): boolean
		if stopped or not present(player) or entries[player] ~= nil then
			return false
		end
		local identityOk, id = pcall(ports.players.identity, player)
		local bodyOk, body = pcall(ports.players.currentBody, player)
		if not identityOk or not userId(id) or users[id] ~= nil or not bodyOk or body == nil then
			return false
		end
		local state = ports.snapshot.state(player)
		if state == nil or state.hp <= 0 or state.facing == nil or state.movementEpoch == nil then
			return false
		end
		local nextEpoch = state.movementEpoch
		if not validIntent(state.facing) or not unitFacing(state.facing) or not validEpoch(nextEpoch) then
			return false
		end

		local entry: Entry<P, B> = {
			player = player,
			userId = id,
			body = body,
			epoch = nextEpoch,
			sequence = -1,
			acceptedCount = 0,
			acknowledgedSequence = 0,
			invalidObservations = 0,
			intent = { x = 0, z = 0 },
			inert = false,
		}
		entries[player] = entry
		users[id] = entry
		if not current(entry) then
			revoke(entry, "admit_identity")
			return false
		end
		if not zero(entry) then
			revoke(entry, "admit_control_refused")
			return false
		end
		if not current(entry) then
			revoke(entry, "admit_identity_after_control")
			return false
		end
		local observedOk, observed = pcall(ports.snapshot.observe, entry.body)
		local timeOk, at = pcall(ports.clock)
		local travelOk, travelRevision = pcall(ports.snapshot.travelRevision, entry.body)
		if
			not observedOk
			or observed == nil
			or observationFault(observed) ~= nil
			or not timeOk
			or not finite(at)
			or not travelOk
			or not finite(travelRevision)
		then
			revoke(entry, "admit_observation_invalid", nil, true)
			return false
		end
		entry.lastAccepted = { x = observed.x, z = observed.z }
		entry.lastAcceptedAt = at
		entry.windowStart = { x = observed.x, z = observed.z, at = at }
		entry.travelRevision = travelRevision
		return true
	end

	local function removePlayer(player: P): boolean
		local entry = entries[player]
		if entry == nil then
			return false
		end
		return revoke(entry, "player_removed", nil, entry.inert)
	end

	local function receive(allowed: boolean, player: P, raw: unknown)
		if stopped then
			return
		end
		local entry = entries[player]
		if entry == nil or not current(entry) then
			if entry ~= nil then
				revoke(entry, "receive_identity")
			end
			return
		end
		if entry.inert then
			return
		end
		local normalizedOk, normalized = pcall(ports.normalize, raw)
		if
			not normalizedOk
			or normalized == nil
			or not validNormalized(normalized)
			or normalized.sequence <= entry.sequence
		then
			return
		end
		local nowOk, now = pcall(ports.clock)
		if not nowOk or not finite(now) then
			return
		end
		local wasMoving = entry.intent.x ~= 0 or entry.intent.z ~= 0
		local isMoving = normalized.intent.x ~= 0 or normalized.intent.z ~= 0
		if not (allowed == true or (allowed == false and wasMoving and not isMoving)) or not current(entry) then
			return
		end
		local state = movementState(entry)
		if state == nil or state.hp <= 0 then
			return
		end
		if state.movementEpoch ~= entry.epoch then
			entry.epoch = state.movementEpoch
			entry.sequence, entry.acceptedCount, entry.acknowledgedSequence = -1, 0, 0
			entry.intent = { x = 0, z = 0 }
		end
		if normalized.epoch ~= entry.epoch then
			if normalized.epoch ~= nil or normalized.intent.x == 0 and normalized.intent.z == 0 then
				entry.acceptedCount += 1
				pcall(ports.remote.acknowledge, player, {
					epoch = entry.epoch,
					sequence = normalized.sequence,
					intent = { x = 0, z = 0 },
					acceptedCount = entry.acceptedCount,
				})
			end
			return
		end
		if normalized.intent.x == 0 and normalized.intent.z == 0 then
			entry.stopSequence = normalized.sequence
			entry.intent = { x = 0, z = 0 }
			zero(entry)
		end
		if
			not ports.snapshot.move(
				player,
				normalized.intent,
				normalized.strafe == true,
				entry.epoch,
				normalized.sequence
			)
		then
			revoke(entry, "movement_queue_refused")
			return
		end
		entry.sequence = normalized.sequence
	end

	local function stepEntry(entry: Entry<P, B>)
		if not current(entry) then
			revoke(entry, "step_identity")
			return
		end
		local state = movementState(entry)
		if state == nil or state.hp <= 0 then
			zero(entry)
			return
		end
		local accepted = state.movement
		local sequence = state.movementSequence
		if accepted == nil or sequence == nil or not validIntent(accepted) then
			revoke(entry, "movement_state_invalid")
			return
		end
		if state.movementEpoch ~= entry.epoch or entry.stopSequence ~= nil and sequence < entry.stopSequence then
			entry.intent = { x = 0, z = 0 }
		else
			entry.intent = { x = accepted.x, z = accepted.z }
			entry.stopSequence = nil
		end
		if state.movementEpoch == entry.epoch and sequence > entry.acknowledgedSequence then
			entry.acknowledgedSequence = sequence
			entry.acceptedCount += 1
			pcall(ports.remote.acknowledge, entry.player, {
				epoch = entry.epoch,
				sequence = sequence,
				intent = { x = accepted.x, z = accepted.z },
				acceptedCount = entry.acceptedCount,
			})
			if accepted.x ~= 0 or accepted.z ~= 0 then
				mark("movement_server_accepted")
			end
		end
		local applied = ports.control.apply(entry.body, entry.intent, state.facing)
		if applied ~= true then
			revoke(entry, "step_control_refused")
			return
		end
		if not current(entry) then
			revoke(entry, "step_identity_after_control")
			return
		end
		local observed = ports.snapshot.observe(entry.body)
		local fault = observationFault(observed)
		if fault ~= nil or observed == nil then
			local reason = fault or "shape:nil"
			if reason == "body_dead" then
				entry.inert = true
				entry.intent = { x = 0, z = 0 }
				zero(entry)
				return
			end
			if string.sub(reason, 1, 6) == "shape:" then
				revoke(entry, "step_observation_invalid", reason)
				return
			end
			entry.invalidObservations += 1
			if entry.invalidObservations >= MAX_INVALID_OBSERVATIONS then
				revoke(
					entry,
					"step_observation_invalid",
					("%s after %d consecutive"):format(reason, entry.invalidObservations)
				)
			else
				mark("movement_observation_skipped", reason)
			end
			return
		end
		entry.invalidObservations = 0
		if entry.inert then
			entry.inert = false
		end
		local time = ports.clock()
		local travelRevision = ports.snapshot.travelRevision(entry.body)
		local lastAccepted, windowStart, lastAcceptedAt = entry.lastAccepted, entry.windowStart, entry.lastAcceptedAt
		if
			lastAccepted == nil
			or windowStart == nil
			or lastAcceptedAt == nil
			or not finite(time)
			or time < lastAcceptedAt
			or not finite(travelRevision)
		then
			revoke(entry, "step_measurement_invalid", nil, true)
			return
		end
		local dx = observed.x - lastAccepted.x
		local dz = observed.z - lastAccepted.z
		local distance = math.sqrt(dx * dx + dz * dz)
		local windowDx = observed.x - windowStart.x
		local windowDz = observed.z - windowStart.z
		local windowDistance = math.sqrt(windowDx * windowDx + windowDz * windowDz)
		local allowed = MAX_STEP_DISPLACEMENT + MAX_SUSTAINED_SPEED * (time - windowStart.at)
		if
			travelRevision == entry.travelRevision and (distance > MAX_STEP_DISPLACEMENT or windowDistance > allowed)
		then
			local restoreOk, restored = pcall(ports.control.restore, entry.body, windowStart.x, windowStart.z)
			revoke(entry, "step_displacement", tostring(distance), not restoreOk or restored ~= true)
			return
		end
		if travelRevision ~= entry.travelRevision or time - windowStart.at >= 1 then
			entry.windowStart = { x = observed.x, z = observed.z, at = time }
		end
		entry.lastAccepted = { x = observed.x, z = observed.z }
		entry.lastAcceptedAt = time
		entry.travelRevision = travelRevision
		local written = ports.snapshot.setPlayerSnapshot(
			entry.player,
			observed.x,
			observed.z,
			math.ceil(observed.hp),
			entry.intent.x ~= 0 or entry.intent.z ~= 0
		)
		if written ~= true then
			revoke(entry, "step_snapshot_refused")
		elseif entry.intent.x ~= 0 or entry.intent.z ~= 0 then
			mark("movement_snapshot_enqueued")
		end
	end

	local function step()
		if stopped then
			return
		end
		local detached: { Entry<P, B> } = {}
		for _, entry in entries do
			table.insert(detached, entry)
		end
		for _, entry in detached do
			if entries[entry.player] == entry then
				local ok, problem = pcall(stepEntry, entry)
				if not ok and entries[entry.player] == entry then
					revoke(entry, "step_error", tostring(problem))
				end
			end
		end
	end

	local remoteOk, acquiredRemote = pcall(ports.remote.connect, receive)
	if not remoteOk or not connection(acquiredRemote) then
		return refusal("remote_connection_invalid")
	end
	remoteConnection = acquiredRemote
	local stepOk, acquiredStep = pcall(ports.step.connect, step)
	if not stepOk or not connection(acquiredStep) then
		disconnect(remoteConnection)
		return refusal("step_connection_invalid")
	end
	stepConnection = acquiredStep
	local closeOk, acquiredClose = pcall(ports.registerClose, function()
		local result = assert(stop)()
		if result.phase ~= "movement_authority_stopped" then
			error("movement authority cleanup failed", 0)
		end
	end)
	if not closeOk or not connection(acquiredClose) then
		disconnect(stepConnection)
		disconnect(remoteConnection)
		return refusal("close_registration_invalid")
	end
	closeDispose = acquiredClose

	local function stopAll(): StopResult
		if stoppedResult ~= nil then
			return stoppedResult
		end
		stopped = true
		local clean = true
		clean = disconnect(remoteConnection) and clean
		clean = disconnect(stepConnection) and clean
		local detached: { Entry<P, B> } = {}
		for _, entry in entries do
			table.insert(detached, entry)
		end
		for _, entry in detached do
			clean = revoke(entry, "authority_stopped", nil, entry.inert) and clean
		end
		if closeDispose ~= nil then
			clean = pcall(closeDispose) and clean
		end
		local result: StopResult =
			{ phase = if clean then "movement_authority_stopped" else "movement_authority_stop_failed" }
		stoppedResult = result
		return result
	end
	stop = stopAll

	local started: Started<P> = {
		phase = "movement_authority_started",
		admitPlayer = admitPlayer,
		removePlayer = removePlayer,
		stop = stopAll,
		dispose = stopAll,
	}
	return started
end

return table.freeze(MovementIntake)
