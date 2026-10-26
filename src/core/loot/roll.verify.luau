--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./roll")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local MobLootRoll = Module.roll({ receiptPrefix = "loot:" })
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	local TABLES = {
		{
			id = "test.loot",
			zoneId = "test",
			mobIds = { "test.husk", "test.binder" },
			rolls = {
				{ itemId = "material", weight = 1, minCount = 1, maxCount = 3 },
				{ itemId = "helmet", weight = 1, minCount = 1, maxCount = 1 },
			},
		},
	}

	describe("MobLootRoll", function()
		it("finds the authored table that names the defeated enemy", function()
			expect(assert(MobLootRoll.tableForMob(TABLES, "test.binder")).id):toBe("test.loot")
			expect(MobLootRoll.tableForMob(TABLES, "test.unnamed")):toBeNil()
			expect(MobLootRoll.tableForMob(nil, "test.husk")):toBeNil()
		end)

		it("hands the same defeat the same drop every time it is replayed", function()
			local first = assert(MobLootRoll.dropFor(TABLES, "test.husk", "7", 400))
			local again = assert(MobLootRoll.dropFor(TABLES, "test.husk", "7", 400))
			expect(again):toEqual(first)
		end)

		it("separates two players who felled their own copy of the same enemy", function()
			local mine = assert(MobLootRoll.dropFor(TABLES, "test.husk", "7", 400))
			local theirs = assert(MobLootRoll.dropFor(TABLES, "test.husk", "9", 400))
			local mineReceipt = MobLootRoll.receiptFor(mine, "test.husk", "7", 400)
			local theirsReceipt = MobLootRoll.receiptFor(theirs, "test.husk", "9", 400)
			expect(mineReceipt == theirsReceipt):toBe(false)
		end)

		it("only ever names an authored item and an authored count", function()
			local counts: { [number]: boolean } = {}
			local items: { [string]: boolean } = {}
			for tick = 1, 400 do
				local drop = assert(MobLootRoll.dropFor(TABLES, "test.husk", "7", tick))
				items[drop.itemId] = true
				counts[drop.count] = true
				if drop.itemId == "helmet" then
					expect(drop.count):toBe(1)
				end
				expect(drop.count >= 1):toBe(true)
				expect(drop.count <= 3):toBe(true)
			end
			local distinct = 0
			for _ in items do
				distinct += 1
			end
			expect(items.material):toBe(true)
			expect(items.helmet):toBe(true)
			expect(distinct):toBe(2)
			expect(counts[1]):toBe(true)
		end)

		it("rolls the same pinned drops on every host because the stream stays in exact integer range", function()
			local picks: { string } = {}
			for tick = 1, 4 do
				local drop = assert(MobLootRoll.dropFor(TABLES, "test.husk", "7", tick))
				table.insert(picks, `{drop.itemId}x{drop.count}`)
			end
			expect(picks):toEqual({ "materialx1", "materialx1", "helmetx1", "helmetx1" })
			local wide = assert(MobLootRoll.dropFor(TABLES, "test.husk", "123456789012", 2147483646))
			expect(wide.itemId):toBe("helmet")
		end)

		it("refuses a defeat it cannot place in the world", function()
			expect(MobLootRoll.dropFor(TABLES, "test.husk", "", 1)):toBeNil()
			expect(MobLootRoll.dropFor(TABLES, "test.husk", "7", -1)):toBeNil()
			expect(MobLootRoll.dropFor(TABLES, nil, "7", 1)):toBeNil()
		end)

		it("drops an authored roll whose numbers are not whole and positive", function()
			expect(MobLootRoll.validRoll({ itemId = "material", weight = 0, minCount = 1, maxCount = 1 })):toBeNil()
			expect(MobLootRoll.validRoll({ itemId = "material", weight = 1, minCount = 2, maxCount = 1 })):toBeNil()
			expect(MobLootRoll.validRoll({ itemId = "", weight = 1, minCount = 1, maxCount = 1 })):toBeNil()
			expect(MobLootRoll.validRoll({ itemId = "material", weight = 1.5, minCount = 1, maxCount = 1 })):toBeNil()
		end)

		it("draws several distinct items from a table that asks for picks", function()
			local pickTable = {
				{
					id = "test.boss",
					zoneId = "test",
					mobIds = { "test.boss" },
					picks = 3,
					rolls = {
						{ itemId = "material", weight = 1, minCount = 1, maxCount = 1 },
						{ itemId = "helmet", weight = 5, minCount = 1, maxCount = 1 },
						{ itemId = "armor", weight = 1, minCount = 1, maxCount = 1 },
						{ itemId = "tonic", weight = 3, minCount = 1, maxCount = 2 },
					},
				},
			}
			for tick = 1, 60 do
				local drops = MobLootRoll.dropsFor(pickTable, "test.boss", "7", tick)
				expect(#drops):toBe(3)
				local seen: { [string]: boolean } = {}
				local receipts: { [string]: boolean } = {}
				for pick, drop in drops do
					expect(seen[drop.itemId]):toBeNil()
					seen[drop.itemId] = true
					receipts[MobLootRoll.receiptFor(drop, "test.boss", "7", tick, nil, pick)] = true
				end
				local distinctReceipts = 0
				for _ in receipts do
					distinctReceipts += 1
				end
				expect(distinctReceipts):toBe(3)
				expect(MobLootRoll.dropsFor(pickTable, "test.boss", "7", tick)):toEqual(drops)
			end
		end)

		it("keeps a single roll for a table without picks and matches dropFor", function()
			for tick = 1, 20 do
				local single = MobLootRoll.dropsFor(TABLES, "test.husk", "7", tick)
				expect(#single):toBe(1)
				expect(single[1]):toEqual(assert(MobLootRoll.dropFor(TABLES, "test.husk", "7", tick)))
			end
		end)

		it("never promises more picks than the table can fill", function()
			local small = {
				{
					id = "test.small",
					zoneId = "test",
					mobIds = { "test.small" },
					picks = 5,
					rolls = {
						{ itemId = "material", weight = 1, minCount = 1, maxCount = 1 },
						{ itemId = "tonic", weight = 1, minCount = 1, maxCount = 1 },
					},
				},
			}
			expect(#MobLootRoll.dropsFor(small, "test.small", "7", 3)):toBe(2)
		end)
	end)
	it("uses the supplied receipt namespace and distinguishes epoch and pick identities", function()
		local law = Module.roll({ receiptPrefix = "drop:" })
		local drop = { tableId = "table", itemId = "item", count = 1 }
		expect(law.receiptFor(drop, "mob", "actor", 42)):toBe("drop:table:mob:actor:42")
		expect(law.receiptFor(drop, "mob", "actor", 42, 3, 1)):toBe("drop:epoch:3:table:mob:actor:42")
		expect(law.receiptFor(drop, "mob", "actor", 42, 3, 2)):toBe("drop:epoch:3:table:mob:actor:42:p2")
	end)
	it("ignores invalid rows and falls back to one pick for invalid pick counts", function()
		local tables = {
			{
				id = "table",
				mobIds = { "mob" },
				picks = 0,
				rolls = {
					false,
					{ itemId = "bad", weight = math.huge, minCount = 1, maxCount = 1 },
					{ itemId = "good", weight = 1, minCount = 2, maxCount = 2 },
				},
			},
		}
		expect(MobLootRoll.dropsFor(tables, "mob", "actor", 0)):toEqual({
			{ tableId = "table", itemId = "good", count = 2 },
		})
		expect(MobLootRoll.dropsFor(tables, "mob", "", 0)):toEqual({})
		expect(MobLootRoll.dropsFor(tables, "mob", "actor", 0.5)):toEqual({})
		expect(MobLootRoll.dropsFor(tables, "mob", "actor", math.huge)):toEqual({})
		expect(MobLootRoll.dropFor({ { id = "empty", mobIds = { "mob" }, rolls = {} } }, "mob", "actor", 0)):toBeNil()
	end)
	it("returns the first matching source table with its metadata and identity intact", function()
		local first = { id = "first", mobIds = { "mob" }, rolls = {}, authoredTag = "retained" }
		local second = { id = "second", mobIds = { "mob" }, rolls = {}, authoredTag = "other" }
		local found = assert(MobLootRoll.tableForMob({ first, second }, "mob"))
		expect(found):toBe(first)
		expect(found.authoredTag):toBe("retained")
	end)
end
