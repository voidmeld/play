--!strict

local Bank = require("./vault")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type Wear = { bag: { [string]: { number } }, bank: { [string]: { number } } }
type Profile = {
	inventory: Bank.Inventory,
	bank: Bank.State,
	collections: { [string]: boolean }?,
	itemWear: Wear?,
	bagSlots: number?,
}

local function config(): Bank.Config<Profile>
	return {
		maxStack = 9999,
		maxBagSlots = 512,
		maxBankSlots = 80,
		maxReceipts = 32,
		itemIdLimit = 64,
		bankerIdLimit = 64,
		requestIdLimit = 40,
		readProfile = function(profile: Profile): unknown
			return { inventory = profile.inventory, bank = profile.bank }
		end,
		writeProfile = function(profile: Profile, inventory: Bank.Inventory, bank: Bank.State): Profile
			local updated = table.clone(profile)
			updated.inventory, updated.bank = inventory, bank
			return updated
		end,
		permanent = function(itemId: string): boolean
			return itemId == "keepsake"
		end,
		fits = function(profile: Profile, before: Bank.Inventory, after: Bank.Inventory): boolean
			local function entries(inventory: Bank.Inventory): number
				local count = 0
				for itemId in inventory do
					if itemId ~= "keepsake" then
						count += 1
					end
				end
				return count
			end
			return entries(after) <= math.max(profile.bagSlots or 24, entries(before))
		end,
		transfer = function(profile: Profile, request: Bank.Request): Profile
			local wear = profile.itemWear
			if wear == nil then
				return profile
			end
			local function copy(storage: { [string]: { number } }): { [string]: { number } }
				local out: { [string]: { number } } = {}
				for itemId, list in storage do
					out[itemId] = table.clone(list)
				end
				return out
			end
			local updated = table.clone(profile)
			local moved = { bag = copy(wear.bag), bank = copy(wear.bank) }
			local source = if request.kind == "deposit" then moved.bag else moved.bank
			local destination = if request.kind == "deposit" then moved.bank else moved.bag
			local copies: { number } = source[request.itemId] or {}
			local received: { number } = destination[request.itemId] or {}
			for _ = 1, math.min(request.count, #copies) do
				local amount = assert(table.remove(copies, 1))
				if amount > 0 then
					table.insert(received, amount)
				end
			end
			table.sort(received, function(a: number, b: number): boolean
				return a > b
			end)
			source[request.itemId] = if #copies > 0 then copies else nil
			destination[request.itemId] = if #received > 0 then received else nil
			updated.itemWear = moved
			return updated
		end,
	}
end

local settings = config()
local vault = Bank.vault(settings)

local function request(kind: string, itemId: string, count: number, id: string)
	return { kind = kind, itemId = itemId, count = count, bankerId = "keeper", requestId = id }
end

return function(suite: Verify.Harness)
	suite:case("refuses permanent carried items without moving or duplicating them", function(context)
		local source: Profile = { inventory = { keepsake = 1 }, bank = vault.default(), collections = {} }
		local deposited, reason = vault.apply(source, request("deposit", "keepsake", 1, "permanent-deposit"))
		context:expect(deposited):toBeNil()
		context:expect(reason):toBe("item_permanent")
		context:expect(source.inventory.keepsake):toBe(1)
		context:expect(source.bank.items.keepsake):toBeNil()
	end)

	suite:case("moves only the deposited worn copy and does not replay its condition movement", function(context)
		local wear: Wear = { bag = {}, bank = {} }
		wear.bag.sword = { 71 }
		local source: Profile = { inventory = { sword = 2 }, bank = vault.default(), collections = {}, itemWear = wear }
		local deposited = assert(vault.apply(source, request("deposit", "sword", 1, "worn-deposit")))
		context:expect(assert(deposited.itemWear).bank.sword):toEqual({ 71 })
		context:expect(assert(deposited.itemWear).bag.sword):toBeNil()
		context:expect(deposited.inventory.sword):toBe(1)
		context:expect(assert(source.itemWear).bag.sword):toEqual({ 71 })
		context:expect((vault.apply(deposited, request("deposit", "sword", 1, "worn-deposit")))):toBe(deposited)
		local withdrawn = assert(vault.apply(deposited, request("withdraw", "sword", 1, "worn-withdraw")))
		context:expect(assert(withdrawn.itemWear).bag.sword):toEqual({ 71 })
		context:expect(assert(withdrawn.itemWear).bank.sword):toBeNil()
		context:expect(withdrawn.inventory.sword):toBe(2)
	end)

	suite:case("moves one owned stack between carried and bank without changing the total", function(context)
		local source: Profile = { inventory = { ore = 3 }, bank = vault.default(), collections = {} }
		local deposited = assert(vault.apply(source, request("deposit", "ore", 2, "d1")))
		context:expect(source.inventory.ore):toBe(3)
		context:expect(deposited.inventory.ore):toBe(1)
		context:expect(deposited.bank.items.ore):toBe(2)
		table.freeze(deposited.bank.items)
		table.freeze(deposited.bank.receipts)
		table.freeze(deposited.bank.receiptOrder)
		local withdrawn = assert(vault.apply(deposited, request("withdraw", "ore", 1, "w1")))
		context:expect(withdrawn.inventory.ore):toBe(2)
		context:expect(withdrawn.bank.items.ore):toBe(1)
		context:expect(deposited.bank.items.ore):toBe(2)
		context:expect(withdrawn.inventory.ore + withdrawn.bank.items.ore):toBe(3)
	end)

	suite:case("refuses invalid counts, unknown items, full slots and overflowing stacks", function(context)
		context:expect(vault.request(request("deposit", "ore", math.huge - math.huge, "nan"))):toBeNil()
		context
			:expect(vault.request({
				kind = "deposit",
				itemId = "ore",
				count = 1,
				bankerId = "b",
				requestId = "x",
				text = "hi",
			}))
			:toBeNil()
		local source: Profile = { inventory = { ore = 3 }, bank = vault.default(), collections = {} }
		context:expect((vault.apply(source, request("deposit", "wood", 1, "missing")))):toBeNil()
		local full = vault.default()
		for index = 1, settings.maxBankSlots do
			full.items["item" .. index] = 1
		end
		context
			:expect((vault.apply({ inventory = { ore = 3 }, bank = full }, request("deposit", "ore", 1, "full"))))
			:toBeNil()
		local stacked = vault.default()
		stacked.items.ore = settings.maxStack
		context
			:expect((vault.apply({ inventory = { ore = 3 }, bank = stacked }, request("deposit", "ore", 1, "stack"))))
			:toBeNil()
	end)

	suite:case("evicts old receipts and replays a request within the receipt ring", function(context)
		local current: Profile = { inventory = { ore = 1 }, bank = vault.default(), collections = {} }
		local transfers = settings.maxReceipts * 2
		for index = 1, transfers do
			local action = request(if index % 2 == 1 then "deposit" else "withdraw", "ore", 1, "turn" .. index)
			current = assert(vault.apply(current, action))
		end
		context:expect(#current.bank.receiptOrder):toBe(settings.maxReceipts)
		context:expect(current.bank.receipts.turn1):toBeNil()
		context:expect(current.bank.receiptOrder[1]):toBe("turn" .. (settings.maxReceipts + 1))
		local recent = request("withdraw", "ore", 1, "turn" .. transfers)
		context:expect((vault.apply(current, recent))):toBe(current)
		context:expect((vault.apply(current, request("withdraw", "ore", 2, "turn" .. transfers)))):toBeNil()
	end)

	suite:case("compacts legacy receipt maps on projection", function(context)
		local legacy: { items: Bank.Inventory, receipts: { [string]: Bank.Request } } = { items = {}, receipts = {} }
		for index = 1, 100 do
			legacy.receipts["old" .. index] = assert(vault.request(request("deposit", "ore", 1, "old" .. index)))
		end
		local projected = assert(vault.project(legacy))
		context:expect(#projected.receiptOrder):toBe(settings.maxReceipts)
		context:expect(#assert(vault.project(projected)).receiptOrder):toBe(settings.maxReceipts)
	end)

	suite:case("uses configured stack and identifier bounds for requests and stored items", function(context)
		local settings = config()
		settings.maxStack, settings.itemIdLimit, settings.bankerIdLimit, settings.requestIdLimit = 3, 2, 3, 4
		local small = Bank.vault(settings)
		local valid = { kind = "deposit", itemId = "ab", count = 3, bankerId = "abc", requestId = "abcd" }
		context:expect(small.request(valid)):toEqual(valid)
		local tooMany = table.clone(valid)
		tooMany.count = 4
		context:expect(small.request(tooMany)):toBeNil()
		local longItem = table.clone(valid)
		longItem.itemId = "abc"
		context:expect(small.request(longItem)):toBeNil()
		local longBanker = table.clone(valid)
		longBanker.bankerId = "abcd"
		context:expect(small.request(longBanker)):toBeNil()
		local longRequest = table.clone(valid)
		longRequest.requestId = "abcde"
		context:expect(small.request(longRequest)):toBeNil()
		context:expect(small.project({ items = { abc = 1 }, receipts = {} })):toBeNil()
		context:expect(small.project({ items = { ab = 4 }, receipts = {} })):toBeNil()
		local bank = small.default()
		bank.items.ab = 3
		local updated, reason = small.apply(
			{ inventory = { ab = 1 }, bank = bank },
			{ kind = "deposit", itemId = "ab", count = 1, bankerId = "a", requestId = "a" }
		)
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("destination_full")
	end)

	suite:case("uses configured bank, bag and receipt capacities", function(context)
		local settings = config()
		settings.maxBankSlots, settings.maxBagSlots, settings.maxReceipts = 1, 2, 2
		local small = Bank.vault(settings)
		local bank = small.default()
		bank.items.other = 1
		local updated, reason =
			small.apply({ inventory = { ore = 1 }, bank = bank }, request("deposit", "ore", 1, "full"))
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("destination_full")
		context:expect(small.project({ items = { ore = 1, other = 1 }, receipts = {} })):toBeNil()
		updated, reason = small.apply(
			{ inventory = { a = 1, b = 1, c = 1 }, bank = small.default() },
			request("deposit", "a", 1, "bag")
		)
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("bank_request_invalid")
		updated, reason =
			small.apply({ inventory = { a = 1, b = 1 }, bank = bank }, request("withdraw", "other", 1, "bag"))
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("destination_full")
		local current: Profile = { inventory = { ore = 1 }, bank = small.default() }
		for index = 1, 4 do
			current = assert(
				small.apply(current, request(if index % 2 == 1 then "deposit" else "withdraw", "ore", 1, "r" .. index))
			)
		end
		context:expect(current.bank.receiptOrder):toEqual({ "r3", "r4" })
		context:expect(current.bank.receipts.r1):toBeNil()
		context:expect((small.apply(current, request("withdraw", "ore", 1, "r4")))):toBe(current)
		local legacy: { items: Bank.Inventory, receipts: { [string]: Bank.Request } } = { items = {}, receipts = {} }
		for index = 1, 3 do
			legacy.receipts["r" .. index] = assert(small.request(request("deposit", "ore", 1, "r" .. index)))
		end
		context:expect(#assert(small.project(legacy)).receiptOrder):toBe(2)
	end)

	suite:case("uses the game's permanent and fit policies and preserves over-capacity withdrawals", function(context)
		local settings = config()
		settings.permanent = function(itemId: string): boolean
			return itemId == "ore"
		end
		local restricted = Bank.vault(settings)
		local updated, reason = restricted.apply(
			{ inventory = { ore = 1 }, bank = restricted.default() },
			request("deposit", "ore", 1, "blocked")
		)
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("item_permanent")
		local bank = vault.default()
		bank.items.ore = 1
		updated, reason =
			vault.apply({ inventory = { other = 1 }, bank = bank, bagSlots = 1 }, request("withdraw", "ore", 1, "full"))
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("destination_full")
		context
			:expect(
				vault.apply(
					{ inventory = { ore = 1, other = 1 }, bank = bank, bagSlots = 1 },
					request("withdraw", "ore", 1, "stack")
				) ~= nil
			)
			:toBe(true)
		settings = config()
		settings.fits = function(_profile: Profile, _before: Bank.Inventory, _after: Bank.Inventory): boolean
			return false
		end
		local noFit = Bank.vault(settings)
		context
			:expect(
				noFit.apply({ inventory = { ore = 1 }, bank = bank }, request("deposit", "ore", 1, "deposit")) ~= nil
			)
			:toBe(true)
		updated, reason = noFit.apply({ inventory = {}, bank = bank }, request("withdraw", "ore", 1, "withdraw"))
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("destination_full")
	end)

	suite:case("uses profile bindings and invokes metadata transfer only for successful new requests", function(context)
		local settings = config()
		local writes, transfers = 0, 0
		settings.writeProfile = function(profile: Profile, inventory: Bank.Inventory, bank: Bank.State): Profile
			writes += 1
			local updated = table.clone(profile)
			updated.inventory, updated.bank = inventory, bank
			return updated
		end
		settings.transfer = function(profile: Profile, _request: Bank.Request): Profile
			transfers += 1
			return profile
		end
		local bound = Bank.vault(settings)
		local source: Profile = { inventory = { ore = 1 }, bank = bound.default(), collections = { known = true } }
		local deposited = assert(bound.apply(source, request("deposit", "ore", 1, "d")))
		context:expect(deposited.collections):toEqual({ known = true })
		context:expect(deposited.inventory):toEqual({})
		context:expect((bound.apply(deposited, request("deposit", "ore", 1, "d")))):toBe(deposited)
		local rejected, reason = bound.apply(deposited, request("deposit", "ore", 2, "d"))
		context:expect(rejected):toBeNil()
		context:expect(reason):toBe("request_conflict")
		context:expect(writes):toBe(1)
		context:expect(transfers):toBe(1)
		settings = config()
		settings.readProfile = function(_profile: Profile): unknown
			return { inventory = {} }
		end
		rejected, reason = Bank.vault(settings).apply(source, request("deposit", "ore", 1, "d"))
		context:expect(rejected):toBeNil()
		context:expect(reason):toBe("bank_state_invalid")
		settings.readProfile = function(_profile: Profile): unknown
			return false
		end
		rejected, reason = Bank.vault(settings).apply(source, request("deposit", "ore", 1, "d"))
		context:expect(rejected):toBeNil()
		context:expect(reason):toBe("bank_request_invalid")
	end)

	suite:case("validates exact plain records and dense, complete receipt orders", function(context)
		context:expect(vault.project(nil)):toEqual(vault.default())
		local first = assert(vault.request(request("deposit", "ore", 1, "d")))
		local cases: { unknown } = {
			{ items = {}, receipts = {}, extra = true },
			{ items = { ore = 0 }, receipts = {} },
			{ items = {}, receipts = { d = first }, receiptOrder = {} },
			{ items = {}, receipts = {}, receiptOrder = { "d" } },
			{ items = {}, receipts = { d = first }, receiptOrder = { "d", "d" } },
			{ items = {}, receipts = { d = first }, receiptOrder = { [2] = "d" } },
			{ items = {}, receipts = { d = first }, receiptOrder = { ["extra"] = "d" } },
			{ items = {}, receipts = { wrong = first }, receiptOrder = { "wrong" } },
			{ items = {}, receipts = { d = first }, receiptOrder = false },
			setmetatable(vault.default(), {}),
			{ items = setmetatable({}, {}), receipts = {} },
			{ items = {}, receipts = setmetatable({}, {}) },
			{ items = {}, receipts = {}, receiptOrder = setmetatable({}, {}) },
		}
		for _, value in cases do
			context:expect(vault.project(value)):toBeNil()
		end
		context:expect(vault.request(setmetatable(request("deposit", "ore", 1, "d"), {}))):toBeNil()
		local otherId = table.clone(first)
		otherId.requestId = "other"
		context:expect(vault.sameRequest(first, otherId)):toBe(true)
		otherId.bankerId = "other"
		context:expect(vault.sameRequest(first, otherId)):toBe(false)
	end)

	suite:case(
		"shares bounded inventory adjustments while preserving existing slots and input values",
		function(context)
			local source: Bank.Inventory = { ore = 2 }
			context:expect((Bank.adjust(source, "ore", 1, 3, 0))):toEqual({ ore = 3 })
			context:expect((Bank.adjust(source, "ore", -2, 3, 0))):toEqual({})
			local adjusted, reason = Bank.adjust(source, "ore", -3, 3, 1)
			context:expect(adjusted):toBeNil()
			context:expect(reason):toBe("goods_insufficient")
			adjusted, reason = Bank.adjust(source, "ore", 2, 3, 1)
			context:expect(adjusted):toBeNil()
			context:expect(reason):toBe("inventory_full")
			adjusted, reason = Bank.adjust(source, "wood", 1, 3, 1)
			context:expect(adjusted):toBeNil()
			context:expect(reason):toBe("inventory_full")
			context:expect(source):toEqual({ ore = 2 })
		end
	)
end
