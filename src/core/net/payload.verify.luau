--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Payload = require("./payload")
local Result = require("../../kernel/result")
local Value = require("../../kernel/value")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local decoder = Payload.create({
	bounds = { maxArguments = 3, maxEntries = 4, maxDepth = 2, maxString = 8, maxKey = 4 },
	atom = function(value: unknown): boolean
		return typeof(value) == "vector"
	end,
})

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("bounded payload graph", function()
		it("copies data graphs, preserves aliases, nil positions and admitted native atoms", function()
			local shared = { a = 1 }
			local source = { a = shared, b = shared }
			local decoded = Result.unwrap(decoder.decode(nil, source, vector.create(1, 2, 3)))
			expect(decoded.n):toBe(3)
			expect(decoded[1]):toBeNil()
			local owned = assert(Value.raw(decoded[2]))
			expect(owned.a == owned.b):toBe(true)
			expect(owned.a == shared):toBe(false)
			expect(decoded[3]):toBe(vector.create(1, 2, 3))
		end)
		it(
			"refuses each graph bound, cycles, metatables and executable values, then accepts a corrected request",
			function()
				local cycle: { [string]: unknown } = {}
				cycle.a = cycle
				local invalid: { unknown } = {
					cycle,
					setmetatable({}, {}),
					{ a = { b = {} } },
					{ a = 1, b = 2, c = 3, d = 4, e = 5 },
					{ abcde = true },
					string.rep("x", 9),
					math.huge,
					function() end,
					coroutine.create(function() end),
					{ [true] = 1 },
				}
				for _, raw in invalid do
					expect(decoder.decode(raw).ok):toBe(false)
				end
				expect(decoder.decode(1, 2, 3, 4).ok):toBe(false)
				expect(decoder.decode({ a = 1 }, nil, true).ok):toBe(true)
			end
		)
	end)
end
