--!strict

local Bank = require("../core/bank/vault")
local Transfer = require("./profile-transfer")
local Value = require("../core/internal/value")

export type Result = {
	read ok: boolean,
	read pending: boolean?,
	read reason: string?,
	read outcome: string?,
	read bank: Bank.State?,
}
export type Subject = { read UserId: number }
export type Point = { read x: number, read y: number, read z: number }
export type Location = { read placeId: string | number, read position: Point }
export type Banker = { read id: string, read placeId: string | number, read position: Point, read enabled: boolean }
export type Dependencies<P, C, S> = {
	profiles: S,
	contextFor: (number) -> C?,
	playerFor: (number) -> Subject?,
	positionFor: (number) -> Location?,
	bankerFor: (string) -> Banker?,
	canBank: (number, P, string, string) -> boolean,
	clock: () -> number,
	identity: ((Subject) -> number?)?,
}
export type Handle = { read intent: (Subject, unknown) -> Result, read forget: (number) -> () }
export type Core<P> = {
	read request: (unknown) -> Bank.Request?,
	read project: (unknown) -> Bank.State?,
	read sameRequest: (Bank.Request, Bank.Request) -> boolean,
	read apply: (P, unknown) -> (P?, string?),
}
export type Config<P, C, S> = {
	read core: Core<P>,
	read read: (S, C) -> P?,
	read commit: (S, C, string, (P) -> (P?, string?)) -> Transfer.Result,
	read bank: (P) -> unknown,
	read transactionId: (number, string) -> string,
	read maxUserId: number,
	read maxReach: number,
	read rateWindowSec: number,
	read rateLimit: number,
}
export type Host<P, C, S> = {
	read create: (Dependencies<P, C, S>) -> (Handle?, string?),
	read reachable: (Location?, Banker?) -> boolean,
	read MAX_REACH: number,
	read RATE_LIMIT: number,
}
local function configure<P, C, S>(config: Config<P, C, S>): Host<P, C, S>
	config = table.freeze(table.clone(config))
	assert(Value.whole(config.maxUserId, 1, 9007199254740991) ~= nil, "invalid bank identity bound")
	assert(Value.whole(config.rateLimit, 1, 9007199254740991) ~= nil, "invalid bank rate bound")
	assert(Value.finite(config.maxReach) and config.maxReach >= 0, "invalid bank reach")
	assert(Value.finite(config.rateWindowSec) and config.rateWindowSec > 0, "invalid bank rate window")
	type Profile = P
	type Deps = Dependencies<P, C, S>
	local BankCore = config.core
	local MAX_USER_ID, MAX_REACH = config.maxUserId, config.maxReach
	local RATE_WINDOW, RATE_LIMIT = config.rateWindowSec, config.rateLimit

	local function actorId(player: Subject): number?
		local ok, userId = pcall(function(): unknown
			return (player).UserId
		end)
		return if ok then Value.whole(userId, 1, MAX_USER_ID) else nil
	end

	local finite = Value.finite

	local function near(playerValue: Location?, bankerValue: Banker?): boolean
		local player = playerValue
		local banker = bankerValue
		if
			type(player) ~= "table"
			or type(banker) ~= "table"
			or type(player.position) ~= "table"
			or type(banker.position) ~= "table"
			or (type(player.placeId) ~= "string" and type(player.placeId) ~= "number")
			or (type(banker.placeId) ~= "string" and type(banker.placeId) ~= "number")
			or player.placeId ~= banker.placeId
			or banker.enabled ~= true
		then
			return false
		end
		local first = player.position
		local second = banker.position
		if
			not finite(first.x)
			or not finite(first.y)
			or not finite(first.z)
			or not finite(second.x)
			or not finite(second.y)
			or not finite(second.z)
		then
			return false
		end
		local dx = first.x - second.x
		local dy = first.y - second.y
		local dz = first.z - second.z
		return dx * dx + dy * dy + dz * dz <= MAX_REACH * MAX_REACH
	end

	local BankService = {}

	function BankService.create(raw: Deps): (Handle?, string?)
		local fields = raw
		if
			type(raw) ~= "table"
			or type(fields.profiles) ~= "table"
			or type(fields.contextFor) ~= "function"
			or type(fields.playerFor) ~= "function"
			or type(fields.positionFor) ~= "function"
			or type(fields.bankerFor) ~= "function"
			or type(fields.canBank) ~= "function"
			or type(fields.clock) ~= "function"
			or (fields.identity ~= nil and type(fields.identity) ~= "function")
		then
			return nil, "dependencies_invalid"
		end
		local deps = raw
		local busy: { [number]: boolean } = {}
		local rates: { [number]: { since: number, count: number } } = {}

		local function rate(userId: number): boolean
			local now = deps.clock()
			local previous = rates[userId]
			if previous == nil or now - previous.since >= RATE_WINDOW then
				rates[userId] = { since = now, count = 1 }
				return true
			end
			if previous.count >= RATE_LIMIT then
				return false
			end
			previous.count += 1
			return true
		end

		local function intent(player: Subject, rawRequest: unknown): Result
			local rawUserId =
				Value.whole(if deps.identity ~= nil then deps.identity(player) else actorId(player), 1, MAX_USER_ID)
			if rawUserId == nil or deps.playerFor(rawUserId) ~= player or not rate(rawUserId) then
				return { ok = false, reason = "actor_or_rate_invalid" }
			end
			local userId = rawUserId
			local request = BankCore.request(rawRequest)
			if request == nil then
				return { ok = false, reason = "request_invalid" }
			end
			if busy[userId] then
				return { ok = false, pending = true, reason = "bank_busy" }
			end
			local context = deps.contextFor(userId)
			if context == nil then
				return { ok = false, reason = "session_unavailable" }
			end
			local profile = config.read(deps.profiles, context)
			if profile == nil then
				return { ok = false, reason = "profile_unavailable" }
			end
			local position = deps.positionFor(userId)
			local banker = deps.bankerFor(request.bankerId)
			if banker == nil or (banker).id ~= request.bankerId or not near(position, banker) then
				return { ok = false, reason = "banker_unreachable" }
			end
			if deps.canBank(userId, profile, request.itemId, request.kind) ~= true then
				return { ok = false, reason = "item_bound" }
			end
			local bank = if config.bank(profile) ~= nil then BankCore.project(config.bank(profile)) else nil
			if bank == nil then
				return { ok = false, reason = "bank_state_invalid" }
			end
			local previous = bank.receipts[request.requestId]
			if previous ~= nil and not BankCore.sameRequest(previous, request) then
				return { ok = false, reason = "request_conflict" }
			end
			busy[userId] = true
			local transactionId = config.transactionId(userId, request.requestId)
			local ok, result = pcall(function(): Transfer.Result
				return config.commit(
					deps.profiles,
					context,
					transactionId,
					function(source: Profile): (Profile?, string?)
						if deps.canBank(userId, source, request.itemId, request.kind) ~= true then
							return nil, "item_bound"
						end
						return BankCore.apply(source, request)
					end
				)
			end)
			busy[userId] = nil
			if not ok or result.outcome == "not_durable" then
				return { ok = false, pending = true, reason = "bank_not_durable" }
			end
			if not result.ok then
				return { ok = false, reason = result.reason }
			end
			local saved = config.read(deps.profiles, context)
			local persisted = if saved ~= nil then BankCore.project(config.bank(saved)) else nil
			local receipt = if persisted ~= nil then persisted.receipts[request.requestId] else nil
			if persisted == nil then
				return { ok = false, pending = true, reason = "receipt_unavailable" }
			end
			if receipt == nil and result.outcome == "replayed" then
				return { ok = true, outcome = result.outcome, bank = persisted }
			end
			if receipt == nil or not BankCore.sameRequest(receipt, request) then
				return { ok = false, pending = true, reason = "receipt_unavailable" }
			end
			return { ok = true, outcome = result.outcome, bank = persisted }
		end

		return table.freeze({
			intent = intent,
			forget = function(userId: number)
				rates[userId] = nil
			end,
		}),
			nil
	end

	BankService.reachable = near
	BankService.MAX_REACH = MAX_REACH
	BankService.RATE_LIMIT = RATE_LIMIT

	return table.freeze(BankService)
end

return table.freeze({ configure = configure })
