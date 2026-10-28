--!strict
export type FlightKind = "save" | "close" | "renewal"
export type State = {
	leaseExpiresAt: number,
	dirty: boolean,
	dirtyDueAt: number?,
	generation: number,
	inFlightGeneration: number?,
	inFlightKind: FlightKind?,
	closed: boolean,
	shutdownDueAt: number?,
	failed: boolean,
	leaseLost: boolean,
	released: boolean,
}
export type Outcome = { ok: boolean, reason: string?, generation: number?, kind: FlightKind? }

export type Config = {
	leaseSeconds: number,
	renewBeforeSeconds: number,
	coalesceSeconds: number,
	shutdownSeconds: number,
	ordinaryReason: string,
	immediateReasons: { [string]: boolean },
}
local Session = {}
function Session.create(config: Config)
	local M = {}
	M.LEASE_SECONDS = config.leaseSeconds
	M.RENEW_BEFORE_SECONDS = config.renewBeforeSeconds
	M.COALESCE_SECONDS = config.coalesceSeconds
	M.SHUTDOWN_SECONDS = config.shutdownSeconds
	local immediate = config.immediateReasons

	local function initial(leaseExpiresAt: number): State
		return {
			leaseExpiresAt = leaseExpiresAt,
			dirty = false,
			dirtyDueAt = nil,
			generation = 0,
			inFlightGeneration = nil,
			inFlightKind = nil,
			closed = false,
			shutdownDueAt = nil,
			failed = false,
			leaseLost = false,
			released = false,
		}
	end

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	function M.open(now: number)
		return initial(now + M.LEASE_SECONDS)
	end

	function M.openAcquired(now: number, persistedExpiry: number): (State?, string?)
		if not finite(now) or not finite(persistedExpiry) then
			return nil, "time_invalid"
		end
		if persistedExpiry <= now then
			return nil, "lease_expired"
		end
		return initial(persistedExpiry), nil
	end
	function M.dirty(s: State, now: number, reason: string): Outcome
		if reason ~= config.ordinaryReason and not immediate[reason] then
			return { ok = false, reason = "reason_invalid" }
		end
		if s.leaseLost or s.released then
			return { ok = false, reason = "lease_unavailable" }
		end
		if now >= s.leaseExpiresAt then
			s.leaseLost = true
			return { ok = false, reason = "lease_lost" }
		end
		if s.closed then
			return { ok = false, reason = "closed" }
		end
		s.dirty = true
		s.generation += 1
		s.dirtyDueAt = if immediate[reason]
			then now
			else math.min(s.dirtyDueAt or now + M.COALESCE_SECONDS, now + M.COALESCE_SECONDS)
		return { ok = true }
	end
	function M.due(s: State, now: number): boolean
		return not s.inFlightGeneration
			and not s.leaseLost
			and not s.released
			and now < s.leaseExpiresAt
			and (s.dirty and s.dirtyDueAt ~= nil and now >= s.dirtyDueAt or now >= s.leaseExpiresAt - M.RENEW_BEFORE_SECONDS)
			and (not s.closed or now <= (s.shutdownDueAt or -1))
	end
	function M.begin(s: State, now: number): Outcome
		if s.leaseLost or s.released then
			return { ok = false, reason = "lease_unavailable" }
		end
		if now >= s.leaseExpiresAt then
			s.leaseLost = true
			return { ok = false, reason = "lease_lost" }
		end
		if not M.due(s, now) then
			return { ok = false, reason = "not_due" }
		end
		s.inFlightGeneration = s.generation
		s.inFlightKind = if s.closed then "close" else if s.dirty then "save" else "renewal"
		return { ok = true, generation = s.generation, kind = s.inFlightKind }
	end
	function M.finish(s: State, now: number, ok: boolean): Outcome
		local flight = s.inFlightGeneration
		local kind = s.inFlightKind
		if flight == nil or kind == nil then
			return { ok = false, reason = "no_flight" }
		end
		if now >= s.leaseExpiresAt then
			s.inFlightGeneration = nil
			s.inFlightKind = nil
			s.failed = true
			s.leaseLost = true
			return { ok = false, reason = "lease_lost" }
		end
		if s.shutdownDueAt ~= nil and now > s.shutdownDueAt then
			s.inFlightGeneration = nil
			s.inFlightKind = nil
			s.dirty = true
			s.dirtyDueAt = now
			s.failed = true
			return { ok = false, reason = "shutdown_expired" }
		end
		s.inFlightGeneration = nil
		s.inFlightKind = nil
		s.failed = not ok
		if ok then
			if kind ~= "renewal" and s.generation == flight then
				s.dirty = false
				s.dirtyDueAt = nil
			end
			if kind == "close" then
				s.released = true
				s.leaseExpiresAt = now
			else
				s.leaseExpiresAt = now + M.LEASE_SECONDS
			end
		else
			if now >= s.leaseExpiresAt then
				s.leaseLost = true
			elseif kind ~= "renewal" then
				s.dirty = true
				s.dirtyDueAt = now
			end
		end
		return { ok = ok, kind = kind :: FlightKind }
	end
	function M.close(s: State, now: number): Outcome
		if s.leaseLost or s.released then
			return { ok = false, reason = "lease_unavailable" }
		end
		if now >= s.leaseExpiresAt then
			s.leaseLost = true
			return { ok = false, reason = "lease_lost" }
		end
		if s.closed then
			return { ok = true }
		end
		s.closed = true
		s.shutdownDueAt = now + M.SHUTDOWN_SECONDS
		s.dirty = true
		s.generation += 1
		s.dirtyDueAt = now
		return { ok = true }
	end
	M.Types = (nil :: unknown) :: { State: State, Outcome: Outcome, FlightKind: FlightKind }

	return table.freeze(M)
end
return table.freeze(Session)
