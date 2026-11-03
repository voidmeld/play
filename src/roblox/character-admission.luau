--!strict
local LeaseRepository = require("../core/identity/character-lease-store")
local Routing = require("../core/identity/routing")
local Stores = require("../core/persistence/store-host")
local Value = require("../core/internal/value")
type Raw = { [unknown]: unknown }
export type Subject = { read Character: unknown, read UserId: number, read Name: string? }
export type Context = {
	read userId: number,
	read characterId: string,
	read key: string,
	read sessionId: string,
	read acquisitionId: string,
	read leaseRevision: number,
}
export type ProfileFacts = { read userId: number, read characterId: string, read version: number }
export type CharacterOutcome<F> = {
	read ok: boolean,
	read reason: string?,
	read profile: F?,
	read lease: { read revision: number }?,
	read context: Context?,
	read releaseReason: string?,
}
export type Route = {
	read userId: number,
	read characterId: string,
	read destinationId: string,
	read routeId: string,
	read fence: number,
	read sourcePlaceId: number?,
}
export type Snapshot = {
	read userId: number,
	read characterId: string,
	read destinationId: string?,
	read routeId: string,
	read fence: number,
}
type Entry = {
	context: Context?,
	userId: number,
	characterId: string,
	sessionId: string,
	acquisitionId: string,
	leaseRevision: number,
	destinationId: string?,
	profile: boolean,
	session: boolean,
	actor: boolean,
	body: boolean,
	movement: boolean,
	renewing: boolean?,
	cleanupRequested: boolean?,
	cleanupDeliberate: boolean?,
	leaseExpiresAt: number?,
}
type Timeline<P> = {
	player: P,
	startedAt: number,
	lastMs: number,
	stages: { string },
	operations: { string },
	dropped: number,
}
export type Runtime<P> = {
	read phase: "character_admission_started",
	read dispose: () -> boolean,
	read cleanup: (P, boolean?) -> boolean,
	read isAdmitted: (P) -> boolean,
	read previewDeparture: (P) -> { read userId: number, read characterId: string, read fence: number }?,
	read prepareReturn: (P) -> (Snapshot?, Snapshot?),
	read recover: (P, unknown) -> boolean,
}
export type Refused = { read phase: "character_admission_refused", read reason: string? }
export type Dependencies<P, F> = NativePorts<P & Subject, F>
export type NativePorts<P, F> = {
	zoneKey: string,
	placeId: number,
	localScenarioCapability: boolean?,
	sessionId: string,
	timing: {
		clock: () -> number,
		publish: (P, string) -> (),
		storePrefix: string?,
		observe: (((Stores.Observation) -> ()) -> () -> ())?,
	}?,
	stage: ((P, string) -> ())?,
	routing: { projectPolicy: index<Routing.API, "projectPolicy">, accept: index<Routing.API, "accept"> },
	routingContent: { binding: unknown, budget: unknown, handoff: unknown, refusals: unknown, unroutedChannels: unknown },
	catalog: { destinations: unknown },
	reclaim: { attempts: number, seconds: number, wait: (number) -> () }?,
	clear: (P) -> boolean,
	preflight: (P) -> boolean,
	refuse: (P, string) -> boolean,
	clock: () -> number,
	identity: ((P) -> unknown)?,
	acquisitionId: (number, number) -> string,
	waitLeaseRenewal: (() -> ())?,
	scheduleLeaseRenewal: ((number, () -> ()) -> ())?,
	character: {
		admit: (unknown) -> CharacterOutcome<F>,
		release: (number, string, string, string, number) -> { read ok: boolean, read reason: string? },
		renew: ((string, string, string, number) -> LeaseRepository.Outcome)?,
	},
	fence: (unknown) -> { read ok: boolean },
	profile: { load: (Context?) -> F?, unload: (Context?) -> boolean, level: (Context?) -> number? },
	session: { bind: (P, Context?) -> (boolean, string?), release: (P, Context?) -> boolean },
	actor: { admitPlayer: (P, F) -> (boolean, string?), removePlayer: (P) -> boolean },
	body: { admitPlayer: (P, string) -> (boolean, string?), removePlayer: (P) -> boolean },
	movement: { admitPlayer: (P) -> (boolean, string?), removePlayer: (P) -> boolean },
	players: {
		present: (P) -> boolean,
		getJoinData: (P) -> unknown,
		getPlayers: () -> { P },
		connectRemoving: ((P) -> boolean) -> () -> (),
		connectAdded: ((P) -> ()) -> () -> (),
	},
	route: { arrive: (unknown, unknown) -> Route? },
	roster: {
		owns: (number, string) -> (boolean, unknown),
		markDeparted: (number, string, string, unknown) -> (boolean, unknown),
		markLevel: (number, string, number) -> boolean,
		markPlayed: (number, string, number) -> boolean,
	},
	warAdmission: {
		depart: (Route, boolean) -> boolean,
		authority: () -> boolean,
		reconnect: (number) -> Route?,
		claim: (Route) -> (boolean, string?),
		restoreDeparture: (Route) -> (boolean, string?),
		refusalCodes: { [string]: boolean },
	}?,
	receipt: (
		P,
		{ read userId: number, read characterId: string, read profileVersion: number, read zoneKey: string }
	) -> (boolean, string?),
}

export type Config<F> = {
	read profileFacts: (F) -> ProfileFacts,
	read projectProfile: (Subject, F, string?) -> (),
	read sameIdentity: (unknown, unknown) -> boolean,
	read leaseFailure: () -> (),
	read idLimit: number,
	read timingRecordLimit: number,
	read timingOperationLimit: number,
	read timingReasonLimit: number,
	read reclaimReason: string,
	read actorRetryReasons: { [string]: boolean },
	read cleanupSeconds: number,
	read retrySeconds: number,
	read renewSeconds: number,
	read leaseSeconds: number,
}
local function start<P, F>(config: Config<F>, deps: Dependencies<P, F>): Runtime<P & Subject> | Refused
	config = table.freeze(table.clone(config))
	local actorRetryReasons = table.freeze(table.clone(config.actorRetryReasons))
	for _, limit in { config.idLimit, config.timingRecordLimit, config.timingOperationLimit, config.timingReasonLimit } do
		assert(limit >= 1 and limit < math.huge and limit % 1 == 0, "invalid admission bound")
	end
	for _, seconds in { config.cleanupSeconds, config.retrySeconds, config.renewSeconds, config.leaseSeconds } do
		assert(Value.finite(seconds) and seconds > 0, "invalid admission interval")
	end
	assert(
		config.retrySeconds <= config.renewSeconds and config.renewSeconds < config.leaseSeconds,
		"invalid admission renewal cadence"
	)
	local CONTEXT_FIELDS = {
		userId = true,
		characterId = true,
		key = true,
		sessionId = true,
		acquisitionId = true,
		leaseRevision = true,
	}

	local TIMING_RECORD_LIMIT = config.timingRecordLimit
	local TIMING_OPERATION_LIMIT = config.timingOperationLimit
	local TIMING_REASON_LIMIT = config.timingReasonLimit
	local RECLAIM_REASON = config.reclaimReason

	local function plain(value: unknown): boolean
		return type(value) == "table" and getmetatable(value) == nil
	end

	local function exact(value: unknown, fields: { [string]: boolean }): Raw?
		if not plain(value) then
			return nil
		end
		local row = assert(Value.raw(value))
		for key in row do
			if type(key) ~= "string" or fields[key] ~= true then
				return nil
			end
		end
		for key in fields do
			if row[key] == nil then
				return nil
			end
		end
		return row
	end

	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= config.idLimit
	end

	local function whole(value: unknown, minimum: number): boolean
		return type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value == math.floor(value)
			and value >= minimum
			and value <= 9007199254740991
	end

	local sameCharacterIdentity = config.sameIdentity

	local function validContext(
		context: unknown,
		subjectId: number,
		characterId: string,
		sessionId: string,
		acquisitionId: string
	): boolean
		local fields = exact(context, CONTEXT_FIELDS)
		if fields == nil then
			return false
		end
		return type(context) == "table"
			and table.isfrozen(context)
			and fields.userId == subjectId
			and fields.characterId == characterId
			and text(fields.key)
			and fields.sessionId == sessionId
			and fields.acquisitionId == acquisitionId
			and whole(fields.leaseRevision, 1)
	end

	local function result(phase: "character_admission_refused", reason: string?): Refused
		return table.freeze({ phase = phase, reason = reason })
	end

	local function detailed(base: string, detail: unknown): string
		return if type(detail) == "string" and #detail > 0 then base .. ":" .. detail else base
	end

	local function refusalReason(decision: unknown): unknown
		if not plain(decision) then
			return nil
		end
		local fields = assert(Value.raw(decision))
		return if plain(fields.refusal) then assert(Value.raw(fields.refusal)).reason else fields.reason
	end

	local function selectProfile(candidate: F?, fallback: F): F
		if type(candidate) == "table" then
			return candidate
		end
		return fallback
	end
	local function beginAdmission(): Runtime<P & Subject> | Refused
		local timing = if type(deps.timing) == "table" then deps.timing else nil
		local storePrefix = if timing ~= nil and type(timing.storePrefix) == "string" then timing.storePrefix else ""
		local timelines: { [thread]: Timeline<P & Subject> } = (setmetatable({}, { __mode = "k" }))
		local function timelineOf(player: P & Subject): Timeline<P & Subject>?
			if timing == nil then
				return nil
			end
			local timeline = timelines[coroutine.running()]
			return if timeline ~= nil and timeline.player == player then timeline else nil
		end
		local function beginTiming(player: P & Subject)
			if timing == nil then
				return
			end
			local ticked, startedAt = pcall(timing.clock)
			if ticked and type(startedAt) == "number" then
				timelines[coroutine.running()] = {
					player = player,
					startedAt = startedAt,
					lastMs = 0,
					stages = {},
					operations = {},
					dropped = 0,
				}
			end
		end
		local function observeStore(observation: Stores.Observation)
			local timeline = timelines[coroutine.running()]
			if timeline == nil then
				return
			end
			if #timeline.operations >= TIMING_OPERATION_LIMIT then
				timeline.dropped += 1
				return
			end
			local store = tostring(observation.store)
			if storePrefix ~= "" and string.sub(store, 1, #storePrefix) == storePrefix then
				store = string.sub(store, #storePrefix + 1)
			end
			table.insert(
				timeline.operations,
				("%s.%s(ms=%d,budgetMs=%d,budgetSleeps=%d,retries=%d)"):format(
					store,
					tostring(observation.operation),
					observation.durationMs,
					observation.budgetWaitMs,
					observation.budgetSleeps,
					observation.retries
				)
			)
		end
		local function settleTiming(player: P & Subject, reason: string?): boolean
			local timeline = timelineOf(player)
			if timeline == nil then
				return false
			end
			timelines[coroutine.running()] = nil
			local record = ("outcome=%s%s stages=%s"):format(
				if reason == nil then "admitted" else "refused",
				if reason == nil
					then ""
					else " reason=" .. string.sub(
						string.gsub(tostring(reason), "%s+", "_"),
						1,
						TIMING_REASON_LIMIT
					),
				table.concat(timeline.stages, ",")
			)
			local kept: { string } = {}
			local length = #record + #" ops="
			for _, operation in timeline.operations do
				length += #operation + 1
				if length > TIMING_RECORD_LIMIT - #" dropped=99999" then
					break
				end
				table.insert(kept, operation)
			end
			record ..= " ops=" .. (if #kept > 0 then table.concat(kept, ";") else "none")
			local dropped = timeline.dropped + #timeline.operations - #kept
			if dropped > 0 then
				record ..= " dropped=" .. tostring(dropped)
			end
			local published = pcall(assert(timing).publish, player, record)
			return published
		end
		local function stamp(player: P & Subject, stage: string)
			if type(deps.stage) == "function" then
				pcall(deps.stage, player, stage)
			end
			local timeline = timelineOf(player)
			if timeline == nil then
				return
			end
			local ticked, now = pcall(assert(timing).clock)
			if ticked and type(now) == "number" then
				local ms = math.max(math.floor((now - timeline.startedAt) * 1000 + 0.5), timeline.lastMs)
				timeline.lastMs = ms
				table.insert(timeline.stages, stage .. ":" .. tostring(ms))
			end
		end
		local zoneKey = deps.zoneKey
		if type(zoneKey) ~= "string" or string.match(zoneKey, "^%l[%l%d_]*$") == nil then
			return result("character_admission_refused", "zone_key_invalid")
		end
		if not whole(deps.placeId, if deps.localScenarioCapability == true then 0 else 1) then
			return result("character_admission_refused", "place_identity_invalid")
		end
		local function projectedPolicy(...: Routing.Policy?): (number, Routing.Policy?)
			local policy = ...
			return select("#", ...), policy
		end
		local projectPolicy = deps.routing.projectPolicy
		local source = {
			binding = deps.routingContent.binding,
			budget = deps.routingContent.budget,
			handoff = deps.routingContent.handoff,
			refusals = deps.routingContent.refusals,
			unroutedChannels = deps.routingContent.unroutedChannels,
			destinations = deps.catalog.destinations,
		}
		local projectedOk, projectedCount, policy = pcall(function()
			return projectedPolicy(projectPolicy(source))
		end)
		if
			not projectedOk
			or projectedCount ~= 1
			or type(policy) ~= "table"
			or not plain(policy)
			or not table.isfrozen(policy)
		then
			return result("character_admission_refused", "routing_invalid")
		end
		local binding = policy.binding
		local boundRoutes: { [P & Subject]: string } = {}
		local entries: { [P & Subject]: Entry } = {}
		local recoveries: { [P & Subject]: Route } = {}
		local warClaims: { [P & Subject]: Route } = {}
		local stopped = false
		local serial = 0
		local reclaimAttempts = 0
		local reclaimSeconds = 0
		local reclaimWait: ((number) -> ())? = nil
		if deps.reclaim ~= nil then
			local reclaim = deps.reclaim
			if
				not plain(reclaim)
				or not whole(reclaim.attempts, 0)
				or type(reclaim.seconds) ~= "number"
				or reclaim.seconds ~= reclaim.seconds
				or reclaim.seconds < 0
				or type(reclaim.wait) ~= "function"
			then
				return result("character_admission_refused", "reclaim_invalid")
			end
			reclaimAttempts = reclaim.attempts
			reclaimSeconds = reclaim.seconds
			reclaimWait = reclaim.wait
		end
		local function call<Args...>(callback: (Args...) -> boolean, ...: Args...): boolean
			local called, accepted = pcall(callback, ...)
			return called and accepted == true
		end
		local function detailedCall<Args...>(callback: (Args...) -> (boolean, unknown), ...: Args...): (boolean, unknown)
			local packed = table.pack(pcall(callback, ...))
			if packed[1] ~= true then
				return false, packed[2]
			end
			if packed[2] ~= true then
				return false, packed[3]
			end
			return true, nil
		end
		local function release(entry: Entry): boolean
			local called, released = pcall(
				deps.character.release,
				entry.userId,
				entry.characterId,
				entry.sessionId,
				entry.acquisitionId,
				entry.leaseRevision
			)
			return called and type(released) == "table" and released.ok == true
		end
		local function cleanup(player: P & Subject, deliberate: boolean?): boolean
			local entry = entries[player]
			if entry ~= nil and entry.renewing == true then
				entry.cleanupRequested = true
				entry.cleanupDeliberate = entry.cleanupDeliberate == true or deliberate == true
				if type(deps.waitLeaseRenewal) ~= "function" then
					return false
				end
				local deadline = deps.clock() + config.cleanupSeconds
				while entry.renewing == true and deps.clock() < deadline do
					deps.waitLeaseRenewal()
				end
				if entry.renewing == true then
					return false
				end
				entry = entries[player]
			end
			if entry == nil then
				boundRoutes[player] = nil
				local cleared = call(deps.clear, player)
				if cleared and warClaims[player] ~= nil then
					cleared = call(assert(deps.warAdmission).depart, warClaims[player], deliberate == true)
					if cleared then
						warClaims[player] = nil
					end
				end
				return cleared
			end
			local ok = call(deps.clear, player)
			if entry.movement then
				local removed = call(deps.movement.removePlayer, player)
				ok = removed and ok
				entry.movement = not removed
			end
			if entry.body then
				local removed = call(deps.body.removePlayer, player)
				ok = removed and ok
				entry.body = not removed
			end
			if entry.actor then
				local removed = call(deps.actor.removePlayer, player)
				local remaining = reclaimAttempts
				while
					not removed
					and remaining > 0
					and deps.warAdmission ~= nil
					and call(deps.warAdmission.authority)
				do
					remaining -= 1
					if not pcall(assert(reclaimWait), reclaimSeconds) then
						break
					end
					if entries[player] ~= entry or not call(deps.warAdmission.authority) then
						break
					end
					removed = call(deps.actor.removePlayer, player)
				end
				ok = removed and ok
				entry.actor = not removed
			end
			local authorityReleased = ok
			if authorityReleased and entry.session then
				authorityReleased = call(deps.session.release, player, entry.context)
				ok = authorityReleased and ok
				if authorityReleased then
					entry.session = false
				end
			end
			if authorityReleased and entry.profile then
				local read, settledLevel = pcall(deps.profile.level, entry.context)
				authorityReleased = call(deps.profile.unload, entry.context)
				ok = authorityReleased and ok
				if authorityReleased then
					entry.profile = false
					if read and type(settledLevel) == "number" and whole(settledLevel, 1) then
						call(deps.roster.markLevel, entry.userId, entry.characterId, settledLevel)
					end
					local ticked, settledAtUnix = pcall(deps.clock)
					if ticked and whole(settledAtUnix, 0) then
						call(deps.roster.markPlayed, entry.userId, entry.characterId, settledAtUnix)
					end
				end
			end
			if authorityReleased then
				authorityReleased = release(entry)
				ok = authorityReleased and ok
			end
			if authorityReleased and warClaims[player] ~= nil then
				authorityReleased = call(assert(deps.warAdmission).depart, warClaims[player], deliberate == true)
				ok = authorityReleased and ok
				if authorityReleased then
					warClaims[player] = nil
				end
			end
			if authorityReleased then
				entries[player] = nil
				boundRoutes[player] = nil
			end
			return ok and authorityReleased
		end
		local function reject(player: P & Subject, reason: string)
			stamp(player, "refused")
			settleTiming(player, reason)
			cleanup(player, true)
			call(deps.refuse, player, reason)
		end
		local function renew(player: P & Subject)
			local entry = entries[player]
			if stopped or entry == nil or entry.movement ~= true then
				return
			end
			entry.renewing = true
			local called, outcome = pcall(
				assert(deps.character.renew),
				entry.characterId,
				entry.sessionId,
				entry.acquisitionId,
				entry.leaseRevision
			)
			entry.renewing = false
			local delay = config.retrySeconds
			if
				called
				and plain(outcome)
				and outcome.ok == true
				and plain(outcome.value)
				and whole(outcome.value.revision, 1)
				and outcome.value.revision == entry.leaseRevision + 1
				and whole(outcome.value.expiresAt, 0)
				and outcome.value.characterId == entry.characterId
				and outcome.value.sessionId == entry.sessionId
				and outcome.value.acquisitionId == entry.acquisitionId
			then
				entry.leaseRevision = outcome.value.revision
				entry.leaseExpiresAt = outcome.value.expiresAt
				delay = config.renewSeconds
			else
				local ticked, now = pcall(deps.clock)
				if ticked and type(now) == "number" and now >= assert(entry.leaseExpiresAt) then
					config.leaseFailure()
					reject(
						player,
						detailed("lease_renewal_refused", if called and plain(outcome) then outcome.reason else nil)
					)
					return
				end
			end
			if entry.cleanupRequested == true then
				cleanup(player, entry.cleanupDeliberate)
				return
			end
			if entries[player] == entry and not stopped then
				assert(deps.scheduleLeaseRenewal)(delay, function()
					if entries[player] == entry then
						renew(player)
					end
				end)
			end
		end
		local function fenced(entry: Entry, fence: unknown, nowUnix: number): boolean
			local called, outcome = pcall(deps.fence, {
				characterId = entry.characterId,
				sessionId = entry.sessionId,
				acquisitionId = entry.acquisitionId,
				revision = entry.leaseRevision,
				fence = fence,
				atUnix = nowUnix,
			})
			return called and type(outcome) == "table" and outcome.ok == true
		end
		local function subjectFor(player: P & Subject): number?
			local mapped: unknown = player.UserId
			if type(deps.identity) == "function" then
				local called, candidate = pcall(deps.identity, player)
				mapped = if called then candidate else nil
			end
			return if type(mapped) == "number" and whole(mapped, 1) then mapped else nil
		end
		local function admitOnce(player: P & Subject)
			if stopped or entries[player] ~= nil or deps.players.present(player) ~= true then
				return
			end
			beginTiming(player)
			local subjectId = subjectFor(player)
			if subjectId == nil then
				reject(player, "identity_invalid")
				return
			end
			stamp(player, "callback_entered")
			if not call(deps.clear, player) then
				reject(player, "clear_refused")
				return
			end
			if not call(deps.preflight, player) then
				reject(player, "preflight_refused")
				return
			end
			stamp(player, "preflight_passed")
			local ticked, nowUnix = pcall(deps.clock)
			if not ticked or not whole(nowUnix, 0) then
				reject(player, "tick_invalid")
				return
			end
			local recovery = recoveries[player]
			recoveries[player] = nil
			local joined, joinData = pcall(deps.players.getJoinData, player)
			stamp(player, "join_data_returned")
			local routed: boolean, arrivedRoute: Route?
			if recovery ~= nil then
				routed, arrivedRoute =
					true, {
						userId = subjectId,
						characterId = recovery.characterId,
						destinationId = recovery.destinationId,
						routeId = recovery.routeId,
						sourcePlaceId = nil,
						fence = recovery.fence,
					}
			else
				routed, arrivedRoute = pcall(deps.route.arrive, if joined then joinData else nil, {
					userId = subjectId,
					sourceUniverseId = binding.universeId,
					sourcePlaceId = binding.sourcePlaceId,
					destinationPlaceId = deps.placeId,
					boundRouteId = boundRoutes[player] or false,
					nowUnix = nowUnix,
				})
			end
			if (not routed or arrivedRoute == nil or type(arrivedRoute) ~= "table") and deps.warAdmission ~= nil then
				local restored, recoveredRoute = pcall(deps.warAdmission.reconnect, subjectId)
				if restored and type(recoveredRoute) == "table" then
					routed, arrivedRoute = true, recoveredRoute
				end
			end
			if
				not routed
				or arrivedRoute == nil
				or type(arrivedRoute) ~= "table"
				or arrivedRoute.userId ~= subjectId
				or not text(arrivedRoute.characterId)
				or not text(arrivedRoute.destinationId)
				or not text(arrivedRoute.routeId)
				or not whole(arrivedRoute.fence, 1)
			then
				reject(player, "route_shape_invalid")
				return
			end
			local route = assert(arrivedRoute)
			local sourcePlaceId = if whole(route.sourcePlaceId, 1) then route.sourcePlaceId else binding.sourcePlaceId
			local decided, decision = pcall(deps.routing.accept, policy, {
				channel = binding.channel,
				universeId = binding.universeId,
				placeId = deps.placeId,
				sourceUniverseId = binding.universeId,
				sourcePlaceId = sourcePlaceId,
				destinationId = route.destinationId,
				characterId = route.characterId,
			})
			if
				not decided
				or not plain(decision)
				or decision.outcome ~= "accepted"
				or decision.route == nil
				or not plain(decision.route)
			then
				reject(player, detailed("routing_refused", refusalReason(decision)))
				return
			end
			stamp(player, "route_accepted")
			local ownedCalled, ownedByRoster, ownedAccount = pcall(deps.roster.owns, subjectId, route.characterId)
			if not ownedCalled or ownedByRoster ~= true then
				reject(player, "roster_ownership_refused")
				return
			end
			if deps.warAdmission ~= nil then
				warClaims[player] = route
				local claim = if recovery ~= nil then deps.warAdmission.restoreDeparture else deps.warAdmission.claim
				local claimed, claimDetail = detailedCall(claim, route)
				if not claimed then
					local codes = deps.warAdmission.refusalCodes
					local publicDetail = if type(claimDetail) == "string"
							and plain(codes)
							and table.isfrozen(codes)
							and codes[claimDetail] == true
						then claimDetail
						else nil
					reject(player, detailed("war_reservation_refused", publicDetail))
					return
				end
			end
			local departedCalled, departed, departedAccount = pcall(
				deps.roster.markDeparted,
				subjectId,
				route.characterId,
				decision.route.destinationId,
				ownedAccount
			)
			if not departedCalled or departed ~= true then
				reject(player, "roster_departure_refused")
				return
			end
			stamp(player, "roster_departed")
			serial += 1
			local acquisitionCalled, acquisitionId = pcall(deps.acquisitionId, subjectId, serial)
			if not acquisitionCalled or not text(acquisitionId) then
				reject(player, "acquisition_invalid")
				return
			end
			local admitted: boolean, admissionOutcome: CharacterOutcome<F>?
			local reclaimsLeft = reclaimAttempts
			while true do
				admitted, admissionOutcome = pcall(deps.character.admit, {
					userId = subjectId,
					characterId = route.characterId,
					sessionId = deps.sessionId,
					acquisitionId = acquisitionId,
					account = departedAccount,
				})
				if
					reclaimsLeft <= 0
					or not admitted
					or admissionOutcome == nil
					or type(admissionOutcome) ~= "table"
					or admissionOutcome.ok == true
					or admissionOutcome.reason ~= RECLAIM_REASON
				then
					break
				end
				reclaimsLeft -= 1
				stamp(player, "lease_reclaim_wait")
				if not pcall(assert(reclaimWait), reclaimSeconds) then
					break
				end
				if deps.players.present(player) ~= true then
					break
				end
			end
			if
				not admitted
				or admissionOutcome == nil
				or type(admissionOutcome) ~= "table"
				or admissionOutcome.ok ~= true
				or admissionOutcome.context == nil
				or not validContext(
					admissionOutcome.context,
					subjectId,
					route.characterId,
					deps.sessionId,
					acquisitionId
				)
			then
				if
					admitted
					and type(admissionOutcome) == "table"
					and admissionOutcome.releaseReason == "release_failed"
					and type(admissionOutcome.lease) == "table"
					and whole(admissionOutcome.lease.revision, 1)
				then
					entries[player] = {
						context = admissionOutcome.context,
						userId = subjectId,
						characterId = route.characterId,
						sessionId = deps.sessionId,
						acquisitionId = acquisitionId,
						leaseRevision = admissionOutcome.lease.revision,
						profile = false,
						session = false,
						actor = false,
						body = false,
						movement = false,
					}
				end
				reject(
					player,
					detailed(
						"lease_refused",
						if type(admissionOutcome) == "table" then admissionOutcome.reason else nil
					)
				)
				return
			end
			stamp(player, "character_admitted")
			local outcome = assert(admissionOutcome)
			local context = assert(outcome.context)
			local entry: Entry = {
				context = context,
				userId = context.userId,
				characterId = context.characterId,
				sessionId = context.sessionId,
				acquisitionId = context.acquisitionId,
				leaseRevision = context.leaseRevision,
				destinationId = route.destinationId,
				profile = false,
				session = false,
				actor = false,
				body = false,
				movement = false,
			}
			entries[player] = entry
			boundRoutes[player] = route.routeId
			if not fenced(entry, route.fence, nowUnix) then
				reject(player, "fence_refused")
				return
			end
			stamp(player, "fenced")
			local loaded, loadedProfile = pcall(deps.profile.load, entry.context)
			if not loaded or type(loadedProfile) ~= "table" then
				reject(player, "profile_unavailable")
				return
			end
			local profile = loadedProfile
			local facts = config.profileFacts(profile)
			local projectionProfile = selectProfile(outcome.profile, profile)
			entry.profile = true
			if
				facts.userId ~= entry.userId
				or facts.characterId ~= entry.characterId
				or not whole(facts.version, 1)
			then
				reject(player, "profile_invalid")
				return
			end
			if not sameCharacterIdentity(projectionProfile, profile) then
				reject(player, "profile_identity_divergent")
				return
			end
			if deps.warAdmission ~= nil and not call(deps.warAdmission.authority) then
				reject(player, "war_authority_lost")
				return
			end
			stamp(player, "profile_loaded")
			local sessionBound, sessionDetail = detailedCall(deps.session.bind, player, entry.context)
			if not sessionBound then
				reject(player, detailed("session_bind_failed", sessionDetail))
				return
			end
			entry.session = true
			stamp(player, "session_bound")
			if deps.warAdmission ~= nil and not call(deps.warAdmission.authority) then
				reject(player, "war_authority_lost")
				return
			end
			config.projectProfile(player, projectionProfile, player.Name)
			local actorAdmitted, actorDetail = detailedCall(deps.actor.admitPlayer, player, profile)
			local actorReclaimsLeft = reclaimAttempts
			while
				not actorAdmitted
				and actorReclaimsLeft > 0
				and type(actorDetail) == "string"
				and actorRetryReasons[actorDetail] == true
			do
				actorReclaimsLeft -= 1
				stamp(player, "actor_admission_wait")
				if not pcall(assert(reclaimWait), reclaimSeconds) then
					break
				end
				if stopped or entries[player] ~= entry or deps.players.present(player) ~= true then
					return
				end
				if deps.warAdmission ~= nil and not call(deps.warAdmission.authority) then
					reject(player, "war_authority_lost")
					return
				end
				actorAdmitted, actorDetail = detailedCall(deps.actor.admitPlayer, player, profile)
			end
			if not actorAdmitted then
				reject(player, detailed("actor_admit_failed", actorDetail))
				return
			end
			entry.actor = true
			stamp(player, "actor_admitted")
			if deps.warAdmission ~= nil and not call(deps.warAdmission.authority) then
				reject(player, "war_authority_lost")
				return
			end
			local bodyAdmitted, bodyDetail = detailedCall(deps.body.admitPlayer, player, route.destinationId)
			if not bodyAdmitted then
				reject(player, detailed("body_admit_failed", bodyDetail))
				return
			end
			entry.body = true
			stamp(player, "body_admitted")
			if deps.warAdmission ~= nil and not call(deps.warAdmission.authority) then
				reject(player, "war_authority_lost")
				return
			end
			local movementAdmitted, movementDetail = detailedCall(deps.movement.admitPlayer, player)
			if not movementAdmitted then
				reject(player, detailed("movement_admit_failed", movementDetail))
				return
			end
			entry.movement = true
			stamp(player, "movement_admitted")
			if deps.warAdmission ~= nil and not call(deps.warAdmission.authority) then
				reject(player, "war_authority_lost")
				return
			end
			local receipted, receiptDetail = detailedCall(
				deps.receipt,
				player,
				table.freeze({
					userId = entry.userId,
					characterId = entry.characterId,
					profileVersion = facts.version,
					zoneKey = zoneKey,
				})
			)
			if not receipted then
				stamp(player, detailed("receipt_unwritten", receiptDetail))
			else
				stamp(player, "receipt_written")
			end
			settleTiming(player, nil)
			if type(deps.character.renew) == "function" and type(deps.scheduleLeaseRenewal) == "function" then
				entry.leaseExpiresAt = nowUnix + config.leaseSeconds
				deps.scheduleLeaseRenewal(config.renewSeconds, function()
					if entries[player] == entry then
						renew(player)
					end
				end)
			end
		end
		local admitting: { [P & Subject]: boolean } = {}
		local function admit(player: P & Subject)
			if admitting[player] == true then
				return
			end
			admitting[player] = true
			local ok, failure = pcall(function()
				admitOnce(player)
			end)
			admitting[player] = nil
			if not ok then
				error(failure, 0)
			end
		end
		local removedOk, disposeRemoved = pcall(deps.players.connectRemoving, function(player)
			return cleanup(player)
		end)
		if not removedOk or type(disposeRemoved) ~= "function" then
			return result("character_admission_refused", "connections_invalid")
		end
		local addedOk, disposeAdded = pcall(deps.players.connectAdded, admit)
		if not addedOk or type(disposeAdded) ~= "function" then
			local removedDisposed = pcall(disposeRemoved)
			return result(
				"character_admission_refused",
				if removedDisposed then "connections_invalid" else "connection_cleanup_failed"
			)
		end
		local function disposeConnections(): boolean
			local clean = pcall(disposeRemoved)
			if not pcall(disposeAdded) then
				clean = false
			end
			return clean
		end
		local listed, players = pcall(deps.players.getPlayers)
		if not listed or type(players) ~= "table" then
			return result(
				"character_admission_refused",
				if disposeConnections() then "players_invalid" else "connection_cleanup_failed"
			)
		end
		local stopObserving: (() -> ())? = nil
		if timing ~= nil and type(timing.observe) == "function" then
			local observing, stop = pcall(timing.observe, observeStore)
			stopObserving = if observing and type(stop) == "function" then stop else nil
		end
		for _, player in players do
			admit(player)
		end
		local runtime: Runtime<P & Subject> = {
			phase = "character_admission_started",
			dispose = function(): boolean
				if stopped then
					return false
				end
				stopped = true
				local ok = disposeConnections()
				if stopObserving ~= nil then
					ok = pcall(stopObserving) and ok
				end
				for player in entries do
					local cleaned, accepted = pcall(cleanup, player, nil)
					ok = cleaned and accepted == true and ok
				end
				return ok
			end,
			cleanup = cleanup,
			isAdmitted = function(player): boolean
				local entry = entries[player]
				return not stopped
					and entry ~= nil
					and entry.movement == true
					and (deps.warAdmission == nil or call(deps.warAdmission.authority))
			end,
			previewDeparture = function(
				player: P & Subject
			): { read userId: number, read characterId: string, read fence: number }?
				local entry = entries[player]
				if stopped or entry == nil or entry.movement ~= true then
					return nil
				end
				return table.freeze({
					userId = entry.userId,
					characterId = entry.characterId,
					fence = entry.leaseRevision,
				})
			end,
			prepareReturn = function(player: P & Subject): (Snapshot?, Snapshot?)
				local entry = entries[player]
				if stopped or entry == nil then
					return nil, nil
				end
				local snapshot = table.freeze({
					userId = entry.userId,
					characterId = entry.characterId,
					destinationId = entry.destinationId,
					routeId = "return:" .. entry.acquisitionId,
					fence = entry.leaseRevision,
				})
				local called, cleaned = pcall(cleanup, player, true)
				if not called or cleaned ~= true then
					return nil, snapshot
				end
				return snapshot, nil
			end,
			recover = function(player: P & Subject, value: unknown): boolean
				local snapshot = if plain(value) then Value.raw(value) else nil
				if
					stopped
					or snapshot == nil
					or snapshot.userId ~= subjectFor(player)
					or type(snapshot.characterId) ~= "string"
					or not text(snapshot.characterId)
					or type(snapshot.destinationId) ~= "string"
					or not text(snapshot.destinationId)
					or type(snapshot.routeId) ~= "string"
					or not text(snapshot.routeId)
					or type(snapshot.fence) ~= "number"
					or not whole(snapshot.fence, 1)
				then
					return false
				end
				local entry = entries[player]
				if entry ~= nil then
					if
						entry.userId ~= snapshot.userId
						or entry.characterId ~= snapshot.characterId
						or entry.destinationId ~= snapshot.destinationId
						or entry.leaseRevision ~= snapshot.fence
						or snapshot.routeId ~= "return:" .. entry.acquisitionId
					then
						return false
					end
					if not cleanup(player, true) then
						return false
					end
				end
				if stopped or deps.players.present(player) ~= true then
					return false
				end
				recoveries[player] = {
					userId = assert(subjectFor(player)),
					characterId = snapshot.characterId,
					destinationId = snapshot.destinationId,
					routeId = snapshot.routeId,
					fence = snapshot.fence,
				}
				admit(player)
				local restored = entries[player]
				return restored ~= nil
					and restored.profile == true
					and restored.session == true
					and restored.actor == true
					and restored.body == true
					and restored.movement == true
			end,
		}
		return table.freeze(runtime)
	end

	return beginAdmission()
end
export type API = { read start: typeof(start) }
local api: API = { start = start }
return table.freeze(api)
