--!strict
local Value = require("../internal/value")
export type Outcome = { ok: boolean, value: unknown, reason: string? }
export type DrainOutcome = { ok: boolean, flushed: number, remaining: number, reason: string? }
export type Operation = "Get" | "Set" | "Update"
export type Observation = {
	store: string,
	operation: Operation,
	durationMs: number,
	budgetWaitMs: number,
	budgetSleeps: number,
	retries: number,
}
export type Observer = (Observation) -> ()
export type BudgetKind = "get" | "set" | "update"
type RawValue = { [unknown]: unknown }
export type QueuedWrite = { id: string, storeName: string, key: string, nextAttemptAt: number }
export type Circuit = {
	success: () -> (),
	failure: (number, unknown) -> (),
	canAttempt: (number) -> boolean,
	begin: (number) -> (),
	enqueue: (
		{ storeName: string, key: string, kind: "set" | "update", payload: unknown },
		number
	) -> (boolean, string?, QueuedWrite?),
	markFailure: (string, number, unknown) -> (),
	markSuccess: (string) -> (),
	hasQueued: (string, string) -> boolean,
	isReadOnly: () -> boolean,
	list: () -> { QueuedWrite },
}
export type RawStore = {
	GetAsync: (RawStore, string, unknown?) -> unknown,
	SetAsync: (RawStore, string, unknown) -> (),
	UpdateAsync: (RawStore, string, (unknown) -> unknown) -> unknown,
}
export type RealDependencies = {
	raw: RawStore,
	sleep: (number) -> (),
	jitter: () -> number,
	now: () -> number,
	clock: () -> number,
	requestBudget: ((BudgetKind) -> number)?,
	waitForBudget: ((BudgetKind) -> (boolean, number?))?,
	observer: (() -> Observer?)?,
	uncachedOptions: () -> unknown,
	validUncachedOptions: (unknown) -> boolean,
}
export type MemoryStore = {
	name: string,
	get: (string) -> unknown,
	set: (string, unknown) -> (),
	update: (string, (unknown) -> unknown) -> unknown,
}
export type TestOptions = { rerun: boolean?, fault: (() -> string?)? }
export type Store = {
	name: string,
	backend: "real" | "memory",
	get: (string) -> unknown,
	getOutcome: (string) -> Outcome,
	getUncachedOutcome: (string) -> Outcome,
	set: (string, unknown) -> Outcome,
	update: (string, (unknown) -> unknown) -> unknown,
	updateOutcome: (string, (unknown) -> unknown) -> Outcome,
	flushQueuedWrites: () -> number,
	hasPendingWrite: (string) -> boolean,
	isReadOnly: () -> boolean,
	writeBudget: (() -> number)?,
}
export type Config = {
	clock: () -> number,
	maxKeyBytes: number,
	maxAttempts: number,
	backoff: (number, number) -> number,
	retry: <T>(() -> (boolean, T), (number) -> (), () -> number) -> (boolean, T),
	warning: (string) -> (),
}
local StoreHost = {}
type QueuedRun = {
	execute: () -> (boolean, unknown),
	retainOnFailure: boolean,
	finish: ((boolean, unknown) -> ())?,
}
local queuedRunsByState: { [unknown]: { [string]: QueuedRun } } = setmetatable({}, { __mode = "k" })
local inFlightByState: { [unknown]: { [string]: boolean } } = setmetatable({}, { __mode = "k" })

local function queuedRunsFor(state: unknown): { [string]: QueuedRun }
	local runs = queuedRunsByState[state]
	if runs == nil then
		runs = {}
		queuedRunsByState[state] = runs
	end
	return runs
end

local function inFlightFor(state: unknown): { [string]: boolean }
	local inFlight = inFlightByState[state]
	if inFlight == nil then
		inFlight = {}
		inFlightByState[state] = inFlight
	end
	return inFlight
end

function StoreHost.create(config: Config)
	local MAX_ATTEMPTS = config.maxAttempts
	local computeBackoffDelay = config.backoff
	local retry = config.retry
	local emitWarning = config.warning
	local function drainQueuedWrites(
		flush: () -> number,
		remaining: () -> number,
		deadline: number,
		clock: () -> number,
		sleep: (number) -> ()
	): DrainOutcome
		if deadline ~= deadline or deadline <= -math.huge or deadline >= math.huge then
			return { ok = false, flushed = 0, remaining = remaining(), reason = "deadline_invalid" }
		end
		local flushed = 0
		local passes = 0
		while true do
			local pending = remaining()
			if pending == 0 then
				return { ok = true, flushed = flushed, remaining = 0, reason = nil }
			end
			local current = clock()
			if current >= deadline then
				return { ok = false, flushed = flushed, remaining = pending, reason = "deadline_exceeded" }
			end
			passes += 1
			if passes > 1000 then
				return { ok = false, flushed = flushed, remaining = pending, reason = "drain_stalled" }
			end
			local ok, count = pcall(flush)
			if not ok then
				return { ok = false, flushed = flushed, remaining = remaining(), reason = "flush_failed" }
			end
			flushed += count
			if remaining() > 0 then
				sleep(math.min(0.05, math.max(0, deadline - current)))
			end
		end
	end

	local function copyDataStoreValue(
		value: unknown,
		copies: RawValue?,
		active: { [unknown]: boolean }?
	): (boolean, unknown)
		local valueType = type(value)
		if value == nil or valueType == "boolean" or valueType == "string" then
			return true, value
		end
		if type(value) == "number" then
			return value == value and value > -math.huge and value < math.huge, value
		end
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return false, nil
		end
		local known: RawValue = copies or {}
		local visiting: { [unknown]: boolean } = active or {}
		if visiting[value] then
			return false, nil
		end
		if known[value] ~= nil then
			return true, known[value]
		end
		local result: RawValue = {}
		known[value] = result
		visiting[value] = true
		for key, child in value do
			local keyType = type(key)
			if
				(keyType ~= "string" and keyType ~= "number")
				or (type(key) == "number" and (key ~= key or key <= -math.huge or key >= math.huge))
			then
				return false, nil
			end
			local ok, childCopy = copyDataStoreValue(child, known, visiting)
			if not ok then
				return false, nil
			end
			result[key] = childCopy
		end
		visiting[value] = nil
		return true, result
	end

	local function success(value: unknown): Outcome
		return { ok = true, value = value, reason = nil }
	end

	local function failure(reason: string): Outcome
		return { ok = false, value = nil, reason = reason }
	end

	local function noObserver(): Observer?
		return nil
	end

	local function elapsedMs(from: number, to: number): number
		return math.floor((to - from) * 1000 + 0.5)
	end

	local function notify(observer: Observer, observation: Observation): boolean
		local delivered = pcall(observer, Value.freezeDeep(observation))
		return delivered
	end

	local function makeMemoryStore(store: MemoryStore, options: TestOptions?, observerOf: () -> Observer?): Store
		local function boundedKey(key: string): string
			if #key > config.maxKeyBytes then
				error(("data store key exceeds %d bytes"):format(config.maxKeyBytes), 2)
			end
			return key
		end
		local rerun = options ~= nil and options.rerun == true
		local fault = if options ~= nil then options.fault else nil

		local function injected(): string?
			return if fault ~= nil then fault() else nil
		end

		local function observed<T>(operation: Operation, run: () -> T): T
			local observer = observerOf()
			if observer == nil then
				return run()
			end
			local startedAt = config.clock()
			local value = run()
			notify(observer, {
				store = store.name,
				operation = operation,
				durationMs = elapsedMs(startedAt, config.clock()),
				budgetWaitMs = 0,
				budgetSleeps = 0,
				retries = 0,
			})
			return value
		end

		local function updateOutcome(key: string, transform: (unknown) -> unknown): Outcome
			boundedKey(key)
			local currentOk, currentValue = copyDataStoreValue(store.get(key))
			if not currentOk then
				return failure("value_invalid")
			end
			local transformOk, nextValue = pcall(transform, currentValue)
			if not transformOk then
				return failure("retry_exhausted")
			end
			if rerun and nextValue ~= nil then
				local firstOk, firstValue = copyDataStoreValue(nextValue)
				if not firstOk then
					return failure("value_invalid")
				end
				transformOk, nextValue = pcall(transform, firstValue)
				if not transformOk then
					return failure("retry_exhausted")
				end
			end
			local storedValue: unknown = nil
			if nextValue ~= nil then
				local nextOk, copy = copyDataStoreValue(nextValue)
				if not nextOk then
					return failure("value_invalid")
				end
				store.set(key, copy)
				storedValue = copy
			end
			local reason = injected()
			if reason ~= nil then
				return failure(reason)
			end
			if storedValue == nil then
				return failure("callback_cancelled")
			end
			local readbackOk, readback = copyDataStoreValue(storedValue)
			return if readbackOk then success(readback) else failure("value_invalid")
		end

		local function getOutcome(key: string): Outcome
			boundedKey(key)
			return observed("Get", function(): Outcome
				local reason = injected()
				if reason ~= nil then
					return failure(reason)
				end
				local ok, value = copyDataStoreValue(store.get(key))
				return if ok then success(value) else failure("value_invalid")
			end)
		end
		return {
			name = store.name,
			backend = "memory",
			get = function(key: string): unknown
				boundedKey(key)
				return observed("Get", function(): unknown
					return store.get(key)
				end)
			end,
			getOutcome = getOutcome,
			getUncachedOutcome = getOutcome,
			set = function(key: string, value): Outcome
				boundedKey(key)
				return observed("Set", function(): Outcome
					local reason = injected()
					if reason ~= nil then
						return failure(reason)
					end
					store.set(key, value)
					return success(nil)
				end)
			end,
			update = function(key: string, transform: (unknown) -> unknown): unknown
				boundedKey(key)
				return observed("Update", function(): unknown
					return store.update(key, transform)
				end)
			end,
			updateOutcome = function(key: string, transform: (unknown) -> unknown): Outcome
				return observed("Update", function(): Outcome
					return updateOutcome(key, transform)
				end)
			end,
			flushQueuedWrites = function(): number
				return 0
			end,
			hasPendingWrite = function(_key: string): boolean
				return false
			end,
			isReadOnly = function(): boolean
				return false
			end,
		}
	end

	local function awaitBudget(
		budget: ((BudgetKind) -> number)?,
		kind: BudgetKind,
		sleep: (number) -> ()
	): (boolean, number)
		if budget == nil then
			return false, 0
		end
		local waited = 0
		while budget(kind) < 1 and waited < MAX_ATTEMPTS do
			sleep(computeBackoffDelay(waited, 1))
			waited += 1
		end
		return budget(kind) >= 1, waited
	end

	local function makeRealStore(name: string, state: unknown, circuit: Circuit, dependencies: RealDependencies): Store
		local raw = dependencies.raw
		local sleep = dependencies.sleep
		local jitter = dependencies.jitter
		local currentTime = dependencies.now
		local clock = dependencies.clock
		local requestBudget = dependencies.requestBudget
		local waitForBudget = dependencies.waitForBudget
			or function(kind: BudgetKind): (boolean, number?)
				return awaitBudget(requestBudget, kind, sleep)
			end
		local observerOf = dependencies.observer or noObserver
		local queuedRuns = queuedRunsFor(state)
		local inFlight = inFlightFor(state)
		local function now(): number
			return currentTime()
		end

		local function perform(
			operation: Operation,
			kind: BudgetKind,
			gated: boolean,
			call: () -> ...unknown
		): (boolean, boolean, unknown)
			local observer = observerOf()
			local startedAt = if observer ~= nil then clock() else 0
			local budgeted: boolean, sleeps: number? = false, 0
			if gated then
				budgeted, sleeps = waitForBudget(kind)
			else
				budgeted, sleeps = awaitBudget(requestBudget, kind, sleep)
			end
			local budgetedAt = if observer ~= nil then clock() else 0
			local attempts = 0
			local ok: boolean, result: unknown = false, nil
			if budgeted or not gated then
				ok, result = retry(function()
					attempts += 1
					local ran, value = pcall(call)
					return ran, value
				end, sleep, jitter)
			end
			if observer ~= nil then
				notify(observer, {
					store = name,
					operation = operation,
					durationMs = elapsedMs(startedAt, clock()),
					budgetWaitMs = elapsedMs(startedAt, budgetedAt),
					budgetSleeps = sleeps or 0,
					retries = math.max(attempts - 1, 0),
				})
			end
			return budgeted, ok, result
		end

		local function written(operation: Operation, kind: BudgetKind, call: () -> ...unknown): (boolean, unknown)
			local budgeted, ok, result = perform(operation, kind, true, call)
			if not budgeted then
				return false, "budget_exhausted"
			end
			return ok, result
		end

		local function noteSuccess()
			circuit.success()
		end

		local function noteFailure(err: unknown)
			circuit.failure(now(), err)
		end

		local function canAttempt(): boolean
			return circuit.canAttempt(now())
		end

		local function enqueueWrite(
			key: string,
			kind: "set" | "update",
			payload: unknown,
			run: () -> (boolean, unknown),
			err: unknown,
			retainOnFailure: boolean,
			finish: ((boolean, unknown) -> ())?
		): (boolean, string?)
			local queued, reason, item = circuit.enqueue({
				storeName = name,
				key = key,
				kind = kind,
				payload = payload,
			}, now())
			if not queued then
				emitWarning(
					string.format("[DataStoreResource] %s:%s(%s) queue failed: %s", name, kind, key, tostring(reason))
				)
				return false, reason
			end
			if item == nil then
				return false, "queue_item_missing"
			end
			local queuedItem = item
			queuedRuns[queuedItem.id] = {
				execute = run,
				retainOnFailure = retainOnFailure,
				finish = finish,
			}
			if err ~= nil then
				circuit.markFailure(queuedItem.id, now(), err)
			end
			return true, nil
		end

		local function flushQueuedWrites(targetKey: string?): number
			local currentTime = now()
			if not circuit.canAttempt(currentTime) then
				return 0
			end
			circuit.begin(currentTime)
			local flushed = 0
			local attempted = 0
			local blockedKeys: { [string]: boolean } = {}
			local queuedSnapshot = (table.clone(circuit.list()))
			for _, queued in queuedSnapshot do
				if queued.storeName ~= name then
					continue
				end
				if targetKey ~= nil and queued.key ~= targetKey then
					continue
				end
				local keyToken = queued.storeName .. "\0" .. queued.key
				if blockedKeys[keyToken] then
					continue
				end
				if inFlight[queued.id] then
					blockedKeys[keyToken] = true
					continue
				end
				if queued.nextAttemptAt > currentTime then
					blockedKeys[keyToken] = true
					continue
				end
				if attempted >= 10 then
					break
				end
				attempted += 1
				local queuedRun = queuedRuns[queued.id]
				if queuedRun == nil then
					circuit.markFailure(queued.id, currentTime, "queued_callback_missing")
					noteFailure("queued_callback_missing")
					emitWarning(string.format("[DataStoreResource] %s queued write callback missing", name))
					blockedKeys[keyToken] = true
				else
					inFlight[queued.id] = true
					local executed, ok, result = pcall(queuedRun.execute)
					inFlight[queued.id] = nil
					if not executed then
						result = ok
						ok = false
					end
					if ok then
						queuedRuns[queued.id] = nil
						circuit.markSuccess(queued.id)
						noteSuccess()
						if queuedRun.finish ~= nil then
							queuedRun.finish(true, result)
						end
						flushed += 1
					else
						if queuedRun.retainOnFailure then
							circuit.markFailure(queued.id, now(), result)
						else
							queuedRuns[queued.id] = nil
							circuit.markSuccess(queued.id)
						end
						if result ~= "budget_exhausted" then
							noteFailure(result)
						end
						if queuedRun.finish ~= nil then
							queuedRun.finish(false, result)
							if queuedRun.retainOnFailure then
								queuedRun.finish = nil
							end
						end
						if result ~= "budget_exhausted" then
							emitWarning(
								string.format("[DataStoreResource] %s queued write failed: %s", name, tostring(result))
							)
						end
						blockedKeys[keyToken] = true
						if not circuit.canAttempt(currentTime) then
							break
						end
					end
				end
			end
			return flushed
		end

		local function getOutcome(key: string, uncached: boolean): Outcome
			if not canAttempt() then
				return failure("circuit_open")
			end
			local options: unknown = nil
			if uncached then
				local made, value = pcall(function(): unknown
					return dependencies.uncachedOptions()
				end)
				if not made or value == nil or not dependencies.validUncachedOptions(value) then
					return failure("uncached_read_unavailable")
				end
				options = value
			end
			circuit.begin(now())
			local budgeted, ok, result = perform("Get", "get", true, function(): unknown
				return raw:GetAsync(key, options)
			end)
			if not budgeted then
				noteFailure("budget_exhausted")
				return failure("budget_exhausted")
			end
			if not ok then
				noteFailure(result)
				return failure("retry_exhausted")
			end
			noteSuccess()
			return success(result)
		end
		return {
			name = name,
			backend = "real",
			get = function(key: string): unknown
				if not canAttempt() then
					emitWarning(
						string.format("[DataStoreResource] %s:get(%s) skipped: datastore circuit open", name, key)
					)
					return nil
				end
				circuit.begin(now())
				local _, ok, result = perform("Get", "get", false, function(): unknown
					return raw:GetAsync(key)
				end)
				if not ok then
					noteFailure(result)
					emitWarning(string.format("[DataStoreResource] %s:get(%s) failed: %s", name, key, tostring(result)))
					return nil
				end
				noteSuccess()
				return result
			end,
			getOutcome = function(key: string): Outcome
				return getOutcome(key, false)
			end,
			getUncachedOutcome = function(key: string): Outcome
				return getOutcome(key, true)
			end,
			set = function(key: string, value): Outcome
				local completed = false
				local operationOk = false
				local operationResult: unknown = nil
				local function run(): (boolean, unknown)
					return written("Set", "set", function()
						raw:SetAsync(key, value)
					end)
				end
				local function finish(ok: boolean, result: unknown)
					completed = true
					operationOk = ok
					operationResult = result
				end
				local allowed = canAttempt()
				local queued, queueFailure = enqueueWrite(
					key,
					"set",
					value,
					run,
					if allowed then nil else "datastore_circuit_open",
					true,
					finish
				)
				if not queued and queueFailure == "queue_full" then
					flushQueuedWrites()
					allowed = canAttempt()
					queued, queueFailure = enqueueWrite(
						key,
						"set",
						value,
						run,
						if allowed then nil else "datastore_circuit_open",
						true,
						finish
					)
				end
				if not queued then
					return failure(queueFailure or "queue_failed")
				end
				if allowed then
					flushQueuedWrites(key)
				end
				if completed and operationOk then
					return success(nil)
				end
				if completed then
					return failure(if operationResult == "budget_exhausted" then operationResult else "retry_exhausted")
				end
				return failure(if allowed then "write_pending" else "circuit_open")
			end,
			update = function(key: string, transform: (unknown) -> unknown): unknown
				local result: unknown
				local completed = false
				local function run(): (boolean, unknown)
					return written("Update", "update", function()
						result = raw:UpdateAsync(key, function(prev: unknown)
							return transform(prev)
						end)
					end)
				end
				local allowed = canAttempt()
				enqueueWrite(
					key,
					"update",
					transform,
					run,
					if allowed then nil else "datastore_circuit_open",
					true,
					function(ok: boolean)
						completed = ok
					end
				)
				if allowed then
					flushQueuedWrites()
				end
				return if completed then result else nil
			end,
			updateOutcome = function(key: string, transform: (unknown) -> unknown): Outcome
				if circuit.hasQueued(name, key) then
					return failure("write_pending")
				end
				if not canAttempt() then
					return failure("circuit_open")
				end
				local completed = false
				local operationOk = false
				local result: unknown = nil
				local function run(): (boolean, unknown)
					return written("Update", "update", function(): unknown
						return raw:UpdateAsync(key, transform)
					end)
				end
				local queued, queueFailure = enqueueWrite(
					key,
					"update",
					transform,
					run,
					nil,
					false,
					function(ok: boolean, value)
						completed = true
						operationOk = ok
						result = value
					end
				)
				if not queued then
					return failure(queueFailure or "queue_failed")
				end
				flushQueuedWrites(key)
				if not completed then
					return failure("write_pending")
				end
				if not operationOk then
					return failure(if result == "budget_exhausted" then result else "retry_exhausted")
				end
				if result == nil then
					return failure("callback_cancelled")
				end
				return success(result)
			end,
			flushQueuedWrites = function(): number
				return flushQueuedWrites(nil)
			end,
			writeBudget = function(): number
				return if requestBudget ~= nil then requestBudget("update") else math.huge
			end,
			hasPendingWrite = function(key: string): boolean
				return circuit.hasQueued(name, key)
			end,
			isReadOnly = function(): boolean
				return circuit.isReadOnly()
			end,
		}
	end

	return table.freeze({ memory = makeMemoryStore, real = makeRealStore, drain = drainQueuedWrites })
end
return table.freeze(StoreHost)
