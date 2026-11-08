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
	local function transact(
		context: C,
		change: ((P) -> (P?, string?))?,
		installed: { previous: P, candidate: P }?
	): Result
		local key = deps.keyFor(context)
		if busy[key] then
			return { outcome = "rejected", restoration = "not_applied", reason = "transaction_busy" }
		end
		busy[key] = true
		local previous: P? = nil
		local candidate: P? = nil
		local applied = false
		local writeSuperseded = false
		local function restore(): Restoration
			local before, expected = previous, candidate
			if not applied or before == nil or expected == nil then
				return "not_applied"
			end
			if writeSuperseded or not deps.sessions.isAdmitted(context) then
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
			local before: P
			if installed ~= nil then
				before = deps.copy(installed.previous)
			else
				before = deps.copy(live)
			end
			previous = before
			local expected: P
			if installed ~= nil then
				expected = deps.copy(installed.candidate)
			else
				assert(change ~= nil)
				local changed, problem = change(deps.copy(before))
				if changed == nil then
					return { outcome = "rejected", restoration = "not_applied", reason = problem or "change_rejected" }
				end
				expected = deps.copy(changed)
			end
			candidate = expected
			if not deps.sessions.isAdmitted(context) then
				return { outcome = "rejected", restoration = "not_applied", reason = "live_changed" }
			end
			applied = true
			if installed ~= nil then
				if not deps.verify(expected, live) then
					local restoration = restore()
					return {
						outcome = if restoration == "restored" then "rolled_back" else "ambiguous",
						restoration = restoration,
						reason = "verification_failed",
					}
				end
			elseif not deps.replace(context, before, deps.copy(expected)) then
				applied = false
				return { outcome = "rejected", restoration = "not_applied", reason = "live_changed" }
			end
			local saved, save = pcall(deps.sessions.save, context)
			local saveReason: string? = if saved then save.reason else "save_failed"
			local refusedSave = not saved or not save.ok
			writeSuperseded = refusedSave
				and (saveReason == "operation_cancelled" or saveReason == "not_admitted" or saveReason == "lock_lost")
			local uncertainSave = refusedSave and (not saved or saveReason == "save_failed" or writeSuperseded)
			if installed ~= nil and (not saved or not save.ok) then
				return {
					outcome = "ambiguous",
					restoration = restore(),
					reason = saveReason or "save_refused",
					saveReason = saveReason,
				}
			end
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
				outcome = if restoration == "restored"
						and durableBefore
						and not uncertainSave
					then "rolled_back"
					else "ambiguous",
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
	local function commit(context: C, change: (P) -> (P?, string?)): Result
		return transact(context, change, nil)
	end
	local function finalize(context: C, previous: P, expected: P): Result
		return transact(context, nil, { previous = previous, candidate = expected })
	end
	return table.freeze({ commit = commit, finalize = finalize })
end

return table.freeze({ new = new })
