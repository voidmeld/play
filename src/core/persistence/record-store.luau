--!strict

local Atomic = require("../../kernel/store")
local Result = require("../../kernel/result")
local Value = require("../../kernel/value")

export type StoreOutcome = Result.Result<Atomic.Readback>
export type Store = Atomic.Port
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
	local codec: Atomic.Codec<R> = table.freeze({ copy = config.copy, equal = config.equal })
	local function read(
		store: Store,
		keyFor: (string, string) -> string,
		partitionId: string,
		subjectId: string
	): Outcome<R>
		local got = store.read(keyFor(partitionId, subjectId))
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
		local result = store.update(
			keyFor(view.partitionId, view.subjectId),
			Atomic.compareAndSwap(state.found, base, nextValue, codec)
		)
		if not result.ok then
			return {
				ok = false,
				value = nil,
				reason = if result.reason == nil or result.reason == "callback_cancelled"
					then "readback_conflict"
					else result.reason,
			}
		end
		local committed = Atomic.committed(result.value, nextValue, codec)
		if not committed.ok then
			return { ok = false, value = nil, reason = "readback_conflict" }
		end
		return { ok = true, value = committed.value }
	end
	return table.freeze({ read = read, update = update })
end

return table.freeze({ configure = configure })
