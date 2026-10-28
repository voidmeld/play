--!strict
export type Outcome = {
	ok: boolean,
	reason: string?,
	deferred: boolean?,
	idle: boolean?,
	characterId: string?,
	standing: number?,
	retryable: boolean?,
}
export type Config = {
	clock: () -> number,
	intervalSec: number,
	maxPoints: number,
	capacity: number,
	authority: () -> boolean,
	writeReady: () -> boolean,
	read: () -> { [string]: number },
	validId: (string) -> boolean,
}
local Credit = {}
function Credit.create(config: Config)
	local pending: { [string]: number } = {}
	local floors: { [string]: number } = {}
	local retiring: { [string]: boolean } = {}
	local acknowledgments: { [string]: number } = {}
	local lastFlush = config.clock()
	assert(
		type(lastFlush) == "number" and lastFlush == lastFlush and math.abs(lastFlush) < math.huge,
		"Invalid standing clock"
	)
	local stopped, busy = false, false
	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value >= 0 and value <= config.maxPoints
	end
	local function authorized(): boolean
		return not stopped and config.authority()
	end
	local function capacity(id: string): boolean
		local retained: { [string]: boolean } = {}
		for key in config.read() do
			retained[key] = true
		end
		for key in pending do
			retained[key] = true
		end
		for key in floors do
			retained[key] = true
		end
		if retained[id] then
			return true
		end
		local count = 0
		for _ in retained do
			count += 1
		end
		return count < config.capacity
	end
	local delivery = { authority = authorized }
	delivery.writeReady = function(): boolean
		return not busy and config.writeReady()
	end
	delivery.flush = function(
		force: boolean,
		hasPatch: boolean,
		commit: ({ [string]: number }, number) -> Outcome
	): Outcome
		if not authorized() then
			return { ok = false, reason = "war_authority_unavailable" }
		end
		if not delivery.writeReady() then
			return { ok = false, reason = "write_in_flight" }
		end
		local now = config.clock()
		if type(now) ~= "number" or now ~= now or math.abs(now) == math.huge or now < lastFlush then
			stopped = true
			return { ok = false, reason = "war_clock_invalid" }
		end
		if not force and now - lastFlush < config.intervalSec then
			return { ok = true, deferred = true }
		end
		if next(pending) == nil and next(acknowledgments) == nil and not hasPatch then
			lastFlush = now
			return { ok = true }
		end
		local totals = table.clone(config.read())
		local captured = table.clone(pending)
		for id, delta in captured do
			local total = math.max(totals[id] or 0, floors[id] or 0) + delta
			if not finite(total) then
				return { ok = false, reason = "realm_standing_limit" }
			end
			totals[id] = total
		end
		local capturedAcknowledgments = table.clone(acknowledgments)
		for id, paid in capturedAcknowledgments do
			if totals[id] == paid then
				totals[id] = nil
			end
		end
		busy = true
		local ran, result = pcall(commit, totals, now)
		busy = false
		if not ran or type(result) ~= "table" or result.ok ~= true then
			if
				ran
				and type(result) == "table"
				and (result.reason == "write_in_flight" or result.reason == "budget_deferred")
			then
				return result
			end
			stopped = true
			return {
				ok = false,
				reason = if ran and type(result) == "table" then result.reason else "war_checkpoint_failed",
			}
		end
		for id, delta in captured do
			local remaining = (pending[id] or 0) - delta
			pending[id] = if remaining > 0 then remaining else nil
		end
		for id, paid in capturedAcknowledgments do
			if acknowledgments[id] == paid then
				acknowledgments[id] = nil
			end
		end
		for id in retiring do
			if pending[id] == nil then
				floors[id], retiring[id] = nil, nil
			end
		end
		lastFlush = now
		return result
	end
	delivery.seed = function(id: string, paid: number): Outcome
		if not authorized() or type(id) ~= "string" or not config.validId(id) then
			return { ok = false, reason = "war_authority_unavailable" }
		end
		if not finite(paid) then
			return { ok = false, reason = "realm_standing_invalid" }
		end
		if not capacity(id) then
			return { ok = false, reason = "war_standing_capacity" }
		end
		retiring[id] = nil
		floors[id] = math.max(floors[id] or 0, paid)
		return { ok = true }
	end
	delivery.retire = function(id: string): boolean
		if pending[id] ~= nil then
			retiring[id] = true
			return false
		end
		retiring[id], floors[id] = nil, nil
		return true
	end
	delivery.accrue = function(id: string, delta: number): boolean
		if not authorized() or type(id) ~= "string" or not config.validId(id) or not finite(delta) then
			return false
		end
		if delta > 0 and not capacity(id) then
			return false
		end
		local value = (pending[id] or 0) + delta
		if not finite(value) or not finite(math.max(config.read()[id] or 0, floors[id] or 0) + value) then
			return false
		end
		if delta > 0 then
			pending[id] = value
		end
		return true
	end
	delivery.pending = function(): { [string]: number }
		return table.clone(pending)
	end
	delivery.total = function(id: string): number
		return math.max(config.read()[id] or 0, floors[id] or 0)
	end
	local cursor = ""
	delivery.recoverNext = function(
		write: (string, number, () -> boolean) -> Outcome,
		stillCurrent: () -> boolean
	): Outcome
		local function guarded(): boolean
			return authorized() and stillCurrent()
		end
		if not guarded() then
			return { ok = false, reason = "war_authority_unavailable" }
		end
		local totals = config.read()
		local ids: { string } = {}
		for id, total in totals do
			if floors[id] == nil and (acknowledgments[id] or -1) < total then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		local id = ids[1]
		for _, key in ids do
			if key > cursor then
				id = key
				break
			end
		end
		if id == nil then
			return { ok = true, idle = true }
		end
		cursor = id
		local captured = totals[id]
		local outcome = write(id, captured, guarded)
		if not guarded() then
			return { ok = false, characterId = id, reason = "war_authority_unavailable" }
		end
		if not outcome.ok then
			return {
				ok = false,
				characterId = id,
				reason = outcome.reason,
				retryable = outcome.reason == "profile_locked",
			}
		end
		if outcome.characterId ~= id or outcome.standing ~= captured then
			return { ok = false, characterId = id, reason = "profile_recovery_readback_conflict" }
		end
		acknowledgments[id] = math.max(acknowledgments[id] or 0, captured)
		return { ok = true, characterId = id }
	end
	delivery.settle = function(
		id: string,
		write: (number, () -> boolean) -> Outcome,
		stillCurrent: () -> boolean
	): Outcome
		local function guarded(): boolean
			return authorized() and stillCurrent()
		end
		if not guarded() then
			return { ok = false, reason = "war_authority_unavailable" }
		end
		local captured = config.read()[id]
		if captured == nil then
			return { ok = true }
		end
		local total = delivery.total(id)
		if (acknowledgments[id] or -1) >= captured and (floors[id] or 0) >= total then
			return { ok = true, deferred = true }
		end
		local outcome = write(total, guarded)
		if not outcome.ok then
			return outcome
		end
		floors[id] = math.max(floors[id] or 0, total)
		acknowledgments[id] = math.max(acknowledgments[id] or 0, captured)
		return { ok = true, deferred = true }
	end
	return table.freeze(delivery)
end
return table.freeze(Credit)
