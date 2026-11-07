--!strict

export type Owner = {
	own: (() -> ()) -> () -> (),
	createChild: () -> Owner,
	dispose: () -> (),
	size: () -> number,
}
export type Outcome = { ok: boolean, reason: string?, expiresAt: number? }
type Entry<C, P> = {
	context: C,
	profile: () -> P?,
	onReleased: () -> (),
	unloading: boolean,
	scheduleGeneration: number,
	writeGeneration: number,
	leaseExpiresAt: number,
	owner: Owner,
	scheduledDetach: (() -> ())?,
}
export type Dependencies<C, P> = {
	clock: () -> number,
	schedule: (number, () -> ()) -> () -> (),
	spawn: ((() -> ()) -> () -> ())?,
	wait: (() -> ())?,
	report: ("write" | "drain" | "held", string, string?) -> (),
	renewalDelay: number,
	retryDelay: number,
	drainBudget: number,
	jitter: () -> number,
	jitterFraction: number,
	keyFor: (C) -> string,
	same: (C, C) -> boolean,
	write: (P, C, number, () -> boolean, boolean, number) -> Outcome,
}

local Sessions = {}

function Sessions.new<C, P>(owner: Owner, deps: Dependencies<C, P>)
	local entries: { [string]: Entry<C, P> } = {}
	local released: { [string]: C } = {}
	local disposed = false
	local drainDeadline: number? = nil

	local function current(ownerKey: string, entry: Entry<C, P>, generation: number): boolean
		return not disposed and entries[ownerKey] == entry and entry.writeGeneration == generation
	end

	local function write(ownerKey: string, entry: Entry<C, P>, generation: number, releaseAfterSave: boolean): Outcome
		local profile = entry.profile()
		if profile == nil then
			return { ok = false, reason = "profile_missing" }
		end
		if deps.clock() >= entry.leaseExpiresAt then
			return { ok = false, reason = "lock_lost" }
		end
		local outcome = deps.write(profile, entry.context, entry.leaseExpiresAt, function(): boolean
			return current(ownerKey, entry, generation)
		end, releaseAfterSave, generation)
		return outcome
	end

	local scheduleEntry: (string, Entry<C, P>, number) -> ()
	local function jittered(delaySeconds: number): number
		local sample = deps.jitter()
		if type(sample) ~= "number" or sample ~= sample or sample < 0 or sample >= 1 then
			sample = 0
		end
		return delaySeconds * (1 - deps.jitterFraction * sample)
	end
	local function detachScheduled(entry: Entry<C, P>)
		local detach = entry.scheduledDetach
		if detach == nil then
			return
		end
		entry.scheduledDetach = nil
		detach()
	end

	local function attempt(owner: string, entry: Entry<C, P>): Outcome
		entry.writeGeneration += 1
		local generation = entry.writeGeneration
		local written = write(owner, entry, generation, entry.unloading)
		if not current(owner, entry, generation) then
			return { ok = false, reason = "operation_cancelled" }
		end
		if written.ok then
			entry.leaseExpiresAt = assert(written.expiresAt)
		end
		local outcome: Outcome = { ok = written.ok, reason = written.reason }
		if outcome.ok and entry.unloading then
			entries[owner] = nil
			released[owner] = entry.context
			entry.owner.dispose()
			entry.onReleased()
		elseif entries[owner] == entry then
			if not outcome.ok then
				deps.report("write", deps.keyFor(entry.context), outcome.reason)
			end
			if entry.unloading and drainDeadline ~= nil and deps.clock() >= drainDeadline then
				return outcome
			end
			scheduleEntry(owner, entry, jittered(if outcome.ok then deps.renewalDelay else deps.retryDelay))
		end
		return outcome
	end

	scheduleEntry = function(owner: string, entry: Entry<C, P>, delaySeconds: number)
		detachScheduled(entry)
		entry.scheduleGeneration += 1
		local generation = entry.scheduleGeneration
		local cancel = deps.schedule(delaySeconds, function()
			if disposed or entries[owner] ~= entry or entry.scheduleGeneration ~= generation then
				return
			end
			detachScheduled(entry)
			attempt(owner, entry)
		end)
		local detach = entry.owner.own(cancel)
		if disposed or entries[owner] ~= entry or entry.scheduleGeneration ~= generation then
			detach()
			return
		end
		entry.scheduledDetach = detach
	end

	local function admit(context: C, leaseExpiresAt: number, profile: () -> P?, onReleased: () -> ())
		released[deps.keyFor(context)] = nil
		local entry: Entry<C, P> = {
			context = context,
			profile = profile,
			onReleased = onReleased,
			unloading = false,
			scheduleGeneration = 0,
			writeGeneration = 0,
			leaseExpiresAt = leaseExpiresAt,
			owner = owner.createChild(),
			scheduledDetach = nil,
		}
		entries[deps.keyFor(context)] = entry
		local ok, reason = pcall(function()
			scheduleEntry(deps.keyFor(context), entry, jittered(deps.renewalDelay))
			return nil
		end)
		if not ok then
			entries[deps.keyFor(context)] = nil
			entry.owner.dispose()
			error(reason, 0)
		end
	end

	local function save(context: C): Outcome
		local entry = entries[deps.keyFor(context)]
		if entry == nil or entry.unloading or not deps.same(entry.context, context) then
			return { ok = false, reason = "not_admitted" }
		end
		return attempt(deps.keyFor(context), entry)
	end

	local function requestSave(context: C): boolean
		local entry = entries[deps.keyFor(context)]
		if entry == nil or entry.unloading or not deps.same(entry.context, context) then
			return false
		end
		scheduleEntry(deps.keyFor(context), entry, 0)
		return true
	end

	local function unload(context: C): Outcome
		local entry = entries[deps.keyFor(context)]
		if entry == nil then
			local settled = released[deps.keyFor(context)]
			return if settled ~= nil and deps.same(settled, context)
				then { ok = true, reason = nil }
				else { ok = false, reason = "not_admitted" }
		end
		if not deps.same(entry.context, context) then
			return { ok = false, reason = "not_admitted" }
		end
		entry.unloading = true
		entry.scheduleGeneration += 1
		detachScheduled(entry)
		entry.writeGeneration += 1
		return attempt(deps.keyFor(context), entry)
	end

	local function drain(): { [string]: Outcome }
		local owners: { { key: string, context: C } } = {}
		for key, entry in entries do
			table.insert(owners, { key = key, context = entry.context })
		end
		local outcomes: { [string]: Outcome } = {}
		if deps.spawn == nil or deps.wait == nil then
			for _, owner in owners do
				outcomes[owner.key] = unload(owner.context)
			end
			return outcomes
		end
		local remaining = #owners
		local deadline = deps.clock() + deps.drainBudget
		drainDeadline = deadline
		for _, admitted in owners do
			local ownerKey = admitted.key
			local cancel = deps.spawn(function()
				local ran, result = pcall(function(): Outcome
					return unload(admitted.context)
				end)
				if ran then
					outcomes[ownerKey] = result
				else
					outcomes[ownerKey] = { ok = false, reason = "drain_failed" }
					deps.report("drain", ownerKey, nil)
				end
				remaining -= 1
			end)
			owner.own(cancel)
		end
		while remaining > 0 and deps.clock() < deadline do
			assert(deps.wait)()
		end
		for _, admitted in owners do
			local ownerKey = admitted.key
			if outcomes[ownerKey] == nil then
				outcomes[ownerKey] = { ok = false, reason = "drain_held" }
				deps.report("held", ownerKey, nil)
			end
		end
		return table.clone(outcomes)
	end

	local function isAdmitted(context: C): boolean
		local entry = entries[deps.keyFor(context)]
		return entry ~= nil and deps.same(entry.context, context)
	end

	local function ownedTaskCount(context: C): number
		local entry = entries[deps.keyFor(context)]
		return if entry ~= nil and deps.same(entry.context, context) then entry.owner.size() else 0
	end

	local function dispose()
		disposed = true
		for key in entries do
			local entry: Entry<C, P> = entries[key]
			entry.scheduleGeneration += 1
			entry.writeGeneration += 1
			detachScheduled(entry)
			entry.owner.dispose()
		end
		table.clear(entries)
		table.clear(released)
	end

	return {
		admit = admit,
		save = save,
		requestSave = requestSave,
		unload = unload,
		drain = drain,
		isAdmitted = isAdmitted,
		ownedTaskCount = ownedTaskCount,
		dispose = dispose,
	}
end

return table.freeze(Sessions)
