--!strict

local Books = require("./book")
local settings: Books.Config = {
	listingTtlSec = 48 * 60 * 60,
	legacyListingTtlSec = 72 * 60 * 60,
	minFeeBps = 300,
	maxFeeBps = 500,
	defaultFeeBps = 500,
	legacyFeeBps = 400,
	maxListings = 600,
	maxReceipts = 2000,
	operationRetentionSec = 45 * 24 * 60 * 60,
	actorWindowSec = 24 * 60 * 60,
	maxReceiptsPerOwner = 160,
	maxOperations = 4096,
	maxOperationsPerActor = 256,
	maxListingsPerSeller = 20,
	maxCount = 1000000,
	maxPrice = 1000000000,
	maxId = 128,
	maxTime = 1000000000000,
	maxCoin = 1000000000000,
	categoryPrefix = "category.",
	maxSearch = 20,
	realms = { north = true, south = true, east = true },
}
local Book = Books.book(settings)
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local T0 = 1000
type State = Books.State
type Receipt = Books.Receipt
type Listing = Books.Listing

local function receipt(value: Receipt): Receipt
	return value
end

local function empty(): State
	return assert(Book.emptyState("north", "ore"))
end

local function list(
	state: unknown,
	opId: string,
	sellerId: number,
	count: number,
	unitPrice: number,
	at: number
): Books.Result
	return Book.apply(state, {
		kind = "list",
		opId = opId,
		actorId = sellerId,
		actorRealmId = "north",
		count = count,
		unitPrice = unitPrice,
	}, at)
end

local function fill(
	state: State?,
	opId: string,
	buyerId: number,
	quantity: number,
	ceiling: number,
	hold: number,
	at: number
): Books.Result
	return Book.apply(state, {
		kind = "fill",
		opId = opId,
		actorId = buyerId,
		actorRealmId = "north",
		quantity = quantity,
		ceilingUnitPrice = ceiling,
		holdCoin = hold,
	}, at)
end

local function seeded(): State
	local state = list(empty(), "l1", 11, 3, 10, T0).state
	state = list(state, "l2", 12, 5, 8, T0 + 1).state
	state = list(state, "l3", 13, 4, 8, T0 + 2).state
	return assert(state)
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("book", function()
		do
			it("lists into a 48-hour realm-local book at the default 5% burning cut", function(own)
				local result = list(empty(), "l1", 11, 3, 10, T0)
				expect(result.ok):toBe(true)
				local listing = (assert(result.state)).listings[1]
				expect(listing.listingId):toBe("l1")
				expect((listing.expiresAtSec - listing.listedAtSec)):toBe(48 * 60 * 60)
				expect((assert(result.state)).feeBps):toBe(500)
				expect((Book.emptyState("north", "ore", 200))):toBeNil()
				expect((Book.emptyState("north", "ore", 600))):toBeNil()
				expect((Book.emptyState("north", "ore", 300) ~= nil)):toBe(true)
			end)

			it("fills a bundle cheapest first, then by listing time, burning the cut per seller", function(own)
				local result = fill(seeded(), "b1", 20, 7, 10, 70, T0 + 10)
				expect(result.ok):toBe(true)
				local proceeds: { [number]: number } = {}
				local purchase: Receipt? = nil
				for _, receipt in assert(result.receipts) do
					if receipt.kind == "proceeds" then
						proceeds[receipt.ownerId] = receipt.coin
					elseif receipt.kind == "purchase" then
						purchase = receipt
					end
				end
				expect(proceeds[12]):toBe(40 - 2)
				expect(proceeds[13]):toBe(16 - 1)
				expect(proceeds[11]):toBeNil()
				expect((assert(purchase)).goods):toBe(7)
				expect((assert(purchase)).coin):toBe(56)
				expect((assert(result.state)).burnedCoin):toBe(3)
				expect(#(assert(result.state)).listings):toBe(2)
				expect((assert(result.state)).listings[2].count):toBe(2)
			end)

			it("fills partially when supply under the ceiling is short and refuses when none is left", function(own)
				local partial = fill(seeded(), "b1", 20, 50, 8, 400, T0 + 10)
				expect(partial.ok):toBe(true)
				expect((assert(partial.receipts))[#(assert(partial.receipts))].goods):toBe(9)
				expect(fill(seeded(), "b2", 20, 1, 7, 7, T0 + 10).reason):toBe("no_supply")
			end)

			it("never fills from the buyer's own listings and refuses a foreign realm or a short hold", function()
				local own = list(empty(), "l1", 20, 3, 5, T0).state
				expect(fill(own, "b1", 20, 1, 5, 5, T0 + 1).reason):toBe("no_supply")
				local foreign = Book.apply(seeded(), {
					kind = "fill",
					opId = "b1",
					actorId = 20,
					actorRealmId = "south",
					quantity = 1,
					ceilingUnitPrice = 10,
					holdCoin = 10,
				}, T0 + 10)
				expect(foreign.reason):toBe("realm_foreign")
				expect(fill(seeded(), "b1", 20, 7, 10, 55, T0 + 10).reason):toBe("hold_insufficient")
				local foreignList = Book.apply(empty(), {
					kind = "list",
					opId = "l1",
					actorId = 11,
					actorRealmId = "east",
					count = 1,
					unitPrice = 1,
				}, T0)
				expect(foreignList.reason):toBe("realm_foreign")
			end)
		end

		do
			it("returns an expired listing's goods once as a return receipt", function(own)
				local state = list(empty(), "l1", 11, 3, 10, T0).state
				local later = Book.apply(state, { kind = "sweep", opId = "s1" }, T0 + settings.listingTtlSec)
				expect(#(assert(later.state)).listings):toBe(0)
				local receipts = assert(Book.receiptsFor(later.state, 11))
				expect(#receipts):toBe(1)
				expect(receipts[1].kind):toBe("return")
				expect(receipts[1].goods):toBe(3)
				local again = Book.apply(later.state, { kind = "sweep", opId = "s2" }, T0 + settings.listingTtlSec + 5)
				expect(#(assert(Book.receiptsFor(again.state, 11)))):toBe(1)
				expect(fill(later.state, "b1", 20, 1, 10, 10, T0 + settings.listingTtlSec).reason):toBe("no_supply")
			end)

			it(
				"reads a stored book written under the earlier 72-hour window and 4% cut and sells under the current cut",
				function(own)
					local state = list(empty(), "l1", 11, 3, 100, T0).state
					local legacy = table.clone(assert(state))
					legacy.feeBps = 400
					legacy.listings = { table.clone((assert(state)).listings[1]) }
					legacy.listings[1].expiresAtSec = T0 + 72 * 60 * 60
					local read = Book.projectState(legacy)
					expect((read ~= nil)):toBe(true)
					expect((assert(read)).feeBps):toBe(settings.defaultFeeBps)
					local sold = fill(legacy, "b1", 20, 3, 100, 300, T0 + 10)
					expect(sold.ok):toBe(true)
					expect((assert(sold.state)).burnedCoin):toBe(15)
					local swept = Book.apply(legacy, { kind = "sweep", opId = "s1" }, T0 + 72 * 60 * 60)
					expect(#(assert(Book.receiptsFor(swept.state, 11)))):toBe(1)
					legacy.listings[1].expiresAtSec = T0 + 60 * 60
					expect((Book.projectState(legacy))):toBeNil()
				end
			)

			it("keeps each item in a category book apart and returns exactly that item", function(own)
				local category = Book.emptyState("north", "category.gear_weapon")
				local function listItem(state: State?, opId: string, itemId: string?, price: number): Books.Result
					return Book.apply(state, {
						kind = "list",
						opId = opId,
						actorId = 11,
						actorRealmId = "north",
						count = 1,
						unitPrice = price,
						itemId = itemId,
					}, T0)
				end
				expect(listItem(category, "n1", nil, 10).reason):toBe("command_invalid")
				expect(Book.apply(empty(), {
					kind = "list",
					opId = "n2",
					actorId = 11,
					actorRealmId = "north",
					count = 1,
					unitPrice = 10,
					itemId = "sword",
				}, T0).reason):toBe("command_invalid")
				local state = listItem(category, "a", "sword_fine", 30).state
				state = listItem(state, "b", "sword", 10).state
				local function fillItem(itemId: string?): Books.Result
					return Book.apply(state, {
						kind = "fill",
						opId = "buy-" .. tostring(itemId),
						actorId = 20,
						actorRealmId = "north",
						quantity = 1,
						ceilingUnitPrice = 50,
						holdCoin = 50,
						itemId = itemId,
					}, T0 + 1)
				end
				expect(fillItem(nil).reason):toBe("command_invalid")
				expect(fillItem("axe").reason):toBe("no_supply")
				local bought = fillItem("sword_fine")
				expect(bought.ok):toBe(true)
				expect((assert(bought.receipts))[2].itemId):toBe("sword_fine")
				expect((assert(bought.receipts))[2].coin):toBe(30)
				expect(#(assert(bought.state)).listings):toBe(1)
				expect((assert(bought.state)).listings[1].itemId):toBe("sword")
				local cancelled =
					Book.apply(state, { kind = "cancel", opId = "c", actorId = 11, listingId = "a" }, T0 + 1)
				expect((assert(cancelled.receipts))[1].itemId):toBe("sword_fine")
				local expired = Book.apply(state, { kind = "sweep", opId = "s" }, T0 + settings.listingTtlSec)
				expect(#(assert(Book.receiptsFor(expired.state, 11)))):toBe(2)
				expect(((assert(Book.receiptsFor(expired.state, 11)))[1].itemId ~= nil)):toBe(true)
				expect(#(assert(Book.search(state, { itemId = "sword" }, T0 + 1)))):toBe(1)
				expect((Book.projectState(state) ~= nil)):toBe(true)
			end)

			it("cancels only the seller's own open listing", function(own)
				local state = seeded()
				expect(
					Book.apply(state, { kind = "cancel", opId = "c1", actorId = 12, listingId = "l1" }, T0 + 5).reason
				):toBe("listing_not_owned")
				local cancelled =
					Book.apply(state, { kind = "cancel", opId = "c2", actorId = 11, listingId = "l1" }, T0 + 5)
				expect(cancelled.ok):toBe(true)
				expect((assert(cancelled.receipts))[1].goods):toBe(3)
				expect(
					Book.apply(
						cancelled.state,
						{ kind = "cancel", opId = "c3", actorId = 11, listingId = "l1" },
						T0 + 6
					).reason
				):toBe("listing_closed")
			end)

			it("drops a receipt only when its owner acknowledges it", function(own)
				local sold = fill(seeded(), "b1", 20, 2, 10, 20, T0 + 10).state
				local stranger = Book.apply(
					sold,
					{ kind = "ack", opId = "a1", actorId = 99, receiptIds = { "b1:purchase" } },
					T0 + 11
				)
				expect(#(assert(Book.receiptsFor(stranger.state, 20)))):toBe(1)
				local owner = Book.apply(
					sold,
					{ kind = "ack", opId = "a2", actorId = 20, receiptIds = { "b1:purchase" } },
					T0 + 11
				)
				expect(#(assert(Book.receiptsFor(owner.state, 20)))):toBe(0)
			end)
		end

		do
			it("replays an exact operation without change and refuses a changed reuse", function(own)
				local first = fill(seeded(), "b1", 20, 2, 10, 20, T0 + 10)
				local replay = fill(first.state, "b1", 20, 2, 10, 20, T0 + 11)
				expect(replay.ok):toBe(true)
				expect(replay.replayed):toBe(true)
				expect((assert(replay.state)).burnedCoin):toBe((assert(first.state)).burnedCoin)
				expect(fill(first.state, "b1", 20, 3, 10, 30, T0 + 11).reason):toBe("operation_conflict")
				expect((Book.knowsOperation(first.state, "b1"))):toBe(true)
				expect((Book.knowsOperation(first.state, "b9"))):toBe(false)
			end)

			it("does not record a refused operation", function(own)
				local refused = fill(seeded(), "b1", 20, 1, 7, 7, T0 + 10)
				expect(refused.ok):toBe(false)
				expect(refused.state):toBeNil()
				expect((Book.knowsOperation(seeded(), "b1"))):toBe(false)
			end)

			it("refuses a backward clock, a malformed state, and an unknown command", function(own)
				expect(list(seeded(), "l9", 14, 1, 1, T0).reason):toBe("clock_regressed")
				expect(list({ schemaVersion = 1 }, "l9", 14, 1, 1, T0).reason):toBe("state_invalid")
				expect(Book.apply(seeded(), { kind = "gift", opId = "g1" }, T0 + 5).reason):toBe("command_invalid")
			end)
		end

		do
			it(
				"reads unit price, then listing time, then id, hiding expired rows, with seller, ceiling and limit",
				function(own)
					local state = seeded()
					local rows = assert(Book.search(state, {}, T0 + 10))
					expect(rows[1].listingId):toBe("l2")
					expect(rows[2].listingId):toBe("l3")
					expect(rows[3].listingId):toBe("l1")
					expect(#(assert(Book.search(state, { sellerId = 11 }, T0 + 10)))):toBe(1)
					expect(#(assert(Book.search(state, { ceilingUnitPrice = 8 }, T0 + 10)))):toBe(2)
					expect(#(assert(Book.search(state, { limit = 1 }, T0 + 10)))):toBe(1)
					expect((Book.search(state, { limit = 21 }, T0 + 10))):toBeNil()
					expect(#(assert(Book.search(state, {}, T0 + 1 + settings.listingTtlSec)))):toBe(1)
					expect(#(assert(Book.search(state, {}, T0 + 2 + settings.listingTtlSec)))):toBe(0)
				end
			)
		end

		do
			it("answers an exact replay even after a later write moved the book clock", function(own)
				local first = fill(seeded(), "b1", 20, 2, 10, 20, T0 + 10)
				local later = list(first.state, "l9", 14, 1, 5, T0 + 100).state
				local replay = fill(later, "b1", 20, 2, 10, 20, T0 + 10)
				expect(replay.ok):toBe(true)
				expect(replay.replayed):toBe(true)
			end)

			it(
				"voids an unknown operation so a late write with that id refuses, and reports a landed one as known",
				function(own)
					local voided = Book.apply(seeded(), { kind = "void", opId = "late" }, T0 + 10)
					expect(voided.ok):toBe(true)
					expect(voided.fence):toBe("voided")
					expect(list(voided.state, "late", 14, 1, 5, T0 + 11).reason):toBe("operation_void")
					local again = Book.apply(voided.state, { kind = "void", opId = "late" }, T0 + 12)
					expect(again.fence):toBe("voided")
					expect(again.replayed):toBe(true)
					local known = Book.apply(seeded(), { kind = "void", opId = "l1" }, T0 + 10)
					expect(known.fence):toBe("known")
					expect(known.replayed):toBe(true)
				end
			)

			it("keeps hashed list, cancel, and fill operations but never acks or sweeps", function(own)
				local sold = fill(seeded(), "b1", 20, 2, 10, 20, T0 + 10).state
				local kept = #(assert(sold)).operationOrder
				expect(#(assert(sold)).operations.b1.fingerprint):toBe(16)
				local acked = Book.apply(
					sold,
					{ kind = "ack", opId = "a1", actorId = 20, receiptIds = { "b1:purchase" } },
					T0 + 11
				)
				local swept = Book.apply(acked.state, { kind = "sweep", opId = "s1" }, T0 + 12)
				expect(#(assert(swept.state)).operationOrder):toBe(kept)
				expect((Book.knowsOperation(swept.state, "a1"))):toBe(false)
			end)

			it("caps open listings per seller and kept operations per actor", function(own)
				local state: State? = empty()
				for index = 1, settings.maxListingsPerSeller do
					state = list(state, "l" .. tostring(index), 11, 1, 5, T0 + index).state
				end
				expect(list(state, "l99", 11, 1, 5, T0 + 50).reason):toBe("seller_listing_cap")
				local looped: State? = empty()
				local at = T0
				local refusal: string? = nil
				for index = 1, settings.maxOperationsPerActor do
					at += 1
					local listed = list(looped, "x" .. tostring(index), 12, 1, 5, at)
					if not listed.ok then
						refusal = listed.reason
						break
					end
					at += 1
					local cancelled = Book.apply(listed.state, {
						kind = "cancel",
						opId = "c" .. tostring(index),
						actorId = 12,
						listingId = "x" .. tostring(index),
					}, at)
					if not cancelled.ok then
						refusal = cancelled.reason
						break
					end
					looped = Book.apply(cancelled.state, {
						kind = "ack",
						opId = "a" .. tostring(index),
						actorId = 12,
						receiptIds = { "return:x" .. tostring(index) },
					}, at).state
				end
				expect(refusal):toBe("actor_saturated")
				expect(list(looped, "other", 13, 1, 5, at + 1).ok):toBe(true)
			end)

			it("still acknowledges receipts when the book holds its maximum receipts", function(own)
				local state = table.clone(seeded())
				local receipts: { Receipt } = {}
				for index = 1, 2000 do
					table.insert(
						receipts,
						receipt({
							receiptId = "r" .. tostring(index),
							ownerId = 30,
							kind = "proceeds",
							opId = "o" .. tostring(index),
							coin = 1,
							goods = 0,
							issuedAtSec = T0,
						})
					)
				end
				state.receipts = receipts
				local full = Book.projectState(state)
				expect((full ~= nil)):toBe(true)
				expect(fill(full, "b1", 20, 1, 10, 10, T0 + 10).reason):toBe("book_saturated")
				local swept = Book.apply(full, { kind = "sweep", opId = "s1" }, T0 + settings.listingTtlSec + 5)
				expect(swept.ok):toBe(true)
				expect(#(assert(swept.state)).receipts):toBe(2003)
				expect((Book.projectState(swept.state) ~= nil)):toBe(true)
				local acked = Book.apply(
					swept.state,
					{ kind = "ack", opId = "a1", actorId = 30, receiptIds = { "r1" } },
					T0 + settings.listingTtlSec + 6
				)
				expect(acked.ok):toBe(true)
				expect(#(assert(acked.state)).receipts):toBe(2002)
			end)
		end

		do
			it("forgets an operation once it is older than the retention, however few ops the book holds", function(own)
				local state = list(empty(), "l1", 11, 1, 5, T0).state
				local later = list(state, "l2", 12, 1, 5, T0 + settings.operationRetentionSec).state
				expect((Book.knowsOperation(later, "l1"))):toBe(false)
				expect((Book.knowsOperation(later, "l2"))):toBe(true)
				local young = list(state, "l3", 12, 1, 5, T0 + settings.operationRetentionSec - 1).state
				expect((Book.knowsOperation(young, "l1"))):toBe(true)
			end)

			it("counts only the last day's operations toward an actor's cap", function(own)
				local state: State? = empty()
				local at = T0
				for index = 1, settings.maxOperationsPerActor / 2 do
					at += 1
					state = list(state, "x" .. tostring(index), 12, 1, 5, at).state
					state = Book.apply(state, {
						kind = "cancel",
						opId = "c" .. tostring(index),
						actorId = 12,
						listingId = "x" .. tostring(index),
					}, at).state
					state = Book.apply(state, {
						kind = "ack",
						opId = "a" .. tostring(index),
						actorId = 12,
						receiptIds = { "return:x" .. tostring(index) },
					}, at).state
				end
				expect(list(state, "blocked", 12, 1, 5, at + 1).reason):toBe("actor_saturated")
				expect(list(state, "fresh", 12, 1, 5, at + 24 * 60 * 60).ok):toBe(true)
			end)

			it(
				"neither lists for, sells to, nor fills from an owner holding the maximum unclaimed receipts",
				function(own)
					local state = seeded()
					local raw = table.clone(assert(state))
					local receipts: { Receipt } = {}
					for index = 1, settings.maxReceiptsPerOwner do
						table.insert(
							receipts,
							receipt({
								receiptId = "p" .. tostring(index),
								ownerId = 12,
								kind = "proceeds",
								opId = "q" .. tostring(index),
								coin = 1,
								goods = 0,
								issuedAtSec = T0,
							})
						)
					end
					raw.receipts = receipts
					local crowded = Book.projectState(raw)
					expect(list(crowded, "l9", 12, 1, 5, T0 + 5).reason):toBe("receipts_unclaimed")
					local bought = fill(crowded, "b1", 20, 1, 10, 10, T0 + 5)
					expect(bought.ok):toBe(true)
					expect((assert(bought.receipts))[1].ownerId):toBe(13)
					local buyer = table.clone(raw)
					for _, receipt in assert(buyer.receipts) do
						receipt.ownerId = 20
					end
					expect(fill(Book.projectState(buyer), "b2", 20, 1, 10, 10, T0 + 5).reason):toBe(
						"receipts_unclaimed"
					)
				end
			)
		end

		it("uses configured realm, identity, numeric and search bounds", function(own)
			local cfg = table.clone(settings)
			cfg.realms = { zone = true }
			cfg.maxId, cfg.maxCount, cfg.maxPrice, cfg.maxCoin, cfg.maxTime = 2, 3, 4, 10, 10
			cfg.listingTtlSec, cfg.legacyListingTtlSec, cfg.maxSearch = 2, 3, 1
			local book = Books.book(cfg)
			local state = assert(book.emptyState("zone", "ab", nil))
			expect(book.emptyState("north", "ab", nil)):toBeNil()
			expect(book.emptyState("zone", "abc", nil)):toBeNil()
			local function listing(opId: string, count: number, price: number, at: number): Books.Result
				return book.apply(state, {
					kind = "list",
					opId = opId,
					actorId = 10,
					actorRealmId = "zone",
					count = count,
					unitPrice = price,
				}, at)
			end
			local listed = listing("ab", 3, 4, 1)
			expect(listed.ok):toBe(true)
			expect(listing("abc", 1, 1, 1).reason):toBe("command_invalid")
			expect(listing("ab", 4, 1, 1).reason):toBe("command_invalid")
			expect(listing("ab", 1, 5, 1).reason):toBe("command_invalid")
			expect(listing("ab", 1, 1, 11).reason):toBe("clock_invalid")
			expect(book.apply(listed.state, {
				kind = "fill",
				opId = "b",
				actorId = 2,
				actorRealmId = "zone",
				quantity = 1,
				ceilingUnitPrice = 4,
				holdCoin = 11,
			}, 2).reason):toBe("command_invalid")
			expect(
				book.apply(
					state,
					{ kind = "list", opId = "b", actorId = 11, actorRealmId = "zone", count = 1, unitPrice = 1 },
					1
				).reason
			):toBe("command_invalid")
			expect(#assert(book.search(listed.state, {}, 1))):toBe(1)
			expect(book.search(listed.state, { limit = 2 }, 1)):toBeNil()
			local category = assert(book.emptyState("zone", "ab", nil))
			cfg.categoryPrefix = "a"
			local categoryBook = Books.book(cfg)
			expect(
				categoryBook.apply(
					category,
					{ kind = "list", opId = "l", actorId = 1, actorRealmId = "zone", count = 1, unitPrice = 1 },
					0
				).reason
			):toBe("command_invalid")
			expect(categoryBook.apply(category, {
				kind = "list",
				opId = "l",
				actorId = 1,
				actorRealmId = "zone",
				count = 1,
				unitPrice = 1,
				itemId = "xy",
			}, 0).ok):toBe(true)
		end)

		it("uses configured fees, current and legacy lifetimes, retention and actor windows", function()
			local cfg = table.clone(settings)
			cfg.minFeeBps, cfg.maxFeeBps, cfg.defaultFeeBps, cfg.legacyFeeBps = 10, 30, 30, 20
			cfg.listingTtlSec, cfg.legacyListingTtlSec = 2, 3
			cfg.operationRetentionSec, cfg.actorWindowSec, cfg.maxOperationsPerActor = 10, 3, 1
			local book = Books.book(cfg)
			expect(book.emptyState("north", "ore", 9)):toBeNil()
			expect(book.emptyState("north", "ore", 31)):toBeNil()
			expect(assert(book.emptyState("north", "ore", 10)).feeBps):toBe(10)
			local state = assert(book.emptyState("north", "ore", nil))
			expect(state.feeBps):toBe(30)
			local listed = book.apply(
				state,
				{ kind = "list", opId = "l", actorId = 1, actorRealmId = "north", count = 1, unitPrice = 1000 },
				0
			)
			expect(assert(listed.state).listings[1].expiresAtSec):toBe(2)
			expect(book.apply(listed.state, { kind = "cancel", opId = "c", actorId = 1, listingId = "l" }, 1).reason):toBe(
				"actor_saturated"
			)
			local legacy = table.clone(assert(listed.state))
			legacy.feeBps = 20
			legacy.listings = { table.clone(legacy.listings[1]) }
			legacy.listings[1].expiresAtSec = 3
			expect(assert(book.projectState(legacy)).feeBps):toBe(30)
			local sold = book.apply(legacy, {
				kind = "fill",
				opId = "b",
				actorId = 2,
				actorRealmId = "north",
				quantity = 1,
				ceilingUnitPrice = 1000,
				holdCoin = 1000,
			}, 1)
			expect(assert(sold.state).burnedCoin):toBe(3)
			local later = book.apply(
				listed.state,
				{ kind = "list", opId = "l2", actorId = 1, actorRealmId = "north", count = 1, unitPrice = 1 },
				3
			)
			expect(later.ok):toBe(true)
			expect(book.knowsOperation(later.state, "l")):toBe(true)
			local retained = book.apply(later.state, { kind = "void", opId = "v" }, 10)
			expect(book.knowsOperation(retained.state, "l")):toBe(false)
			expect(book.knowsOperation(retained.state, "l2")):toBe(true)
		end)

		it("uses configured listing, receipt and operation capacities", function()
			local cfg = table.clone(settings)
			cfg.maxListings, cfg.maxListingsPerSeller, cfg.maxReceiptsPerOwner = 2, 1, 1
			local book = Books.book(cfg)
			local state = assert(book.emptyState("north", "ore", nil))
			local function listing(previous: unknown, id: string, actorId: number): Books.Result
				return book.apply(
					previous,
					{ kind = "list", opId = id, actorId = actorId, actorRealmId = "north", count = 1, unitPrice = 1 },
					0
				)
			end
			local first = listing(state, "a", 1)
			expect(listing(first.state, "b", 1).reason):toBe("seller_listing_cap")
			local second = listing(first.state, "b", 2)
			expect(listing(second.state, "c", 3).reason):toBe("book_full")
			local cancelled = book.apply(first.state, { kind = "cancel", opId = "c", actorId = 1, listingId = "a" }, 0)
			expect(listing(cancelled.state, "d", 1).reason):toBe("receipts_unclaimed")
			cfg.maxReceipts = 1
			local receiptBound = Books.book(cfg)
			expect(receiptBound.apply(first.state, {
				kind = "fill",
				opId = "buy",
				actorId = 2,
				actorRealmId = "north",
				quantity = 1,
				ceilingUnitPrice = 1,
				holdCoin = 1,
			}, 0).reason):toBe("book_saturated")
			cfg.maxOperations = 1
			local operationBound = Books.book(cfg)
			expect(operationBound.apply(first.state, { kind = "void", opId = "v" }, 0).reason):toBe("book_saturated")
		end)
	end)
end
