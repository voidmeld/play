--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Sender = require("./movement-sender")
local Verify = require("../../.lute/dependencies/verify/src/core")

local EPS = 1e-6

local function resendDecision(
	held: Sender.Planar,
	last: Sender.Planar?,
	now: number,
	previous: number,
	minimum: number
): (Sender.Planar, boolean)
	local world = { x = held.x, z = held.z }
	if math.sqrt(world.x * world.x + world.z * world.z) < EPS then
		return world, false
	end
	if last == nil or math.sqrt(last.x * last.x + last.z * last.z) < EPS then
		return world, true
	end
	if now - previous < minimum then
		return world, false
	end
	local dot = (world.x * last.x + world.z * last.z)
		/ (math.sqrt(world.x ^ 2 + world.z ^ 2) * math.sqrt(last.x ^ 2 + last.z ^ 2))
	return world, dot < math.cos(math.rad(2))
end

type Fault = { reason: string, configure: (Configuration) -> (), sample: unknown }
type Configuration = {
	disconnectThrows: string?,
	clockThrows: boolean?,
	sendThrows: boolean?,
	sendFalse: boolean?,
	ackThrows: boolean?,
	badAckConnection: boolean?,
	heartbeatThrows: boolean?,
	badHeartbeatConnection: boolean?,
	actionThrows: boolean?,
	badActionConnection: boolean?,
	enableThrows: boolean?,
	enableFalse: boolean?,
	resendThrows: boolean?,
	resendInvalid: boolean?,
	cameraThrows: boolean?,
	camera: unknown,
	markThrows: boolean?,
}
type Callbacks = {
	ack: ((unknown) -> ())?,
	heartbeat: (() -> ())?,
	action: ((unknown) -> boolean)?,
}
type Event = { kind: string, payload: Sender.Payload?, value: boolean? }

local function harness(option: Configuration?)
	local settings: Configuration = option or {}
	local callbacks: Callbacks = { ack = nil, heartbeat = nil, action = nil }
	local sent: { Sender.Payload } = {}
	local attempts: { Sender.Payload } = {}
	local events: { Event } = {}
	local connections: { string } = {}
	local enabled: { boolean } = {}
	local marks: { string } = {}
	local now = 10
	local function connection(name: string): Sender.Connection
		return {
			Disconnect = function(_: Sender.Connection)
				table.insert(connections, name)
				if settings.disconnectThrows == name then
					error(name)
				end
			end,
		}
	end
	local dependencies = {
		clock = function(): number
			if settings.clockThrows then
				error("clock")
			end
			return now
		end,
		remote = {
			send = function(payload: Sender.Payload)
				table.insert(attempts, payload)
				table.insert(events, { kind = "send", payload = payload })
				if settings.sendThrows then
					error("send")
				end
				table.insert(sent, payload)
				return settings.sendFalse ~= true
			end,
			connect = function(callback: (unknown) -> ()): Sender.Connection
				if settings.ackThrows then
					error("ack")
				end
				callbacks.ack = callback
				return if settings.badAckConnection then {} else connection("ack")
			end,
		},
		heartbeat = {
			connect = function(callback: () -> ()): Sender.Connection
				if settings.heartbeatThrows then
					error("heartbeat")
				end
				callbacks.heartbeat = callback
				return if settings.badHeartbeatConnection then {} else connection("heartbeat")
			end,
		},
		action = {
			connect = function(callback: (unknown) -> boolean): Sender.Connection
				if settings.actionThrows then
					error("action")
				end
				callbacks.action = callback
				return if settings.badActionConnection then {} else connection("action")
			end,
			setEnabled = function(value: boolean): boolean
				if settings.enableThrows then
					error("enabled")
				end
				table.insert(enabled, value)
				table.insert(events, { kind = "enabled", value = value })
				return settings.enableFalse ~= true
			end,
		},
		motion = {
			resendDecision = function(
				held: Sender.Planar,
				_look: Sender.Planar,
				_up: Sender.Planar,
				last: Sender.Planar?,
				_cos: number,
				current: number,
				previous: number,
				minimum: number
			): (Sender.Planar, boolean)
				if settings.resendThrows then
					error("resend")
				end
				if settings.resendInvalid then
					return { x = math.huge, z = 0 }, true
				end
				return resendDecision(held, last, current, previous, minimum)
			end,
		},
		camera = {
			read = function(): unknown
				if settings.cameraThrows then
					error("camera")
				end
				return settings.camera or { look = { x = 0, z = -1 }, up = { x = 0, z = 0 } }
			end,
		},
		mark = function(phase: string)
			if settings.markThrows then
				error("mark")
			end
			table.insert(marks, phase)
		end,
	}
	return dependencies,
		{
			activate = function(result: Sender.Started, body: unknown)
				return result.activate(body)
			end,
			action = function(raw: unknown)
				return assert(callbacks.action, "action is not connected")(raw)
			end,
			ack = function(raw: unknown)
				assert(callbacks.ack, "ack is not connected")(raw)
			end,
			step = function()
				assert(callbacks.heartbeat, "heartbeat is not connected")()
			end,
			now = function(value: number)
				now = value
			end,
			sent = sent,
			attempts = attempts,
			events = events,
			settings = settings,
			enabled = enabled,
			marks = marks,
			connections = connections,
			callbacks = callbacks,
		}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("movement sender", function()
		it("echoes the acknowledged body epoch and clears held movement when placement invalidates it", function()
			local dependencies, observed = harness()
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			local body = {}
			expect(result.activate(body)):toBe(true)
			local initial = observed.sent[1]
			expect(initial.epoch):toBeNil()
			observed.ack({ epoch = 7, sequence = initial.sequence, intent = initial.intent, acceptedCount = 1 })
			observed.action({ x = 1, y = 0 })
			local held = observed.sent[#observed.sent]
			expect(held.epoch):toBe(7)
			expect(held.intent):toEqual({ x = 1, z = 0 })
			observed.ack({ epoch = 8, sequence = held.sequence, intent = { x = 0, z = 0 }, acceptedCount = 1 })
			observed.now(11)
			observed.step()
			expect(observed.sent[#observed.sent]):toBe(held)
			observed.ack({ epoch = 7, sequence = held.sequence, intent = held.intent, acceptedCount = 99 })
			expect(result.activate(body)):toBe(true)
			local handshake = observed.sent[#observed.sent]
			for index, receipt in
				{
					{ epoch = 7, sequence = handshake.sequence, intent = handshake.intent, acceptedCount = 99 },
					{ epoch = 8, sequence = held.sequence, intent = { x = 0, z = 0 }, acceptedCount = 99 },
					{ epoch = 8, sequence = handshake.sequence, intent = handshake.intent, acceptedCount = 1 },
					{ epoch = 8, sequence = handshake.sequence, intent = { x = 1, z = 0 }, acceptedCount = 2 },
				}
			do
				observed.ack(receipt)
				observed.now(11 + index * 0.1)
				observed.action({ x = 1, y = 0 })
				local nonzero = observed.sent[#observed.sent]
				expect(nonzero.epoch):toBeNil()
				observed.ack({ epoch = 8, sequence = nonzero.sequence, intent = nonzero.intent, acceptedCount = 99 })
				observed.action({ x = 0, y = 0 })
				expect(observed.sent[#observed.sent].epoch):toBeNil()
			end
			observed.ack({ epoch = 8, sequence = handshake.sequence, intent = handshake.intent, acceptedCount = 2 })
			observed.now(11.5)
			observed.action({ x = 0, y = 1 })
			local resumed = observed.sent[#observed.sent]
			expect(resumed.epoch):toBe(8)
			expect(resumed.intent):toEqual({ x = 0, z = -1 })
			result.stop()
		end)

		it(
			"keeps diagonal travel admitted beyond the pending bound when Vector3 acknowledgements round to float32",
			function()
				local dependencies, observed = harness()
				local result = Sender.start(dependencies)
				assert(result.phase == "movement_sender_started")
				expect(result.activate({})):toBe(true)
				local wire = buffer.create(4)
				local function float32(value: number): number
					buffer.writef32(wire, 0, value)
					return buffer.readf32(wire, 0)
				end
				for _ = 1, 128 do
					expect(observed.action({ x = 1, y = 1 })):toBe(true)
					local payload = observed.sent[#observed.sent]
					observed.ack({
						epoch = 1,
						sequence = payload.sequence,
						intent = { x = float32(payload.intent.x), z = float32(payload.intent.z) },
						acceptedCount = payload.sequence,
					})
				end
				expect(observed.enabled[#observed.enabled]):toBe(true)
				expect(table.find(observed.marks, "movement_acknowledged") ~= nil):toBe(true)
			end
		)

		it("rejects an adjacent float32 intent rather than allowing a numeric tolerance", function()
			local dependencies, observed = harness()
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			result.activate({})
			observed.action({ x = 1, y = 1 })
			observed.ack({
				epoch = 1,
				sequence = 2,
				intent = { x = 0.7071067690849304 - 2 ^ -24, z = -0.7071067690849304 },
				acceptedCount = 2,
			})
			expect(table.find(observed.marks, "movement_acknowledged")):toBeNil()
			observed.ack({
				epoch = 1,
				sequence = 2,
				intent = { x = 0.7071067690849304, z = -0.7071067690849304 },
				acceptedCount = 2,
			})
			expect(table.find(observed.marks, "movement_acknowledged") ~= nil):toBe(true)
		end)

		it("compensates partial connection acquisition", function()
			local dependencies, observed = harness({ actionThrows = true })
			expect(Sender.start(dependencies)):toEqual({
				phase = "movement_sender_refused",
				reason = "action_connection_invalid",
			})
			expect(observed.connections):toEqual({ "heartbeat", "ack" })
		end)

		it("contains cleanup throws and returns one stable stop receipt", function()
			local dependencies, observed = harness({ disconnectThrows = "heartbeat" })
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			result.activate({})
			local first = result.stop()
			local second = result.stop()
			expect(first):toEqual(second)
			expect(first.phase):toBe("movement_sender_stop_failed")
			expect(observed.connections):toEqual({ "action", "heartbeat", "ack" })
		end)

		it("sends an initial zero handshake, normalizes action vectors, and resends only held movement", function()
			local dependencies, observed = harness()
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			expect(result.phase):toBe("movement_sender_started")
			expect(result.activate({ body = 1 })):toBe(true)
			expect(observed.enabled):toEqual({ false, true })
			expect(observed.sent[1]):toEqual({ intent = { x = 0, z = 0 }, sequence = 1, sentAt = 10 })
			expect(observed.action({ x = 3, y = -4 })):toBe(true)
			expect(observed.sent[2].intent):toEqual({ x = 0.6, z = 0.8 })
			observed.now(10.02)
			observed.step()
			expect(#observed.sent):toBe(2)
			observed.now(10.1)
			observed.step()
			expect(#observed.sent):toBe(3)
			expect(observed.action({ x = 0, y = 0 })):toBe(true)
			expect(observed.action({ x = -1, y = 0 })):toBe(true)
			expect(#observed.sent):toBe(4)
			observed.now(10.2)
			observed.step()
			expect(#observed.sent):toBe(5)
			expect(observed.sent[5].intent):toEqual({ x = -1, z = 0 })
		end)

		it(
			"marks readiness, one nonzero send, its exact acknowledgement, and only a post-nonzero zero acknowledgement",
			function()
				local dependencies, observed = harness()
				local result = Sender.start(dependencies)
				assert(result.phase == "movement_sender_started")
				expect(result.activate({})):toBe(true)
				observed.ack({ epoch = 1, sequence = 1, intent = { x = 0, z = 0 }, acceptedCount = 1 })
				expect(observed.action({ x = 1, y = 0 })):toBe(true)
				observed.ack({ epoch = 1, sequence = 2, intent = { x = 1, z = 0 }, acceptedCount = 2 })
				expect(observed.action({ x = 0, y = 0 })):toBe(true)
				observed.ack({ epoch = 1, sequence = 3, intent = { x = 0, z = 0 }, acceptedCount = 3 })
				expect(observed.marks):toEqual({
					"movement_input_ready",
					"movement_intent_sent",
					"movement_acknowledged",
					"movement_release_acknowledged",
				})
			end
		)

		it("marks covered nonzero intent before a cumulative release acknowledgement", function()
			local dependencies, observed = harness()
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			expect(result.activate({})):toBe(true)
			expect(observed.action({ x = 1, y = 0 })):toBe(true)
			expect(observed.action({ x = 0, y = 0 })):toBe(true)
			observed.ack({ epoch = 1, sequence = 3, intent = { x = 0, z = 0 }, acceptedCount = 1 })
			observed.ack({ epoch = 1, sequence = 3, intent = { x = 0, z = 0 }, acceptedCount = 2 })
			expect(observed.marks):toEqual({
				"movement_input_ready",
				"movement_intent_sent",
				"movement_acknowledged",
				"movement_release_acknowledged",
			})
		end)

		it("does not acknowledge movement for zero-only, malformed, stale, or duplicate acknowledgements", function()
			local dependencies, observed = harness()
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			expect(result.activate({})):toBe(true)
			observed.ack({ epoch = 1, sequence = 1, intent = { x = 0, z = 0 }, acceptedCount = 1, extra = true })
			observed.ack({ epoch = 1, sequence = 1, intent = { x = 0, z = 0 }, acceptedCount = 1 })
			expect(observed.action({ x = 0, y = 0 })):toBe(true)
			observed.ack({ epoch = 1, sequence = 2, intent = { x = 0, z = 0 }, acceptedCount = 2 })
			observed.ack({ epoch = 1, sequence = 1, intent = { x = 0, z = 0 }, acceptedCount = 3 })
			observed.ack({ epoch = 1, sequence = 2, intent = { x = 0, z = 0 }, acceptedCount = 3 })
			expect(observed.marks):toEqual({ "movement_input_ready" })
		end)

		it("contains observability failures without changing movement authority", function()
			local dependencies, observed = harness({ markThrows = true })
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			expect(result.activate({})):toBe(true)
			expect(observed.action({ x = 1, y = 0 })):toBe(true)
			observed.ack({ epoch = 1, sequence = 2, intent = { x = 1, z = 0 }, acceptedCount = 1 })
			expect(observed.sent[2].intent):toEqual({ x = 1, z = 0 })
		end)

		it(
			"binds acknowledgements to a known sent intent and monotonically advancing server epoch, sequence, and count",
			function()
				local dependencies, observed = harness()
				local result = Sender.start(dependencies)
				assert(result.phase == "movement_sender_started")
				local first, second = {}, {}
				result.activate(first)
				observed.ack({ epoch = 1, sequence = 1, intent = { x = 0, z = 0 }, acceptedCount = 1 })
				observed.action({ x = 1, y = 0 })
				observed.ack({ epoch = 1, sequence = 2, intent = { x = 1, z = 0 }, acceptedCount = 2 })
				observed.ack({ epoch = 1, sequence = 2, intent = { x = 1, z = 0 }, acceptedCount = 3 })
				result.revoke(first)
				result.activate(second)
				local handshake = observed.sent[#observed.sent]
				expect(handshake.sequence):toBe(4)
				observed.ack({ epoch = 1, sequence = handshake.sequence, intent = { x = 0, z = 0 }, acceptedCount = 4 })
				observed.ack({ epoch = 2, sequence = handshake.sequence, intent = { x = 0, z = 0 }, acceptedCount = 1 })
				observed.ack({ epoch = 2, sequence = 999, intent = { x = 0, z = 0 }, acceptedCount = 2 })
				result.stop()
				expect(observed.connections):toEqual({ "action", "heartbeat", "ack" })
			end
		)

		it("contains malformed acknowledgements without changing the active sender", function()
			local dependencies, observed = harness()
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			result.activate({})
			observed.ack({ epoch = 1, sequence = 1, intent = { x = 0, z = 0 }, acceptedCount = 1, extra = true })
			observed.ack({ epoch = 1, sequence = 1, intent = { x = math.huge, z = 0 }, acceptedCount = 1 })
			expect(#observed.sent):toBe(1)
			expect(observed.action({ x = 0, y = 1 })):toBe(true)
			expect(#observed.sent):toBe(2)
		end)

		it(
			"fails closed after a nonzero send when ordinary input, clock, camera, or world mapping is invalid",
			function()
				local faults: { Fault } = {
					{
						reason = "sample_invalid",
						configure = function(_: Configuration) end,
						sample = { x = math.huge, y = 0 },
					},
					{
						reason = "clock_invalid",
						configure = function(settings: Configuration)
							settings.clockThrows = true
						end,
						sample = { x = 1, y = 0 },
					},
					{
						reason = "camera_invalid",
						configure = function(settings: Configuration)
							settings.cameraThrows = true
						end,
						sample = { x = 1, y = 0 },
					},
					{
						reason = "camera_invalid",
						configure = function(settings: Configuration)
							settings.camera = { look = { x = 0, z = 0 }, up = { x = 0, z = 0 }, extra = true }
						end,
						sample = { x = 1, y = 0 },
					},
					{
						reason = "resend_invalid",
						configure = function(settings: Configuration)
							settings.resendThrows = true
						end,
						sample = { x = 1, y = 0 },
					},
					{
						reason = "resend_invalid",
						configure = function(settings: Configuration)
							settings.resendInvalid = true
						end,
						sample = { x = 1, y = 0 },
					},
				}
				for _, fault in faults do
					for _, heartbeat in { false, true } do
						if heartbeat and fault.reason == "sample_invalid" then
							continue
						end
						local dependencies, observed = harness()
						local result = Sender.start(dependencies)
						assert(result.phase == "movement_sender_started")
						result.activate({})
						observed.action({ x = 1, y = 0 })
						fault.configure(observed.settings)
						if heartbeat then
							observed.step()
						else
							expect(observed.action(fault.sample)):toBe(false)
						end
						expect(table.find(observed.marks, "movement_refused_" .. fault.reason) ~= nil):toBe(true)
						expect(observed.enabled[#observed.enabled]):toBe(false)
						expect(observed.attempts[#observed.attempts].intent):toEqual({ x = 0, z = 0 })
						if fault.reason == "clock_invalid" then
							expect(observed.attempts[#observed.attempts].sentAt):toBe(10)
						end
						expect(observed.events[#observed.events - 1].kind):toBe("enabled")
						expect(observed.events[#observed.events - 1].value):toBe(false)
						local sends = #observed.attempts
						assert(observed.callbacks.action, "action is not connected")({ x = 1, y = 0 })
						assert(observed.callbacks.heartbeat, "heartbeat is not connected")()
						expect(#observed.attempts):toBe(sends)
					end
				end
			end
		)

		it("attempts terminal zero when an ordinary remote send returns false or throws", function()
			local faults: { (Configuration) -> () } = {
				function(settings: Configuration)
					settings.sendFalse = true
				end,
				function(settings: Configuration)
					settings.sendThrows = true
				end,
			}
			for _, configure in faults do
				local dependencies, observed = harness()
				local result = Sender.start(dependencies)
				assert(result.phase == "movement_sender_started")
				result.activate({})
				configure(observed.settings)
				expect(observed.action({ x = 1, y = 0 })):toBe(false)
				expect(table.find(observed.marks, "movement_refused_send_refused") ~= nil):toBe(true)
				expect(observed.enabled[#observed.enabled]):toBe(false)
				expect(observed.attempts[#observed.attempts].intent):toEqual({ x = 0, z = 0 })
			end
		end)

		it("disables before best-effort zero on revocation and leaves late callbacks inert", function()
			local dependencies, observed = harness()
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			local body = {}
			result.activate(body)
			expect(result.revoke(body)):toBe(true)
			expect(observed.enabled):toEqual({ false, true, false })
			expect(observed.sent[#observed.sent].intent):toEqual({ x = 0, z = 0 })
			expect(observed.action({ x = 1, y = 0 })):toBe(false)
			local count = #observed.sent
			result.stop()
			assert(observed.callbacks.action, "action is not connected")({ x = 1, y = 0 })
			assert(observed.callbacks.heartbeat, "heartbeat is not connected")()
			assert(observed.callbacks.ack, "ack is not connected")({
				epoch = 1,
				sequence = 1,
				intent = { x = 0, z = 0 },
				acceptedCount = 1,
			})
			expect(#observed.sent):toBe(count)
		end)

		it(
			"coalesces unacknowledged bursts and retains the latest heading after a stale ledger acknowledgement",
			function()
				local dependencies, observed = harness()
				local result = Sender.start(dependencies)
				assert(result.phase == "movement_sender_started")
				result.activate({})
				for _ = 1, 63 do
					expect(observed.action({ x = 1, y = 0 })):toBe(true)
				end
				expect(#observed.sent):toBe(2)
				observed.ack({ epoch = 1, sequence = 2, intent = { x = 1, z = 0 }, acceptedCount = 1 })
				for _ = 1, 63 do
					expect(observed.action({ x = 0, y = 1 })):toBe(true)
				end
				observed.ack({ epoch = 1, sequence = 1, intent = { x = 0, z = 0 }, acceptedCount = 2 })
				observed.now(10.1)
				observed.step()
				expect(#observed.sent):toBe(3)
				expect(observed.sent[3].intent):toEqual({ x = 0, z = -1 })
				expect(table.find(observed.marks, "movement_refused_pending_limit")):toBeNil()
				expect(observed.enabled[#observed.enabled]):toBe(true)
			end
		)

		it("reclaims sends the server never answers so an unanswered walk cannot wedge the sender forever", function()
			local dependencies, observed = harness()
			local result = Sender.start(dependencies)
			assert(result.phase == "movement_sender_started")
			result.activate({})
			for index = 1, 200 do
				observed.now(10 + index * 0.05)
				expect(observed.action({ x = 1, y = 0 })):toBe(true)
			end
			expect(table.find(observed.marks, "movement_refused_pending_limit") ~= nil):toBe(false)
			expect(observed.enabled[#observed.enabled]):toBe(true)
		end)
	end)
end
