--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Intake = require("./movement-intake")
local Value = require("../core/value")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Point = Intake.Point
type Subject = { userId: number, valid: boolean }
type Body = { x: number, z: number, hp: number, travelRevision: number? }
type Ack = Intake.Ack
type State = Intake.State
type Request = { subject: Subject, intent: Point, strafe: boolean, epoch: number, sequence: number }
type Options = {
	allow: ((Subject, number) -> boolean)?,
	queueRefused: boolean?,
	controlFalseFor: number?,
	disconnectThrows: string?,
	ackThrows: boolean?,
	clockThrows: boolean?,
	closeThrows: boolean?,
	controlFalse: boolean?,
	controlThrows: boolean?,
	markThrows: boolean?,
	normalizeThrows: boolean?,
	rateDenied: boolean?,
	remoteConnectThrows: boolean?,
	restoreThrows: boolean?,
	snapshotFalse: boolean?,
	snapshotThrows: boolean?,
	stepConnectThrows: boolean?,
}
type Observed = {
	add: (number) -> Subject,
	commit: (Subject, State) -> (),
	requests: { Request },
	setBody: (Subject, Body) -> (),
	mutateBody: (Subject, number, number) -> (),
	advanceTime: (number) -> (),
	authorizeTravel: (Subject) -> (),
	remote: (Subject, unknown) -> (),
	step: () -> (),
	close: () -> (),
	applied: { { body: Body, intent: Point, facing: Point? } },
	acknowledgements: { { subject: Subject, ack: Ack } },
	snapshots: { { subject: Subject, x: number, z: number, hp: number } },
	inputActivity: { boolean },
	disconnects: { string },
	marks: { string },
	markDetails: { [string]: string? },
}

local function readPoint(raw: unknown): Point?
	local record = Value.record(raw, { x = true, z = true }, true)
	if record == nil then
		return nil
	end
	local x, z = record.x, record.z
	if type(x) ~= "number" or type(z) ~= "number" then
		return nil
	end
	return { x = x, z = z }
end

local function parse(raw: unknown): Intake.Normalized?
	local record = Value.record(raw, { sequence = true, intent = true, strafe = true, epoch = true }, false)
	if record == nil or type(record.sequence) ~= "number" then
		return nil
	end
	local intent = readPoint(record.intent)
	if intent == nil then
		return nil
	end
	local strafe, epoch = record.strafe, record.epoch
	return {
		sequence = record.sequence,
		intent = intent,
		strafe = if type(strafe) == "boolean" then strafe else nil,
		epoch = if type(epoch) == "number" then epoch else nil,
	}
end

local function connection(name: string, option: Options, disconnects: { string }): () -> ()
	return function()
		table.insert(disconnects, name)
		if option.disconnectThrows == name then
			error(name)
		end
	end
end

local function harness(options: Options?): (Intake.Dependencies<Subject, Body>, Observed)
	local option: Options = options or {}
	local remote: ((boolean, Subject, unknown) -> ())? = nil
	local stepped: (() -> ())? = nil
	local close: (() -> ())? = nil
	local applied: { { body: Body, intent: Point, facing: Point? } } = {}
	local acknowledgements: { { subject: Subject, ack: Ack } } = {}
	local snapshots: { { subject: Subject, x: number, z: number, hp: number } } = {}
	local inputActivity: { boolean } = {}
	local players: { [Subject]: boolean } = {}
	local bodies: { [Subject]: Body } = {}
	local states: { [Subject]: State } = {}
	local requests: { Request } = {}
	local disconnects: { string } = {}
	local marks: { string } = {}
	local markDetails: { [string]: string? } = {}
	local now = 1
	local dependencies: Intake.Dependencies<Subject, Body> = {
		clock = function(): number
			if option.clockThrows then
				error("clock")
			end
			return now
		end,
		registerClose = function(callback: () -> ()): () -> ()
			if option.closeThrows then
				error("close")
			end
			close = callback
			return function()
				close = nil
			end
		end,
		remote = {
			connect = function(callback: (boolean, Subject, unknown) -> ()): () -> ()
				if option.remoteConnectThrows then
					error("remote_connect")
				end
				remote = callback
				return connection("remote", option, disconnects)
			end,
			acknowledge = function(subject: Subject, ack: Ack)
				if option.ackThrows then
					error("ack")
				end
				table.insert(acknowledgements, { subject = subject, ack = ack })
			end,
		},
		step = {
			connect = function(callback: () -> ()): () -> ()
				if option.stepConnectThrows then
					error("step_connect")
				end
				stepped = callback
				return connection("step", option, disconnects)
			end,
		},
		players = {
			validatePlayer = function(subject: Subject): boolean
				return subject.valid
			end,
			isPresent = function(subject: Subject): boolean
				return players[subject] == true
			end,
			identity = function(subject: Subject): number
				return subject.userId
			end,
			currentBody = function(subject: Subject): Body?
				return bodies[subject]
			end,
		},
		normalize = function(raw: unknown): Intake.Normalized?
			if option.normalizeThrows then
				error("normalize")
			end
			return parse(raw)
		end,
		control = {
			apply = function(body: Body, intent: Point, facing: Point?): boolean
				table.insert(
					applied,
					{ body = body, intent = table.clone(intent), facing = if facing then table.clone(facing) else nil }
				)
				if option.controlThrows then
					error("control")
				end
				return option.controlFalse ~= true
					and (option.controlFalseFor ~= body.x or (intent.x == 0 and intent.z == 0))
			end,
			restore = function(body: Body, x: number, z: number): boolean
				if option.restoreThrows then
					error("restore")
				end
				body.x = x
				body.z = z
				return true
			end,
		},
		snapshot = {
			state = function(subject: Subject): State?
				return states[subject]
			end,
			reset = function(subject: Subject, epoch: number)
				local state = states[subject]
				if state ~= nil and state.movementEpoch == epoch then
					states[subject] = {
						hp = state.hp,
						movementEpoch = epoch + 1,
						movementSequence = 0,
						movement = { x = 0, z = 0 },
					}
				end
			end,
			move = function(subject: Subject, intent: Point, strafe: boolean, epoch: number, sequence: number): boolean
				table.insert(
					requests,
					{ subject = subject, intent = intent, strafe = strafe, epoch = epoch, sequence = sequence }
				)
				return option.queueRefused ~= true
			end,
			travelRevision = function(body: Body): number
				return body.travelRevision or 0
			end,
			observe = function(body: Body): Intake.Observation?
				if option.snapshotThrows then
					error("snapshot")
				end
				return { x = body.x, z = body.z, hp = body.hp }
			end,
			setPlayerSnapshot = function(
				subject: Subject,
				x: number,
				z: number,
				hp: number,
				activeInput: boolean?
			): boolean
				if option.snapshotFalse then
					return false
				end
				table.insert(snapshots, { subject = subject, x = x, z = z, hp = hp })
				table.insert(inputActivity, activeInput == true)
				return true
			end,
		},
		mark = function(phase: string, detail: string?)
			if option.markThrows then
				error("mark")
			end
			table.insert(marks, phase)
			markDetails[phase] = detail
		end,
	}
	local observed: Observed = {
		add = function(userId: number): Subject
			local subject: Subject = { userId = userId, valid = true }
			players[subject] = true
			states[subject] = {
				hp = 100,
				facing = { x = 0, z = -1 },
				movement = { x = 0, z = 0 },
				movementEpoch = 1,
				movementSequence = 0,
			}
			bodies[subject] = { x = userId, z = -userId, hp = 100 }
			return subject
		end,
		commit = function(subject: Subject, state: State)
			states[subject] = state
		end,
		requests = requests,
		setBody = function(subject: Subject, body: Body)
			bodies[subject] = body
		end,
		mutateBody = function(subject: Subject, x: number, z: number)
			bodies[subject].x = x
			bodies[subject].z = z
		end,
		advanceTime = function(seconds: number)
			now += seconds
		end,
		authorizeTravel = function(subject: Subject)
			bodies[subject].travelRevision = (bodies[subject].travelRevision or 0) + 1
		end,
		remote = function(subject: Subject, payload: unknown)
			assert(remote)(
				if option.allow then option.allow(subject, now) else option.rateDenied ~= true,
				subject,
				payload
			)
		end,
		step = function()
			assert(stepped)()
		end,
		close = function()
			assert(close)()
		end,
		applied = applied,
		acknowledgements = acknowledgements,
		snapshots = snapshots,
		inputActivity = inputActivity,
		disconnects = disconnects,
		marks = marks,
		markDetails = markDetails,
	}
	return dependencies, observed
end

local function started(dependencies: Intake.Dependencies<Subject, Body>): Intake.Started<Subject>
	local result = Intake.start(dependencies)
	assert(result.phase == "movement_authority_started")
	return result
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("movement intake committed state", function()
		it("refuses and restores a same-body frontier displacement", function()
			local dependencies, observed = harness()
			local authority = started(dependencies)
			local subject = observed.add(101)
			expect(authority.admitPlayer(subject)):toBe(true)
			observed.mutateBody(subject, 601, 601)
			observed.step()
			expect(observed.snapshots[#observed.snapshots]):toEqual({ subject = subject, x = 101, z = -101, hp = 100 })
			expect(observed.marks):toContain("movement_revoked_step_displacement")
			expect(authority.removePlayer(subject)):toBe(false)
			authority.stop()
		end)

		it("never snapshots a displacement when physical restoration fails", function()
			local dependencies, observed = harness({ restoreThrows = true })
			local authority = started(dependencies)
			local subject = observed.add(101)
			expect(authority.admitPlayer(subject)):toBe(true)
			observed.mutateBody(subject, 601, 601)
			observed.step()
			expect(#observed.snapshots):toBe(0)
			expect(observed.marks):toContain("movement_revoked_step_displacement")
			authority.stop()
		end)

		it("allows an explicit server travel revision and refuses sustained excessive speed", function()
			local dependencies, observed = harness()
			local authority = started(dependencies)
			local subject = observed.add(101)
			expect(authority.admitPlayer(subject)):toBe(true)
			observed.authorizeTravel(subject)
			observed.mutateBody(subject, 601, 601)
			observed.step()
			expect(observed.snapshots[#observed.snapshots]):toEqual({ subject = subject, x = 601, z = 601, hp = 100 })
			for index = 1, 10 do
				observed.advanceTime(0.1)
				observed.mutateBody(subject, 601 + index * 8, 601)
				observed.step()
			end
			expect(observed.snapshots[#observed.snapshots].x):toBe(601)
			expect(observed.marks):toContain("movement_revoked_step_displacement")
			authority.stop()
		end)

		it("detaches caller-owned ports after startup", function()
			local dependencies, observed = harness()
			local result = started(dependencies)
			local subject = observed.add(36)
			expect(result.admitPlayer(subject)):toBe(true)
			dependencies.control.apply = function(): boolean
				return false
			end
			dependencies.snapshot.setPlayerSnapshot = function(): boolean
				return false
			end
			observed.step()
			expect(#observed.snapshots):toBe(1)
			expect(result.removePlayer(subject)):toBe(true)
		end)

		it("attempts both disconnects and every entry once before a stable failed stop receipt", function()
			local dependencies, observed = harness({ disconnectThrows = "remote" })
			local result = started(dependencies)
			local first = observed.add(81)
			local second = observed.add(82)
			expect(result.admitPlayer(first)):toBe(true)
			expect(result.admitPlayer(second)):toBe(true)
			local stopped = result.stop()
			expect(stopped.phase):toBe("movement_authority_stop_failed")
			expect(result.stop()):toBe(stopped)
			expect(observed.disconnects):toEqual({ "remote", "step" })
			expect(#observed.snapshots):toBe(2)
			expect(observed.applied[#observed.applied - 1].intent):toEqual({ x = 0, z = 0 })
			expect(observed.applied[#observed.applied].intent):toEqual({ x = 0, z = 0 })
		end)

		it("refuses unusable connections and rejects an unsafe initial control step", function()
			local unsafeDependencies, observed = harness({ controlFalse = true })
			local result = started(unsafeDependencies)
			expect(result.admitPlayer(observed.add(41))):toBe(false)
			local throwing = harness({ remoteConnectThrows = true })
			expect(Intake.start(throwing)):toEqual({
				phase = "movement_authority_refused",
				reason = "remote_connection_invalid",
			})
			local stepThrowing, stepObserved = harness({ stepConnectThrows = true })
			expect(Intake.start(stepThrowing)):toEqual({
				phase = "movement_authority_refused",
				reason = "step_connection_invalid",
			})
			expect(stepObserved.disconnects):toEqual({ "remote" })
			local closing, closeObserved = harness({ closeThrows = true })
			expect(Intake.start(closing)):toEqual({
				phase = "movement_authority_refused",
				reason = "close_registration_invalid",
			})
			expect(closeObserved.disconnects):toEqual({ "step", "remote" })
		end)

		it("projects and acknowledges only committed movement, preserving the authoritative heading", function()
			local dependencies, observed = harness()
			local result = started(dependencies)
			local subject = observed.add(11)
			expect(result.admitPlayer(subject)):toBe(true)
			observed.remote(subject, { epoch = 1, sequence = 1, intent = { x = 1, z = 0 } })
			expect(#observed.requests):toBe(1)
			expect(#observed.acknowledgements):toBe(0)
			observed.step()
			expect(observed.applied[#observed.applied].intent):toEqual({ x = 0, z = 0 })
			expect(#observed.acknowledgements):toBe(0)
			observed.commit(subject, {
				hp = 100,
				facing = { x = 1, z = 0 },
				movement = { x = 1, z = 0 },
				movementEpoch = 1,
				movementSequence = 1,
			})
			observed.step()
			expect(observed.applied[#observed.applied].intent):toEqual({ x = 1, z = 0 })
			expect(observed.applied[#observed.applied].facing):toEqual({ x = 1, z = 0 })
			expect(observed.acknowledgements[1].ack):toEqual({
				epoch = 1,
				sequence = 1,
				intent = { x = 1, z = 0 },
				acceptedCount = 1,
			})
			expect(observed.inputActivity[#observed.inputActivity]):toBe(true)
			observed.remote(subject, { epoch = 1, sequence = 2, intent = { x = 0, z = 1 }, strafe = true })
			expect(observed.requests[2].strafe):toBe(true)
			observed.commit(subject, {
				hp = 100,
				facing = { x = 1, z = 0 },
				movement = { x = 0, z = 1 },
				movementEpoch = 1,
				movementSequence = 2,
			})
			observed.step()
			expect(observed.applied[#observed.applied].facing):toEqual({ x = 1, z = 0 })
			result.stop()
		end)

		it("never projects or acknowledges a queued turn rejected by the store", function()
			for _, queueRefused in { false, true } do
				local dependencies, observed = harness({ queueRefused = queueRefused })
				local result = started(dependencies)
				local subject = observed.add(11)
				expect(result.admitPlayer(subject)):toBe(true)
				observed.remote(subject, { epoch = 1, sequence = 1, intent = { x = 1, z = 0 } })
				observed.step()
				expect(observed.applied[#observed.applied].intent):toEqual({ x = 0, z = 0 })
				expect(#observed.acknowledgements):toBe(0)
				if queueRefused then
					expect(observed.marks):toContain("movement_revoked_movement_queue_refused")
				end
				result.stop()
			end
		end)

		it(
			"releases immediately without acknowledging an uncommitted stop or letting an older commit restart it",
			function()
				local allowed = true
				local dependencies, observed = harness({
					allow = function()
						return allowed
					end,
				})
				local result = started(dependencies)
				local subject = observed.add(11)
				expect(result.admitPlayer(subject)):toBe(true)
				observed.remote(subject, { epoch = 1, sequence = 1, intent = { x = 1, z = 0 } })
				observed.commit(subject, {
					hp = 100,
					facing = { x = 1, z = 0 },
					movement = { x = 1, z = 0 },
					movementEpoch = 1,
					movementSequence = 1,
				})
				observed.step()
				allowed = false
				observed.remote(subject, { epoch = 1, sequence = 2, intent = { x = 0, z = 0 } })
				expect(#observed.requests):toBe(2)
				expect(observed.applied[#observed.applied].intent):toEqual({ x = 0, z = 0 })
				observed.step()
				expect(observed.applied[#observed.applied].intent):toEqual({ x = 0, z = 0 })
				expect(#observed.acknowledgements):toBe(1)
				observed.commit(subject, {
					hp = 100,
					facing = { x = 1, z = 0 },
					movement = { x = 0, z = 0 },
					movementEpoch = 1,
					movementSequence = 2,
				})
				observed.step()
				expect(observed.acknowledgements[2].ack.intent):toEqual({ x = 0, z = 0 })
				expect(observed.inputActivity[#observed.inputActivity]):toBe(false)
				expect(observed.applied[#observed.applied].facing):toEqual({ x = 1, z = 0 })
				result.stop()
			end
		)

		it(
			"refuses malformed, replayed, foreign and rate-denied requests while allowing the zero epoch handshake",
			function()
				local allowed = true
				local dependencies, observed = harness({
					allow = function()
						return allowed
					end,
				})
				local result = started(dependencies)
				local subject = observed.add(11)
				expect(result.admitPlayer(subject)):toBe(true)
				observed.remote(subject, { sequence = 0, intent = { x = 0, z = 0 } })
				expect(observed.acknowledgements[1].ack.epoch):toBe(1)
				expect(#observed.requests):toBe(0)
				for _, payload in
					{
						false,
						{ bad = true },
						{ sequence = 1, intent = { x = 1, z = 0 } },
						{ epoch = 1, sequence = 1, intent = { x = 2, z = 0 } },
						{ epoch = 1, sequence = 1, intent = { x = math.nan, z = 0 } },
					}
				do
					observed.remote(subject, payload)
				end
				observed.remote(observed.add(12), { epoch = 1, sequence = 1, intent = { x = 1, z = 0 } })
				expect(#observed.requests):toBe(0)
				observed.remote(subject, { epoch = 1, sequence = 1, intent = { x = 1, z = 0 } })
				observed.remote(subject, { epoch = 1, sequence = 1, intent = { x = 0, z = 0 } })
				allowed = false
				observed.remote(subject, { epoch = 1, sequence = 2, intent = { x = 1, z = 0 } })
				expect(#observed.requests):toBe(1)
				result.stop()
			end
		)

		it("requires a new authored seed after body replacement and rejects the prior body's packets", function()
			local dependencies, observed = harness()
			local result = started(dependencies)
			local subject = observed.add(11)
			expect(result.admitPlayer(subject)):toBe(true)
			observed.setBody(subject, { x = 11, z = -11, hp = 100 })
			observed.step()
			expect(result.admitPlayer(subject)):toBe(false)
			observed.commit(subject, {
				hp = 100,
				facing = { x = 0, z = 1 },
				movement = { x = 0, z = 0 },
				movementEpoch = 3,
				movementSequence = 0,
			})
			expect(result.admitPlayer(subject)):toBe(true)
			observed.remote(subject, { epoch = 1, sequence = 99, intent = { x = 1, z = 0 } })
			expect(#observed.requests):toBe(0)
			expect(observed.acknowledgements[1].ack.epoch):toBe(3)
			observed.remote(subject, { epoch = 3, sequence = 1, intent = { x = 0, z = 1 } })
			expect(observed.requests[1].epoch):toBe(3)
			result.stop()
		end)

		it(
			"contains transient unreadable observations, preserves fractional health, and retires persistent failures",
			function()
				local dependencies, observed = harness()
				local result = started(dependencies)
				local subject = observed.add(11)
				local body: Body = { x = 11, z = -11, hp = 100 }
				observed.setBody(subject, body)
				expect(result.admitPlayer(subject)):toBe(true)
				body.hp = -1
				observed.step()
				expect(observed.markDetails.movement_observation_skipped):toBe("hp_not_positive:-1")
				body.hp = 0.3
				observed.step()
				expect(observed.snapshots[#observed.snapshots].hp):toBe(1)
				body.hp = -1
				for _ = 1, 3 do
					observed.step()
				end
				expect(observed.markDetails.movement_revoked_step_observation_invalid):toBe(
					"hp_not_positive:-1 after 3 consecutive"
				)
				expect(result.removePlayer(subject)):toBe(false)
				result.stop()
			end
		)

		it("contains one failed player while another continues, and stops idempotently", function()
			local dependencies, observed = harness({ controlFalseFor = 11 })
			local result = started(dependencies)
			local first, second = observed.add(11), observed.add(12)
			expect(result.admitPlayer(first)):toBe(true)
			expect(result.admitPlayer(second)):toBe(true)
			observed.commit(first, {
				hp = 100,
				facing = { x = 1, z = 0 },
				movement = { x = 1, z = 0 },
				movementEpoch = 1,
				movementSequence = 1,
			})
			local beforeStep = #observed.snapshots
			observed.step()
			expect(observed.marks):toContain("movement_revoked_step_control_refused")
			local continued = false
			for index = beforeStep + 1, #observed.snapshots do
				if observed.snapshots[index].subject == second then
					continued = true
				end
			end
			expect(continued):toBe(true)
			local receipt = result.stop()
			expect(result.stop()):toBe(receipt)
			expect(result.admitPlayer(observed.add(13))):toBe(false)
		end)
	end)
end
