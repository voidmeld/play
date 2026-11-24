--!strict

export type Ownership<O, C> = {
	read current: () -> O?,
	read create: () -> O,
	read run: <T...>(O, () -> T...) -> T...,
	read dispose: (O) -> (),
	read checkpoint: (O) -> C,
	read rollback: (O, C) -> (),
}

local function lifetime<O, C, N>(ownership: Ownership<O, C>, adopt: (N) -> (), report: (string) -> ())
	local loose: { O } = {}
	local stale = {}
	local function settle<T...>(owner: O, ok: boolean, ...: T...): T...
		if not ok then
			ownership.dispose(owner)
			error((...), 0)
		end
		return ...
	end
	local function withOwner<T...>(build: () -> T...): T...
		if ownership.current() ~= nil then
			return build()
		end
		local owner = ownership.create()
		table.insert(loose, owner)
		return settle(owner, pcall(ownership.run, owner, build))
	end
	local function attempt<T...>(build: () -> T...): T...
		return withOwner(function(): T...
			local owner = assert(ownership.current(), "equipment_runtime_owner_missing")
			local checkpoint = ownership.checkpoint(owner)
			local function finish(ok: boolean, ...: T...): T...
				if not ok then
					ownership.rollback(owner, checkpoint)
					error((...), 0)
				end
				if (...) == nil then
					ownership.rollback(owner, checkpoint)
				end
				return ...
			end
			return finish(pcall(build))
		end)
	end
	local function assertCurrent(fence: (() -> boolean)?)
		if fence ~= nil and not fence() then
			error(stale, 0)
		end
	end
	local function afterExternal(fence: (() -> boolean)?, ok: boolean, value: N)
		if fence == nil or fence() then
			return
		end
		if ok then
			local owner = ownership.create()
			local adopted = pcall(ownership.run, owner, function()
				adopt(value)
			end)
			ownership.dispose(owner)
			if not adopted then
				report("stale external mesh could not be adopted for disposal")
			end
		end
		error(stale, 0)
	end
	return table.freeze({
		withOwner = withOwner,
		attempt = attempt,
		assertCurrent = assertCurrent,
		afterExternal = afterExternal,
		stale = stale,
		disposeLoose = function()
			for index = #loose, 1, -1 do
				ownership.dispose(loose[index])
				loose[index] = nil
			end
		end,
	})
end

export type MeshCache<K, V> = {
	read peek: (K) -> V?,
	read get: (K) -> V?,
}

local function meshCache<K, V>(cache: MeshCache<K, V>, ceiling: number)
	local refused: { [K]: boolean } = {}
	local inFlight: { [K]: boolean } = {}
	local function resolve(key: K, step: () -> (), clock: () -> number): V
		if refused[key] == true then
			error("gear_mesh_refused:" .. tostring(key), 0)
		end
		if inFlight[key] == true then
			local deadline = clock() + ceiling
			while inFlight[key] == true and clock() < deadline do
				step()
			end
			if refused[key] == true then
				error("gear_mesh_refused:" .. tostring(key), 0)
			end
			local settled = cache.peek(key)
			if settled == nil then
				error("gear_mesh_pending:" .. tostring(key), 0)
			end
			return settled
		end
		inFlight[key] = true
		local ok, entry = pcall(cache.get, key)
		inFlight[key] = nil
		if not ok or entry == nil then
			error(if ok then "gear_mesh_refused:" .. tostring(key) else entry, 0)
		end
		return entry
	end
	return table.freeze({
		resolve = resolve,
		refuse = function(key: K)
			refused[key] = true
		end,
		isRefused = function(key: K): boolean
			return refused[key] == true
		end,
		isInFlight = function(key: K): boolean
			return inFlight[key] == true
		end,
		refusedCount = function(): number
			local count = 0
			for _ in refused do
				count += 1
			end
			return count
		end,
		reset = function()
			table.clear(refused)
			table.clear(inFlight)
		end,
	})
end

export type Failure<A> = { application: A, reason: string }
export type BatchState<P, O> = { accessoryOwners: { [P]: O } }
export type BatchHost<A, P, O> = {
	read slot: (A) -> string,
	read pieceSlot: (P) -> string?,
	read permitted: (A) -> string?,
	read createOwner: () -> O,
	read run: <T...>(O, () -> T...) -> T...,
	read dispose: (O) -> (),
	read make: (A) -> ({ P }?, string?),
	read attach: (A, P) -> string?,
	read assertCurrent: () -> (),
	read refused: (A, string) -> (),
}

local function applyBatch<A, P, O>(
	host: BatchHost<A, P, O>,
	state: BatchState<P, O>,
	applications: { A },
	reused: { [A]: boolean },
	reusedPieces: { [P]: boolean },
	previous: { P },
	retiredOwners: { [O]: boolean },
	retiredPieces: { [P]: boolean }
): ({ A }, { Failure<A> })
	local canonical: { [string]: A } = {}
	for _, application in applications do
		host.assertCurrent()
		canonical[host.slot(application)] = application
	end
	local successful: { [string]: boolean } = {}
	local applied: { A } = {}
	local failures: { Failure<A> } = {}
	for _, application in applications do
		if reused[application] == true then
			successful[host.slot(application)] = true
			table.insert(applied, application)
			continue
		end
		local refusal = host.permitted(application)
		if refusal ~= nil then
			host.refused(application, refusal)
			table.insert(failures, { application = application, reason = refusal })
			continue
		end
		local owner = host.createOwner()
		local made, pieces, makeFailure = pcall(host.run, owner, function()
			return host.make(application)
		end)
		if not made then
			host.dispose(owner)
			error(pieces, 0)
		end
		if pieces == nil then
			host.dispose(owner)
			local reason = makeFailure or "accessory_invalid"
			host.refused(application, reason)
			table.insert(failures, { application = application, reason = reason })
			continue
		end
		local failure: string? = nil
		host.run(owner, function()
			for _, piece in pieces do
				host.assertCurrent()
				failure = host.attach(application, piece)
				if failure ~= nil then
					break
				end
			end
		end)
		if failure == nil then
			for _, piece in pieces do
				state.accessoryOwners[piece] = owner
			end
			successful[host.slot(application)] = true
			table.insert(applied, application)
		else
			host.dispose(owner)
			table.insert(failures, { application = application, reason = failure })
		end
	end
	for _, piece in previous do
		host.assertCurrent()
		if reusedPieces[piece] ~= true then
			local slot = host.pieceSlot(piece)
			if slot == nil or canonical[slot] == nil or successful[slot] == true then
				local owner = state.accessoryOwners[piece]
				if owner ~= nil then
					retiredOwners[owner] = true
					for sibling, siblingOwner in state.accessoryOwners do
						if siblingOwner == owner then
							retiredPieces[sibling] = true
						end
					end
				end
			end
		end
	end
	return applied, failures
end

return table.freeze({ lifetime = lifetime, meshCache = meshCache, applyBatch = applyBatch })
