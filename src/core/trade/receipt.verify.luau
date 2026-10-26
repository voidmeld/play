--!strict

local Exchange = require("./exchange")
local Receipts = require("./receipt")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local exchange =
	Exchange.exchange({ maxItems = 2, maxCount = 3, maxCoin = 4, maxUserId = 10, maxRevision = 2, idLimit = 8 })
local settings: Receipts.Config = {
	offer = exchange.offer,
	tradeIdLimit = 2,
	characterIdLimit = 3,
	maxUserId = 10,
	maxRevision = 2,
	maxTimestamp = 20,
	maxPointers = 1,
}
local receipts = Receipts.receipts(settings)

local function receipt(): Receipts.Projected
	return {
		tradeId = "ab",
		players = { 1, 10 },
		revision = 2,
		expiresAt = 20,
		phase = "prepared",
		offers = { [1] = { coin = 4, items = {} }, [10] = { coin = 0, items = { { itemId = "ore", count = 3 } } } },
		characters = { [1] = "one", [10] = "ten" },
		grants = { [1] = true },
	}
end

return function(suite: Verify.Harness)
	suite:case("projects numeric and wire maps, copies records and preserves grant markers", function(context)
		local source = receipt()
		local projected = assert(receipts.project(source))
		context:expect(projected):toEqual(source)
		context:expect(projected == source):toBe(false)
		context:expect(projected.players == source.players):toBe(false)
		local wire = assert(receipts.wire(projected))
		context:expect(wire.characters["10"]):toBe("ten")
		context:expect(wire.grants["1"]):toBe(true)
		context:expect(receipts.project(wire)):toEqual(source)
		context:expect(table.isfrozen(wire.offers["1"])):toBe(true)
	end)

	suite:case("uses configured trade, character, user, revision, time and offer bounds", function(context)
		local cases: { Receipts.Projected } = {}
		local value = receipt()
		value.tradeId = "abc"
		table.insert(cases, value)
		value = receipt()
		value.characters[1] = "long"
		table.insert(cases, value)
		value = receipt()
		value.players[2] = 11
		table.insert(cases, value)
		value = receipt()
		value.revision = 3
		table.insert(cases, value)
		value = receipt()
		value.expiresAt = 21
		table.insert(cases, value)
		value = receipt()
		value.expiresAt = 0
		table.insert(cases, value)
		value = receipt()
		value.offers[1].coin = 5
		table.insert(cases, value)
		for _, candidate in cases do
			context:expect(receipts.project(candidate)):toBeNil()
		end
		local cfg = table.clone(settings)
		cfg.offer = function(_value: unknown): Exchange.Offer?
			return nil
		end
		context:expect(Receipts.receipts(cfg).project(receipt())):toBeNil()
	end)

	suite:case(
		"rejects mixed aliases, extra participants, bad phases, false grants and unknown fields",
		function(context)
			local wire = assert(receipts.wire(receipt()))
			local offers: { [unknown]: unknown } =
				{ ["1"] = wire.offers["1"], ["10"] = wire.offers["10"], [1] = wire.offers["1"] }
			local malformed: { [string]: unknown } = {
				tradeId = wire.tradeId,
				players = wire.players,
				offers = offers,
				characters = wire.characters,
				grants = wire.grants,
				phase = wire.phase,
				revision = wire.revision,
				expiresAt = wire.expiresAt,
			}
			context:expect(receipts.project(malformed)):toBeNil()
			malformed.offers = wire.offers
			malformed.phase = "open"
			context:expect(receipts.project(malformed)):toBeNil()
			malformed.phase = "committed"
			malformed.grants = { ["1"] = false }
			context:expect(receipts.project(malformed)):toBeNil()
			malformed.grants = { ["9"] = true }
			context:expect(receipts.project(malformed)):toBeNil()
			malformed.grants = wire.grants
			malformed.extra = true
			context:expect(receipts.project(malformed)):toBeNil()
			context:expect(receipts.project(setmetatable(receipt(), {}))):toBeNil()
		end
	)

	suite:case("uses configured pointer capacity and validates receipt identity", function(context)
		context:expect(receipts.pointers(nil)):toEqual({})
		local first = receipt()
		local second = receipt()
		second.tradeId = "cd"
		local pointers = { ab = { tradeId = "ab", receipt = first }, cd = { tradeId = "cd", receipt = second } }
		context:expect(receipts.pointers({ ab = pointers.ab }) ~= nil):toBe(true)
		context:expect(receipts.pointers(pointers)):toBeNil()
		local cfg = table.clone(settings)
		cfg.maxPointers = 2
		context:expect(Receipts.receipts(cfg).pointers(pointers) ~= nil):toBe(true)
		context:expect(receipts.pointers({ ab = pointers.cd })):toBeNil()
		context:expect(receipts.pointers({ ab = { tradeId = "ab", receipt = second } })):toBeNil()
		context:expect(receipts.pointers({ ab = { tradeId = "ab", receipt = first, extra = true } })):toBeNil()
	end)
end
