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
	do
		suite:case("lists into a 48-hour realm-local book at the default 5% burning cut", function(context)
			local result = list(empty(), "l1", 11, 3, 10, T0)
			context:expect(result.ok):toBe(true)
			local listing = (assert(result.state)).listings[1]
			context:expect(listing.listingId):toBe("l1")
			context:expect((listing.expiresAtSec - listing.listedAtSec)):toBe(48 * 60 * 60)
			context:expect((assert(result.state)).feeBps):toBe(500)
			context:expect((Book.emptyState("north", "ore", 200))):toBeNil()
			context:expect((Book.emptyState("north", "ore", 600))):toBeNil()
			context:expect((Book.emptyState("north", "ore", 300) ~= nil)):toBe(true)
		end)

		suite:case("fills a bundle cheapest first, then by listing time, burning the cut per seller", function(context)
			local result = fill(seeded(), "b1", 20, 7, 10, 70, T0 + 10)
			context:expect(result.ok):toBe(true)
			local proceeds: { [number]: number } = {}
			local purchase: Receipt? = nil
			for _, receipt in assert(result.receipts) do
				if receipt.kind == "proceeds" then
					proceeds[receipt.ownerId] = receipt.coin
				elseif receipt.kind == "purchase" then
					purchase = receipt
				end
			end
			context:expect(proceeds[12]):toBe(40 - 2)
			context:expect(proceeds[13]):toBe(16 - 1)
			context:expect(proceeds[11]):toBeNil()
			context:expect((assert(purchase)).goods):toBe(7)
			context:expect((assert(purchase)).coin):toBe(56)
			context:expect((assert(result.state)).burnedCoin):toBe(3)
			context:expect(#(assert(result.state)).listings):toBe(2)
			context:expect((assert(result.state)).listings[2].count):toBe(2)
		end)

		suite:case(
			"fills partially when supply under the ceiling is short and refuses when none is left",
			function(context)
				local partial = fill(seeded(), "b1", 20, 50, 8, 400, T0 + 10)
				context:expect(partial.ok):toBe(true)
				context:expect((assert(partial.receipts))[#(assert(partial.receipts))].goods):toBe(9)
				context:expect(fill(seeded(), "b2", 20, 1, 7, 7, T0 + 10).reason):toBe("no_supply")
			end
		)

		suite:case(
			"never fills from the buyer's own listings and refuses a foreign realm or a short hold",
			function(context)
				local own = list(empty(), "l1", 20, 3, 5, T0).state
				context:expect(fill(own, "b1", 20, 1, 5, 5, T0 + 1).reason):toBe("no_supply")
				local foreign = Book.apply(seeded(), {
					kind = "fill",
					opId = "b1",
					actorId = 20,
					actorRealmId = "south",
					quantity = 1,
					ceilingUnitPrice = 10,
					holdCoin = 10,
				}, T0 + 10)
				context:expect(foreign.reason):toBe("realm_foreign")
				context:expect(fill(seeded(), "b1", 20, 7, 10, 55, T0 + 10).reason):toBe("hold_insufficient")
				local foreignList = Book.apply(empty(), {
					kind = "list",
					opId = "l1",
					actorId = 11,
					actorRealmId = "east",
					count = 1,
					unitPrice = 1,
				}, T0)
				context:expect(foreignList.reason):toBe("realm_foreign")
			end
		)
	end

	do
		suite:case("returns an expired listing's goods once as a return receipt", function(context)
			local state = list(empty(), "l1", 11, 3, 10, T0).state
			local later = Book.apply(state, { kind = "sweep", opId = "s1" }, T0 + settings.listingTtlSec)
			context:expect(#(assert(later.state)).listings):toBe(0)
			local receipts = assert(Book.receiptsFor(later.state, 11))
			context:expect(#receipts):toBe(1)
			context:expect(receipts[1].kind):toBe("return")
			context:expect(receipts[1].goods):toBe(3)
			local again = Book.apply(later.state, { kind = "sweep", opId = "s2" }, T0 + settings.listingTtlSec + 5)
			context:expect(#(assert(Book.receiptsFor(again.state, 11)))):toBe(1)
			context:expect(fill(later.state, "b1", 20, 1, 10, 10, T0 + settings.listingTtlSec).reason):toBe("no_supply")
		end)

		suite:case(
			"reads a stored book written under the earlier 72-hour window and 4% cut and sells under the current cut",
			function(context)
				local state = list(empty(), "l1", 11, 3, 100, T0).state
				local legacy = table.clone(assert(state))
				legacy.feeBps = 400
				legacy.listings = { table.clone((assert(state)).listings[1]) }
				legacy.listings[1].expiresAtSec = T0 + 72 * 60 * 60
				local read = Book.projectState(legacy)
				context:expect((read ~= nil)):toBe(true)
				context:expect((assert(read)).feeBps):toBe(settings.defaultFeeBps)
				local sold = fill(legacy, "b1", 20, 3, 100, 300, T0 + 10)
				context:expect(sold.ok):toBe(true)
				context:expect((assert(sold.state)).burnedCoin):toBe(15)
				local swept = Book.apply(legacy, { kind = "sweep", opId = "s1" }, T0 + 72 * 60 * 60)
				context:expect(#(assert(Book.receiptsFor(swept.state, 11)))):toBe(1)
				legacy.listings[1].expiresAtSec = T0 + 60 * 60
				context:expect((Book.projectState(legacy))):toBeNil()
			end
		)

		suite:case("keeps each item in a category book apart and returns exactly that item", function(context)
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
			context:expect(listItem(category, "n1", nil, 10).reason):toBe("command_invalid")
			context
				:expect(Book.apply(empty(), {
					kind = "list",
					opId = "n2",
					actorId = 11,
					actorRealmId = "north",
					count = 1,
					unitPrice = 10,
					itemId = "sword",
				}, T0).reason)
				:toBe("command_invalid")
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
			context:expect(fillItem(nil).reason):toBe("command_invalid")
			context:expect(fillItem("axe").reason):toBe("no_supply")
			local bought = fillItem("sword_fine")
			context:expect(bought.ok):toBe(true)
			context:expect((assert(bought.receipts))[2].itemId):toBe("sword_fine")
			context:expect((assert(bought.receipts))[2].coin):toBe(30)
			context:expect(#(assert(bought.state)).listings):toBe(1)
			context:expect((assert(bought.state)).listings[1].itemId):toBe("sword")
			local cancelled = Book.apply(state, { kind = "cancel", opId = "c", actorId = 11, listingId = "a" }, T0 + 1)
			context:expect((assert(cancelled.receipts))[1].itemId):toBe("sword_fine")
			local expired = Book.apply(state, { kind = "sweep", opId = "s" }, T0 + settings.listingTtlSec)
			context:expect(#(assert(Book.receiptsFor(expired.state, 11)))):toBe(2)
			context:expect(((assert(Book.receiptsFor(expired.state, 11)))[1].itemId ~= nil)):toBe(true)
			context:expect(#(assert(Book.search(state, { itemId = "sword" }, T0 + 1)))):toBe(1)
			context:expect((Book.projectState(state) ~= nil)):toBe(true)
		end)

		suite:case("cancels only the seller's own open listing", function(context)
			local state = seeded()
			context
				:expect(
					Book.apply(state, { kind = "cancel", opId = "c1", actorId = 12, listingId = "l1" }, T0 + 5).reason
				)
				:toBe("listing_not_owned")
			local cancelled =
				Book.apply(state, { kind = "cancel", opId = "c2", actorId = 11, listingId = "l1" }, T0 + 5)
			context:expect(cancelled.ok):toBe(true)
			context:expect((assert(cancelled.receipts))[1].goods):toBe(3)
			context
				:expect(
					Book.apply(
						cancelled.state,
						{ kind = "cancel", opId = "c3", actorId = 11, listingId = "l1" },
						T0 + 6
					).reason
				)
				:toBe("listing_closed")
		end)

		suite:case("drops a receipt only when its owner acknowledges it", function(context)
			local sold = fill(seeded(), "b1", 20, 2, 10, 20, T0 + 10).state
			local stranger =
				Book.apply(sold, { kind = "ack", opId = "a1", actorId = 99, receiptIds = { "b1:purchase" } }, T0 + 11)
			context:expect(#(assert(Book.receiptsFor(stranger.state, 20)))):toBe(1)
			local owner =
				Book.apply(sold, { kind = "ack", opId = "a2", actorId = 20, receiptIds = { "b1:purchase" } }, T0 + 11)
			context:expect(#(assert(Book.receiptsFor(owner.state, 20)))):toBe(0)
		end)
	end

	do
		suite:case("replays an exact operation without change and refuses a changed reuse", function(context)
			local first = fill(seeded(), "b1", 20, 2, 10, 20, T0 + 10)
			local replay = fill(first.state, "b1", 20, 2, 10, 20, T0 + 11)
			context:expect(replay.ok):toBe(true)
			context:expect(replay.replayed):toBe(true)
			context:expect((assert(replay.state)).burnedCoin):toBe((assert(first.state)).burnedCoin)
			context:expect(fill(first.state, "b1", 20, 3, 10, 30, T0 + 11).reason):toBe("operation_conflict")
			context:expect((Book.knowsOperation(first.state, "b1"))):toBe(true)
			context:expect((Book.knowsOperation(first.state, "b9"))):toBe(false)
		end)

		suite:case("does not record a refused operation", function(context)
			local refused = fill(seeded(), "b1", 20, 1, 7, 7, T0 + 10)
			context:expect(refused.ok):toBe(false)
			context:expect(refused.state):toBeNil()
			context:expect((Book.knowsOperation(seeded(), "b1"))):toBe(false)
		end)

		suite:case("refuses a backward clock, a malformed state, and an unknown command", function(context)
			context:expect(list(seeded(), "l9", 14, 1, 1, T0).reason):toBe("clock_regressed")
			context:expect(list({ schemaVersion = 1 }, "l9", 14, 1, 1, T0).reason):toBe("state_invalid")
			context:expect(Book.apply(seeded(), { kind = "gift", opId = "g1" }, T0 + 5).reason):toBe("command_invalid")
		end)
	end

	do
		suite:case(
			"reads unit price, then listing time, then id, hiding expired rows, with seller, ceiling and limit",
			function(context)
				local state = seeded()
				local rows = assert(Book.search(state, {}, T0 + 10))
				context:expect(rows[1].listingId):toBe("l2")
				context:expect(rows[2].listingId):toBe("l3")
				context:expect(rows[3].listingId):toBe("l1")
				context:expect(#(assert(Book.search(state, { sellerId = 11 }, T0 + 10)))):toBe(1)
				context:expect(#(assert(Book.search(state, { ceilingUnitPrice = 8 }, T0 + 10)))):toBe(2)
				context:expect(#(assert(Book.search(state, { limit = 1 }, T0 + 10)))):toBe(1)
				context:expect((Book.search(state, { limit = 21 }, T0 + 10))):toBeNil()
				context:expect(#(assert(Book.search(state, {}, T0 + 1 + settings.listingTtlSec)))):toBe(1)
				context:expect(#(assert(Book.search(state, {}, T0 + 2 + settings.listingTtlSec)))):toBe(0)
			end
		)
	end

	do
		suite:case("answers an exact replay even after a later write moved the book clock", function(context)
			local first = fill(seeded(), "b1", 20, 2, 10, 20, T0 + 10)
			local later = list(first.state, "l9", 14, 1, 5, T0 + 100).state
			local replay = fill(later, "b1", 20, 2, 10, 20, T0 + 10)
			context:expect(replay.ok):toBe(true)
			context:expect(replay.replayed):toBe(true)
		end)

		suite:case(
			"voids an unknown operation so a late write with that id refuses, and reports a landed one as known",
			function(context)
				local voided = Book.apply(seeded(), { kind = "void", opId = "late" }, T0 + 10)
				context:expect(voided.ok):toBe(true)
				context:expect(voided.fence):toBe("voided")
				context:expect(list(voided.state, "late", 14, 1, 5, T0 + 11).reason):toBe("operation_void")
				local again = Book.apply(voided.state, { kind = "void", opId = "late" }, T0 + 12)
				context:expect(again.fence):toBe("voided")
				context:expect(again.replayed):toBe(true)
				local known = Book.apply(seeded(), { kind = "void", opId = "l1" }, T0 + 10)
				context:expect(known.fence):toBe("known")
				context:expect(known.replayed):toBe(true)
			end
		)

		suite:case("keeps hashed list, cancel, and fill operations but never acks or sweeps", function(context)
			local sold = fill(seeded(), "b1", 20, 2, 10, 20, T0 + 10).state
			local kept = #(assert(sold)).operationOrder
			context:expect(#(assert(sold)).operations.b1.fingerprint):toBe(16)
			local acked =
				Book.apply(sold, { kind = "ack", opId = "a1", actorId = 20, receiptIds = { "b1:purchase" } }, T0 + 11)
			local swept = Book.apply(acked.state, { kind = "sweep", opId = "s1" }, T0 + 12)
			context:expect(#(assert(swept.state)).operationOrder):toBe(kept)
			context:expect((Book.knowsOperation(swept.state, "a1"))):toBe(false)
		end)

		suite:case("caps open listings per seller and kept operations per actor", function(context)
			local state: State? = empty()
			for index = 1, settings.maxListingsPerSeller do
				state = list(state, "l" .. tostring(index), 11, 1, 5, T0 + index).state
			end
			context:expect(list(state, "l99", 11, 1, 5, T0 + 50).reason):toBe("seller_listing_cap")
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
			context:expect(refusal):toBe("actor_saturated")
			context:expect(list(looped, "other", 13, 1, 5, at + 1).ok):toBe(true)
		end)

		suite:case("still acknowledges receipts when the book holds its maximum receipts", function(context)
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
			context:expect((full ~= nil)):toBe(true)
			context:expect(fill(full, "b1", 20, 1, 10, 10, T0 + 10).reason):toBe("book_saturated")
			local swept = Book.apply(full, { kind = "sweep", opId = "s1" }, T0 + settings.listingTtlSec + 5)
			context:expect(swept.ok):toBe(true)
			context:expect(#(assert(swept.state)).receipts):toBe(2003)
			context:expect((Book.projectState(swept.state) ~= nil)):toBe(true)
			local acked = Book.apply(
				swept.state,
				{ kind = "ack", opId = "a1", actorId = 30, receiptIds = { "r1" } },
				T0 + settings.listingTtlSec + 6
			)
			context:expect(acked.ok):toBe(true)
			context:expect(#(assert(acked.state)).receipts):toBe(2002)
		end)
	end

	do
		suite:case(
			"forgets an operation once it is older than the retention, however few ops the book holds",
			function(context)
				local state = list(empty(), "l1", 11, 1, 5, T0).state
				local later = list(state, "l2", 12, 1, 5, T0 + settings.operationRetentionSec).state
				context:expect((Book.knowsOperation(later, "l1"))):toBe(false)
				context:expect((Book.knowsOperation(later, "l2"))):toBe(true)
				local young = list(state, "l3", 12, 1, 5, T0 + settings.operationRetentionSec - 1).state
				context:expect((Book.knowsOperation(young, "l1"))):toBe(true)
			end
		)

		suite:case("counts only the last day's operations toward an actor's cap", function(context)
			local state: State? = empty()
			local at = T0
			for index = 1, settings.maxOperationsPerActor / 2 do
				at += 1
				state = list(state, "x" .. tostring(index), 12, 1, 5, at).state
				state = Book.apply(
					state,
					{ kind = "cancel", opId = "c" .. tostring(index), actorId = 12, listingId = "x" .. tostring(index) },
					at
				).state
				state = Book.apply(state, {
					kind = "ack",
					opId = "a" .. tostring(index),
					actorId = 12,
					receiptIds = { "return:x" .. tostring(index) },
				}, at).state
			end
			context:expect(list(state, "blocked", 12, 1, 5, at + 1).reason):toBe("actor_saturated")
			context:expect(list(state, "fresh", 12, 1, 5, at + 24 * 60 * 60).ok):toBe(true)
		end)

		suite:case(
			"neither lists for, sells to, nor fills from an owner holding the maximum unclaimed receipts",
			function(context)
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
				context:expect(list(crowded, "l9", 12, 1, 5, T0 + 5).reason):toBe("receipts_unclaimed")
				local bought = fill(crowded, "b1", 20, 1, 10, 10, T0 + 5)
				context:expect(bought.ok):toBe(true)
				context:expect((assert(bought.receipts))[1].ownerId):toBe(13)
				local buyer = table.clone(raw)
				for _, receipt in assert(buyer.receipts) do
					receipt.ownerId = 20
				end
				context
					:expect(fill(Book.projectState(buyer), "b2", 20, 1, 10, 10, T0 + 5).reason)
					:toBe("receipts_unclaimed")
			end
		)
	end

	suite:case("uses configured realm, identity, numeric and search bounds", function(context)
		local cfg = table.clone(settings)
		cfg.realms = { zone = true }
		cfg.maxId, cfg.maxCount, cfg.maxPrice, cfg.maxCoin, cfg.maxTime = 2, 3, 4, 10, 10
		cfg.listingTtlSec, cfg.legacyListingTtlSec, cfg.maxSearch = 2, 3, 1
		local book = Books.book(cfg)
		local state = assert(book.emptyState("zone", "ab", nil))
		context:expect(book.emptyState("north", "ab", nil)):toBeNil()
		context:expect(book.emptyState("zone", "abc", nil)):toBeNil()
		local function listing(opId: string, count: number, price: number, at: number): Books.Result
			return book.apply(
				state,
				{ kind = "list", opId = opId, actorId = 10, actorRealmId = "zone", count = count, unitPrice = price },
				at
			)
		end
		local listed = listing("ab", 3, 4, 1)
		context:expect(listed.ok):toBe(true)
		context:expect(listing("abc", 1, 1, 1).reason):toBe("command_invalid")
		context:expect(listing("ab", 4, 1, 1).reason):toBe("command_invalid")
		context:expect(listing("ab", 1, 5, 1).reason):toBe("command_invalid")
		context:expect(listing("ab", 1, 1, 11).reason):toBe("clock_invalid")
		context
			:expect(book.apply(listed.state, {
				kind = "fill",
				opId = "b",
				actorId = 2,
				actorRealmId = "zone",
				quantity = 1,
				ceilingUnitPrice = 4,
				holdCoin = 11,
			}, 2).reason)
			:toBe("command_invalid")
		context
			:expect(
				book.apply(
					state,
					{ kind = "list", opId = "b", actorId = 11, actorRealmId = "zone", count = 1, unitPrice = 1 },
					1
				).reason
			)
			:toBe("command_invalid")
		context:expect(#assert(book.search(listed.state, {}, 1))):toBe(1)
		context:expect(book.search(listed.state, { limit = 2 }, 1)):toBeNil()
		local category = assert(book.emptyState("zone", "ab", nil))
		cfg.categoryPrefix = "a"
		local categoryBook = Books.book(cfg)
		context
			:expect(
				categoryBook.apply(
					category,
					{ kind = "list", opId = "l", actorId = 1, actorRealmId = "zone", count = 1, unitPrice = 1 },
					0
				).reason
			)
			:toBe("command_invalid")
		context
			:expect(categoryBook.apply(category, {
				kind = "list",
				opId = "l",
				actorId = 1,
				actorRealmId = "zone",
				count = 1,
				unitPrice = 1,
				itemId = "xy",
			}, 0).ok)
			:toBe(true)
	end)

	suite:case("uses configured fees, current and legacy lifetimes, retention and actor windows", function(context)
		local cfg = table.clone(settings)
		cfg.minFeeBps, cfg.maxFeeBps, cfg.defaultFeeBps, cfg.legacyFeeBps = 10, 30, 30, 20
		cfg.listingTtlSec, cfg.legacyListingTtlSec = 2, 3
		cfg.operationRetentionSec, cfg.actorWindowSec, cfg.maxOperationsPerActor = 10, 3, 1
		local book = Books.book(cfg)
		context:expect(book.emptyState("north", "ore", 9)):toBeNil()
		context:expect(book.emptyState("north", "ore", 31)):toBeNil()
		context:expect(assert(book.emptyState("north", "ore", 10)).feeBps):toBe(10)
		local state = assert(book.emptyState("north", "ore", nil))
		context:expect(state.feeBps):toBe(30)
		local listed = book.apply(
			state,
			{ kind = "list", opId = "l", actorId = 1, actorRealmId = "north", count = 1, unitPrice = 1000 },
			0
		)
		context:expect(assert(listed.state).listings[1].expiresAtSec):toBe(2)
		context
			:expect(book.apply(listed.state, { kind = "cancel", opId = "c", actorId = 1, listingId = "l" }, 1).reason)
			:toBe("actor_saturated")
		local legacy = table.clone(assert(listed.state))
		legacy.feeBps = 20
		legacy.listings = { table.clone(legacy.listings[1]) }
		legacy.listings[1].expiresAtSec = 3
		context:expect(assert(book.projectState(legacy)).feeBps):toBe(30)
		local sold = book.apply(legacy, {
			kind = "fill",
			opId = "b",
			actorId = 2,
			actorRealmId = "north",
			quantity = 1,
			ceilingUnitPrice = 1000,
			holdCoin = 1000,
		}, 1)
		context:expect(assert(sold.state).burnedCoin):toBe(3)
		local later = book.apply(
			listed.state,
			{ kind = "list", opId = "l2", actorId = 1, actorRealmId = "north", count = 1, unitPrice = 1 },
			3
		)
		context:expect(later.ok):toBe(true)
		context:expect(book.knowsOperation(later.state, "l")):toBe(true)
		local retained = book.apply(later.state, { kind = "void", opId = "v" }, 10)
		context:expect(book.knowsOperation(retained.state, "l")):toBe(false)
		context:expect(book.knowsOperation(retained.state, "l2")):toBe(true)
	end)

	suite:case("uses configured listing, receipt and operation capacities", function(context)
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
		context:expect(listing(first.state, "b", 1).reason):toBe("seller_listing_cap")
		local second = listing(first.state, "b", 2)
		context:expect(listing(second.state, "c", 3).reason):toBe("book_full")
		local cancelled = book.apply(first.state, { kind = "cancel", opId = "c", actorId = 1, listingId = "a" }, 0)
		context:expect(listing(cancelled.state, "d", 1).reason):toBe("receipts_unclaimed")
		cfg.maxReceipts = 1
		local receiptBound = Books.book(cfg)
		context
			:expect(receiptBound.apply(first.state, {
				kind = "fill",
				opId = "buy",
				actorId = 2,
				actorRealmId = "north",
				quantity = 1,
				ceilingUnitPrice = 1,
				holdCoin = 1,
			}, 0).reason)
			:toBe("book_saturated")
		cfg.maxOperations = 1
		local operationBound = Books.book(cfg)
		context
			:expect(operationBound.apply(first.state, { kind = "void", opId = "v" }, 0).reason)
			:toBe("book_saturated")
	end)
end
