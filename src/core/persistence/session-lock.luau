--!strict

local SessionLock = {}

export type LockState = {
	sessionId: string?,

	lockExpiry: number,
}

export type AcquireResult = {
	granted: boolean,
	newState: LockState?,
	reason: string,
}

local function sl_tryAcquire(state: LockState, requesterId: string, now: number, ttl: number): AcquireResult
	local ownLock = state.sessionId == requesterId
	local lockFresh = state.sessionId ~= nil and state.lockExpiry > now

	if state.sessionId == nil then
		return { granted = true, newState = { sessionId = requesterId, lockExpiry = now + ttl }, reason = "unlocked" }
	elseif ownLock then
		return { granted = true, newState = { sessionId = requesterId, lockExpiry = now + ttl }, reason = "refresh" }
	elseif lockFresh then
		return { granted = false, newState = nil, reason = "held" }
	else
		return { granted = true, newState = { sessionId = requesterId, lockExpiry = now + ttl }, reason = "steal" }
	end
end
SessionLock.tryAcquire = sl_tryAcquire

local function sl_release(state: LockState, sessionId: string): LockState?
	if state.sessionId ~= sessionId then
		return nil
	end
	return { sessionId = nil, lockExpiry = 0 }
end
SessionLock.release = sl_release

local function sl_isLocked(state: LockState, sessionId: string, now: number): boolean
	return state.sessionId == sessionId and state.lockExpiry > now
end
SessionLock.isLocked = sl_isLocked

return table.freeze(SessionLock)
