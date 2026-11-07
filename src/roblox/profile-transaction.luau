--!strict

local Sessions = require("./profile-sessions")

export type Outcome = "committed" | "rolled_back" | "ambiguous" | "rejected"
export type Restoration = "not_applied" | "restored" | "superseded" | "failed"
export type Result = { outcome: Outcome, restoration: Restoration, reason: string?, saveReason: string? }
export type SessionPort<C> = { isAdmitted: (C) -> boolean, save: (C) -> Sessions.Outcome }
export type Dependencies<C, P> = {
	sessions: SessionPort<C>,
	keyFor: (C) -> string,
	live: (C) -> P?,
	replace: (C, P, P) -> boolean,
	readback: (C) -> (P?, string?),
	copy: (P) -> P,
	equal: (P, P) -> boolean,
	verify: (P, P) -> boolean,
}

local function new<C, P>(deps: Dependencies<C, P>)
	local busy: { [string]: boolean } = {}
	local function commit(context: C, change: (P) -> (P?, string?)): Result
		local key = deps.keyFor(context)
		if busy[key] then
			return { outcome = "rejected", restoration = "not_applied", reason = "transaction_busy" }
		end
		busy[key] = true
		local previous: P? = nil
		local candidate: P? = nil
		local applied = false
		local function restore(): Restoration
			local before, expected = previous, candidate
			if not applied or before == nil or expected == nil then
				return "not_applied"
			end
			if not deps.sessions.isAdmitted(context) then
				return "superseded"
			end
			local current = deps.live(context)
			if current == nil or not deps.equal(current, expected) then
				return "superseded"
			end
			return if deps.replace(context, expected, deps.copy(before)) then "restored" else "superseded"
		end
		local ran, result = pcall(function(): Result
			if not deps.sessions.isAdmitted(context) then
				return { outcome = "rejected", restoration = "not_applied", reason = "not_admitted" }
			end
			local live = deps.live(context)
			if live == nil then
				return { outcome = "rejected", restoration = "not_applied", reason = "profile_missing" }
			end
			local before = deps.copy(live)
			previous = before
			local changed, problem = change(deps.copy(before))
			if changed == nil then
				return { outcome = "rejected", restoration = "not_applied", reason = problem or "change_rejected" }
			end
			local expected = deps.copy(changed)
			candidate = expected
			if not deps.sessions.isAdmitted(context) then
				return { outcome = "rejected", restoration = "not_applied", reason = "live_changed" }
			end
			applied = true
			if not deps.replace(context, before, deps.copy(expected)) then
				applied = false
				return { outcome = "rejected", restoration = "not_applied", reason = "live_changed" }
			end
			local saved, save = pcall(deps.sessions.save, context)
			local saveReason: string? = if saved then save.reason else "save_failed"
			local read, stored, readReason = pcall(deps.readback, context)
			local current = deps.live(context)
			local admitted = deps.sessions.isAdmitted(context)
			if
				saved
				and save.ok
				and read
				and stored ~= nil
				and admitted
				and current ~= nil
				and deps.verify(expected, current)
				and deps.verify(expected, stored)
			then
				return { outcome = "committed", restoration = "not_applied" }
			end
			local restoration = restore()
			local durableBefore = read and stored ~= nil and deps.equal(before, stored)
			local reason: string = if not admitted
				then "session_replaced"
				elseif not saved or not save.ok then saveReason or "save_refused"
				elseif not read or stored == nil then readReason or "readback_failed"
				else "verification_failed"
			return {
				outcome = if restoration == "restored" and durableBefore then "rolled_back" else "ambiguous",
				restoration = restoration,
				reason = reason,
				saveReason = saveReason,
			}
		end)
		if not ran then
			local restored, restoration = pcall(restore)
			busy[key] = nil
			return {
				outcome = if applied then "ambiguous" else "rejected",
				restoration = if restored then restoration else "failed",
				reason = "operation_failed",
			}
		end
		busy[key] = nil
		return result
	end
	return table.freeze({ commit = commit })
end

return table.freeze({ new = new })
