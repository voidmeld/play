--!strict

local Value = require("../value")

export type State = {
	classId: string,
	revision: number,
	ranks: { [string]: number },
	respecCount: number,
}
export type Loadout = { roles: { [string]: { ranks: { [string]: number }, respecCount: number } } }
export type Intent =
	{ kind: "view" }
	| { kind: "select", revision: number, talentId: string }
	| { kind: "respec", revision: number }
export type Result = { ok: boolean, state: Loadout, reason: string? }

local System = {}

function System.default(classId: string): State
	return { classId = classId, revision = 0, ranks = {}, respecCount = 0 }
end

function System.toLoadout(state: State): Loadout
	return { roles = { [state.classId] = { ranks = table.clone(state.ranks), respecCount = state.respecCount } } }
end

function System.fromLoadout(classId: string, revision: number, loadout: Loadout): State
	local bucket = loadout.roles[classId] or { ranks = {}, respecCount = 0 }
	return {
		classId = classId,
		revision = revision,
		ranks = table.clone(bucket.ranks),
		respecCount = bucket.respecCount,
	}
end

function System.decodeIntent(value: unknown): (Intent?, string?)
	local raw = Value.record(value, { kind = true, revision = true, talentId = true })
	if raw == nil then
		return nil, "invalid_intent"
	end
	if raw.kind == "view" and Value.record(value, { kind = true }) ~= nil then
		return { kind = "view" }, nil
	end
	local revision = raw.revision
	local validRevision = type(revision) == "number"
		and revision == revision
		and revision >= 0
		and revision == math.floor(revision)
	if
		raw.kind == "select"
		and Value.record(value, { kind = true, revision = true, talentId = true }) ~= nil
		and validRevision
		and type(revision) == "number"
	then
		local talentId = Value.opaque(raw.talentId, 128)
		if talentId ~= nil then
			return { kind = "select", revision = revision, talentId = talentId }, nil
		end
	end
	if
		raw.kind == "respec"
		and Value.record(value, { kind = true, revision = true }) ~= nil
		and validRevision
		and type(revision) == "number"
	then
		return { kind = "respec", revision = revision }, nil
	end
	return nil, "invalid_intent"
end

function System.change(
	state: State,
	intent: Intent,
	admission: (true | string)?,
	advance: (Loadout, Intent) -> Result
): (State?, string?)
	if intent.kind == "view" then
		return state, nil
	end
	if intent.revision ~= state.revision then
		return nil, "stale_projection"
	end
	if intent.kind == "respec" and admission ~= true then
		return nil, admission or "seek_trainer"
	end
	local result = advance(System.toLoadout(state), intent)
	if not result.ok then
		return nil, result.reason
	end
	return System.fromLoadout(state.classId, state.revision + 1, result.state), nil
end

function System.rules<R, C>(runtimeClass: (R) -> string, compile: (Loadout, string, number, R) -> (C?, string?))
	local Core = {}
	function Core.normalize(raw: unknown, classId: string, level: number, runtime: R?): (State?, string?, C?)
		local fields = Value.record(raw, { classId = true, revision = true, ranks = true, respecCount = true })
		if runtime == nil or runtimeClass(runtime) ~= classId or fields == nil then
			return nil, "invalid_shape", nil
		end
		local revision = Value.whole(fields.revision, 0, math.huge)
		local respecCount = Value.whole(fields.respecCount, 0, math.huge)
		if fields.classId ~= classId or revision == nil or respecCount == nil then
			return nil, "invalid_identity", nil
		end
		local rawRanks = if type(fields.ranks) == "table" and getmetatable(fields.ranks) == nil
			then Value.raw(fields.ranks)
			else nil
		if rawRanks == nil then
			return nil, "invalid_ranks", nil
		end
		local ranks: { [string]: number } = {}
		for talentId, rank in rawRanks do
			local counted = Value.whole(rank, 1, math.huge)
			if type(talentId) ~= "string" or counted == nil then
				return nil, "invalid_ranks", nil
			end
			ranks[talentId] = counted
		end
		local candidate = { classId = classId, revision = revision, ranks = ranks, respecCount = respecCount }
		local compiled, reason = compile(System.toLoadout(candidate), classId, level, runtime)
		if compiled == nil then
			return nil, reason or "invalid_ranks", nil
		end
		return candidate, nil, compiled
	end
	function Core.load(raw: unknown, classId: string, level: number, runtime: R?): (State?, string?)
		local state = Core.normalize(raw, classId, level, runtime)
		if state ~= nil then
			return state, nil
		end
		local refunded = System.default(classId)
		local _, reason = Core.normalize(refunded, classId, level, runtime)
		if reason ~= nil then
			return nil, reason
		end
		return refunded, nil
	end
	return table.freeze(Core)
end

return table.freeze(System)
