--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Books = require("./book")
local Conservation = require("./conservation")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local Wallets = require("./wallet")

local book = Books.book({
	listingTtlSec = 10,
	legacyListingTtlSec = 20,
	minFeeBps = 300,
	maxFeeBps = 500,
	defaultFeeBps = 500,
	legacyFeeBps = 400,
	maxListings = 10,
	maxReceipts = 30,
	operationRetentionSec = 50,
	actorWindowSec = 10,
	maxReceiptsPerOwner = 10,
	maxOperations = 30,
	maxOperationsPerActor = 10,
	maxListingsPerSeller = 10,
	maxCount = 100,
	maxPrice = 100,
	maxId = 30,
	maxTime = 100,
	maxCoin = 1000,
	categoryPrefix = "category.",
	maxSearch = 10,
	realms = { zone = true },
})
local wallet = Wallets.wallet({
	claimedWindow = 30,
	healRetentionSec = 40,
	maxPending = 10,
	maxId = 30,
	maxCount = 100,
	maxCoin = 1000,
	maxTime = 100,
	realms = { zone = true },
})
local audit = Conservation.conservation({ projectBook = book.projectState, projectWallet = wallet.projectState })

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("conservation", function()
		it("conserves goods and coin through holds, listings, settlement, claims and acknowledgement", function(own)
			local seller = assert(wallet.emptyState(1, 0, { ore = 3 }))
			local buyer = assert(wallet.emptyState(2, 20, {}))
			local state = assert(book.emptyState("zone", "ore", nil))
			local function conserved()
				expect(audit.audit({ seller, buyer }, { state }, { coin = 20, goods = { ore = 3 } }).ok):toBe(true)
			end
			conserved()
			seller = assert(wallet.beginConsign(seller, "l", "zone", "ore", 2, 0).state)
			conserved()
			state = assert(
				book.apply(
					state,
					{ kind = "list", opId = "l", actorId = 1, actorRealmId = "zone", count = 2, unitPrice = 5 },
					0
				).state
			)
			conserved()
			seller = assert(wallet.settleConsign(seller, "l").state)
			buyer = assert(wallet.beginBuy(buyer, "b", "zone", "ore", 20, 0).state)
			conserved()
			state = assert(book.apply(state, {
				kind = "fill",
				opId = "b",
				actorId = 2,
				actorRealmId = "zone",
				quantity = 2,
				ceilingUnitPrice = 5,
				holdCoin = 20,
			}, 0).state)
			conserved()
			for _, receipt in state.receipts do
				if receipt.ownerId == 1 then
					seller = assert(wallet.claim(seller, receipt, "ore").state)
				else
					buyer = assert(wallet.claim(buyer, receipt, "ore").state)
				end
				conserved()
			end
			state = assert(
				book.apply(state, { kind = "ack", opId = "a1", actorId = 1, receiptIds = { "b:proceeds:1" } }, 0).state
			)
			state = assert(
				book.apply(state, { kind = "ack", opId = "a2", actorId = 2, receiptIds = { "b:purchase" } }, 0).state
			)
			conserved()
		end)

		it("counts expired returns once before and after their owner claims them", function()
			local seller = assert(wallet.emptyState(1, 0, {}))
			local state = assert(
				book.apply(
					book.emptyState("zone", "ore", nil),
					{ kind = "list", opId = "l", actorId = 1, actorRealmId = "zone", count = 1, unitPrice = 1 },
					0
				).state
			)
			state = assert(book.apply(state, { kind = "sweep", opId = "s" }, 10).state)
			expect(audit.audit({ seller }, { state }, { coin = 0, goods = { ore = 1 } }).ok):toBe(true)
			seller = assert(wallet.claim(seller, state.receipts[1], "ore").state)
			expect(audit.audit({ seller }, { state }, { coin = 0, goods = { ore = 1 } }).ok):toBe(true)
		end)

		it("reports malformed inputs, invalid projected values and imbalance reasons", function()
			local _, reason = audit.measure(false, {})
			expect(reason):toBe("input_invalid")
			_, reason = audit.measure({ false }, {})
			expect(reason):toBe("wallet_invalid")
			_, reason = audit.measure({}, { false })
			expect(reason):toBe("book_invalid")
			expect(audit.audit({}, {}, { coin = 1, goods = {} }).reason):toBe("coin_unbalanced")
			expect(audit.audit({}, {}, { coin = 0, goods = { ore = 1 } }).reason):toBe("goods_unbalanced:ore")
			expect(audit.audit(false, {}, { coin = 0, goods = {} }).reason):toBe("input_invalid")
			local custom = Conservation.conservation({
				projectBook = function(_value: unknown): Books.State?
					return nil
				end,
				projectWallet = wallet.projectState,
			})
			_, reason = custom.measure({}, { book.emptyState("zone", "ore", nil) })
			expect(reason):toBe("book_invalid")
		end)
	end)
end
