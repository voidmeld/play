--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Codec = require("./codec")
local Result = require("./result")
local Value = require("./value")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Row = { schemaVersion: number, amount: number }

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("record and persisted-data codecs", function()
		it("admits one version after game-owned migration and keeps its field policy detached", function()
			local fields = { schemaVersion = true, amount = true }
			local calls = 0
			local copy = Codec.versioned({
				version = 2,
				fields = fields,
				required = true,
				migrate = function(raw: unknown): unknown
					calls += 1
					local old = Value.record(raw, { schemaVersion = true, amountText = true }, true)
					if old and old.schemaVersion == 1 and type(old.amountText) == "string" then
						return { schemaVersion = 2, amount = tonumber(old.amountText) }
					end
					return raw
				end,
				decode = function(raw: Value.Raw): (Row?, string?)
					local amount = Value.whole(raw.amount, 0, 100)
					if amount == nil then
						return nil, "amount_invalid"
					end
					return { schemaVersion = 2, amount = amount }, nil
				end,
			})
			local migrated, reason = copy({ schemaVersion = 1, amountText = "7" })
			expect(migrated):toEqual({ schemaVersion = 2, amount = 7 })
			expect(reason):toBeNil()
			expect(calls):toBe(1)
			fields.extra = true
			expect(select(2, copy({ schemaVersion = 2, amount = 7, extra = true }))):toBe("record_invalid")
			expect(select(2, copy({ schemaVersion = 3, amount = 7 }))):toBe("schema_unsupported")
			expect(select(2, copy({ schemaVersion = 2, amount = -1 }))):toBe("amount_invalid")
			expect(select(2, copy(setmetatable({ schemaVersion = 2, amount = 7 }, {})))):toBe("record_invalid")
		end)
		it("copies shared acyclic data without retaining the original graph", function()
			local shared = { amount = 7 }
			local original = { first = shared, second = shared }
			local copied = assert(Value.raw(Result.unwrap(Codec.copyData(original))))
			expect(copied.first):toBe(copied.second)
			expect(copied.first).never:toBe(shared)
			local child = copied.first
			assert(type(child) == "table")
			table.clear(child)
			expect(shared.amount):toBe(7)
			expect(Result.unwrap(Codec.copyData(nil))):toBeNil()
			expect(Result.unwrap(Codec.copyData(false))):toBe(false)
		end)
		it("refuses cycles, metatables, nonfinite values and executable leaves", function()
			local cycle: Value.Raw = {}
			cycle.self = cycle
			for _, invalid in { cycle, setmetatable({}, {}), { amount = math.huge }, { run = function() end } } do
				expect(Result.reason(Codec.copyData(invalid))):toBe("value_invalid")
			end
			expect(Result.reason(Codec.copyData({ [math.huge] = "invalid" }))):toBe("value_invalid")
		end)
		it("compares all admitted fields and refuses invalid data even against itself", function()
			expect(Codec.equalData({ amount = 7 }, { amount = 7 })):toBe(true)
			expect(Codec.equalData({ amount = 7 }, { amount = 8 })):toBe(false)
			expect(Codec.equalData({ amount = 7 }, { amount = 7, extra = true })):toBe(false)
			local invalid = setmetatable({ amount = 7 }, {})
			expect(Codec.equalData(invalid, invalid)):toBe(false)
		end)
	end)
end
