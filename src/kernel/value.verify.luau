--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Value = require("../kernel/value")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("value", function()
		it("keeps permissive field copies separate from plain-record admission", function()
			local original = setmetatable({ held = 1 }, { __index = { virtual = 2 } })
			local fields = assert(Value.raw(original))
			expect(Value.hasMetatable(original)):toBe(true)
			original.held = 2
			expect(fields.held):toBe(1)
			expect(fields.virtual):toBe(nil)
			expect(Value.hasMetatable(fields)):toBe(false)
			expect(Value.record(original, { held = true }, true)):toBe(nil)
			expect(Value.record(fields, { held = true }, true) ~= nil):toBe(true)
		end)
		it("accepts only finite numbers", function()
			local accepted: { unknown } = { 0, -0.5, 1e308, -1e308, 2 ^ 53 }
			for _, value in accepted do
				expect(Value.finite(value)):toBe(true)
			end
			local refused: { unknown } = { math.nan, math.huge, -math.huge, "1", true, {}, nil }
			for _, value in refused do
				expect(Value.finite(value)):toBe(false)
			end
		end)

		it("accepts only strings with content", function()
			expect(Value.nonempty("a")):toBe(true)
			expect(Value.nonempty(" ")):toBe(true)
			local refused: { unknown } = { "", 1, true, {}, nil }
			for _, value in refused do
				expect(Value.nonempty(value)):toBe(false)
			end
		end)

		it("keeps whole numbers inside their bounds", function()
			expect(Value.whole(3, 1, 5)):toBe(3)
			expect(Value.whole(0, 1, 5)):toBeNil()
			expect(Value.whole(1.5, 1, 5)):toBeNil()
			expect(Value.whole(math.huge, 1, math.huge)):toBeNil()
			expect(Value.whole(math.nan, -math.huge, math.huge)):toBeNil()
		end)
	end)
end
