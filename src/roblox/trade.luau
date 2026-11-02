--!strict

local Exchange = require("../core/trade/exchange")
local ReceiptTypes = require("../core/trade/receipt")
local Transfer = require("./profile-transfer")
local Value = require("../core/internal/value")

export type Subject = { read UserId: number }
export type Location = { read x: number, read y: number, read z: number }
export type Context = Transfer.Identity
export type Account = {
	coin: number,
	inventory: { [string]: number },
	pending: { [string]: ReceiptTypes.Pointer }?,
}
export type State = Exchange.State & { sessions: { [number]: Context }?, characters: { [number]: string }? }
export type ReceiptOutcome = { read ok: boolean, read value: unknown, read reason: string? }
export type Dependencies<P, Surface> = {
	read profiles: Surface,
	read receipts: {
		read getOutcome: (string) -> ReceiptOutcome,
		read updateOutcome: (string, (ReceiptTypes.Projected?) -> ReceiptTypes.Projected?) -> ReceiptOutcome,
	},
	read contextFor: (number) -> Context?,
	read playerFor: (number) -> Subject?,
	read positionFor: (number) -> Location?,
	read allowed: (number) -> boolean,
	read tradeable: (number, P, string, number) -> boolean,
	read newId: () -> string,
	read clock: () -> number,
	read identity: ((Subject) -> unknown)?,
	read schedule: ((number, () -> ()) -> ())?,
}
export type Result = {
	ok: boolean,
	reason: string?,
	pending: boolean?,
	tradeId: string?,
	state: State?,
	outcomes: { [string]: Result }?,
}
export type Service = {
	read intent: (Subject, unknown) -> Result,
	read recover: (string, number?) -> Result,
	read admit: (number) -> Result,
	read playerRemoving: (Subject) -> Result,
	read sweepExpired: () -> number,
	read state: (string) -> State?,
	read stateFor: (number) -> State?,
}
export type ExchangeOps = {
	read offer: (unknown) -> Exchange.Offer?,
	read empty: (string, number, number) -> Exchange.State?,
	read step: (Exchange.State, number, unknown) -> (Exchange.State?, string?),
	read settled: (Exchange.State) -> Exchange.State?,
}
export type ReceiptOps = {
	read project: (unknown) -> ReceiptTypes.Projected?,
	read wire: (unknown) -> ReceiptTypes.Wire?,
}
export type Effect<P> = (P) -> (P?, string?)
export type Config<P, Surface> = {
	read exchange: ExchangeOps,
	read receipts: ReceiptOps,
	read account: (P) -> Account,
	read withAccount: (P, Account) -> P,
	read capacity: (P) -> number,
	read entries: ({ [string]: number }) -> number,
	read unboundCount: (P, string) -> number,
	read related: (P, P) -> boolean,
	read recorded: (P, string) -> boolean,
	read profileFor: (Surface, (number) -> Context?, number) -> (P?, Context?),
	read commit: (Surface, Context, string, Effect<P>) -> Transfer.Result,
	read receiptKey: (string) -> string,
	read transactionId: (string, string, number) -> string,
	read maxCoin: number,
	read maxUserId: number,
	read maxStack: number,
	read maxDistance: number,
	read idLimit: number,
	read maxRecoverySlots: number,
	read maxCompleted: number,
	read rateWindowSec: number,
	read rateLimit: number,
	read tradeTtlSec: number,
}
export type Host<P, Surface> = {
	read create: (Dependencies<P, Surface>) -> (Service?, string?),
	read MAX_DISTANCE: number,
	read RATE_LIMIT: number,
	read TRADE_TTL_SEC: number,
}

local function configure<P, Surface>(config: Config<P, Surface>): Host<P, Surface>
	config = table.freeze(table.clone(config))
	for _, value in
		{
			config.maxUserId,
			config.maxStack,
			config.idLimit,
			config.maxRecoverySlots,
			config.maxCompleted,
			config.rateLimit,
		}
	do
		assert(Value.whole(value, 1, 9007199254740991) ~= nil, "invalid trade bound")
	end
	assert(Value.whole(config.maxCoin, 0, 9007199254740991) ~= nil, "invalid trade coin bound")
	assert(Value.finite(config.maxDistance) and config.maxDistance >= 0, "invalid trade distance")
	assert(Value.finite(config.rateWindowSec) and config.rateWindowSec > 0, "invalid trade rate window")
	assert(Value.finite(config.tradeTtlSec) and config.tradeTtlSec > 0, "invalid trade lifetime")
	type Profile = P
	type Deps = Dependencies<P, Surface>
	type Offer = Exchange.Offer
	type TradeReceipt = ReceiptTypes.Projected
	type CommitResult = Transfer.Result
	type ProfileEffect = Effect<P>
	local MAX_DISTANCE = config.maxDistance
	local TradeCore = config.exchange
	local Receipt = config.receipts
	local function accountOf(profile: Profile): Account
		return config.account(profile)
	end
	local function withPointers(profile: Profile, pointers: { [string]: ReceiptTypes.Pointer }): Profile
		local account = table.clone(accountOf(profile))
		account.pending = pointers
		return config.withAccount(profile, account)
	end
	local sameSession = Transfer.sameSession
	local MAX_GOLD = config.maxCoin
	local MAX_USER_ID = config.maxUserId
	local MAX_STACK = config.maxStack
	local RATE_WINDOW_SEC = config.rateWindowSec
	local RATE_LIMIT = config.rateLimit
	local TRADE_TTL_SEC = config.tradeTtlSec

	local function whole(value: unknown, low: number, high: number): boolean
		return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
	end

	local function opaque(value: unknown): boolean
		return type(value) == "string"
			and #value > 0
			and #value <= config.idLimit
			and string.match(value, "^[%w%.%-_:]+$") ~= nil
	end

	local function hosted(state: Exchange.State, prior: State?): State
		return {
			tradeId = state.tradeId,
			expiresAt = state.expiresAt,
			players = state.players,
			phase = state.phase,
			revision = state.revision,
			offers = state.offers,
			locks = state.locks,
			confirms = state.confirms,
			sessions = if prior ~= nil then prior.sessions else nil,
			characters = if prior ~= nil then prior.characters else nil,
		}
	end

	local function exact(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" or getmetatable(value) ~= nil then
			return false
		end
		local raw = Value.raw(value)
		if raw == nil then
			return false
		end
		for key in raw do
			if type(key) ~= "string" or fields[key] ~= true then
				return false
			end
		end
		return true
	end

	local function itemCount(inventory: unknown, itemId: string): number?
		local raw = Value.raw(inventory)
		if raw == nil then
			return nil
		end
		local value = raw[itemId] or 0
		return if type(value) == "number" and whole(value, 0, MAX_STACK) then value else nil
	end

	local function profileFor(deps: Deps, userId: number): (Profile?, Context?)
		return config.profileFor(deps.profiles, deps.contextFor, userId)
	end

	local function itemRoom(profile: Profile, outgoing: Offer, incoming: Offer): boolean
		local inventory = accountOf(profile).inventory
		if type(inventory) ~= "table" then
			return false
		end
		local deltas: { [string]: number } = {}
		for _, stack in outgoing.items do
			deltas[stack.itemId] = (deltas[stack.itemId] or 0) - stack.count
		end
		for _, stack in incoming.items do
			deltas[stack.itemId] = (deltas[stack.itemId] or 0) + stack.count
		end
		local entries = 0
		for itemId, count in inventory do
			if type(itemId) ~= "string" or not whole(count, 1, MAX_STACK) then
				return false
			end
			entries += 1
		end
		for itemId, delta in deltas do
			local before = itemCount(inventory, itemId)
			if before == nil then
				return false
			end
			local after = before + delta
			if after < 0 or after > MAX_STACK then
				return false
			end
			if before == 0 and after > 0 then
				entries += 1
			elseif before > 0 and after == 0 then
				entries -= 1
			end
		end
		return entries <= math.max(config.capacity(profile), config.entries(accountOf(profile).inventory))
	end

	local function debit(profile: Profile, offer: Offer): (Profile?, string?)
		if
			type(accountOf(profile).inventory) ~= "table"
			or not whole(accountOf(profile).coin, 0, MAX_GOLD)
			or accountOf(profile).coin < offer.coin
		then
			return nil, "coin_insufficient"
		end
		local inventory = table.clone(accountOf(profile).inventory)
		for _, stack in offer.items do
			local before = itemCount(inventory, stack.itemId)
			if before == nil or before < stack.count or config.unboundCount(profile, stack.itemId) < stack.count then
				return nil, "goods_insufficient"
			end
			inventory[stack.itemId] = if before == stack.count then nil else before - stack.count
		end
		local updated = table.clone(accountOf(profile))
		updated.coin = accountOf(profile).coin - offer.coin
		updated.inventory = inventory
		return config.withAccount(profile, updated), nil
	end

	local function credit(profile: Profile, offer: Offer): (Profile?, string?)
		if
			type(accountOf(profile).inventory) ~= "table"
			or not whole(accountOf(profile).coin, 0, MAX_GOLD)
			or accountOf(profile).coin + offer.coin > MAX_GOLD
		then
			return nil, "coin_overflow"
		end
		local inventory = table.clone(accountOf(profile).inventory)
		local entries = 0
		for _ in inventory do
			entries += 1
		end
		for _, stack in offer.items do
			local before = itemCount(inventory, stack.itemId)
			if before == nil or before + stack.count > MAX_STACK then
				return nil, "goods_overflow"
			end
			if before == 0 then
				entries += 1
			end
			inventory[stack.itemId] = before + stack.count
		end
		if entries > config.maxRecoverySlots then
			return nil, "inventory_full"
		end
		local updated = table.clone(accountOf(profile))
		updated.coin = accountOf(profile).coin + offer.coin
		updated.inventory = inventory
		return config.withAccount(profile, updated), nil
	end

	local function txId(tradeId: string, phase: string, userId: number): string
		return config.transactionId(tradeId, phase, userId)
	end

	local function holdWithPointer(profile: Profile, offer: Offer, receipt: TradeReceipt): (Profile?, string?)
		local pending = accountOf(profile).pending
		if pending ~= nil and type(pending) ~= "table" then
			return nil, "pending_trade_invalid"
		end
		for otherId in pending or {} do
			if otherId ~= receipt.tradeId then
				return nil, "pending_trade"
			end
		end
		local updated, reason = debit(profile, offer)
		if updated == nil then
			return nil, reason
		end
		local pointers = table.clone(pending or {})
		pointers[receipt.tradeId] = {
			tradeId = receipt.tradeId,
			receipt = assert(Receipt.wire(receipt)),
		}
		return withPointers(updated, pointers), nil
	end

	local function creditAndClear(profile: Profile, offer: Offer, tradeId: string): (Profile?, string?)
		local updated, reason = credit(profile, offer)
		if updated == nil then
			return nil, reason
		end
		local pointers = table.clone(accountOf(profile).pending or {})
		pointers[tradeId] = nil
		return withPointers(updated, pointers), nil
	end

	local function commitProfile(
		deps: Deps,
		userId: number,
		transactionId: string,
		effect: ProfileEffect,
		receipt: TradeReceipt?
	): CommitResult
		local _, context = profileFor(deps, userId)
		if context == nil or (receipt ~= nil and context.characterId ~= receipt.characters[userId]) then
			return { ok = false, outcome = "not_durable", reason = "session_unavailable" }
		end
		return Transfer.settle(deps.contextFor, userId, context, true, function(): CommitResult
			return config.commit(deps.profiles, context, transactionId, effect)
		end)
	end

	local function receiptRead(deps: Deps, tradeId: string): (TradeReceipt?, boolean, string?)
		local ok, result = pcall(deps.receipts.getOutcome, config.receiptKey(tradeId))
		if not ok or result.ok ~= true then
			return nil,
				false,
				if ok and result.reason == "receipt_invalid" then "receipt_invalid" else "receipt_unavailable"
		end
		local receipt = Receipt.project(result.value)
		if result.value ~= nil and receipt == nil then
			return nil, false, "receipt_invalid"
		end
		return receipt, true, nil
	end

	local function receiptWrite(
		deps: Deps,
		tradeId: string,
		phase: string,
		make: (TradeReceipt?) -> TradeReceipt?
	): TradeReceipt?
		local key = config.receiptKey(tradeId)
		local ok, result = pcall(function()
			return deps.receipts.updateOutcome(key, function(raw: unknown): TradeReceipt?
				if raw == nil then
					return make(nil)
				end
				local current = Receipt.project(raw)
				if current == nil then
					return nil
				end
				return make(current)
			end)
		end)
		local readback = if ok and result.ok then Receipt.project(result.value) else nil
		if readback ~= nil and readback.phase == phase then
			return readback
		end
		local read = receiptRead(deps, tradeId)
		return if read ~= nil and read.phase == phase then read else nil
	end

	local function validReceipt(receiptValue: unknown, tradeId: string, state: State?): boolean
		local receipt = Receipt.project(receiptValue)
		if receipt == nil or receipt.tradeId ~= tradeId then
			return false
		end
		for _, userId in receipt.players do
			local normalized = receipt.offers[userId]
			if state ~= nil then
				if state.characters ~= nil and receipt.characters[userId] ~= state.characters[userId] then
					return false
				end
				local original = state.offers[userId]
				if original == nil or original.coin ~= normalized.coin or #original.items ~= #normalized.items then
					return false
				end
				for index, stack in original.items do
					if
						stack.itemId ~= normalized.items[index].itemId
						or stack.count ~= normalized.items[index].count
					then
						return false
					end
				end
			end
		end
		return state == nil
			or (
				receipt.revision == state.revision
				and receipt.expiresAt == state.expiresAt
				and receipt.players[1] == state.players[1]
				and receipt.players[2] == state.players[2]
			)
	end

	local function present(deps: Deps, firstId: number, secondId: number): boolean
		local first = deps.playerFor(firstId)
		local second = deps.playerFor(secondId)
		local firstProfile, firstContext = profileFor(deps, firstId)
		local secondProfile, secondContext = profileFor(deps, secondId)
		if
			first == nil
			or second == nil
			or firstProfile == nil
			or secondProfile == nil
			or not config.related(firstProfile, secondProfile)
			or not deps.allowed(firstId)
			or not deps.allowed(secondId)
		then
			return false
		end
		if
			deps.playerFor(firstId) ~= first
			or deps.playerFor(secondId) ~= second
			or not sameSession(firstContext, deps.contextFor(firstId))
			or not sameSession(secondContext, deps.contextFor(secondId))
		then
			return false
		end
		firstProfile = profileFor(deps, firstId)
		secondProfile = profileFor(deps, secondId)
		local firstPos = deps.positionFor(firstId)
		local secondPos = deps.positionFor(secondId)
		if
			firstProfile == nil
			or secondProfile == nil
			or not config.related(firstProfile, secondProfile)
			or firstPos == nil
			or secondPos == nil
		then
			return false
		end
		if
			type(firstPos.x) ~= "number"
			or type(firstPos.y) ~= "number"
			or type(firstPos.z) ~= "number"
			or type(secondPos.x) ~= "number"
			or type(secondPos.y) ~= "number"
			or type(secondPos.z) ~= "number"
		then
			return false
		end
		local dx = firstPos.x - secondPos.x
		local dy = firstPos.y - secondPos.y
		local dz = firstPos.z - secondPos.z
		return dx * dx + dy * dy + dz * dz <= MAX_DISTANCE * MAX_DISTANCE
	end

	local function admissible(deps: Deps, state: State): (boolean, string?)
		local firstId, secondId = state.players[1], state.players[2]
		if not present(deps, firstId, secondId) then
			return false, "trade_unavailable"
		end
		for _, userId in state.players do
			local profile = profileFor(deps, userId)
			if profile == nil then
				return false, "trade_unavailable"
			end
			local offer = state.offers[userId]
			local otherId = if userId == firstId then secondId else firstId
			if not itemRoom(profile, offer, state.offers[otherId]) then
				return false, "capacity_or_ownership"
			end
			if
				not whole(accountOf(profile).coin, 0, MAX_GOLD)
				or accountOf(profile).coin < offer.coin
				or accountOf(profile).coin - offer.coin + state.offers[otherId].coin > MAX_GOLD
			then
				return false, "coin_insufficient"
			end
			for _, stack in offer.items do
				if not deps.tradeable(userId, profile, stack.itemId, stack.count) then
					return false, "item_bound"
				end
			end
		end
		return true, nil
	end

	local TradeService = {}

	function TradeService.create(depsValue: Deps): (Service?, string?)
		local deps = depsValue
		if
			type(deps) ~= "table"
			or type(deps.profiles) ~= "table"
			or type(deps.receipts) ~= "table"
			or type(deps.receipts.getOutcome) ~= "function"
			or type(deps.receipts.updateOutcome) ~= "function"
			or type(deps.contextFor) ~= "function"
			or type(deps.playerFor) ~= "function"
			or type(deps.positionFor) ~= "function"
			or type(deps.allowed) ~= "function"
			or type(deps.tradeable) ~= "function"
			or type(deps.newId) ~= "function"
			or type(deps.clock) ~= "function"
		then
			return nil, "dependencies_invalid"
		end
		local trades: { [string]: State } = {}
		local active: { [number]: string } = {}
		local inFlight: { [string]: boolean } = {}
		local recoverySessions: { [string]: { [number]: Context | false } } = {}
		local cancelRequested: { [string]: boolean } = {}
		local rates: { [number]: { since: number, count: number } } = {}
		local completed: { string } = {}
		local function recoveryCurrent(tradeId: string, participantId: number?): boolean
			local sessions: { [number]: Context | false } = recoverySessions[tradeId] or {}
			for userId, context in sessions do
				if participantId ~= nil and userId ~= participantId then
					continue
				end
				local current = deps.contextFor(userId)
				if
					(context == false and current ~= nil) or (context ~= false and not sameSession(context, current))
				then
					return false
				end
			end
			return true
		end
		local function checkedCommit(
			commitDeps: Deps,
			userId: number,
			transactionId: string,
			effect: ProfileEffect,
			receipt: TradeReceipt
		): CommitResult
			if not recoveryCurrent(receipt.tradeId, userId) then
				return { ok = false, outcome = "not_durable", reason = "session_replaced" }
			end
			return commitProfile(commitDeps, userId, transactionId, effect, receipt)
		end
		local function receiptProfile(receipt: TradeReceipt, userId: number): Profile?
			local profile, context = profileFor(deps, userId)
			if context == nil or context.characterId ~= receipt.characters[userId] then
				return nil
			end
			return profile
		end
		local function liveSessions(state: State?): boolean
			if state == nil or state.sessions == nil then
				return false
			end
			for _, userId in state.players do
				if not sameSession(state.sessions[userId], deps.contextFor(userId)) then
					return false
				end
			end
			return true
		end

		local function rate(userId: number): boolean
			local now = deps.clock()
			local previous = rates[userId]
			if previous == nil or now - previous.since >= RATE_WINDOW_SEC then
				rates[userId] = { since = now, count = 1 }
				return true
			end
			if previous.count >= RATE_LIMIT then
				return false
			end
			previous.count += 1
			return true
		end

		local function finish(tradeId: string, state: State)
			trades[tradeId] = state
			if state.phase == "settled" or state.phase == "cancelled" then
				for _, userId in state.players do
					if active[userId] == tradeId then
						active[userId] = nil
					end
				end
				if table.find(completed, tradeId) == nil then
					completed[#completed + 1] = tradeId
					if #completed > config.maxCompleted then
						trades[assert(table.remove(completed, 1))] = nil
					end
				end
			end
		end

		local function release(receipt: TradeReceipt): boolean
			for _, userId in receipt.players do
				local profile = receiptProfile(receipt, userId)
				if profile ~= nil and config.recorded(profile, txId(receipt.tradeId, "hold", userId)) then
					local result = checkedCommit(deps, userId, txId(receipt.tradeId, "refund", userId), function(source)
						return creditAndClear(source, receipt.offers[userId], receipt.tradeId)
					end, receipt)
					if not result.ok then
						return false
					end
				end
			end
			return true
		end

		local function clearResolvedPointers(receipt: TradeReceipt): boolean
			for _, userId in receipt.players do
				local profile = receiptProfile(receipt, userId)
				if
					profile ~= nil
					and type(accountOf(profile).pending) == "table"
					and (accountOf(profile).pending or {})[receipt.tradeId] ~= nil
				then
					local result = checkedCommit(deps, userId, txId(receipt.tradeId, "clear", userId), function(source)
						local pointers = table.clone(accountOf(source).pending or {})
						pointers[receipt.tradeId] = nil
						return withPointers(source, pointers), nil
					end, receipt)
					if not result.ok then
						return false
					end
				end
			end
			return true
		end

		local function settleOwned(tradeId: string): Result
			local state = trades[tradeId]
			local receipt, readable, readProblem = receiptRead(deps, tradeId)
			if not recoveryCurrent(tradeId) then
				return { ok = false, pending = true, reason = "session_replaced" }
			end
			if not readable then
				return { ok = false, pending = true, reason = readProblem or "receipt_unavailable" }
			end
			if state == nil and receipt == nil then
				return { ok = false, pending = false, reason = "trade_unknown" }
			end
			if receipt ~= nil and not validReceipt(receipt, tradeId, state) then
				return { ok = false, pending = true, reason = "receipt_invalid" }
			end
			if receipt == nil and (state == nil or state.phase ~= "confirmed") then
				return { ok = false, pending = false, reason = "not_confirmed" }
			end
			local function done(ok: boolean, pending: boolean, reason: string?): Result
				return { ok = ok, pending = pending, reason = reason }
			end
			local function cancelPrepared(reason: string): Result
				local cancelled = receiptWrite(
					deps,
					tradeId,
					"cancelled",
					function(current: TradeReceipt?): TradeReceipt?
						if current == nil or current.phase ~= "prepared" then
							return nil
						end
						local nextReceipt = table.clone(current)
						nextReceipt.phase = "cancelled"
						return nextReceipt
					end
				)
				if cancelled == nil then
					return done(false, true, "cancel_pending")
				end
				local released = release(cancelled)
				if state ~= nil then
					local cancelledState = table.clone(state)
					cancelledState.phase = "cancelled"
					finish(tradeId, cancelledState)
				end
				return done(false, not released, reason)
			end
			if receipt == nil then
				if state == nil then
					return done(false, false, "trade_unknown")
				end
				if not liveSessions(state) then
					local cancelled = table.clone(state)
					cancelled.phase = "cancelled"
					finish(tradeId, cancelled)
					return done(false, false, "session_replaced")
				end
				local allowed, reason = admissible(deps, state)
				if not allowed then
					local cancelled = table.clone(state)
					cancelled.phase = "cancelled"
					finish(tradeId, cancelled)
					return done(false, false, reason)
				end
				receipt = receiptWrite(deps, tradeId, "prepared", function(previous: TradeReceipt?): TradeReceipt?
					if previous ~= nil then
						return nil
					end
					return {
						tradeId = tradeId,
						players = table.clone(state.players),
						offers = table.clone(state.offers),
						characters = assert(state.characters),
						revision = state.revision,
						expiresAt = state.expiresAt,
						phase = "prepared",
						grants = {},
					}
				end)
				if receipt == nil then
					return done(false, true, "receipt_unavailable")
				end
				if not validReceipt(receipt, tradeId, state) then
					return done(false, true, "receipt_invalid")
				end
			end
			if receipt == nil then
				return done(false, true, "receipt_unavailable")
			end
			if receipt.phase == "cancelled" then
				local released = release(receipt)
				if state ~= nil then
					local cancelled = table.clone(state)
					cancelled.phase = "cancelled"
					finish(tradeId, cancelled)
				end
				return done(false, not released, "trade_cancelled")
			end
			if receipt.phase == "prepared" then
				local preparedReceipt = receipt
				if state ~= nil and not liveSessions(state) then
					return cancelPrepared("session_replaced")
				end
				if deps.clock() >= receipt.expiresAt or cancelRequested[tradeId] then
					return cancelPrepared(if cancelRequested[tradeId] then "trade_cancelled" else "trade_expired")
				end
				for _, userId in receipt.players do
					if receiptProfile(receipt, userId) == nil then
						return done(false, true, "session_unavailable")
					end
					local result = checkedCommit(deps, userId, txId(tradeId, "hold", userId), function(profile)
						return holdWithPointer(profile, preparedReceipt.offers[userId], preparedReceipt)
					end, preparedReceipt)
					if not result.ok then
						if cancelRequested[tradeId] or deps.clock() >= receipt.expiresAt then
							return cancelPrepared(
								if cancelRequested[tradeId] then "trade_cancelled" else "trade_expired"
							)
						end
						if result.outcome == "rejected" then
							local cancelled = receiptWrite(
								deps,
								tradeId,
								"cancelled",
								function(current: TradeReceipt?): TradeReceipt?
									if current == nil or current.phase ~= "prepared" then
										return nil
									end
									local nextReceipt = table.clone(current)
									nextReceipt.phase = "cancelled"
									return nextReceipt
								end
							)
							if cancelled ~= nil then
								if state ~= nil then
									local cancelledState = table.clone(state)
									cancelledState.phase = "cancelled"
									finish(tradeId, cancelledState)
								end
								return done(false, not release(cancelled), "hold_rejected")
							end
						end
						return done(false, true, "hold_pending")
					end
					if cancelRequested[tradeId] or deps.clock() >= receipt.expiresAt then
						return cancelPrepared(if cancelRequested[tradeId] then "trade_cancelled" else "trade_expired")
					end
					if state ~= nil and not liveSessions(state) then
						return cancelPrepared("session_replaced")
					end
				end
				receipt = receiptWrite(deps, tradeId, "committed", function(current: TradeReceipt?): TradeReceipt?
					if current == nil or current.phase ~= "prepared" then
						return nil
					end
					local nextReceipt = table.clone(current)
					nextReceipt.phase = "committed"
					return nextReceipt
				end)
				if receipt == nil then
					return done(false, true, "commit_pending")
				end
				if not validReceipt(receipt, tradeId, state) then
					return done(false, true, "receipt_invalid")
				end
			end
			if receipt == nil then
				return done(false, true, "commit_pending")
			end
			if receipt.phase == "committed" then
				for _, userId in receipt.players do
					local currentReceipt = receipt
					if currentReceipt == nil then
						return done(false, true, "grant_pending")
					end
					if receiptProfile(currentReceipt, userId) ~= nil then
						if currentReceipt.grants[userId] ~= true then
							local otherId = if userId == currentReceipt.players[1]
								then currentReceipt.players[2]
								else currentReceipt.players[1]
							local result = checkedCommit(deps, userId, txId(tradeId, "grant", userId), function(profile)
								return credit(profile, currentReceipt.offers[otherId])
							end, currentReceipt)
							if not result.ok then
								return done(false, true, "grant_pending")
							end
							receipt = receiptWrite(
								deps,
								tradeId,
								"committed",
								function(current: TradeReceipt?): TradeReceipt?
									if current == nil or current.phase ~= "committed" then
										return nil
									end
									local updated = table.clone(current)
									local grants = table.clone(current.grants)
									grants[userId] = true
									updated.grants = grants
									return updated
								end
							)
							if receipt == nil or receipt.grants[userId] ~= true then
								return done(false, true, "grant_receipt_pending")
							end
						end
						local clearReceipt = receipt
						if clearReceipt == nil then
							return done(false, true, "grant_pending")
						end
						local cleared = checkedCommit(deps, userId, txId(tradeId, "clear", userId), function(source)
							local pointers = table.clone(accountOf(source).pending or {})
							pointers[tradeId] = nil
							return withPointers(source, pointers), nil
						end, clearReceipt)
						if not cleared.ok then
							return done(false, true, "cleanup_pending")
						end
					end
				end
				receipt = receiptRead(deps, tradeId)
				if
					receipt == nil
					or not validReceipt(receipt, tradeId, state)
					or receipt.grants[receipt.players[1]] ~= true
					or receipt.grants[receipt.players[2]] ~= true
				then
					return done(false, true, "grant_pending")
				end
				receipt = receiptWrite(deps, tradeId, "resolved", function(current: TradeReceipt?): TradeReceipt?
					if current == nil or current.phase ~= "committed" then
						return nil
					end
					local nextReceipt = table.clone(current)
					nextReceipt.phase = "resolved"
					return nextReceipt
				end)
				if receipt == nil then
					return done(false, true, "resolve_pending")
				end
				if not validReceipt(receipt, tradeId, state) then
					return done(false, true, "receipt_invalid")
				end
			end
			if receipt == nil then
				return done(false, true, "grant_pending")
			end
			if state ~= nil and receipt.phase == "resolved" then
				local settled = TradeCore.settled(state)
				finish(tradeId, if settled ~= nil then hosted(settled, state) else state)
			end
			local cleared = if receipt.phase == "resolved" then clearResolvedPointers(receipt) else false
			return done(cleared, not cleared, if cleared then nil else "cleanup_pending")
		end

		local function cancelOwned(tradeId: string): Result
			local state = trades[tradeId]
			local receipt, readable, readProblem = receiptRead(deps, tradeId)
			if not recoveryCurrent(tradeId) then
				return { ok = false, pending = true, reason = "session_replaced" }
			end
			if not readable then
				return { ok = false, pending = true, reason = readProblem or "receipt_unavailable" }
			end
			if receipt == nil then
				if state == nil then
					return { ok = false, reason = "trade_unknown" }
				end
				local cancelled = table.clone(state)
				cancelled.phase = "cancelled"
				finish(tradeId, cancelled)
				return { ok = true, state = cancelled }
			end
			if not validReceipt(receipt, tradeId, state) then
				return { ok = false, pending = true, reason = "receipt_invalid" }
			end
			if receipt.phase == "prepared" then
				local cancelled = receiptWrite(
					deps,
					tradeId,
					"cancelled",
					function(current: TradeReceipt?): TradeReceipt?
						if current == nil or current.phase ~= "prepared" then
							return nil
						end
						local nextReceipt = table.clone(current)
						nextReceipt.phase = "cancelled"
						return nextReceipt
					end
				)
				if cancelled == nil then
					return { ok = false, pending = true, reason = "cancel_pending" }
				end
			end
			return settleOwned(tradeId)
		end

		local function serialized(tradeId: string, operation: (string) -> Result, userId: number?): Result
			local state = trades[tradeId]
			local participants = if state ~= nil then state.players else nil
			if participants == nil and userId ~= nil then
				local profile = profileFor(deps, userId)
				local pointer = if profile ~= nil and type(accountOf(profile).pending) == "table"
					then (accountOf(profile).pending or {})[tradeId]
					else nil
				participants = if type(pointer) == "table" and type(pointer.receipt) == "table"
					then pointer.receipt.players
					else nil
			end
			if participants == nil and userId ~= nil then
				local receipt, readable = receiptRead(deps, tradeId)
				local projected = if readable then Receipt.project(receipt) else nil
				if projected ~= nil and table.find(projected.players, userId) ~= nil then
					participants = projected.players
				end
			end
			if participants == nil then
				return { ok = false, pending = true, reason = "session_unavailable" }
			end
			local sessions: { [number]: Context | false } = {}
			for _, participant in (participants or {}) do
				local context = deps.contextFor(participant)
				sessions[participant] = if context ~= nil then table.freeze(table.clone(context)) else false
			end
			recoverySessions[tradeId] = sessions
			inFlight[tradeId] = true
			local ok, result = pcall(operation, tradeId)
			inFlight[tradeId] = nil
			recoverySessions[tradeId] = nil
			cancelRequested[tradeId] = nil
			return if ok then result else { ok = false, pending = true, reason = "recovery_pending" }
		end

		local function settle(tradeId: string, userId: number?): Result
			if inFlight[tradeId] then
				return { ok = false, pending = true, reason = "trade_busy" }
			end
			return serialized(tradeId, settleOwned, userId)
		end

		local function cancelTrade(tradeId: string): Result
			if inFlight[tradeId] then
				cancelRequested[tradeId] = true
				return { ok = false, pending = true, reason = "cancel_pending" }
			end
			return serialized(tradeId, cancelOwned)
		end

		local function admit(userId: number): Result
			local profile = profileFor(deps, userId)
			if profile == nil then
				return { ok = false, pending = true, reason = "session_unavailable" }
			end
			local pointers = accountOf(profile).pending or {}
			if type(pointers) ~= "table" then
				return { ok = false, pending = true, reason = "pending_trades_invalid" }
			end
			local outcomes = {}
			for tradeId, pointer in pointers do
				if
					not opaque(tradeId)
					or type(pointer) ~= "table"
					or pointer.tradeId ~= tradeId
					or type(pointer.receipt) ~= "table"
					or not validReceipt(Receipt.project(pointer.receipt), tradeId, nil)
					or (pointer.receipt.players[1] ~= userId and pointer.receipt.players[2] ~= userId)
				then
					return { ok = false, pending = true, reason = "pending_trade_invalid" }
				end
				outcomes[tradeId] = settle(tradeId, userId)
			end
			return { ok = true, outcomes = outcomes }
		end

		local function playerRemoving(player: Subject): Result
			local readId, userId = pcall(function(): unknown
				return if deps.identity ~= nil then deps.identity(player) else (player).UserId
			end)
			if not readId or type(userId) ~= "number" or not whole(userId, 1, MAX_USER_ID) then
				return { ok = false, reason = "actor_invalid" }
			end
			local tradeId = active[userId]
			rates[userId] = nil
			return if tradeId ~= nil then cancelTrade(tradeId) else { ok = true }
		end

		local function sweepExpired(): number
			local expired = 0
			for tradeId, state in trades do
				if active[state.players[1]] == tradeId and deps.clock() >= state.expiresAt then
					cancelTrade(tradeId)
					expired += 1
				end
			end
			return expired
		end

		local function intent(player: Subject, request: unknown): Result
			local readId, userId = pcall(function(): unknown
				return if deps.identity ~= nil then deps.identity(player) else (player).UserId
			end)
			if
				not readId
				or type(userId) ~= "number"
				or not whole(userId, 1, MAX_USER_ID)
				or deps.playerFor(userId) ~= player
				or not rate(userId)
			then
				return { ok = false, reason = "rate_or_actor_invalid" }
			end
			if
				not exact(request, { kind = true, targetUserId = true, tradeId = true, revision = true, offer = true })
			then
				return { ok = false, reason = "request_invalid" }
			end
			local raw = Value.raw(request)
			if raw == nil then
				return { ok = false, reason = "request_invalid" }
			end
			if raw.kind == "open" then
				local firstProfile = profileFor(deps, userId)
				local secondProfile: Profile? = if type(raw.targetUserId) == "number"
						and whole(raw.targetUserId, 1, MAX_USER_ID)
					then profileFor(deps, raw.targetUserId)
					else nil
				if
					not exact(raw, { kind = true, targetUserId = true })
					or type(raw.targetUserId) ~= "number"
					or not whole(raw.targetUserId, 1, MAX_USER_ID)
					or active[userId] ~= nil
					or active[raw.targetUserId] ~= nil
					or firstProfile == nil
					or secondProfile == nil
					or (accountOf(firstProfile).pending ~= nil and type(accountOf(firstProfile).pending) ~= "table")
					or (accountOf(secondProfile).pending ~= nil and type(accountOf(secondProfile).pending) ~= "table")
					or next(accountOf(firstProfile).pending or {}) ~= nil
					or next(accountOf(secondProfile).pending or {}) ~= nil
					or not present(deps, userId, raw.targetUserId)
				then
					return { ok = false, reason = "trade_unavailable" }
				end
				local tradeId = deps.newId()
				local initial = TradeCore.empty(tradeId, userId, raw.targetUserId)
				if initial == nil then
					return { ok = false, reason = "trade_id_invalid" }
				end
				local state = hosted(initial, nil)
				state.expiresAt = deps.clock() + TRADE_TTL_SEC
				do
					local sessions: { [number]: Context } = {}
					local characters: { [number]: string } = {}
					state.sessions, state.characters = sessions, characters
					for _, id in state.players do
						local context = deps.contextFor(id)
						if
							context == nil
							or type(context.characterId) ~= "string"
							or type(context.sessionId) ~= "string"
							or type(context.acquisitionId) ~= "string"
							or type(context.leaseRevision) ~= "number"
						then
							return { ok = false, reason = "session_unavailable" }
						end
						sessions[id] = table.freeze(table.clone(context))
						characters[id] = context.characterId
					end
				end
				if active[userId] ~= nil or active[raw.targetUserId] ~= nil then
					return { ok = false, reason = "trade_unavailable" }
				end
				active[userId], active[raw.targetUserId] = tradeId, tradeId
				local existing, readable = receiptRead(deps, tradeId)
				if not readable or existing ~= nil or trades[tradeId] ~= nil or not liveSessions(state) then
					if active[userId] == tradeId then
						active[userId] = nil
					end
					if active[raw.targetUserId] == tradeId then
						active[raw.targetUserId] = nil
					end
					return { ok = false, reason = "trade_id_unavailable" }
				end
				trades[tradeId] = state
				active[userId] = tradeId
				active[raw.targetUserId] = tradeId
				if type(deps.schedule) == "function" then
					deps.schedule(TRADE_TTL_SEC, function()
						if active[userId] == tradeId then
							cancelTrade(tradeId)
						end
					end)
				end
				return { ok = true, tradeId = tradeId, state = state }
			end
			if
				type(raw.tradeId) ~= "string"
				or not opaque(raw.tradeId)
				or not exact(raw, {
					kind = true,
					tradeId = true,
					revision = true,
					offer = true,
				})
			then
				return { ok = false, reason = "request_invalid" }
			end
			local state = trades[raw.tradeId]
			if state == nil or active[userId] ~= raw.tradeId then
				return { ok = false, reason = "trade_unknown" }
			end
			if raw.kind == "cancel" then
				if raw.offer ~= nil or raw.revision ~= state.revision then
					return { ok = false, reason = "revision_stale" }
				end
				return cancelTrade(raw.tradeId)
			end
			if not liveSessions(state) then
				cancelTrade(raw.tradeId)
				return { ok = false, reason = "session_replaced" }
			end
			if deps.clock() >= state.expiresAt then
				cancelTrade(raw.tradeId)
				return { ok = false, reason = "trade_expired" }
			end
			if not present(deps, state.players[1], state.players[2]) then
				return { ok = false, reason = "trade_unavailable" }
			end
			if active[userId] ~= raw.tradeId or deps.playerFor(userId) ~= player then
				return { ok = false, reason = "trade_unknown" }
			end
			if trades[raw.tradeId] ~= state then
				return { ok = false, reason = "revision_stale" }
			end
			if not liveSessions(state) then
				cancelTrade(raw.tradeId)
				return { ok = false, reason = "session_replaced" }
			end
			if deps.clock() >= state.expiresAt then
				cancelTrade(raw.tradeId)
				return { ok = false, reason = "trade_expired" }
			end
			if raw.kind == "offer" and TradeCore.offer(raw.offer) == nil then
				return { ok = false, reason = "offer_invalid" }
			end
			local nextStateValue, reason = TradeCore.step(state, userId, {
				kind = raw.kind,
				revision = raw.revision,
				offer = raw.offer,
			})
			if nextStateValue == nil then
				return { ok = false, reason = reason }
			end
			local nextState = hosted(nextStateValue, state)
			if nextState.phase == "cancelled" then
				finish(raw.tradeId, nextState)
				return { ok = true, state = nextState }
			end
			trades[raw.tradeId] = nextState
			if nextState.phase == "confirmed" then
				local result = settle(raw.tradeId)
				return {
					ok = result.ok,
					pending = result.pending,
					reason = result.reason,
					state = trades[raw.tradeId],
				}
			end
			return { ok = true, state = nextState }
		end

		return table.freeze({
			intent = intent,
			recover = settle,
			admit = admit,
			playerRemoving = playerRemoving,
			sweepExpired = sweepExpired,
			state = function(tradeId: string): State?
				return trades[tradeId]
			end,
			stateFor = function(userId: number): State?
				return if active[userId] ~= nil then trades[active[userId]] else nil
			end,
		}),
			nil
	end

	TradeService.MAX_DISTANCE = MAX_DISTANCE
	TradeService.RATE_LIMIT = RATE_LIMIT
	TradeService.TRADE_TTL_SEC = TRADE_TTL_SEC
	return table.freeze(TradeService)
end

return table.freeze({ configure = configure })
