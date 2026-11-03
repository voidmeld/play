--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Exchange = require("../core/trade/exchange")
local Receipt = require("../core/trade/receipt")
local Trade = require("./trade")
local Transfer = require("./profile-transfer")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Profile = { account: Trade.Account, recorded: { [string]: boolean }, group: string }
type Surface = { [number]: Profile }
local exchange =
	Exchange.exchange({ maxItems = 3, maxCount = 10, maxCoin = 100, maxUserId = 100, maxRevision = 100, idLimit = 32 })
local receipts = Receipt.receipts({
	offer = exchange.offer,
	tradeIdLimit = 32,
	characterIdLimit = 32,
	maxUserId = 100,
	maxRevision = 100,
	maxTimestamp = 10000,
	maxPointers = 8,
})

local function rig()
	local profiles: Surface = {
		[1] = { account = { coin = 20, inventory = { ore = 3 }, pending = {} }, recorded = {}, group = "alpha" },
		[2] = { account = { coin = 20, inventory = { wood = 2 }, pending = {} }, recorded = {}, group = "alpha" },
	}
	local contexts: { [number]: Trade.Context } = {}
	local players: { [number]: Trade.Subject } = { [1] = { UserId = 1 }, [2] = { UserId = 2 } }
	for id in players do
		contexts[id] = {
			userId = id,
			characterId = "character-" .. id,
			key = "profile-" .. id,
			sessionId = "session-" .. id,
			acquisitionId = "acquisition-" .. id,
			leaseRevision = 1,
		}
	end
	local store: { [string]: Receipt.Projected } = {}
	local fail: { [string]: boolean } = {}
	local now, sequence = 100, 0
	local blocked, ambiguous = false, false
	local function contextFor(id: number): Trade.Context?
		return contexts[id]
	end
	local host = Trade.configure({
		exchange = exchange,
		receipts = receipts,
		account = function(profile: Profile): Trade.Account
			return profile.account
		end,
		withAccount = function(profile: Profile, account: Trade.Account): Profile
			return { account = account, recorded = profile.recorded, group = profile.group }
		end,
		capacity = function(_profile: Profile): number
			return 3
		end,
		entries = function(bag: { [string]: number }): number
			local count = 0
			for _ in bag do
				count += 1
			end
			return count
		end,
		unboundCount = function(profile: Profile, id: string): number
			return profile.account.inventory[id] or 0
		end,
		related = function(first: Profile, second: Profile): boolean
			return first.group == second.group
		end,
		recorded = function(profile: Profile, id: string): boolean
			return profile.recorded[id] == true
		end,
		profileFor = function(
			surface: Surface,
			resolve: (number) -> Trade.Context?,
			id: number
		): (Profile?, Trade.Context?)
			local context = resolve(id)
			return if context ~= nil then surface[id] else nil, context
		end,
		commit = function(
			surface: Surface,
			context: Trade.Context,
			id: string,
			effect: Trade.Effect<Profile>
		): Transfer.Result
			if not Transfer.sameSession(contexts[context.userId], context) then
				return { ok = false, outcome = "rejected", reason = "session_replaced" }
			end
			local profile = surface[context.userId]
			if profile.recorded[id] then
				return { ok = true, outcome = "replayed" }
			end
			if fail[id] then
				return { ok = false, outcome = "not_durable", reason = "save_failed" }
			end
			local nextProfile, reason = effect(profile)
			if nextProfile == nil then
				return { ok = false, outcome = "rejected", reason = reason }
			end
			local recorded = table.clone(nextProfile.recorded)
			recorded[id] = true
			surface[context.userId] = { account = nextProfile.account, group = nextProfile.group, recorded = recorded }
			return { ok = true, outcome = "committed" }
		end,
		receiptKey = function(id: string): string
			return "receipt:" .. id
		end,
		transactionId = function(id: string, phase: string, user: number): string
			return id .. ":" .. phase .. ":" .. user
		end,
		maxCoin = 100,
		maxUserId = 100,
		maxStack = 10,
		maxDistance = 8,
		idLimit = 32,
		maxRecoverySlots = 8,
		maxCompleted = 4,
		rateWindowSec = 1,
		rateLimit = 20,
		tradeTtlSec = 20,
	})
	local deps: Trade.Dependencies<Profile, Surface> = {
		profiles = profiles,
		receipts = {
			getOutcome = function(key: string): Trade.ReceiptOutcome
				return if blocked then { ok = false, reason = "store_failure" } else { ok = true, value = store[key] }
			end,
			updateOutcome = function(
				key: string,
				apply: (Receipt.Projected?) -> Receipt.Projected?
			): Trade.ReceiptOutcome
				local nextReceipt = apply(store[key])
				if nextReceipt == nil then
					return { ok = false, reason = "callback_cancelled" }
				end
				store[key] = nextReceipt
				if ambiguous then
					ambiguous = false
					return { ok = false, reason = "store_failure" }
				end
				return { ok = true, value = nextReceipt }
			end,
		},
		contextFor = contextFor,
		playerFor = function(id: number): Trade.Subject?
			return players[id]
		end,
		positionFor = function(_id: number): Trade.Location?
			return { x = 0, y = 0, z = 0 }
		end,
		allowed = function(_id: number): boolean
			return true
		end,
		tradeable = function(_id: number, _profile: Profile, item: string, _count: number): boolean
			return item ~= "bound"
		end,
		newId = function(): string
			sequence += 1
			return "exchange-" .. sequence
		end,
		clock = function(): number
			return now
		end,
	}
	return {
		service = assert(host.create(deps)),
		profiles = profiles,
		contexts = contexts,
		players = players,
		fail = fail,
		store = store,
		restart = function()
			return assert(host.create(deps))
		end,
		block = function(value: boolean)
			blocked = value
		end,
		ambiguous = function()
			ambiguous = true
		end,
		advance = function()
			now += 21
		end,
	}
end

local function ready(service: Trade.Service, players: { [number]: Trade.Subject }): string
	local opened = service.intent(players[1], { kind = "open", targetUserId = 2 })
	assert(opened.ok, opened.reason)
	local id = assert(opened.tradeId)
	assert(service.intent(players[1], {
		kind = "offer",
		tradeId = id,
		revision = 0,
		offer = { coin = 5, items = { { itemId = "ore", count = 2 } } },
	}).ok)
	assert(service.intent(players[2], {
		kind = "offer",
		tradeId = id,
		revision = 1,
		offer = { coin = 2, items = { { itemId = "wood", count = 1 } } },
	}).ok)
	for _, kind in { "lock", "confirm" } do
		for userId = 1, if kind == "lock" then 2 else 1 do
			local player = players[userId]
			assert(service.intent(player, { kind = kind, tradeId = id, revision = 2 }).ok)
		end
	end
	return id
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("trade host", function()
		it("conserves both accounts and makes recovery replay safe", function()
			local scene = rig()
			local id = ready(scene.service, scene.players)
			expect(scene.service.intent(scene.players[2], { kind = "confirm", tradeId = id, revision = 2 }).ok):toBe(
				true
			)
			expect(scene.profiles[1].account.coin):toBe(17)
			expect(scene.profiles[2].account.coin):toBe(23)
			expect(scene.profiles[1].account.inventory):toEqual({ ore = 1, wood = 1 })
			expect(scene.profiles[2].account.inventory):toEqual({ ore = 2, wood = 1 })
			local first = scene.profiles[1]
			expect(scene.service.recover(id).ok):toBe(true)
			expect(scene.profiles[1]):toBe(first)
		end)
		it("retains a committed decision across grant failure and fresh admission", function()
			local scene = rig()
			local id = ready(scene.service, scene.players)
			scene.fail[id .. ":grant:2"] = true
			expect(scene.service.intent(scene.players[2], { kind = "confirm", tradeId = id, revision = 2 }).pending):toBe(
				true
			)
			expect(scene.store["receipt:" .. id].phase):toBe("committed")
			scene.fail[id .. ":grant:2"] = nil
			local restarted = scene.restart()
			expect(restarted.admit(2).ok):toBe(true)
			expect(scene.profiles[2].account.coin):toBe(23)
			expect(restarted.admit(2).ok):toBe(true)
			expect(scene.profiles[2].account.coin):toBe(23)
		end)
		it("fails closed while the receipt cannot be read then reconciles an uncertain write", function()
			local scene = rig()
			local id = ready(scene.service, scene.players)
			scene.block(true)
			expect(scene.service.intent(scene.players[2], { kind = "confirm", tradeId = id, revision = 2 }).ok):toBe(
				false
			)
			expect(scene.profiles[1].account.coin):toBe(20)
			scene.block(false)
			scene.ambiguous()
			expect(scene.service.recover(id).ok):toBe(true)
			expect(scene.profiles[1].account.coin + scene.profiles[2].account.coin):toBe(40)
		end)
		it("cancels reviewed consent when the captured session changes", function()
			local scene = rig()
			local id = ready(scene.service, scene.players)
			local prior = scene.contexts[1]
			scene.contexts[1] = {
				userId = prior.userId,
				characterId = prior.characterId,
				key = prior.key,
				sessionId = prior.sessionId,
				acquisitionId = prior.acquisitionId,
				leaseRevision = prior.leaseRevision + 1,
			}
			expect(scene.service.intent(scene.players[2], { kind = "confirm", tradeId = id, revision = 2 }).reason):toBe(
				"session_replaced"
			)
			expect(scene.profiles[1].account.coin):toBe(20)
		end)
		it("expires active offers without transferring either account", function()
			local scene = rig()
			ready(scene.service, scene.players)
			scene.advance()
			expect(scene.service.sweepExpired()):toBe(1)
			expect(scene.service.stateFor(1)):toBeNil()
			expect(scene.profiles[1].account.coin):toBe(20)
		end)
	end)
end
