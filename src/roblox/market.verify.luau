--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Books = require("../core/market/book")
local Host = require("./market")
local Settlement = require("./market-settlement")
local Verify = require("../../.lute/dependencies/verify/src/core")
local Wallets = require("../core/market/wallet")

type Rarity = "plain" | "special"
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
local settlement = Settlement.configure({ wallet = wallet, receiptsFor = book.receiptsFor, healRetentionSec = 500 })

local function rig()
	local accounts: { [number]: Wallets.State } = {
		[1] = assert(wallet.emptyState(1, 100, { ore = 5, blade = 1 })),
		[2] = assert(wallet.emptyState(2, 100, {})),
	}
	local states: { [string]: Books.State } = {}
	local defs: { [string]: Host.Item<Rarity> } = {
		blade = { id = "blade", name = "Blade", rarity = "special", slot = "hand", levelReq = 2, sellValue = 3 },
	}
	local now, sequence = 100, 0
	local permitted = true
	local host = Host.configure({
		items = {
			get = function(id: string): Host.Item<Rarity>?
				return defs[id]
			end,
		},
		goods = {
			bookIds = function(): { string }
				return { "category.equipment" }
			end,
			isCategoryBook = function(id: unknown): boolean
				return id == "category.equipment"
			end,
			bookFor = function(value: unknown): (string?, string?)
				return if value ~= nil then "category.equipment" else nil, nil
			end,
		},
		matchesItem = function(item: Host.Item<Rarity>, query: Host.ItemFilters): boolean
			return (query.rarity == nil or item.rarity == query.rarity)
				and (query.minLevel == nil or (item.levelReq or 0) >= query.minLevel)
		end,
		settlement = settlement,
		search = book.search,
		npcTrade = wallet.npcTrade,
		feeBps = 500,
		joinRetrySec = 5,
		maxActiveListings = 5,
		maxCatalogUnitPrice = 100,
		maxSearchLimit = 10,
		maxSearchPrice = 100,
	})
	local port: Settlement.BookService = {
		read = function(realm: string, id: string): Settlement.BookResult
			local key = realm .. ":" .. id
			if states[key] == nil then
				states[key] = assert(book.emptyState(realm, id))
			end
			return { ok = true, state = states[key], replayed = false, ambiguous = false }
		end,
		apply = function(realm: string, id: string, command: unknown): Settlement.BookResult
			local key = realm .. ":" .. id
			local applied = book.apply(states[key] or book.emptyState(realm, id), command, now)
			if applied.state ~= nil then
				states[key] = applied.state
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
	local service = assert(host.mount({
		book = port,
		catalog = {
			materials = { { id = "ore", label = "Ore", npcFloor = 1, npcCeiling = 4 } },
			maxQuantity = 10,
			maxUnitPrice = 100,
			visibleListings = 5,
			searchLimit = 10,
		},
		walletFor = function(id: number): Host.Wallet?
			if accounts[id] == nil then
				return nil
			end
			return {
				read = function(): Wallets.State?
					return accounts[id]
				end,
				write = function(updated: Wallets.State): boolean
					accounts[id] = updated
					return true
				end,
				room = function(_item: string): number
					return 10
				end,
			}
		end,
		realmFor = function(_id: number): string?
			return "north"
		end,
		clock = function(): number
			return now
		end,
		newOpId = function(): string
			sequence += 1
			return "operation-" .. sequence
		end,
		tradingAllowed = function(_id: number): boolean
			return permitted
		end,
	}))
	return {
		service = service,
		accounts = accounts,
		deny = function()
			permitted = false
		end,
		advance = function()
			now += 1
		end,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("market host", function()
		it("lists and buys configured item facts with the consumer's rarity type", function()
			local scene = rig()
			expect(scene.service.listItem(1, "blade", 1, 5).ok):toBe(true)
			expect(scene.service.join(2).ok):toBe(true)
			local page = scene.service.searchItems(2, { rarity = "special" })
			expect(page.ok):toBe(true)
			expect(page.total):toBe(1)
			expect(page.rows[1].rarity):toBe("special")
			expect(scene.service.buyItem(2, "blade", 1, 5).ok):toBe(true)
			expect(scene.accounts[2].goods.blade):toBe(1)
			expect(scene.service.refresh(1).ok):toBe(true)
			expect(scene.accounts[1].coin):toBe(104)
		end)
		it("admits material merchant trades independently from shared-book trading policy", function()
			local scene = rig()
			scene.deny()
			expect(scene.service.list(1, "ore", 1, 5).ok):toBe(false)
			expect(scene.service.npcSell(1, "ore", 1).ok):toBe(true)
			expect(scene.accounts[1].coin):toBe(101)
			expect(scene.service.npcBuy(1, "ore", 1).ok):toBe(true)
			expect(scene.accounts[1].coin):toBe(97)
		end)
		it("rejects forged filters and detaches item projections from profile authority", function()
			local scene = rig()
			expect(scene.service.searchItems(1, { forged = true }).ok):toBe(false)
			local listable = scene.service.listable(1)
			expect(#listable):toBe(1)
			expect(listable[1].count):toBe(1)
			expect(scene.service.searchItems(1, { page = -1 }).ok):toBe(false)
			expect(scene.accounts[1].goods.blade):toBe(1)
		end)
		it("claims and projects material books across forgetting and readmission", function()
			local scene = rig()
			expect(scene.service.list(1, "ore", 2, 5).ok):toBe(true)
			expect(scene.service.join(2).ok):toBe(true)
			expect(scene.service.buy(2, "ore", 2, 5).ok):toBe(true)
			scene.service.forget(2)
			expect(scene.service.join(2).ok):toBe(true)
			expect(scene.service.projection(2).materials[1].held):toBe(2)
		end)
	end)
end
