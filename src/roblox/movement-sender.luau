--!strict

export type Planar = { read x: number, read z: number }

export type Refused = { read phase: "movement_sender_refused", read reason: string }
export type Stopped = { read phase: "movement_sender_stopped" | "movement_sender_stop_failed" }
export type Started = {
	read phase: "movement_sender_started",
	read activate: (unknown) -> boolean,
	read revoke: (unknown) -> boolean,
	read sample: (unknown) -> boolean,
	read stop: () -> Stopped,
	read dispose: () -> Stopped,
}
export type StartResult = Started | Refused
export type Payload = { read intent: Planar, read sequence: number, read sentAt: number, read epoch: number? }
type Entry = {
	body: unknown,
	ledger: { [number]: Payload },
	pending: number,
	pendingIntentSequence: number?,
	held: Planar,
	lastSent: Planar?,
	lastSendTime: number,
	lastFiniteTime: number?,
	serverEpoch: number?,
	nonzeroSent: boolean,
	releaseSequences: { [number]: boolean },
	inert: boolean,
	revoking: boolean,
}

local MovementSender = {}
local Value = require("../core/value")
export type Connection = { read Disconnect: ((Connection) -> ())? }
export type Dependencies = {
	clock: () -> number,
	remote: { send: (Payload) -> boolean, connect: ((unknown) -> ()) -> Connection },
	heartbeat: { connect: (() -> ()) -> Connection },
	action: { connect: ((unknown) -> boolean) -> Connection, setEnabled: (boolean) -> boolean },
	motion: { resendDecision: (Planar, Planar, Planar, Planar?, number, number, number, number) -> (Planar, boolean) },
	camera: { read: () -> unknown },
	mark: (string) -> (),
}
local function numberValue(value: unknown): number
	assert(type(value) == "number")
	return value
end

local MAX_SEQUENCE = 2147483647
local MAX_SAFE_INTEGER = 9007199254740991
local MAX_PENDING = 64
local COS_2DEG = math.cos(math.rad(2))
local RESEND_INTERVAL = 0.05
local PENDING_RECLAIM_SECONDS = 1
local WIRE_COMPONENT = buffer.create(4)

local function wireComponent(value: number): number
	buffer.writef32(WIRE_COMPONENT, 0, value)
	return buffer.readf32(WIRE_COMPONENT, 0)
end

local DEPENDENCY_FIELDS = {
	clock = true,
	remote = true,
	heartbeat = true,
	action = true,
	motion = true,
	camera = true,
	mark = true,
}
local REMOTE_FIELDS = { send = true, connect = true }
local HEARTBEAT_FIELDS = { connect = true }
local ACTION_FIELDS = { connect = true, setEnabled = true }
local MOTION_FIELDS = { resendDecision = true }
local CAMERA_PORT_FIELDS = { read = true }
local SAMPLE_FIELDS = { x = true, y = true }
local PLANAR_FIELDS = { x = true, z = true }
local CAMERA_FIELDS = { look = true, up = true }
local ACK_FIELDS = { epoch = true, sequence = true, intent = true, acceptedCount = true }

local function exact(raw: unknown, fields: { [string]: boolean }): boolean
	return Value.record(raw, fields, true) ~= nil
end

local finite = Value.finite

local function whole(value: unknown, maximum: number): boolean
	return type(value) == "number" and finite(value) and value == math.floor(value) and value >= 0 and value <= maximum
end

local function positiveWhole(value: unknown, maximum: number): boolean
	return type(value) == "number" and whole(value, maximum) and value > 0
end

local function planar(raw: unknown): boolean
	local value = Value.raw(raw)
	if value == nil then
		return false
	end
	return exact(value, PLANAR_FIELDS)
		and finite(value.x)
		and finite(value.z)
		and type(value.x) == "number"
		and type(value.z) == "number"
		and value.x >= -1
		and value.x <= 1
		and value.z >= -1
		and value.z <= 1
		and value.x * value.x + value.z * value.z <= 1 + 1e-6
end

local function readPlanar(raw: unknown): Planar
	local row = assert(Value.raw(raw))
	return { x = numberValue(row.x), z = numberValue(row.z) }
end

local function connection(value: Connection?): boolean
	return type(value) == "table" and getmetatable(value) == nil and type(value.Disconnect) == "function"
end

local function disconnect(value: Connection?): boolean
	if value == nil or not connection(value) then
		return false
	end
	local method = value.Disconnect
	return method ~= nil and (pcall(method, value))
end

local function validDependencies(raw: unknown): boolean
	local value = Value.raw(raw)
	if value == nil then
		return false
	end
	if not exact(value, DEPENDENCY_FIELDS) then
		return false
	end
	if
		not exact(value.remote, REMOTE_FIELDS)
		or not exact(value.heartbeat, HEARTBEAT_FIELDS)
		or not exact(value.action, ACTION_FIELDS)
		or not exact(value.motion, MOTION_FIELDS)
		or not exact(value.camera, CAMERA_PORT_FIELDS)
	then
		return false
	end
	return type(value.clock) == "function"
		and type(assert(Value.raw(value.remote)).send) == "function"
		and type(assert(Value.raw(value.remote)).connect) == "function"
		and type(assert(Value.raw(value.heartbeat)).connect) == "function"
		and type(assert(Value.raw(value.action)).connect) == "function"
		and type(assert(Value.raw(value.action)).setEnabled) == "function"
		and type(assert(Value.raw(value.motion)).resendDecision) == "function"
		and type(assert(Value.raw(value.camera)).read) == "function"
		and type(value.mark) == "function"
end

local function refusal(reason: string): Refused
	local refused: Refused = { phase = "movement_sender_refused", reason = reason }
	return table.freeze(refused)
end

local function zero(): Planar
	return table.freeze({ x = 0, z = 0 })
end

local function normalizedSample(raw: unknown): Planar?
	local value = Value.raw(raw)
	if value == nil then
		return nil
	end
	if not exact(value, SAMPLE_FIELDS) or not finite(value.x) or not finite(value.y) then
		return nil
	end
	local x, z = numberValue(value.x), -numberValue(value.y)
	local magnitude = math.sqrt(x * x + z * z)
	if magnitude < 1e-4 then
		return zero()
	end
	return table.freeze({ x = x / magnitude, z = z / magnitude })
end

function MovementSender.start(dependencies: Dependencies): StartResult
	if not validDependencies(dependencies) then
		return refusal("dependencies_invalid")
	end
	local ports = table.freeze({
		clock = dependencies.clock,
		remote = table.freeze({ send = dependencies.remote.send, connect = dependencies.remote.connect }),
		heartbeat = table.freeze({ connect = dependencies.heartbeat.connect }),
		action = table.freeze({ connect = dependencies.action.connect, setEnabled = dependencies.action.setEnabled }),
		resendDecision = dependencies.motion.resendDecision,
		camera = table.freeze({ read = dependencies.camera.read }),
		mark = dependencies.mark,
	})
	local stopped = false
	local stoppedResult: Stopped? = nil
	local ackConnection: Connection? = nil
	local heartbeatConnection: Connection? = nil
	local actionConnection: Connection? = nil
	local active: Entry? = nil
	local sequence = 0
	local lastServerEpoch = 0
	local lastServerBody: unknown = nil
	local lastAcceptedCount = 0
	local lastAcknowledgedSequence = -1
	local marked: { [string]: boolean } = {}

	local function mark(phase: string)
		if marked[phase] == true then
			return
		end
		local ok = pcall(ports.mark, phase)
		if ok then
			marked[phase] = true
		end
	end

	local function current(entry: Entry?): boolean
		return entry ~= nil and not stopped and active == entry and entry.inert ~= true and entry.revoking ~= true
	end

	local function enabled(value: boolean): boolean
		local ok, result = pcall(ports.action.setEnabled, value)
		return ok and result == true
	end

	local function now(): number?
		local ok, value = pcall(ports.clock)
		return if ok and type(value) == "number" and finite(value) then value else nil
	end

	local revoke: (Entry, string?, boolean?) -> boolean

	local function reclaim(entry: Entry)
		local reference = entry.lastFiniteTime
		if reference == nil then
			return
		end
		for candidate, payload in entry.ledger do
			if reference - payload.sentAt >= PENDING_RECLAIM_SECONDS then
				entry.ledger[candidate] = nil
				entry.pending -= 1
			end
		end
	end

	local function sent(entry: Entry, intent: Planar, terminal: boolean?): boolean
		if
			(not terminal and not current(entry))
			or (terminal and (stopped or active ~= entry or entry.inert == true))
			or sequence >= MAX_SEQUENCE
		then
			return false
		end
		if not terminal then
			reclaim(entry)
		end
		if not terminal and (sequence >= MAX_SEQUENCE - 1 or entry.pending >= MAX_PENDING) then
			revoke(entry, if entry.pending >= MAX_PENDING then "pending_limit" else "sequence_limit")
			return false
		end
		local sentAt = now()
		if terminal and sentAt == nil then
			sentAt = entry.lastFiniteTime
		end
		if sentAt == nil then
			if not terminal then
				revoke(entry, "clock_invalid")
			end
			return false
		end
		entry.lastFiniteTime = sentAt
		sequence += 1
		local payload = table.freeze({
			intent = table.freeze({ x = intent.x, z = intent.z }),
			sequence = sequence,
			sentAt = sentAt,
			epoch = entry.serverEpoch,
		})
		local ok, accepted = pcall(ports.remote.send, payload)
		if not ok or accepted ~= true then
			if not terminal then
				revoke(entry, "send_refused")
			end
			return false
		end
		entry.ledger[sequence] = payload
		entry.pending += 1
		if entry.lastSent == nil or entry.lastSent.x ~= intent.x or entry.lastSent.z ~= intent.z then
			entry.pendingIntentSequence = sequence
		end
		entry.lastSent = payload.intent
		entry.lastSendTime = sentAt
		if intent.x ~= 0 or intent.z ~= 0 then
			entry.nonzeroSent = true
			mark("movement_intent_sent")
		elseif entry.nonzeroSent then
			entry.releaseSequences[sequence] = true
		end
		return true
	end

	revoke = function(entry: Entry, reason: string?, keepContext: boolean?): boolean
		if active ~= entry or entry.inert == true or entry.revoking == true then
			return false
		end
		entry.revoking = true
		if reason ~= nil then
			mark("movement_refused_" .. reason)
		end
		local disabled = keepContext == true or enabled(false)
		local zeroed = sent(entry, zero(), true)
		entry.inert = true
		active = nil
		return disabled and zeroed
	end

	local function receive(value: unknown)
		local raw = Value.raw(value)
		local entry = active
		if stopped or entry == nil or raw == nil or not exact(raw, ACK_FIELDS) then
			return
		end
		if
			not positiveWhole(raw.epoch, MAX_SAFE_INTEGER)
			or not whole(raw.sequence, MAX_SEQUENCE)
			or not positiveWhole(raw.acceptedCount, MAX_SAFE_INTEGER)
			or not planar(raw.intent)
		then
			return
		end
		assert(type(raw.epoch) == "number" and type(raw.sequence) == "number" and type(raw.acceptedCount) == "number")
		local intent = assert(Value.raw(raw.intent))
		local payload = entry.ledger[raw.sequence]
		if
			payload ~= nil
			and entry.serverEpoch ~= nil
			and raw.epoch > entry.serverEpoch
			and intent.x == 0
			and intent.z == 0
		then
			entry.serverEpoch = raw.epoch
			lastServerEpoch = raw.epoch
			lastAcceptedCount, lastAcknowledgedSequence = raw.acceptedCount, raw.sequence
			table.clear(entry.ledger)
			table.clear(entry.releaseSequences)
			entry.pending, entry.pendingIntentSequence = 0, nil
			entry.held, entry.lastSent = zero(), nil
			return
		end
		local release = entry.releaseSequences[raw.sequence] == true
		if
			payload == nil
			or wireComponent(payload.intent.x) ~= intent.x
			or wireComponent(payload.intent.z) ~= intent.z
		then
			return
		end
		if entry.serverEpoch == nil then
			if
				raw.epoch < lastServerEpoch
				or (
					raw.epoch == lastServerEpoch
					and (
						entry.body ~= lastServerBody
						or payload.intent.x ~= 0
						or payload.intent.z ~= 0
						or raw.sequence <= lastAcknowledgedSequence
						or raw.acceptedCount <= lastAcceptedCount
					)
				)
			then
				return
			end
			entry.serverEpoch = raw.epoch
			lastServerEpoch = raw.epoch
			lastServerBody = entry.body
			lastAcceptedCount = raw.acceptedCount
			lastAcknowledgedSequence = raw.sequence
		elseif
			raw.epoch ~= entry.serverEpoch
			or raw.acceptedCount <= lastAcceptedCount
			or raw.sequence <= lastAcknowledgedSequence
		then
			return
		else
			entry.serverEpoch = raw.epoch
			lastAcceptedCount = raw.acceptedCount
			lastAcknowledgedSequence = raw.sequence
		end
		local coveredNonzero = false
		for candidate, candidatePayload in entry.ledger do
			if candidate <= raw.sequence then
				coveredNonzero = coveredNonzero or candidatePayload.intent.x ~= 0 or candidatePayload.intent.z ~= 0
				entry.ledger[candidate] = nil
				entry.pending -= 1
			end
		end
		if coveredNonzero then
			mark("movement_acknowledged")
		end
		if entry.pendingIntentSequence ~= nil and raw.sequence >= entry.pendingIntentSequence then
			entry.pendingIntentSequence = nil
		end
		if release then
			mark("movement_release_acknowledged")
		end
		entry.releaseSequences[raw.sequence] = nil
	end

	local function update(entry: Entry): boolean
		if not current(entry) then
			return false
		end
		local currentTime = now()
		if currentTime == nil then
			revoke(entry, "clock_invalid")
			return false
		end
		local readOk, cameraValue = pcall(ports.camera.read)
		local camera = Value.raw(cameraValue)
		if
			not readOk
			or camera == nil
			or not exact(camera, CAMERA_FIELDS)
			or not planar(camera.look)
			or not planar(camera.up)
		then
			revoke(entry, "camera_invalid")
			return false
		end
		local decisionOk, rawMapped, resend = pcall(
			ports.resendDecision,
			entry.held,
			readPlanar(camera.look),
			readPlanar(camera.up),
			entry.lastSent,
			COS_2DEG,
			currentTime,
			entry.lastSendTime,
			RESEND_INTERVAL
		)
		local mapped = Value.raw(rawMapped)
		if not decisionOk or type(resend) ~= "boolean" or mapped == nil or not planar(mapped) then
			revoke(entry, "resend_invalid")
			return false
		end
		if mapped.x == 0 and mapped.z == 0 then
			if entry.lastSent ~= nil and entry.lastSent.x == 0 and entry.lastSent.z == 0 then
				return true
			end
			return sent(entry, zero())
		end
		if entry.nonzeroSent and currentTime - entry.lastSendTime < RESEND_INTERVAL then
			return true
		end
		local retryPending = entry.pendingIntentSequence ~= nil and currentTime - entry.lastSendTime >= RESEND_INTERVAL
		if resend or retryPending or not entry.nonzeroSent then
			return sent(entry, table.freeze({ x = numberValue(mapped.x), z = numberValue(mapped.z) }))
		end
		return true
	end

	local function sample(raw: unknown): boolean
		local entry = active
		if entry == nil or not current(entry) then
			return false
		end
		local held = normalizedSample(raw)
		if held == nil then
			revoke(entry, "sample_invalid")
			return false
		end
		entry.held = held
		return update(entry)
	end

	local function step()
		local entry = active
		if entry ~= nil and (entry.held.x ~= 0 or entry.held.z ~= 0) then
			update(entry)
		end
	end

	local function stop(): Stopped
		if stoppedResult ~= nil then
			return stoppedResult
		end
		local entry = active
		local clean = true
		if entry ~= nil then
			clean = revoke(entry) and clean
		else
			clean = enabled(false) and clean
		end
		stopped = true
		clean = disconnect(actionConnection) and clean
		clean = disconnect(heartbeatConnection) and clean
		clean = disconnect(ackConnection) and clean
		local receipt: Stopped = {
			phase = if clean then "movement_sender_stopped" else "movement_sender_stop_failed",
		}
		stoppedResult = table.freeze(receipt)
		return receipt
	end

	if not enabled(false) then
		return refusal("action_disable_invalid")
	end
	local ackOk, acquiredAck = pcall(ports.remote.connect, receive)
	if not ackOk or not connection(acquiredAck) then
		return refusal("ack_connection_invalid")
	end
	ackConnection = acquiredAck
	local heartbeatOk, acquiredHeartbeat = pcall(ports.heartbeat.connect, step)
	if not heartbeatOk or not connection(acquiredHeartbeat) then
		disconnect(ackConnection)
		return refusal("heartbeat_connection_invalid")
	end
	heartbeatConnection = acquiredHeartbeat
	local actionOk, acquiredAction = pcall(ports.action.connect, sample)
	if not actionOk or not connection(acquiredAction) then
		disconnect(heartbeatConnection)
		disconnect(ackConnection)
		return refusal("action_connection_invalid")
	end
	actionConnection = acquiredAction

	local function activate(body: unknown): boolean
		if stopped or body == nil or sequence >= MAX_SEQUENCE - 1 then
			return false
		end
		if active ~= nil then
			if not revoke(active, nil, active.body == body) then
				enabled(false)
				return false
			end
		end
		local entry: Entry = {
			body = body,
			ledger = {},
			pending = 0,
			pendingIntentSequence = nil,
			held = zero(),
			lastSent = nil,
			lastSendTime = -math.huge,
			lastFiniteTime = nil,
			serverEpoch = nil,
			nonzeroSent = false,
			releaseSequences = {},
			inert = false,
			revoking = false,
		}
		active = entry
		local handshake = sent(entry, zero())
		local activated = if handshake then enabled(true) else false
		if not activated then
			revoke(entry)
			return false
		end
		mark("movement_input_ready")
		return true
	end

	local started: Started = {
		phase = "movement_sender_started",
		activate = activate,
		revoke = function(body: unknown): boolean
			local entry = active
			return entry ~= nil and current(entry) and entry.body == body and revoke(entry)
		end,
		sample = sample,
		stop = stop,
		dispose = stop,
	}
	return table.freeze(started)
end

return table.freeze(MovementSender)
