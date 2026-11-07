--!strict

local Admission = require("../../src/roblox/character-admission")
local Atomic = require("../../src/roblox/persistence/store")
local Content = require("./content")
local DataStore = require("../../src/roblox/data-store")
local Events = require("../../src/roblox/remote-events")
local Protocol = require("./protocol")
local Routing = require("../../src/core/identity/routing")
local Server = require("./server")
local State = require("./state")
local Stores = require("../../src/core/persistence/store-host")
local Value = require("../../src/kernel/value")

export type Subject = Admission.Subject
export type NativePorts = {
	serverId: string,
	universeId: number,
	placeId: number,
	sourcePlaceId: number,
	storeName: string,
	storage: Stores.RealDependencies,
	circuit: Stores.Circuit,
	owner: index<Server.Ports, "owner">,
	clock: () -> number,
	schedule: (number, () -> ()) -> () -> (),
	newId: () -> string,
	report: (string) -> (),
	filter: (number, string, number) -> string?,
	contact: index<Server.Ports, "contact">,
	elapsed: index<Server.Ports, "elapsed">,
	remote: Protocol.ServerPorts<Subject>,
	players: index<Admission.NativePorts<Subject, State.Profile>, "players">,
	clear: (Subject) -> boolean,
	refuse: (Subject, string) -> boolean,
	actor: index<Admission.NativePorts<Subject, State.Profile>, "actor">,
	body: index<Admission.NativePorts<Subject, State.Profile>, "body">,
	movement: index<Admission.NativePorts<Subject, State.Profile>, "movement">,
	onClose: ((() -> boolean) -> ())?,
}

local function start(native: NativePorts)
	local retry = DataStore.retryPolicy({ attempts = 3, baseDelay = 0.2, maxDelay = 2 })
	local stores = Stores.create({
		clock = native.clock,
		maxKeyBytes = 256,
		maxAttempts = 3,
		backoff = retry.delay,
		retry = retry.run,
		warning = native.report,
	})
	local backend = stores.real(native.storeName, {}, native.circuit, native.storage)
	local function playerFor(userId: number): Subject?
		for _, player in native.players.getPlayers() do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end
	local function deliver(userId: number, response: Protocol.Response)
		local player = playerFor(userId)
		if player ~= nil then
			native.remote.sendResponse(player, response)
		end
	end
	local world = Server.new({
		store = Atomic.new(backend),
		owner = native.owner,
		clock = native.clock,
		schedule = native.schedule,
		serverId = native.serverId,
		newId = native.newId,
		filter = native.filter,
		deliver = deliver,
		report = native.report,
		contact = native.contact,
		elapsed = native.elapsed,
	})
	local routing = Routing.create({
		realms = { harbor = "Harbor" },
		structuralId = function(raw: unknown)
			return Value.identifier(raw, 64)
		end,
		namespacedId = function(raw: unknown): string?
			return if type(raw) == "string"
					and #raw <= 64
					and string.match(raw, "^[%w_]+:[%w_]+$") ~= nil
				then raw
				else nil
		end,
		idLimit = 64,
		refusalLineLimit = 64,
		unroutedStatusLimit = 8,
		unroutedReasonLimit = 64,
		unknownRequestId = "missing",
		invalidBinding = {
			id = "binding_invalid",
			recoverable = false,
			retryable = false,
			holdsAtDoor = true,
			line = "Admission unavailable",
		},
	})
	local refusals: { Routing.RefusalRow } = {}
	for _, id in routing.REASON_IDS do
		table.insert(refusals, { id = id, recoverable = true, retryable = true, holdsAtDoor = true, line = id })
	end
	local destinations = {
		{
			id = "harbor:entry",
			zoneId = "Harbor",
			realm = "Harbor",
			isStarter = true,
			requiresUnlock = false,
			unlockId = "",
			minLevel = 1,
		},
	}
	local admission = Admission.start({
		profileFacts = function(profile: State.Profile): Admission.ProfileFacts
			return { userId = profile.userId, characterId = profile.characterId, version = 1 }
		end,
		projectProfile = function(_player, _profile) end,
		sameIdentity = function(first: unknown, second: unknown): boolean
			local a, b = Value.raw(first), Value.raw(second)
			return a ~= nil and b ~= nil and a.userId == b.userId and a.characterId == b.characterId
		end,
		leaseFailure = function()
			native.report("admission_lease_lost")
		end,
		idLimit = 128,
		timingRecordLimit = 1024,
		timingOperationLimit = 16,
		timingReasonLimit = 64,
		reclaimReason = "session_held",
		actorRetryReasons = {},
		cleanupSeconds = 10,
		retrySeconds = 2,
		renewSeconds = 20,
		leaseSeconds = Content.leaseSeconds,
	}, {
		zoneKey = "harbor",
		placeId = native.placeId,
		sessionId = native.serverId,
		routing = { projectPolicy = routing.projectPolicy, accept = routing.accept },
		routingContent = {
			binding = {
				channel = "fixture",
				universeId = native.universeId,
				sourcePlaceId = native.sourcePlaceId,
				places = { { destinationId = "harbor:entry", placeId = native.placeId } },
			},
			budget = { targetSeconds = 5, maxAttemptsPerSession = 2 },
			handoff = { freshnessSeconds = 10 },
			refusals = refusals,
			unroutedChannels = {},
		},
		catalog = { destinations = destinations },
		clear = native.clear,
		preflight = function(player: Subject): boolean
			return world.create(player.UserId, "Traveler" .. tostring(player.UserId))
		end,
		refuse = native.refuse,
		clock = native.clock,
		acquisitionId = function(_userId, _serial)
			return native.newId()
		end,
		character = {
			admit = function(raw: unknown): Admission.CharacterOutcome<State.Profile>
				local row = Value.raw(raw)
				if
					row == nil
					or type(row.userId) ~= "number"
					or type(row.acquisitionId) ~= "string"
					or row.sessionId ~= native.serverId
				then
					return { ok = false, reason = "identity_invalid" }
				end
				return world.join(row.userId, row.acquisitionId)
			end,
			release = function(userId, _characterId, _sessionId, _acquisitionId, _revision)
				return { ok = world.close(userId) }
			end,
		},
		fence = function(raw: unknown)
			local row = Value.raw(raw)
			local userId = if row ~= nil and type(row.characterId) == "string"
				then tonumber(string.match(row.characterId, "^character:(%d+)$"))
				else nil
			local context = if userId ~= nil then world.context(userId) else nil
			return {
				ok = row ~= nil
					and context ~= nil
					and context.acquisitionId == row.acquisitionId
					and context.sessionId == row.sessionId
					and context.leaseRevision == row.revision,
			}
		end,
		profile = {
			load = world.profile,
			unload = function(context)
				return context ~= nil and world.close(context.userId)
			end,
			level = function(context)
				local profile = world.profile(context)
				return if profile ~= nil then Content.levels.levelForXp(profile.xp) else nil
			end,
		},
		session = {
			bind = function(player, context)
				return context ~= nil and context.userId == player.UserId and world.profile(context) ~= nil, nil
			end,
			release = function(_player, _context)
				return true
			end,
		},
		actor = native.actor,
		body = native.body,
		movement = native.movement,
		players = native.players,
		route = {
			arrive = function(_joinData, raw): Admission.Route?
				local row = Value.raw(raw)
				if row == nil or type(row.userId) ~= "number" then
					return nil
				end
				return {
					userId = row.userId,
					characterId = "character:" .. tostring(row.userId),
					destinationId = "harbor:entry",
					routeId = native.newId(),
					fence = 1,
					sourcePlaceId = native.sourcePlaceId,
				}
			end,
		},
		roster = {
			owns = world.owns,
			markDeparted = function(userId, characterId, _destination, account)
				local owned = world.owns(userId, characterId)
				return owned, account
			end,
			markLevel = function()
				return true
			end,
			markPlayed = function()
				return true
			end,
		},
		receipt = function(player, _receipt)
			deliver(player.UserId, { ok = true, view = world.view(player.UserId) })
			return true, nil
		end,
	})
	if admission.phase ~= "character_admission_started" then
		error(admission.reason or "admission configuration refused")
	end
	type Handler = (Subject, unknown) -> ()
	local handler: Handler? = nil
	local transport = Events.transport({
		register = function(_name: string, callback: Handler, _options: boolean?)
			handler = callback
			return function()
				handler = nil
			end
		end,
		served = function(_name: string)
			return if handler ~= nil then 1 else 0
		end,
		connect = function(_event: string, callback: (Subject, ...unknown) -> ())
			return native.remote.connectRequest(callback)
		end,
		receive = function(_name: string, player: Subject, ...: unknown)
			local callback = handler
			if callback ~= nil then
				callback(player, if select("#", ...) == 1 then (...) else nil)
			end
		end,
		own = function(cleanup)
			native.owner.own(cleanup)
		end,
	})
	local release = transport.serve("world", "world", function(player: Subject, raw: unknown)
		if not admission.isAdmitted(player) then
			deliver(player.UserId, { ok = false, reason = "not_admitted" })
			return
		end
		deliver(player.UserId, world.request(player.UserId, raw))
	end, nil)
	local function shutdown(): boolean
		release()
		local cleaned = admission.dispose()
		local drained = world.drain()
		if cleaned and drained then
			native.owner.dispose()
		end
		return cleaned and drained
	end
	if native.onClose ~= nil then
		native.onClose(shutdown)
	end
	return table.freeze({ world = world, admission = admission, shutdown = shutdown })
end

return table.freeze({ start = start })
