--!strict

export type Identity = {
	read userId: number,
	read characterId: string,
	read key: string,
	read sessionId: string,
	read acquisitionId: string,
	read leaseRevision: number,
}

export type Outcome = "committed" | "replayed" | "rejected" | "not_durable"

export type Result = {
	ok: boolean,
	outcome: Outcome,
	reason: string?,
}

type Readable<T> = { peek: (self: Readable<T>) -> T }

export type Reader<P> = {
	read profile: (Identity) -> Readable<P?>?,
}

local function sameSession(left: Identity?, right: Identity?): boolean
	return left ~= nil
		and right ~= nil
		and left.userId == right.userId
		and left.characterId == right.characterId
		and left.key == right.key
		and left.sessionId == right.sessionId
		and left.acquisitionId == right.acquisitionId
		and left.leaseRevision == right.leaseRevision
end

local function profileFor<P>(reader: Reader<P>, contextFor: (number) -> Identity?, userId: number): (P?, Identity?)
	local context = contextFor(userId)
	if context == nil then
		return nil, nil
	end
	local readable = reader.profile(context)
	return if readable ~= nil then readable:peek() else nil, context
end

local function settle(
	contextFor: (number) -> Identity?,
	userId: number,
	context: Identity,
	strict: boolean,
	run: () -> Result
): Result
	local ran, result = pcall(run)
	if strict and not sameSession(context, contextFor(userId)) then
		return { ok = false, outcome = "not_durable", reason = "session_replaced" }
	end
	return if ran then result else { ok = false, outcome = "not_durable", reason = "profile_unavailable" }
end

local function exclusive<K, T, F>(busy: { [K]: boolean }, key: K, refused: F, body: () -> T): T | F
	if busy[key] then
		return refused
	end
	busy[key] = true
	local ran, result = pcall(body)
	busy[key] = nil
	if not ran then
		error(result, 0)
	end
	return result
end

return {
	sameSession = sameSession,
	profileFor = profileFor,
	settle = settle,
	exclusive = exclusive,
}
