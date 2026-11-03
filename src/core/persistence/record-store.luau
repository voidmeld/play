--!strict

local StoreHost = require("./store-host")
local Value = require("../internal/value")

export type StoreOutcome = StoreHost.Outcome
export type Store = { get: (string) -> StoreOutcome, updateOutcome: (string, (unknown) -> unknown) -> StoreOutcome }
export type Accepted<R> = { ok: true, value: R, reason: string?, found: boolean? }
export type Refused = { ok: false, value: nil, reason: string?, found: boolean? }
export type Outcome<R> = Accepted<R> | Refused
export type View = { read partitionId: string, read subjectId: string, read revision: number }
export type Config<R> = {
	read copy: (unknown) -> (R?, string?),
	read empty: (string, string) -> (R?, string?),
	read equal: (R, R) -> boolean,
	read view: (R) -> View,
	read withRevision: (R, number) -> R,
	read maxRevision: number,
}
export type API<R> = {
	read read: (Store, (string, string) -> string, string, string) -> Outcome<R>,
	read update: (Store, (string, string) -> string, unknown, unknown) -> Outcome<R>,
}

local function configure<R>(config: Config<R>): API<R>
	config = table.freeze(table.clone(config))
	assert(Value.whole(config.maxRevision, 1, 9007199254740991) ~= nil, "invalid record revision limit")
	local function read(
		store: Store,
		keyFor: (string, string) -> string,
		partitionId: string,
		subjectId: string
	): Outcome<R>
		local got = store.get(keyFor(partitionId, subjectId))
		if not got.ok then
			return { ok = false, value = nil, reason = got.reason or "read_failed" }
		end
		local found = got.value ~= nil
		local value: R?
		local reason: string?
		if found then
			value, reason = config.copy(got.value)
		else
			value, reason = config.empty(partitionId, subjectId)
		end
		if value == nil then
			return { ok = false, value = nil, reason = reason, found = found }
		end
		local view = config.view(assert(value))
		if view.partitionId ~= partitionId or view.subjectId ~= subjectId then
			return { ok = false, value = nil, reason = "identity_mismatch", found = found }
		end
		return { ok = true, value = value, reason = reason, found = found }
	end

	local function update(
		store: Store,
		keyFor: (string, string) -> string,
		snapshot: unknown,
		desired: unknown
	): Outcome<R>
		local wanted, reason = config.copy(desired)
		if wanted == nil then
			return { ok = false, value = nil, reason = reason }
		end
		local view = config.view(wanted)
		if view.revision >= config.maxRevision then
			return { ok = false, value = nil, reason = "revision_max" }
		end
		local state = Value.raw(snapshot)
		if state == nil or state.ok ~= true or type(state.found) ~= "boolean" then
			return { ok = false, value = nil, reason = "snapshot_invalid" }
		end
		local base = config.copy(state.value)
		if base == nil then
			return { ok = false, value = nil, reason = "snapshot_invalid" }
		end
		local priorView = config.view(base)
		if
			priorView.partitionId ~= view.partitionId
			or priorView.subjectId ~= view.subjectId
			or priorView.revision ~= view.revision
			or (not state.found and priorView.revision ~= 0)
		then
			return { ok = false, value = nil, reason = "expected_mismatch" }
		end
		local nextValue = config.withRevision(wanted, view.revision + 1)
		local result = store.updateOutcome(keyFor(view.partitionId, view.subjectId), function(current)
			if not state.found then
				if current ~= nil then
					return nil
				end
			else
				local prior = config.copy(current)
				if prior == nil or not config.equal(prior, base) then
					return nil
				end
			end
			return (config.copy(nextValue))
		end)
		if not result.ok then
			return {
				ok = false,
				value = nil,
				reason = if result.reason == nil or result.reason == "callback_cancelled"
					then "readback_conflict"
					else result.reason,
			}
		end
		local value = config.copy(result.value)
		if value == nil or not config.equal(value, nextValue) then
			return { ok = false, value = nil, reason = "readback_conflict" }
		end
		return { ok = true, value = value }
	end
	return table.freeze({ read = read, update = update })
end

return table.freeze({ configure = configure })
