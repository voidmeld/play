--!strict

local Fellowship = require("../core/social/fellowship")
local Records = require("./social-records")
local Transfer = require("./profile-transfer")

local SocialHost = {}

export type Membership = Records.Membership
export type Response = Records.Result | Fellowship.Result
export type Host = {
	read serially: <T>(actorUserId: number, body: () -> T) -> T | Records.Refusal,
	read loadRecord: (fellowshipId: string, fresh: boolean) -> Records.Result,
	read cachedRecord: (fellowshipId: string) -> Fellowship.State?,
	read remember: (state: Fellowship.State) -> (),
	read membershipOf: (userId: number, fresh: boolean) -> Membership?,
	read cachedMembership: (userId: number) -> Membership?,
	read adopt: (userId: number, membership: Membership?) -> (),
	read forget: (userId: number) -> (),
	read settle: (userId: number) -> string?,
	read settleUnlessBusy: (userId: number) -> string?,
	read commitRecord: (fellowshipId: string, event: unknown) -> Records.Result,
	read claimThenCommit: (actorUserId: number, fellowshipId: string, commit: () -> Records.Result) -> Response,
	read isMember: (state: Fellowship.State, userId: number) -> boolean,
}

local function unavailable(): Records.Refusal
	return { ok = false, state = nil, replayed = false, reason = "fellowship_unavailable" }
end

function SocialHost.fellowships(source: Records.Service?): Host
	local records = source
	local fellowshipCache: { [string]: Fellowship.State } = {}
	local membershipCache: { [number]: Membership | false } = {}
	local busyActors: { [number]: boolean } = {}

	local function serially<T>(actorUserId: number, body: () -> T): T | Records.Refusal
		return Transfer.exclusive(
			busyActors,
			actorUserId,
			{ ok = false, state = nil, replayed = false, reason = "social_busy" },
			body
		)
	end

	local function loadRecord(fellowshipId: string, fresh: boolean): Records.Result
		if records == nil then
			return unavailable()
		end
		local cached = fellowshipCache[fellowshipId]
		if not fresh and cached ~= nil then
			return { ok = true, state = cached, replayed = false, reason = nil }
		end
		local outcome = records.read(fellowshipId)
		if outcome.ok then
			fellowshipCache[fellowshipId] = outcome.state
		elseif outcome.reason == "fellowship_unknown" then
			fellowshipCache[fellowshipId] = nil
		end
		return outcome
	end

	local function isMember(state: Fellowship.State, userId: number): boolean
		for _, member in state.members do
			if member.userId == userId then
				return true
			end
		end
		return false
	end

	local function cachedMembership(userId: number): Membership?
		local cached = membershipCache[userId]
		return if cached == false then nil else cached
	end

	local function membershipOf(userId: number, fresh: boolean): Membership?
		if records == nil then
			return nil
		end
		local cached = membershipCache[userId]
		if not fresh and cached ~= nil then
			return if cached == false then nil else cached
		end
		local outcome = records.readMembership(userId)
		if not outcome.ok then
			return if cached == false or cached == nil then nil else cached
		end
		membershipCache[userId] = if outcome.membership ~= nil then outcome.membership else false
		return outcome.membership
	end

	local function settle(userId: number): string?
		local membership = membershipOf(userId, true)
		local active = records
		if membership == nil or active == nil then
			return nil
		end
		local outcome = loadRecord(membership.fellowshipId, true)
		if not outcome.ok and outcome.reason ~= "fellowship_unknown" then
			return membership.fellowshipId
		end
		if not outcome.ok or not isMember(outcome.state, userId) then
			local released = active.releaseMembership(userId, membership)
			if released.ok then
				membershipCache[userId] = if released.membership ~= nil then released.membership else false
				return if released.membership ~= nil then released.membership.fellowshipId else nil
			end
			return membership.fellowshipId
		end
		if membership.pending then
			local confirmed = active.confirmMembership(userId, membership.fellowshipId)
			if confirmed.ok and confirmed.membership ~= nil then
				membershipCache[userId] = confirmed.membership
			end
		end
		return membership.fellowshipId
	end

	local function settleUnlessBusy(userId: number): string?
		if busyActors[userId] then
			local cached = membershipCache[userId]
			return if cached == nil or cached == false then nil else cached.fellowshipId
		end
		busyActors[userId] = true
		local ran, settled = pcall(settle, userId)
		busyActors[userId] = nil
		if not ran then
			error(settled, 0)
		end
		return settled
	end

	local function commitRecord(fellowshipId: string, event: unknown): Records.Result
		if records == nil then
			return unavailable()
		end
		local result = records.apply(fellowshipId, event)
		if result.ok then
			fellowshipCache[fellowshipId] = result.state
		end
		return result
	end

	local function claimThenCommit(actorUserId: number, fellowshipId: string, commit: () -> Records.Result): Response
		local active = records
		if active == nil then
			return unavailable()
		end
		local claimed = active.claimMembership(actorUserId, fellowshipId)
		if not claimed.ok then
			local refusal: Fellowship.Result = { ok = false, state = nil, replayed = false, reason = claimed.reason }
			return refusal
		end
		if claimed.membership ~= nil then
			membershipCache[actorUserId] = claimed.membership
		else
			membershipCache[actorUserId] = nil
		end
		local result = commit()
		if not result.ok then
			settle(actorUserId)
			return result
		end
		local confirmed = active.confirmMembership(actorUserId, fellowshipId)
		if not confirmed.ok and confirmed.reason == "membership_moved" then
			local reclaimed = active.claimMembership(actorUserId, fellowshipId)
			confirmed = if reclaimed.ok then active.confirmMembership(actorUserId, fellowshipId) else reclaimed
			if not confirmed.ok then
				membershipCache[actorUserId] = nil
				local refused: Fellowship.Result = {
					ok = false,
					state = result.state,
					replayed = false,
					reason = "membership_unconfirmed",
				}
				return refused
			end
		end
		if confirmed.ok and confirmed.membership ~= nil then
			membershipCache[actorUserId] = confirmed.membership
		end
		return result
	end

	local host: Host = {
		serially = serially,
		loadRecord = loadRecord,
		cachedRecord = function(fellowshipId: string): Fellowship.State?
			return fellowshipCache[fellowshipId]
		end,
		remember = function(state: Fellowship.State)
			fellowshipCache[state.fellowshipId] = state
		end,
		membershipOf = membershipOf,
		cachedMembership = cachedMembership,
		adopt = function(userId: number, membership: Membership?)
			membershipCache[userId] = if membership ~= nil then membership else false
		end,
		forget = function(userId: number)
			membershipCache[userId] = nil
		end,
		settle = settle,
		settleUnlessBusy = settleUnlessBusy,
		commitRecord = commitRecord,
		claimThenCommit = claimThenCommit,
		isMember = isMember,
	}
	return table.freeze(host)
end

return table.freeze(SocialHost)
