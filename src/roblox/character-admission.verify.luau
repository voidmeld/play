--!strict
local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Host = require("./character-admission")
local LeaseStores = require("../core/identity/character-lease-store")
local Routing = require("../core/identity/routing")
local Value = require("../kernel/value")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Profile = { account: number, subject: string, generation: number, identity: string }
local fixtureUniverse = 101
local fixtureSource = 202
local fixtureDestination = 303
local function rig()
	local trace: { string } = {}
	local pending: { () -> () } = {}
	local subject: Host.Subject = { UserId = 41, Name = "Subject", Character = false }
	local profile: Profile = { account = 41, subject = "subject", generation = 7, identity = "private" }
	local control = {
		now = 0,
		bodyFailure = false,
		removalFailure = false,
		renewFailure = false,
		releases = 0,
		renewals = 0,
		failures = 0,
		version = 0,
		connectionFailure = false,
	}
	local function mark(name: string): boolean
		table.insert(trace, name)
		return true
	end
	local config: Host.Config<Profile> = {
		profileFacts = function(model: Profile): Host.ProfileFacts
			return { userId = model.account, characterId = model.subject, version = model.generation }
		end,
		projectProfile = function(_subject: Host.Subject, _model: Profile, _name: string?)
			mark("project")
		end,
		sameIdentity = function(a: unknown, b: unknown): boolean
			local left = Value.raw(a)
			local right = Value.raw(b)
			return left ~= nil and right ~= nil and left.identity == right.identity
		end,
		leaseFailure = function()
			control.failures += 1
		end,
		idLimit = 32,
		timingRecordLimit = 500,
		timingOperationLimit = 8,
		timingReasonLimit = 32,
		reclaimReason = "held",
		actorRetryReasons = { busy = true },
		cleanupSeconds = 2,
		retrySeconds = 1,
		renewSeconds = 5,
		leaseSeconds = 20,
	}
	local policy: Routing.Policy = table.freeze({
		binding = table.freeze({
			channel = "alpha",
			universeId = fixtureUniverse,
			sourcePlaceId = fixtureSource,
			places = {},
		}),
		budget = { targetSeconds = 5, maxAttemptsPerSession = 2 },
		handoff = { freshnessSeconds = 10 },
		refusals = {},
		destinations = {},
		placeByDestinationId = {},
	})
	local route: Routing.Route = {
		requestId = "request",
		destinationId = "hub:entry",
		zoneId = "sector",
		realm = "Side A",
		characterId = "subject",
		realmId = "side_a",
		universeId = fixtureUniverse,
		sourcePlaceId = fixtureSource,
		destinationPlaceId = fixtureDestination,
		sessionId = "session",
		acquisitionId = "attempt1",
		issuedAtUnix = 0,
		deadlineAtUnix = 5,
		carrierExpiresAtUnix = 10,
		attempt = 1,
	}
	local deps: Host.Dependencies<Host.Subject, Profile> = {
		zoneKey = "sector",
		placeId = fixtureDestination,
		sessionId = "session",
		routing = {
			projectPolicy = function(_raw: unknown): Routing.Policy?
				return policy
			end,
			accept = function(_policy: unknown, _arrival: unknown): Routing.Decision
				return { outcome = "accepted", route = route }
			end,
		},
		routingContent = {},
		catalog = {},
		clear = function(_subject)
			return mark("clear")
		end,
		preflight = function(_subject)
			return mark("preflight")
		end,
		refuse = function(_subject, _reason)
			return mark("refuse")
		end,
		clock = function(): number
			return control.now
		end,
		acquisitionId = function(_id: number, serial: number): string
			return "attempt" .. serial
		end,
		scheduleLeaseRenewal = function(_seconds: number, callback: () -> ())
			table.insert(pending, callback)
		end,
		character = {
			admit = function(raw: unknown): Host.CharacterOutcome<Profile>
				local fields = assert(Value.raw(raw))
				assert(type(fields.sessionId) == "string" and type(fields.acquisitionId) == "string")
				mark("lease")
				return {
					ok = true,
					profile = profile,
					lease = { revision = 1 },
					context = table.freeze({
						userId = subject.UserId,
						characterId = "subject",
						key = "record:subject",
						sessionId = fields.sessionId,
						acquisitionId = fields.acquisitionId,
						leaseRevision = 1,
					}),
				}
			end,
			release = function(_id, _character, _session, _acquisition, _revision)
				control.releases += 1
				return { ok = mark("release") }
			end,
			renew = function(
				character: string,
				session: string,
				acquisition: string,
				revision: number
			): LeaseStores.Outcome
				control.renewals += 1
				if control.renewFailure then
					return { ok = false, value = nil, reason = "offline" }
				end
				return {
					ok = true,
					value = {
						schemaVersion = 7,
						revision = revision + 1,
						characterId = character,
						zoneId = "sector",
						sessionId = session,
						acquisitionId = acquisition,
						expiresAt = control.now + 20,
						retirement = false,
						arrival = false,
					},
				}
			end,
		},
		fence = function(_raw)
			return { ok = mark("fence") }
		end,
		profile = {
			load = function(_context): Profile?
				mark("load")
				return profile
			end,
			unload = function(_context): boolean
				return mark("unload")
			end,
			level = function(_context): number?
				return 7
			end,
		},
		session = {
			bind = function(_subject, _context)
				return mark("bind"), nil
			end,
			release = function(_subject, _context)
				return mark("unbind")
			end,
		},
		actor = {
			admitPlayer = function(_subject, _model)
				return mark("actor"), nil
			end,
			removePlayer = function(_subject)
				mark("removeActor")
				return not control.removalFailure
			end,
		},
		body = {
			admitPlayer = function(_subject, _destination)
				mark("body")
				return not control.bodyFailure, "body_failed"
			end,
			removePlayer = function(_subject)
				return mark("removeBody")
			end,
		},
		movement = {
			admitPlayer = function(_subject)
				return mark("movement"), nil
			end,
			removePlayer = function(_subject)
				return mark("removeMovement")
			end,
		},
		players = {
			present = function(_subject)
				return true
			end,
			getJoinData = function(_subject): unknown
				return {}
			end,
			getPlayers = function()
				return { subject }
			end,
			connectRemoving = function(_callback)
				return function()
					mark("disconnectRemoving")
				end
			end,
			connectAdded = function(_callback)
				if control.connectionFailure then
					error("connection refused")
				end
				return function()
					mark("disconnectAdded")
				end
			end,
		},
		route = {
			arrive = function(_carrier, _expectation): Host.Route?
				return {
					userId = 41,
					characterId = "subject",
					destinationId = "hub:entry",
					routeId = "route",
					fence = 1,
				}
			end,
		},
		roster = {
			owns = function(_id, _character)
				return true, {}
			end,
			markDeparted = function(_id, _character, _destination, _account)
				return true, {}
			end,
			markLevel = function(_id, _character, _level)
				return true
			end,
			markPlayed = function(_id, _character, _time)
				return true
			end,
		},
		receipt = function(_subject, receipt)
			control.version = receipt.profileVersion
			return mark("receipt"), nil
		end,
	}
	local function start(): Host.Runtime<Host.Subject> | Host.Refused
		return Host.start(config, deps)
	end
	return { start = start, subject = subject, control = control, trace = trace, pending = pending }
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("staged character admission", function()
		it("admits an opaque profile in order and unwinds its owners in reverse", function()
			local r = rig()
			local runtime = r.start()
			assert(runtime.phase == "character_admission_started")
			expect(runtime.isAdmitted(r.subject)):toBe(true)
			expect(r.control.version):toBe(7)
			local joined = table.concat(r.trace, ",")
			expect(string.find(joined, "load,bind,project,actor,body,movement,receipt", 1, true) ~= nil):toBe(true)
			expect(runtime.cleanup(r.subject)):toBe(true)
			local trace = table.concat(r.trace, ",")
			expect(string.find(trace, "removeMovement,removeBody,removeActor,unbind,unload,release", 1, true) ~= nil):toBe(
				true
			)
			expect(runtime.isAdmitted(r.subject)):toBe(false)
		end)
		it("unwinds completed owners after a later admission stage refuses", function()
			local r = rig()
			r.control.bodyFailure = true
			local runtime = r.start()
			assert(runtime.phase == "character_admission_started")
			expect(runtime.isAdmitted(r.subject)):toBe(false)
			expect(r.control.releases):toBe(1)
			expect(string.find(table.concat(r.trace, ","), "removeActor,unbind,unload,release", 1, true) ~= nil):toBe(
				true
			)
		end)
		it("retains session and lease authority until actor removal succeeds", function()
			local r = rig()
			local runtime = r.start()
			assert(runtime.phase == "character_admission_started")
			r.control.removalFailure = true
			expect(runtime.cleanup(r.subject)):toBe(false)
			expect(r.control.releases):toBe(0)
			expect((string.find(table.concat(r.trace, ","), "unbind", 1, true))):toBe(nil)
			r.control.removalFailure = false
			expect(runtime.cleanup(r.subject)):toBe(true)
			expect(r.control.releases):toBe(1)
		end)
		it("prevents an old renewal callback from advancing a replacement admission", function()
			local r = rig()
			local runtime = r.start()
			assert(runtime.phase == "character_admission_started")
			local old = assert(r.pending[1])
			local snapshot = runtime.prepareReturn(r.subject)
			assert(snapshot ~= nil)
			expect(runtime.recover(r.subject, snapshot)):toBe(true)
			old()
			expect(r.control.renewals):toBe(0)
			assert(r.pending[2])()
			expect(r.control.renewals):toBe(1)
			expect(assert(runtime.previewDeparture(r.subject)).fence):toBe(2)
			expect(runtime.dispose()):toBe(true)
			assert(r.pending[3])()
			expect(r.control.renewals):toBe(1)
		end)
		it("fences and unwinds an expired lease after renewal failure", function()
			local r = rig()
			local runtime = r.start()
			assert(runtime.phase == "character_admission_started")
			r.control.renewFailure = true
			r.control.now = 20
			assert(r.pending[1])()
			expect(r.control.failures):toBe(1)
			expect(runtime.isAdmitted(r.subject)):toBe(false)
			expect(r.control.releases):toBe(1)
		end)
		it("releases installed listeners when later connection setup fails", function()
			local r = rig()
			r.control.connectionFailure = true
			expect(r.start().phase):toBe("character_admission_refused")
			expect(table.concat(r.trace, ",")):toBe("disconnectRemoving")
			expect(r.control.releases):toBe(0)
		end)
	end)
end
