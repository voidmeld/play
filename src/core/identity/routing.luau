--!strict

local Shape = require("../social/shape")

export type DestinationProjection = {
	read id: string,
	read zoneId: string,
	read realm: string,
	read isStarter: boolean,
	read requiresUnlock: boolean,
	read unlockId: string,
	read minLevel: number,
}

export type PlaceBinding = {
	read destinationId: string,
	read placeId: number,
}

export type Binding = {
	read channel: string,
	read universeId: number,
	read sourcePlaceId: number,
	read places: { PlaceBinding },
}

export type Budget = {
	read targetSeconds: number,
	read maxAttemptsPerSession: number,
}

export type RefusalRow = {
	read id: string,
	read recoverable: boolean,
	read retryable: boolean,
	read holdsAtDoor: boolean,
	read line: string,
}

export type Handoff = {
	read freshnessSeconds: number,
}

export type Policy = {
	read binding: Binding,
	read budget: Budget,
	read handoff: Handoff,
	read refusals: { [string]: RefusalRow },
	read destinations: { [string]: DestinationProjection },
	read placeByDestinationId: { [string]: number },
}

export type Session = {
	read sessionId: string,
	read acquisitionId: string,
	read leaseRevision: number,
}

export type Character = {
	read characterId: string,
	read realmId: string,
	read level: number,
}

export type Request = {
	read channel: string,
	read universeId: number,
	read sourcePlaceId: number,
	read requestId: string,
	read destinationId: string,
	read character: Character,
	read requestSession: Session,
	read heldSession: Session,
	read selectionAtUnix: number,
	read issuedAtUnix: number,
	read nowUnix: number,
	read attempt: number,
	read resolution: unknown,
}

export type Route = {
	read requestId: string,
	read destinationId: string,
	read zoneId: string,
	read realm: string,
	read characterId: string,
	read realmId: string,
	read universeId: number,
	read sourcePlaceId: number,
	read destinationPlaceId: number,
	read sessionId: string,
	read acquisitionId: string,
	read issuedAtUnix: number,
	read deadlineAtUnix: number,
	read carrierExpiresAtUnix: number,
	read attempt: number,
}

export type Refusal = {
	read requestId: string,
	read reason: string,
	read recoverable: boolean,
	read retryable: boolean,
	read holdsAtDoor: boolean,
	read attempt: number,
	read line: string,
}

export type Decision = {
	read outcome: string,
	read route: Route?,
	read refusal: Refusal?,
}

export type Arrival = {
	read channel: string,
	read universeId: number,
	read placeId: number,
	read sourceUniverseId: number,
	read sourcePlaceId: number,
	read destinationId: string,
	read characterId: string,
}

export type Config = {
	read realms: { [string]: string },
	read structuralId: (unknown) -> string?,
	read namespacedId: (unknown) -> string?,
	read idLimit: number,
	read refusalLineLimit: number,
	read unroutedStatusLimit: number,
	read unroutedReasonLimit: number,
	read unknownRequestId: string,
	read invalidBinding: RefusalRow,
}
export type API = {
	read projectPolicy: (unknown) -> Policy?,
	read refuse: (unknown, unknown, unknown, unknown) -> Decision,
	read decide: (unknown, unknown) -> Decision,
	read accept: (unknown, unknown) -> Decision,
	read boundPlaceIds: (unknown) -> { number },
	read REASON_IDS: { string },
	read REALMS: { [string]: string },
}

local function create(config: Config): API
	config = table.freeze(table.clone(config))
	for _, limit in { config.idLimit, config.refusalLineLimit, config.unroutedStatusLimit, config.unroutedReasonLimit } do
		assert(limit >= 1 and limit < math.huge and limit % 1 == 0, "invalid routing text limit")
	end
	assert(
		#config.unknownRequestId > 0 and #config.unknownRequestId <= config.idLimit,
		"invalid unknown request identity"
	)
	assert(
		config.invalidBinding.id == "binding_invalid"
			and #config.invalidBinding.line > 0
			and #config.invalidBinding.line <= config.refusalLineLimit,
		"invalid binding refusal"
	)

	local MAX_SAFE_INTEGER = 9007199254740991
	local UNKNOWN_REQUEST_ID = config.unknownRequestId

	local REASON_IDS: { string } = {
		"channel_unrouted",
		"binding_invalid",
		"intent_malformed",
		"attempts_exhausted",
		"intent_stale",
		"target_missed",
		"session_split",
		"destination_unknown",
		"destination_unbound",
		"destination_locked",
		"realm_mismatch",
		"below_min_level",
		"handoff_refused",
		"travel_paused",
		"released_recoverable",
	}

	local BINDING_INVALID = table.freeze(table.clone(config.invalidBinding))

	local BINDING_FIELDS: { [string]: boolean } = {
		channel = true,
		universeId = true,
		sourcePlaceId = true,
		places = true,
	}

	local PLACE_FIELDS: { [string]: boolean } = {
		destinationId = true,
		placeId = true,
	}

	local BUDGET_FIELDS: { [string]: boolean } = {
		targetSeconds = true,
		maxAttemptsPerSession = true,
	}

	local HANDOFF_FIELDS: { [string]: boolean } = {
		freshnessSeconds = true,
	}

	local REFUSAL_FIELDS: { [string]: boolean } = {
		id = true,
		recoverable = true,
		retryable = true,
		holdsAtDoor = true,
		line = true,
	}

	local UNROUTED_FIELDS: { [string]: boolean } = {
		channel = true,
		routedFromGate = true,
		reason = true,
	}

	local SESSION_FIELDS: { [string]: boolean } = {
		sessionId = true,
		acquisitionId = true,
		leaseRevision = true,
	}

	local CHARACTER_FIELDS: { [string]: boolean } = {
		characterId = true,
		realmId = true,
		level = true,
	}

	local REQUEST_FIELDS: { [string]: boolean } = {
		channel = true,
		universeId = true,
		sourcePlaceId = true,
		requestId = true,
		destinationId = true,
		character = true,
		requestSession = true,
		heldSession = true,
		selectionAtUnix = true,
		issuedAtUnix = true,
		nowUnix = true,
		attempt = true,
		resolution = true,
	}

	local ARRIVAL_FIELDS: { [string]: boolean } = {
		channel = true,
		universeId = true,
		placeId = true,
		sourceUniverseId = true,
		sourcePlaceId = true,
		destinationId = true,
		characterId = true,
	}

	local REALMS = table.freeze(table.clone(config.realms))

	local function plainRaw(value: unknown): Shape.Raw?
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return nil
		end
		return Shape.raw(value)
	end

	local function exactRaw(value: unknown, fields: { [string]: boolean }): Shape.Raw?
		if not Shape.exact(value, fields) then
			return nil
		end
		return Shape.raw(value)
	end

	local function rowsOf(source: unknown): { unknown }?
		local list = plainRaw(source)
		local count = Shape.denseLength(source)
		if list == nil or count == nil then
			return nil
		end
		local rows: { unknown } = {}
		for index = 1, count do
			rows[index] = list[index]
		end
		return rows
	end

	local function whole(value: unknown, minimum: number): number?
		if
			type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value == math.floor(value)
			and value >= minimum
			and value <= MAX_SAFE_INTEGER
		then
			return value
		end
		return nil
	end

	local function text(value: unknown, maximum: number): string?
		if type(value) == "string" and #value > 0 and #value <= maximum then
			return value
		end
		return nil
	end

	local structuralId = config.structuralId
	local namespacedId = config.namespacedId

	local function sessionOf(value: unknown): Session?
		local raw = exactRaw(value, SESSION_FIELDS)
		if raw == nil then
			return nil
		end
		local sessionId = text(raw.sessionId, config.idLimit)
		local acquisitionId = text(raw.acquisitionId, config.idLimit)
		local leaseRevision = whole(raw.leaseRevision, 1)
		if sessionId == nil or acquisitionId == nil or leaseRevision == nil then
			return nil
		end
		return { sessionId = sessionId, acquisitionId = acquisitionId, leaseRevision = leaseRevision }
	end

	local function sameSession(left: Session, right: Session): boolean
		return left.sessionId == right.sessionId
			and left.acquisitionId == right.acquisitionId
			and left.leaseRevision == right.leaseRevision
	end

	local function characterOf(value: unknown): Character?
		local raw = exactRaw(value, CHARACTER_FIELDS)
		if raw == nil then
			return nil
		end
		local characterId = text(raw.characterId, config.idLimit)
		local realmId = Shape.string(raw.realmId)
		local level = whole(raw.level, 1)
		if characterId == nil or realmId == nil or REALMS[realmId] == nil or level == nil then
			return nil
		end
		return { characterId = characterId, realmId = realmId, level = level }
	end

	local function refusalRowOf(value: unknown): RefusalRow?
		local raw = exactRaw(value, REFUSAL_FIELDS)
		if raw == nil then
			return nil
		end
		local id = structuralId(raw.id)
		local recoverable = Shape.boolean(raw.recoverable)
		local retryable = Shape.boolean(raw.retryable)
		local holdsAtDoor = Shape.boolean(raw.holdsAtDoor)
		local line = text(raw.line, config.refusalLineLimit)
		if id == nil or recoverable == nil or retryable == nil or holdsAtDoor == nil or line == nil then
			return nil
		end
		return table.freeze({
			id = id,
			recoverable = recoverable,
			retryable = retryable,
			holdsAtDoor = holdsAtDoor,
			line = line,
		})
	end

	local function projectRefusals(source: unknown): { [string]: RefusalRow }?
		local list = rowsOf(source)
		if list == nil or #list == 0 then
			return nil
		end
		local rows: { [string]: RefusalRow } = {}
		for _, entry in list do
			local row = refusalRowOf(entry)
			if row == nil or rows[row.id] ~= nil then
				return nil
			end
			rows[row.id] = row
		end
		for _, reason in REASON_IDS do
			if rows[reason] == nil then
				return nil
			end
		end
		return table.freeze(rows)
	end

	local function destinationOf(value: unknown): DestinationProjection?
		local raw = plainRaw(value)
		if raw == nil then
			return nil
		end
		local id = namespacedId(raw.id)
		local zoneId = structuralId(raw.zoneId)
		local realm = Shape.string(raw.realm)
		local isStarter = Shape.boolean(raw.isStarter)
		local requiresUnlock = Shape.boolean(raw.requiresUnlock)
		local unlockId = Shape.string(raw.unlockId)
		local minLevel = whole(raw.minLevel, 1)
		if
			id == nil
			or zoneId == nil
			or realm == nil
			or isStarter == nil
			or requiresUnlock == nil
			or unlockId == nil
			or minLevel == nil
		then
			return nil
		end
		return table.freeze({
			id = id,
			zoneId = zoneId,
			realm = realm,
			isStarter = isStarter,
			requiresUnlock = requiresUnlock,
			unlockId = unlockId,
			minLevel = minLevel,
		})
	end

	local function projectDestinations(source: unknown): { [string]: DestinationProjection }?
		local list = rowsOf(source)
		if list == nil or #list == 0 then
			return nil
		end
		local rows: { [string]: DestinationProjection } = {}
		for _, entry in list do
			local row = destinationOf(entry)
			if row == nil or rows[row.id] ~= nil then
				return nil
			end
			rows[row.id] = row
		end
		return table.freeze(rows)
	end

	local function projectUnrouted(source: unknown): { [string]: boolean }?
		local list = rowsOf(source)
		if list == nil then
			return nil
		end
		local channels: { [string]: boolean } = {}
		for _, entry in list do
			local raw = exactRaw(entry, UNROUTED_FIELDS)
			if raw == nil then
				return nil
			end
			local channel = structuralId(raw.channel)
			if
				channel == nil
				or text(raw.routedFromGate, config.unroutedStatusLimit) == nil
				or text(raw.reason, config.unroutedReasonLimit) == nil
				or channels[channel]
			then
				return nil
			end
			channels[channel] = true
		end
		return table.freeze(channels)
	end

	local function budgetOf(value: unknown): Budget?
		local raw = exactRaw(value, BUDGET_FIELDS)
		if raw == nil then
			return nil
		end
		local targetSeconds = whole(raw.targetSeconds, 1)
		local maxAttemptsPerSession = whole(raw.maxAttemptsPerSession, 1)
		if targetSeconds == nil or maxAttemptsPerSession == nil then
			return nil
		end
		return table.freeze({ targetSeconds = targetSeconds, maxAttemptsPerSession = maxAttemptsPerSession })
	end

	local function handoffOf(value: unknown, minimum: number): Handoff?
		local raw = exactRaw(value, HANDOFF_FIELDS)
		local freshnessSeconds = if raw ~= nil then whole(raw.freshnessSeconds, minimum) else nil
		if freshnessSeconds == nil then
			return nil
		end
		return table.freeze({ freshnessSeconds = freshnessSeconds })
	end

	local function placeOf(value: unknown): PlaceBinding?
		local raw = exactRaw(value, PLACE_FIELDS)
		if raw == nil then
			return nil
		end
		local destinationId = namespacedId(raw.destinationId)
		local placeId = whole(raw.placeId, 1)
		if destinationId == nil or placeId == nil then
			return nil
		end
		return table.freeze({ destinationId = destinationId, placeId = placeId })
	end

	local function projectBinding(
		source: unknown,
		destinations: { [string]: DestinationProjection },
		unrouted: { [string]: boolean }
	): Binding?
		local raw = exactRaw(source, BINDING_FIELDS)
		if raw == nil then
			return nil
		end
		local channel = structuralId(raw.channel)
		local universeId = whole(raw.universeId, 1)
		local sourcePlaceId = whole(raw.sourcePlaceId, 1)
		if channel == nil or unrouted[channel] or universeId == nil or sourcePlaceId == nil then
			return nil
		end
		local list = rowsOf(raw.places)
		if list == nil or #list == 0 then
			return nil
		end
		local places: { PlaceBinding } = {}
		local seenDestinations: { [string]: boolean } = {}
		local seenPlaces: { [number]: boolean } = {}
		for _, entry in list do
			local place = placeOf(entry)
			if
				place == nil
				or destinations[place.destinationId] == nil
				or seenDestinations[place.destinationId]
				or seenPlaces[place.placeId]
				or place.placeId == sourcePlaceId
			then
				return nil
			end
			seenDestinations[place.destinationId] = true
			seenPlaces[place.placeId] = true
			places[#places + 1] = place
		end
		return table.freeze({
			channel = channel,
			universeId = universeId,
			sourcePlaceId = sourcePlaceId,
			places = table.freeze(places),
		})
	end

	local Routing = {}

	function Routing.projectPolicy(source: unknown): Policy?
		local raw = plainRaw(source)
		if raw == nil then
			return nil
		end
		local destinations = projectDestinations(raw.destinations)
		local unrouted = projectUnrouted(raw.unroutedChannels)
		local refusals = projectRefusals(raw.refusals)
		local budget = budgetOf(raw.budget)
		if destinations == nil or unrouted == nil or refusals == nil or budget == nil then
			return nil
		end
		local handoff = handoffOf(raw.handoff, budget.targetSeconds)
		if handoff == nil then
			return nil
		end
		local binding = projectBinding(raw.binding, destinations, unrouted)
		if binding == nil then
			return nil
		end
		local placeByDestinationId: { [string]: number } = {}
		for _, place in binding.places do
			placeByDestinationId[place.destinationId] = place.placeId
		end
		return table.freeze({
			binding = binding,
			budget = budget,
			handoff = handoff,
			refusals = refusals,
			destinations = destinations,
			placeByDestinationId = table.freeze(placeByDestinationId),
		})
	end

	local function mapOf<V>(value: unknown, valueOf: (unknown) -> V?): { [string]: V }?
		return Shape.map(value, Shape.string, valueOf)
	end

	local function policyOf(value: unknown): Policy?
		local raw = plainRaw(value)
		if raw == nil then
			return nil
		end
		local refusals = mapOf(raw.refusals, refusalRowOf)
		local destinations = mapOf(raw.destinations, destinationOf)
		local placeByDestinationId = mapOf(raw.placeByDestinationId, Shape.number)
		local binding = plainRaw(raw.binding)
		local budget = budgetOf(raw.budget)
		local handoff = handoffOf(raw.handoff, 1)
		if
			refusals == nil
			or destinations == nil
			or placeByDestinationId == nil
			or binding == nil
			or budget == nil
			or handoff == nil
		then
			return nil
		end
		local channel = Shape.string(binding.channel)
		local universeId = Shape.number(binding.universeId)
		local sourcePlaceId = Shape.number(binding.sourcePlaceId)
		local places = Shape.array(binding.places, placeOf)
		if channel == nil or universeId == nil or sourcePlaceId == nil or places == nil then
			return nil
		end
		return {
			binding = { channel = channel, universeId = universeId, sourcePlaceId = sourcePlaceId, places = places },
			budget = budget,
			handoff = handoff,
			refusals = refusals,
			destinations = destinations,
			placeByDestinationId = placeByDestinationId,
		}
	end

	local function refusalFor(policy: Policy?, requestId: unknown, reason: string, attempt: unknown): Refusal
		local row = if policy ~= nil then policy.refusals[reason] else nil
		local resolved = if row ~= nil then row else BINDING_INVALID
		return table.freeze({
			requestId = text(requestId, config.idLimit) or UNKNOWN_REQUEST_ID,
			reason = resolved.id,
			recoverable = resolved.recoverable,
			retryable = resolved.retryable,
			holdsAtDoor = resolved.holdsAtDoor,
			attempt = whole(attempt, 1) or 1,
			line = resolved.line,
		})
	end

	local function refused(policy: Policy?, requestId: unknown, reason: string, attempt: unknown): Decision
		return table.freeze({
			outcome = "refused",
			route = nil,
			refusal = refusalFor(policy, requestId, reason, attempt),
		})
	end

	function Routing.refuse(policy: unknown, requestId: unknown, reason: unknown, attempt: unknown): Decision
		local resolved = if policy ~= nil then policyOf(policy) else nil
		if type(reason) ~= "string" or (policy ~= nil and resolved == nil) then
			return refused(nil, requestId, "binding_invalid", attempt)
		end
		local known = false
		for _, id in REASON_IDS do
			if id == reason then
				known = true
			end
		end
		if not known then
			return refused(nil, requestId, "binding_invalid", attempt)
		end
		return refused(resolved, requestId, reason, attempt)
	end

	local function classifyUnroutable(policy: Policy, request: Request): string
		local destination = policy.destinations[request.destinationId]
		if destination == nil then
			return "destination_unknown"
		end
		if destination.isStarter and destination.realm ~= REALMS[request.character.realmId] then
			return "realm_mismatch"
		end
		if request.character.level < destination.minLevel then
			return "below_min_level"
		end
		if destination.requiresUnlock then
			return "destination_locked"
		end
		return "destination_unknown"
	end

	local function requestOf(value: unknown): Request?
		local raw = plainRaw(value)
		if raw == nil then
			return nil
		end
		for key in raw do
			if type(key) ~= "string" or REQUEST_FIELDS[key] ~= true then
				return nil
			end
		end
		for key in REQUEST_FIELDS do
			if key ~= "resolution" and raw[key] == nil then
				return nil
			end
		end
		local channel = structuralId(raw.channel)
		local universeId = whole(raw.universeId, 1)
		local sourcePlaceId = whole(raw.sourcePlaceId, 1)
		local requestId = text(raw.requestId, config.idLimit)
		local destinationId = namespacedId(raw.destinationId)
		local character = characterOf(raw.character)
		local requestSession = sessionOf(raw.requestSession)
		local heldSession = sessionOf(raw.heldSession)
		local selectionAtUnix = whole(raw.selectionAtUnix, 0)
		local issuedAtUnix = whole(raw.issuedAtUnix, 0)
		local nowUnix = whole(raw.nowUnix, 0)
		local attempt = whole(raw.attempt, 1)
		if
			channel == nil
			or universeId == nil
			or sourcePlaceId == nil
			or requestId == nil
			or destinationId == nil
			or character == nil
			or requestSession == nil
			or heldSession == nil
			or selectionAtUnix == nil
			or issuedAtUnix == nil
			or nowUnix == nil
			or attempt == nil
		then
			return nil
		end
		return {
			channel = channel,
			universeId = universeId,
			sourcePlaceId = sourcePlaceId,
			requestId = requestId,
			destinationId = destinationId,
			character = character,
			requestSession = requestSession,
			heldSession = heldSession,
			selectionAtUnix = selectionAtUnix,
			issuedAtUnix = issuedAtUnix,
			nowUnix = nowUnix,
			attempt = attempt,
			resolution = raw.resolution,
		}
	end

	local function requestIdOf(request: unknown): unknown
		local raw = plainRaw(request)
		return if raw ~= nil then raw.requestId else nil
	end

	function Routing.decide(policy: unknown, request: unknown): Decision
		local resolved = policyOf(policy)
		if resolved == nil then
			return refused(nil, requestIdOf(request), "binding_invalid", nil)
		end
		local requestFields = requestOf(request)
		if requestFields == nil then
			return refused(resolved, requestIdOf(request), "intent_malformed", nil)
		end
		local binding = resolved.binding
		if
			requestFields.channel ~= binding.channel
			or requestFields.universeId ~= binding.universeId
			or requestFields.sourcePlaceId ~= binding.sourcePlaceId
		then
			return refused(resolved, requestFields.requestId, "channel_unrouted", requestFields.attempt)
		end
		if requestFields.attempt > resolved.budget.maxAttemptsPerSession then
			return refused(resolved, requestFields.requestId, "attempts_exhausted", requestFields.attempt)
		end
		if
			requestFields.nowUnix < requestFields.issuedAtUnix
			or requestFields.issuedAtUnix < requestFields.selectionAtUnix
		then
			return refused(resolved, requestFields.requestId, "intent_stale", requestFields.attempt)
		end
		local deadlineAtUnix = requestFields.issuedAtUnix + resolved.budget.targetSeconds
		if requestFields.nowUnix > deadlineAtUnix then
			return refused(resolved, requestFields.requestId, "target_missed", requestFields.attempt)
		end
		if not sameSession(requestFields.requestSession, requestFields.heldSession) then
			return refused(resolved, requestFields.requestId, "session_split", requestFields.attempt)
		end
		local resolution = requestFields.resolution
		if resolution == nil then
			return refused(
				resolved,
				requestFields.requestId,
				classifyUnroutable(resolved, requestFields),
				requestFields.attempt
			)
		end
		local destination = resolved.destinations[requestFields.destinationId]
		local resolutionFields = plainRaw(resolution)
		local resolvedDestination = if resolutionFields ~= nil then plainRaw(resolutionFields.destination) else nil
		if
			resolutionFields == nil
			or resolvedDestination == nil
			or destination == nil
			or resolvedDestination.id ~= requestFields.destinationId
			or resolvedDestination.zoneId ~= destination.zoneId
			or resolvedDestination.realm ~= destination.realm
			or resolutionFields.characterId ~= requestFields.character.characterId
			or resolutionFields.realmId ~= requestFields.character.realmId
		then
			return refused(resolved, requestFields.requestId, "intent_malformed", requestFields.attempt)
		end
		local destinationPlaceId = resolved.placeByDestinationId[requestFields.destinationId]
		if destinationPlaceId == nil then
			return refused(resolved, requestFields.requestId, "destination_unbound", requestFields.attempt)
		end
		return table.freeze({
			outcome = "routed",
			refusal = nil,
			route = table.freeze({
				requestId = requestFields.requestId,
				destinationId = requestFields.destinationId,
				zoneId = destination.zoneId,
				realm = destination.realm,
				characterId = requestFields.character.characterId,
				realmId = requestFields.character.realmId,
				universeId = binding.universeId,
				sourcePlaceId = binding.sourcePlaceId,
				destinationPlaceId = destinationPlaceId,
				sessionId = requestFields.heldSession.sessionId,
				acquisitionId = requestFields.heldSession.acquisitionId,
				issuedAtUnix = requestFields.issuedAtUnix,
				deadlineAtUnix = deadlineAtUnix,
				carrierExpiresAtUnix = requestFields.issuedAtUnix + resolved.handoff.freshnessSeconds,
				attempt = requestFields.attempt,
			}),
		})
	end

	local function arrivalOf(value: unknown): Arrival?
		local raw = exactRaw(value, ARRIVAL_FIELDS)
		if raw == nil then
			return nil
		end
		local channel = structuralId(raw.channel)
		local universeId = whole(raw.universeId, 1)
		local placeId = whole(raw.placeId, 1)
		local sourceUniverseId = whole(raw.sourceUniverseId, 1)
		local sourcePlaceId = whole(raw.sourcePlaceId, 1)
		local destinationId = namespacedId(raw.destinationId)
		local characterId = text(raw.characterId, config.idLimit)
		if
			channel == nil
			or universeId == nil
			or placeId == nil
			or sourceUniverseId == nil
			or sourcePlaceId == nil
			or destinationId == nil
			or characterId == nil
		then
			return nil
		end
		return {
			channel = channel,
			universeId = universeId,
			placeId = placeId,
			sourceUniverseId = sourceUniverseId,
			sourcePlaceId = sourcePlaceId,
			destinationId = destinationId,
			characterId = characterId,
		}
	end

	function Routing.accept(policy: unknown, arrival: unknown): Decision
		local resolved = policyOf(policy)
		if resolved == nil then
			return refused(nil, nil, "binding_invalid", nil)
		end
		local arrivalFields = arrivalOf(arrival)
		if arrivalFields == nil then
			return refused(resolved, nil, "intent_malformed", nil)
		end
		local binding = resolved.binding
		if
			arrivalFields.channel ~= binding.channel
			or arrivalFields.universeId ~= binding.universeId
			or arrivalFields.sourceUniverseId ~= binding.universeId
			or arrivalFields.sourcePlaceId ~= binding.sourcePlaceId
		then
			return refused(resolved, nil, "channel_unrouted", nil)
		end
		local destinationPlaceId = resolved.placeByDestinationId[arrivalFields.destinationId]
		if destinationPlaceId == nil then
			return refused(
				resolved,
				nil,
				if resolved.destinations[arrivalFields.destinationId] == nil
					then "destination_unknown"
					else "destination_unbound",
				nil
			)
		end
		if destinationPlaceId ~= arrivalFields.placeId then
			return refused(resolved, nil, "destination_unknown", nil)
		end
		local destination = resolved.destinations[arrivalFields.destinationId]
		return table.freeze({
			outcome = "accepted",
			refusal = nil,
			route = table.freeze({
				requestId = UNKNOWN_REQUEST_ID,
				destinationId = arrivalFields.destinationId,
				zoneId = destination.zoneId,
				realm = destination.realm,
				characterId = arrivalFields.characterId,
				realmId = "",
				universeId = binding.universeId,
				sourcePlaceId = binding.sourcePlaceId,
				destinationPlaceId = destinationPlaceId,
				sessionId = "",
				acquisitionId = "",
				issuedAtUnix = 0,
				deadlineAtUnix = 0,
				carrierExpiresAtUnix = 0,
				attempt = 1,
			}),
		})
	end

	function Routing.boundPlaceIds(policy: unknown): { number }
		local resolved = policyOf(policy)
		local ids: { number } = {}
		if resolved == nil then
			return table.freeze(ids)
		end
		for _, place in resolved.binding.places do
			ids[#ids + 1] = place.placeId
		end
		return table.freeze(ids)
	end

	Routing.REASON_IDS = table.freeze(REASON_IDS)
	Routing.REALMS = REALMS

	return table.freeze(Routing)
end

return table.freeze({ create = create })
