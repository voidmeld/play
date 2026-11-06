--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Books = require("../core/market/book")
local Host = require("./market-settlement")
local Verify = require("../../.lute/dependencies/verify/src/core")
local Wallets = require("../core/market/wallet")

local book = Books.book({
	listingTtlSec = 50,
	minFeeBps = 0,
	maxFeeBps = 1000,
	defaultFeeBps = 500,
	maxListings = 20,
	maxReceipts = 40,
	operationRetentionSec = 1000,
	actorWindowSec = 100,
	maxReceiptsPerOwner = 20,
	maxOperations = 100,
	maxOperationsPerActor = 50,
	maxListingsPerSeller = 5,
	maxCount = 100,
	maxPrice = 100,
	maxId = 64,
	maxTime = 100000,
	maxCoin = 10000,
	categoryPrefix = "category.",
	maxSearch = 10,
	realms = { north = true },
})
local wallet = Wallets.wallet({
	claimedWindow = 50,
	healRetentionSec = 500,
	maxPending = 8,
	maxId = 64,
	maxCount = 100,
	maxCoin = 10000,
	maxTime = 100000,
	realms = { north = true },
})
local coordinator = Host.configure({ wallet = wallet, receiptsFor = book.receiptsFor, healRetentionSec = 500 })

local function rig()
	local state = assert(book.emptyState("north", "ore"))
	local accounts: { [number]: Wallets.State } = {
		[1] = assert(wallet.emptyState(1, 100, { ore = 5 })),
		[2] = assert(wallet.emptyState(2, 100, {})),
	}
	local sequence, now = 0, 100
	local uncertain, unavailable = false, false
	local faults: { [number]: boolean } = {}
	local bookPort: Host.BookService = {
		read = function(_realm: string, _material: string): Host.BookResult
			return { ok = true, state = state, replayed = false, ambiguous = false }
		end,
		apply = function(_realm: string, _material: string, command: unknown): Host.BookResult
			if unavailable then
				return { ok = false, replayed = false, ambiguous = true, reason = "store_unavailable" }
			end
			local applied = book.apply(state, command, now)
			if applied.state ~= nil then
				state = applied.state
			end
			if uncertain then
				uncertain = false
				return { ok = false, replayed = false, ambiguous = true, reason = "reply_lost" }
			end
			return {
				ok = applied.ok,
				state = applied.state,
				replayed = applied.replayed,
				ambiguous = false,
				receipts = applied.receipts,
				reason = applied.reason,
				fence = applied.fence,
			}
		end,
	}
	local function connect(id: number): Host.Service
		return assert(coordinator.create({
			book = bookPort,
			wallet = {
				read = function(): Wallets.State?
					return accounts[id]
				end,
				write = function(updated: Wallets.State): boolean
					if faults[id] then
						return false
					end
					accounts[id] = updated
					return true
				end,
				room = function(_item: string): number
					return 100
				end,
			},
			clock = function(): number
				return now
			end,
			newOpId = function(): string
				sequence += 1
				return "operation-" .. sequence
			end,
		}))
	end
	return {
		first = connect(1),
		second = connect(2),
		accounts = accounts,
		faults = faults,
		state = function()
			return state
		end,
		restart = connect,
		uncertain = function()
			uncertain = true
		end,
		unavailable = function(value: boolean)
			unavailable = value
		end,
		advance = function()
			now += 501
		end,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("market settlement host", function()
		it("conserves goods and coin through listing, purchase and receipt acknowledgment", function()
			local scene = rig()
			expect(scene.first.consign("north", "ore", 2, 5).ok):toBe(true)
			expect(scene.second.buy("north", "ore", 2, 5).ok):toBe(true)
			expect(scene.first.claimAll("north", "ore").ok):toBe(true)
			expect(scene.second.claimAll("north", "ore").ok):toBe(true)
			expect(scene.accounts[1].goods.ore):toBe(3)
			expect(scene.accounts[2].goods.ore):toBe(2)
			expect(scene.accounts[1].coin + scene.accounts[2].coin + scene.state().burnedCoin):toBe(200)
			local before = scene.accounts[1]
			expect(scene.first.claimAll("north", "ore").ok):toBe(true)
			expect(scene.accounts[1]):toBe(before)
		end)
		it("reconciles a lost listing reply with a durable known fence", function()
			local scene = rig()
			scene.uncertain()
			expect(scene.first.consign("north", "ore", 2, 5).pending):toBe(true)
			expect(scene.accounts[1].goods.ore):toBe(3)
			expect(scene.restart(1).heal().ok):toBe(true)
			expect(scene.accounts[1].pending):toEqual({})
			expect(scene.accounts[1].goods.ore):toBe(3)
		end)
		it("keeps an ambiguous absent operation held until a void fence commits", function()
			local scene = rig()
			scene.unavailable(true)
			expect(scene.first.consign("north", "ore", 2, 5).pending):toBe(true)
			expect(scene.first.heal().pending):toBe(true)
			expect(scene.accounts[1].goods.ore):toBe(3)
			scene.unavailable(false)
			expect(scene.first.heal().ok):toBe(true)
			expect(scene.accounts[1].goods.ore):toBe(5)
			expect(scene.first.heal().ok):toBe(true)
			expect(scene.accounts[1].goods.ore):toBe(5)
		end)
		it("leaves old ambiguous holds for audit and refuses an undurable initial debit", function()
			local scene = rig()
			scene.faults[1] = true
			expect(scene.first.consign("north", "ore", 2, 5).ok):toBe(false)
			expect(#scene.state().listings):toBe(0)
			scene.faults[1] = nil
			scene.unavailable(true)
			expect(scene.first.consign("north", "ore", 2, 5).pending):toBe(true)
			scene.advance()
			scene.unavailable(false)
			expect(scene.first.heal().ok):toBe(true)
			expect(scene.accounts[1].goods.ore):toBe(3)
			expect(next(scene.accounts[1].pending) ~= nil):toBe(true)
		end)
	end)
end
