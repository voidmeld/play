--!strict

local Books = require("../core/market/book")
local SettlementHost = require("./market-settlement")
local Value = require("../core/internal/value")
local Wallets = require("../core/market/wallet")

type Outcome = SettlementHost.Outcome
type Settlement = SettlementHost.Service
export type Wallet = {
	read read: () -> Wallets.State?,
	read write: (Wallets.State) -> boolean,
	read room: (string) -> number,
}
type BookService = SettlementHost.BookService
type BookState = Books.State
export type Item<R> = {
	read id: string,
	read name: string,
	read rarity: R,
	read slot: string?,
	read levelReq: number?,
	read weaponFamily: string?,
	read armorFamily: string?,
	read classReq: { string }?,
	read sellValue: number?,
}
export type Items<R> = { read get: (string) -> Item<R>? }
export type Material = { id: string, label: string, npcFloor: number, npcCeiling: number }
export type Catalog = {
	materials: { Material },
	maxQuantity: number,
	maxUnitPrice: number,
	maxItemQuantity: number?,
	maxItemUnitPrice: number?,
	visibleListings: number,
	searchLimit: number,
}

type ListingOrder = { read unitPrice: number, read listedAtSec: number, read listingId: string }
type SearchQuery = { read materialId: string?, read ceilingUnitPrice: number? }
type MaterialListing = { read count: number, read unitPrice: number }
type OwnListing = MaterialListing & { read listingId: string, read expiresAtSec: number }
type MaterialProjection = {
	read materialId: string,
	read label: string,
	read held: number,
	read npcFloor: number,
	read npcCeiling: number,
	read loaded: boolean,
	read listings: { MaterialListing },
	read own: { OwnListing },
}
type SearchRow = MaterialListing & { read materialId: string, read label: string, read own: boolean }
type SortedSearchRow = SearchRow & { read listingId: string, read listedAtSec: number }
type SearchProjection = { read materialId: string, read ceilingUnitPrice: number, read rows: { SearchRow } }
export type ItemRow<R> = {
	read listingId: string?,
	read bookId: string,
	read itemId: string,
	read name: string,
	read slot: string?,
	read levelReq: number?,
	read rarity: R,
	read family: string?,
	read count: number,
	read unitPrice: number,
	read own: boolean,
	read expiresAtSec: number,
}
type SortedItemRow<R> = ItemRow<R> & { read listingId: string, read listedAtSec: number }
export type ItemPage<R> = {
	read ok: boolean,
	read reason: string?,
	read rows: { ItemRow<R> },
	read total: number,
	read page: number,
}
export type ListableItem<R> = {
	read itemId: string,
	read name: string,
	read slot: string?,
	read levelReq: number?,
	read rarity: R,
	read count: number,
	read suggestedPrice: number,
}
export type Projection = {
	read available: boolean,
	read realmId: string | false,
	read feeBps: number,
	read materials: { MaterialProjection },
	read coin: number?,
	read maxQuantity: number?,
	read maxUnitPrice: number?,
	read search: SearchProjection?,
}

export type Dependencies<R> = {
	read book: BookService,
	read catalog: Catalog,
	read walletFor: (number) -> Wallet?,
	read realmFor: (number) -> string?,
	read clock: () -> number,
	read newOpId: () -> string,
	read tradingAllowed: (number) -> boolean,
	read items: Items<R>?,
}

export type Service<R> = {
	read join: (number) -> Outcome,
	read list: (number, unknown, unknown, unknown) -> Outcome,
	read buy: (number, unknown, unknown, unknown) -> Outcome,
	read cancel: (number, unknown, unknown) -> Outcome,
	read refresh: (number) -> Outcome,
	read npcSell: (number, unknown, unknown) -> Outcome,
	read npcBuy: (number, unknown, unknown) -> Outcome,
	read listItem: (number, unknown, unknown, unknown) -> Outcome,
	read buyItem: (number, unknown, unknown, unknown) -> Outcome,
	read searchItems: (number, unknown) -> ItemPage<R>,
	read listable: (number) -> { ListableItem<R> },
	read search: (number, unknown, unknown) -> Outcome,
	read projection: (number) -> Projection,
	read forget: (number) -> (),
}

export type ItemFilters = {
	read page: number?,
	read ceilingUnitPrice: number?,
	read minLevel: number?,
	read maxLevel: number?,
	read bookId: string?,
	read itemId: string?,
	read own: boolean?,
	read slot: string?,
	read rarity: string?,
	read family: string?,
	read classId: string?,
}

export type GoodsOps = {
	read bookIds: () -> { string },
	read isCategoryBook: (unknown) -> boolean,
	read bookFor: (unknown) -> (string?, string?),
}
export type Config<R> = {
	read items: Items<R>,
	read goods: GoodsOps,
	read matchesItem: (Item<R>, ItemFilters) -> boolean,
	read settlement: SettlementHost.Host,
	read search: (unknown, unknown, unknown) -> { Books.Listing }?,
	read npcTrade: (unknown, unknown, unknown, unknown, unknown) -> Wallets.Result,
	read feeBps: number,
	read joinRetrySec: number,
	read maxActiveListings: number,
	read maxCatalogUnitPrice: number,
	read maxSearchLimit: number,
	read maxSearchPrice: number,
}
export type Host<R> = { read mount: (Dependencies<R>) -> (Service<R>?, string?), read MAX_ACTIVE_LISTINGS: number }

local function configure<R>(config: Config<R>): Host<R>
	config = table.freeze(table.clone(config))
	for _, bound in
		{ config.maxActiveListings, config.maxCatalogUnitPrice, config.maxSearchLimit, config.maxSearchPrice }
	do
		assert(Value.whole(bound, 1, 9007199254740991) ~= nil, "invalid market bound")
	end
	assert(Value.finite(config.joinRetrySec) and config.joinRetrySec >= 0, "invalid market join retry")
	assert(Value.whole(config.feeBps, 0, 10000) ~= nil, "invalid market fee")
	local MarketSettlement = config.settlement
	local MarketGoods = config.goods
	local MarketBookCore = { search = config.search, DEFAULT_FEE_BPS = config.feeBps }
	local MarketWalletCore = { npcTrade = config.npcTrade }

	local FILTER_FIELDS: { [string]: string } = {
		page = "number",
		ceilingUnitPrice = "number",
		minLevel = "number",
		maxLevel = "number",
		bookId = "string",
		itemId = "string",
		own = "boolean",
		slot = "string",
		rarity = "string",
		family = "string",
		classId = "string",
	}

	local function itemFilters(raw: unknown): ItemFilters?
		local fields = Value.raw(raw)
		if fields == nil then
			return nil
		end
		for key, value in fields do
			if type(key) ~= "string" or FILTER_FIELDS[key] ~= type(value) then
				return nil
			end
		end
		return {
			page = if type(fields.page) == "number" then fields.page else nil,
			ceilingUnitPrice = if type(fields.ceilingUnitPrice) == "number" then fields.ceilingUnitPrice else nil,
			minLevel = if type(fields.minLevel) == "number" then fields.minLevel else nil,
			maxLevel = if type(fields.maxLevel) == "number" then fields.maxLevel else nil,
			bookId = if type(fields.bookId) == "string" then fields.bookId else nil,
			itemId = if type(fields.itemId) == "string" then fields.itemId else nil,
			own = if type(fields.own) == "boolean" then fields.own else nil,
			slot = if type(fields.slot) == "string" then fields.slot else nil,
			rarity = if type(fields.rarity) == "string" then fields.rarity else nil,
			family = if type(fields.family) == "string" then fields.family else nil,
			classId = if type(fields.classId) == "string" then fields.classId else nil,
		}
	end

	local matchesItem = config.matchesItem

	local JOIN_RETRY_SEC = config.joinRetrySec

	local MarketService = {}

	local function whole(value: unknown, minimum: number, maximum: number): boolean
		return type(value) == "number" and value == math.floor(value) and value >= minimum and value <= maximum
	end

	local function catalogMaterials(raw: Catalog): ({ Material }?, { [string]: Material }?)
		local catalog = raw
		if
			type(catalog) ~= "table"
			or type(catalog.materials) ~= "table"
			or not whole(catalog.maxUnitPrice, 1, config.maxCatalogUnitPrice)
			or not whole(catalog.searchLimit, 1, config.maxSearchLimit)
		then
			return nil, nil
		end
		local byId: { [string]: Material } = {}
		for _, material in catalog.materials do
			if
				type(material) ~= "table"
				or type(material.id) ~= "string"
				or type(material.label) ~= "string"
				or not whole(material.npcFloor, 1, catalog.maxUnitPrice)
				or not whole(material.npcCeiling, material.npcFloor + 1, catalog.maxUnitPrice)
			then
				return nil, nil
			end
			byId[material.id] = material
		end
		return catalog.materials, byId
	end

	local function listingBefore(left: ListingOrder, right: ListingOrder): boolean
		if left.unitPrice ~= right.unitPrice then
			return left.unitPrice < right.unitPrice
		end
		if left.listedAtSec ~= right.listedAtSec then
			return left.listedAtSec < right.listedAtSec
		end
		return left.listingId < right.listingId
	end

	function MarketService.mount(raw: Dependencies<R>): (Service<R>?, string?)
		local deps = raw
		if
			type(raw) ~= "table"
			or type(deps.book) ~= "table"
			or type(deps.walletFor) ~= "function"
			or type(deps.realmFor) ~= "function"
			or type(deps.clock) ~= "function"
			or type(deps.newOpId) ~= "function"
			or type(deps.tradingAllowed) ~= "function"
		then
			return nil, "dependencies_invalid"
		end
		local materials, materialById = catalogMaterials(deps.catalog)
		if materials == nil or materialById == nil then
			return nil, "catalog_invalid"
		end
		local items: Items<R> = if deps.items ~= nil then deps.items else config.items
		local bookIds: { string } = {}
		for _, material in materials do
			bookIds[#bookIds + 1] = material.id
		end
		for _, bookId in MarketGoods.bookIds() do
			bookIds[#bookIds + 1] = bookId
		end
		local settlements: { [number]: Settlement } = {}
		local bookCache: { [string]: BookState } = {}
		local joined: { [number]: boolean } = {}
		local joinTriedAt: { [number]: number } = {}
		local searches: { [number]: SearchQuery } = {}

		local function settlementFor(userId: number): Settlement?
			local existing = settlements[userId]
			if existing ~= nil then
				return existing
			end
			local wallet = deps.walletFor(userId)
			if wallet == nil or wallet.read() == nil then
				return nil
			end
			local settlement = MarketSettlement.create({
				book = deps.book,
				wallet = wallet,
				clock = deps.clock,
				newOpId = deps.newOpId,
			})
			if settlement == nil then
				return nil
			end
			settlements[userId] = settlement
			return settlement
		end

		local function refreshBook(realmId: string, materialId: string)
			local read = deps.book.read(realmId, materialId)
			if read.ok and read.state ~= nil then
				bookCache[realmId .. "|" .. materialId] = read.state
			end
		end

		local function done(result: Outcome, realmId: string?, materialId: string?): Outcome
			if realmId ~= nil and materialId ~= nil then
				refreshBook(realmId, materialId)
			end
			return { ok = result.ok, reason = result.reason, pending = result.pending }
		end

		local function join(userId: number): Outcome
			if joined[userId] then
				return { ok = true, reason = nil, pending = false }
			end
			local triedAt = joinTriedAt[userId]
			if triedAt ~= nil and deps.clock() - triedAt < JOIN_RETRY_SEC then
				return { ok = false, reason = "market_settling", pending = true }
			end
			local realmId = deps.realmFor(userId)
			local settlement = settlementFor(userId)
			if realmId == nil or settlement == nil then
				return { ok = false, reason = "market_unavailable", pending = false }
			end
			joinTriedAt[userId] = deps.clock()
			local healed = settlement.heal()
			local problem: string? = if healed.ok then nil else healed.reason
			for _, bookId in bookIds do
				local claimed = settlement.claimAll(realmId, bookId)
				if not claimed.ok then
					problem = claimed.reason
				end
				refreshBook(realmId, bookId)
			end
			if type(problem) == "string" then
				return { ok = false, reason = problem, pending = true }
			end
			joined[userId] = true
			joinTriedAt[userId] = nil
			return { ok = true, reason = nil, pending = false }
		end

		local function context(userId: number, materialId: unknown): (Settlement?, string?, string?)
			local realmId = deps.realmFor(userId)
			if realmId == nil then
				return nil, nil, "market_unavailable"
			end
			if
				type(materialId) ~= "string"
				or ((materialById)[materialId] == nil and not MarketGoods.isCategoryBook(materialId))
			then
				return nil, nil, "material_unknown"
			end
			local settlement = settlementFor(userId)
			if settlement == nil then
				return nil, nil, "market_unavailable"
			end
			if not joined[userId] and not join(userId).ok then
				return nil, nil, "market_settling"
			end
			return settlement, realmId, nil
		end

		local function activeListings(userId: number, realmId: string): number
			local active = 0
			local listedAt = deps.clock()
			for _, bookId in bookIds do
				local book = bookCache[realmId .. "|" .. bookId]
				if book ~= nil then
					active += #(MarketBookCore.search(book, { sellerId = userId }, listedAt) or {})
				end
			end
			local wallet = deps.walletFor(userId)
			local state = if wallet ~= nil then wallet.read() else nil
			if state ~= nil then
				for _, pending in state.pending do
					if pending.kind == "consign" then
						active += 1
					end
				end
			end
			return active
		end

		local function list(userId: number, materialId: unknown, count: unknown, unitPrice: unknown): Outcome
			local settlement, realmId, refusal = context(userId, materialId)
			if settlement == nil or realmId == nil then
				return { ok = false, reason = refusal, pending = false }
			end
			if
				type(materialId) ~= "string"
				or type(count) ~= "number"
				or type(unitPrice) ~= "number"
				or not whole(count, 1, deps.catalog.maxQuantity)
				or not whole(unitPrice, 1, deps.catalog.maxUnitPrice)
			then
				return { ok = false, reason = "market_request_invalid", pending = false }
			end
			if not deps.tradingAllowed(userId) then
				return { ok = false, reason = "trading_not_allowed", pending = false }
			end
			if activeListings(userId, realmId) >= MarketService.MAX_ACTIVE_LISTINGS then
				return { ok = false, reason = "seller_listing_cap", pending = false }
			end
			return done(settlement.consign(realmId, materialId, count, unitPrice), realmId, materialId)
		end

		local function itemBook(itemId: unknown): (string?, Item<R>?, string?)
			if type(itemId) ~= "string" then
				return nil, nil, "market_request_invalid"
			end
			if (materialById)[itemId] ~= nil then
				return nil, nil, "material_unknown"
			end
			local def = items.get(itemId)
			local bookId, reason = MarketGoods.bookFor(def)
			if bookId == nil then
				return nil, nil, reason
			end
			return bookId, def, nil
		end

		local function itemCaps(): (number, number)
			local catalog = deps.catalog
			return catalog.maxItemQuantity or catalog.maxQuantity, catalog.maxItemUnitPrice or catalog.maxUnitPrice
		end

		local function listItem(userId: number, itemId: unknown, count: unknown, unitPrice: unknown): Outcome
			local bookId, _, refusal = itemBook(itemId)
			if bookId == nil then
				return { ok = false, reason = refusal, pending = false }
			end
			local settlement, realmId, contextRefusal = context(userId, bookId)
			if settlement == nil or realmId == nil then
				return { ok = false, reason = contextRefusal, pending = false }
			end
			local maxCount, maxPrice = itemCaps()
			if
				type(itemId) ~= "string"
				or type(count) ~= "number"
				or type(unitPrice) ~= "number"
				or not whole(count, 1, maxCount)
				or not whole(unitPrice, 1, maxPrice)
			then
				return { ok = false, reason = "market_request_invalid", pending = false }
			end
			if not deps.tradingAllowed(userId) then
				return { ok = false, reason = "trading_not_allowed", pending = false }
			end
			if activeListings(userId, realmId) >= MarketService.MAX_ACTIVE_LISTINGS then
				return { ok = false, reason = "seller_listing_cap", pending = false }
			end
			return done(settlement.consign(realmId, bookId, count, unitPrice, itemId), realmId, bookId)
		end

		local function buyItem(userId: number, itemId: unknown, quantity: unknown, ceilingUnitPrice: unknown): Outcome
			local bookId, _, refusal = itemBook(itemId)
			if bookId == nil then
				return { ok = false, reason = refusal, pending = false }
			end
			local settlement, realmId, contextRefusal = context(userId, bookId)
			if settlement == nil or realmId == nil then
				return { ok = false, reason = contextRefusal, pending = false }
			end
			local maxCount, maxPrice = itemCaps()
			if
				type(itemId) ~= "string"
				or type(quantity) ~= "number"
				or type(ceilingUnitPrice) ~= "number"
				or not whole(quantity, 1, maxCount)
				or not whole(ceilingUnitPrice, 1, maxPrice)
			then
				return { ok = false, reason = "market_request_invalid", pending = false }
			end
			if not deps.tradingAllowed(userId) then
				return { ok = false, reason = "trading_not_allowed", pending = false }
			end
			local wallet = deps.walletFor(userId)
			if wallet == nil or wallet.room(itemId) < quantity then
				return { ok = false, reason = "inventory_full", pending = false }
			end
			return done(settlement.buy(realmId, bookId, quantity, ceilingUnitPrice, itemId), realmId, bookId)
		end

		local function buy(userId: number, materialId: unknown, quantity: unknown, ceilingUnitPrice: unknown): Outcome
			local settlement, realmId, refusal = context(userId, materialId)
			if settlement == nil or realmId == nil then
				return { ok = false, reason = refusal, pending = false }
			end
			if
				type(materialId) ~= "string"
				or type(quantity) ~= "number"
				or type(ceilingUnitPrice) ~= "number"
				or not whole(quantity, 1, deps.catalog.maxQuantity)
				or not whole(ceilingUnitPrice, 1, deps.catalog.maxUnitPrice)
			then
				return { ok = false, reason = "market_request_invalid", pending = false }
			end
			if not deps.tradingAllowed(userId) then
				return { ok = false, reason = "trading_not_allowed", pending = false }
			end
			local wallet = deps.walletFor(userId)
			if wallet == nil or wallet.room(materialId) < quantity then
				return { ok = false, reason = "inventory_full", pending = false }
			end
			return done(settlement.buy(realmId, materialId, quantity, ceilingUnitPrice), realmId, materialId)
		end

		local function cancel(userId: number, materialId: unknown, listingId: unknown): Outcome
			local settlement, realmId, refusal = context(userId, materialId)
			if settlement == nil or realmId == nil then
				return { ok = false, reason = refusal, pending = false }
			end
			if type(materialId) ~= "string" or type(listingId) ~= "string" or #listingId == 0 or #listingId > 128 then
				return { ok = false, reason = "market_request_invalid", pending = false }
			end
			return done(settlement.cancel(realmId, materialId, listingId), realmId, materialId)
		end

		local function merchant(userId: number, side: string, materialId: unknown, count: unknown): Outcome
			local settlement, _, refusal = context(userId, materialId)
			if settlement == nil then
				return { ok = false, reason = refusal, pending = false }
			end
			if
				type(materialId) ~= "string"
				or type(count) ~= "number"
				or not whole(count, 1, deps.catalog.maxQuantity)
			then
				return { ok = false, reason = "market_request_invalid", pending = false }
			end
			local material = (materialById)[materialId]
			if material == nil then
				return { ok = false, reason = "material_unknown", pending = false }
			end
			local wallet = deps.walletFor(userId)
			if wallet == nil then
				return { ok = false, reason = "market_unavailable", pending = false }
			end
			if side == "buy" and wallet.room(materialId) < count then
				return { ok = false, reason = "inventory_full", pending = false }
			end
			local state = wallet.read()
			if state == nil then
				return { ok = false, reason = "market_unavailable", pending = false }
			end
			local traded = MarketWalletCore.npcTrade(
				state,
				side,
				materialId,
				count,
				if side == "sell" then material.npcFloor else material.npcCeiling
			)
			if not traded.ok then
				return { ok = false, reason = traded.reason, pending = false }
			end
			if not wallet.write(traded.state) then
				return { ok = false, reason = "wallet_not_durable", pending = false }
			end
			return { ok = true, reason = nil, pending = false }
		end

		local function npcSell(userId: number, materialId: unknown, count: unknown): Outcome
			return merchant(userId, "sell", materialId, count)
		end

		local function npcBuy(userId: number, materialId: unknown, count: unknown): Outcome
			return merchant(userId, "buy", materialId, count)
		end

		local function search(userId: number, materialId: unknown, ceilingUnitPrice: unknown): Outcome
			if
				type(materialId) ~= "string"
				or type(ceilingUnitPrice) ~= "number"
				or (materialId ~= "" and (materialById)[materialId] == nil)
				or not whole(ceilingUnitPrice, 0, deps.catalog.maxUnitPrice)
			then
				return { ok = false, reason = "market_request_invalid", pending = false }
			end
			searches[userId] = {
				materialId = if materialId == "" then nil else materialId,
				ceilingUnitPrice = if ceilingUnitPrice == 0 then nil else ceilingUnitPrice,
			}
			return { ok = true, reason = nil, pending = false }
		end

		local function searchRows(userId: number, realmId: string, nowSec: number)
			local stored = searches[userId]
			local query: SearchQuery = if stored ~= nil then stored else { materialId = nil, ceilingUnitPrice = nil }
			local rows: { SortedSearchRow } = {}
			for _, material in materials do
				local book = bookCache[realmId .. "|" .. material.id]
				if book ~= nil and (query.materialId == nil or query.materialId == material.id) then
					local page = MarketBookCore.search(book, {
						ceilingUnitPrice = query.ceilingUnitPrice,
						limit = deps.catalog.searchLimit,
					}, nowSec)
					for _, listing in (page or {}) do
						rows[#rows + 1] = {
							listingId = listing.listingId,
							listedAtSec = listing.listedAtSec,
							materialId = material.id,
							label = material.label,
							count = listing.count,
							unitPrice = listing.unitPrice,
							own = listing.sellerId == userId,
						}
					end
				end
			end
			table.sort(rows, listingBefore)
			local page: { SearchRow } = {}
			for index = 1, math.min(#rows, deps.catalog.searchLimit) do
				local row = rows[index]
				page[index] = table.freeze({
					materialId = row.materialId,
					label = row.label,
					count = row.count,
					unitPrice = row.unitPrice,
					own = row.own,
				})
			end
			return table.freeze({
				materialId = if query.materialId ~= nil then query.materialId else "",
				ceilingUnitPrice = if query.ceilingUnitPrice ~= nil then query.ceilingUnitPrice else 0,
				rows = table.freeze(page),
			})
		end

		local function searchItems(userId: number, filters: unknown): ItemPage<R>
			local realmId = deps.realmFor(userId)
			if realmId == nil then
				return { ok = false, reason = "market_unavailable", rows = {}, total = 0, page = 1 }
			end
			local query = itemFilters(filters)
			if query == nil then
				return { ok = false, reason = "market_request_invalid", rows = {}, total = 0, page = 1 }
			end
			local page = if query.page == nil then 1 else query.page
			if
				not whole(page, 1, 1000)
				or (query.ceilingUnitPrice ~= nil and not whole(query.ceilingUnitPrice, 1, config.maxSearchPrice))
				or (query.minLevel ~= nil and not whole(query.minLevel, 0, 100))
				or (query.maxLevel ~= nil and not whole(query.maxLevel, 0, 100))
				or (query.bookId ~= nil and not MarketGoods.isCategoryBook(query.bookId))
			then
				return { ok = false, reason = "market_request_invalid", rows = {}, total = 0, page = 1 }
			end
			local nowSec = deps.clock()
			local found: { SortedItemRow<R> } = {}
			for _, bookId in MarketGoods.bookIds() do
				local book = bookCache[realmId .. "|" .. bookId]
				if book ~= nil and (query.bookId == nil or query.bookId == bookId) then
					for _, listing in book.listings do
						local def = if listing.itemId ~= nil then items.get(listing.itemId) else nil
						if
							def ~= nil
							and listing.expiresAtSec > nowSec
							and (query.itemId == nil or listing.itemId == query.itemId)
							and (query.own ~= true or listing.sellerId == userId)
							and (query.ceilingUnitPrice == nil or listing.unitPrice <= query.ceilingUnitPrice)
							and matchesItem(def, query)
						then
							found[#found + 1] = {
								listingId = listing.listingId,
								listedAtSec = listing.listedAtSec,
								bookId = bookId,
								itemId = def.id,
								name = def.name,
								slot = def.slot,
								levelReq = def.levelReq,
								rarity = def.rarity,
								family = def.weaponFamily or def.armorFamily,
								count = listing.count,
								unitPrice = listing.unitPrice,
								own = listing.sellerId == userId,
								expiresAtSec = listing.expiresAtSec,
							}
						end
					end
				end
			end
			table.sort(found, listingBefore)
			local size = deps.catalog.searchLimit
			local rows: { ItemRow<R> } = {}
			for index = (page - 1) * size + 1, math.min(#found, page * size) do
				local row = found[index]
				rows[#rows + 1] = table.freeze({
					listingId = if row.own then row.listingId else nil,
					bookId = row.bookId,
					itemId = row.itemId,
					name = row.name,
					slot = row.slot,
					levelReq = row.levelReq,
					rarity = row.rarity,
					family = row.family,
					count = row.count,
					unitPrice = row.unitPrice,
					own = row.own,
					expiresAtSec = row.expiresAtSec,
				})
			end
			return { ok = true, reason = nil, rows = table.freeze(rows), total = #found, page = page }
		end

		local function listable(userId: number): { ListableItem<R> }
			local wallet = deps.walletFor(userId)
			local state = if wallet ~= nil then wallet.read() else nil
			local rows: { ListableItem<R> } = {}
			if state == nil then
				return rows
			end
			local maxCount = itemCaps()
			for itemId, count in state.goods do
				local def = items.get(itemId)
				if (materialById)[itemId] == nil and def ~= nil and MarketGoods.bookFor(def) ~= nil then
					rows[#rows + 1] = table.freeze({
						itemId = itemId,
						name = def.name,
						slot = def.slot,
						levelReq = def.levelReq,
						rarity = def.rarity,
						count = math.min(count, maxCount),
						suggestedPrice = math.max(1, (def.sellValue or 5) * 2),
					})
				end
			end
			table.sort(rows, function(left: ListableItem<R>, right: ListableItem<R>): boolean
				return left.itemId < right.itemId
			end)
			return rows
		end

		local function refresh(userId: number): Outcome
			local realmId = deps.realmFor(userId)
			local settlement = settlementFor(userId)
			if realmId == nil or settlement == nil then
				return { ok = false, reason = "market_unavailable", pending = false }
			end
			local healed = settlement.heal()
			local problem: string? = if healed.ok then nil else healed.reason
			for _, bookId in bookIds do
				local claimed = settlement.claimAll(realmId, bookId)
				if not claimed.ok then
					problem = claimed.reason
				end
				refreshBook(realmId, bookId)
			end
			return { ok = problem == nil, reason = problem, pending = problem ~= nil }
		end

		local function projection(userId: number): Projection
			local realmId = deps.realmFor(userId)
			local wallet = deps.walletFor(userId)
			local state = if wallet ~= nil then wallet.read() else nil
			if realmId == nil or state == nil then
				local empty: Projection = { available = false, realmId = false, feeBps = 0, materials = {} }
				return table.freeze(empty)
			end
			local rows: { MaterialProjection } = {}
			local nowSec = deps.clock()
			for _, material in materials do
				local book = bookCache[realmId .. "|" .. material.id]
				local listings: { MaterialListing } = {}
				local own: { OwnListing } = {}
				if book ~= nil then
					for _, listing in (MarketBookCore.search(book, {}, nowSec) or {}) do
						if listing.sellerId ~= userId and #listings < deps.catalog.visibleListings then
							listings[#listings + 1] =
								table.freeze({ count = listing.count, unitPrice = listing.unitPrice })
						end
					end
					for _, listing in (MarketBookCore.search(book, { sellerId = userId }, nowSec) or {}) do
						own[#own + 1] = table.freeze({
							listingId = listing.listingId,
							count = listing.count,
							unitPrice = listing.unitPrice,
							expiresAtSec = listing.expiresAtSec,
						})
					end
				end
				rows[#rows + 1] = table.freeze({
					materialId = material.id,
					label = material.label,
					held = state.goods[material.id] or 0,
					npcFloor = material.npcFloor,
					npcCeiling = material.npcCeiling,
					loaded = book ~= nil,
					listings = table.freeze(listings),
					own = table.freeze(own),
				})
			end
			return table.freeze({
				available = true,
				realmId = realmId,
				coin = state.coin,
				feeBps = MarketBookCore.DEFAULT_FEE_BPS,
				maxQuantity = deps.catalog.maxQuantity,
				maxUnitPrice = deps.catalog.maxUnitPrice,
				materials = table.freeze(rows),
				search = searchRows(userId, realmId, nowSec),
			})
		end

		local function forget(userId: number)
			settlements[userId] = nil
			joined[userId] = nil
			joinTriedAt[userId] = nil
			searches[userId] = nil
		end

		return table.freeze({
			join = join,
			list = list,
			buy = buy,
			cancel = cancel,
			refresh = refresh,
			npcSell = npcSell,
			npcBuy = npcBuy,
			listItem = listItem,
			buyItem = buyItem,
			searchItems = searchItems,
			listable = listable,
			search = search,
			projection = projection,
			forget = forget,
		}),
			nil
	end

	MarketService.MAX_ACTIVE_LISTINGS = config.maxActiveListings

	return table.freeze(MarketService)
end

return table.freeze({ configure = configure })
