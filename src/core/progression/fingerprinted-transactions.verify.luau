--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Transactions = require("./fingerprinted-transactions")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type Profile = { balance: number, receipts: Transactions.Receipts }
local bounds = { maxDepth = 4, maxEntries = 8, maxBytes = 128 }
local rules = Transactions.create({
	maxTransactionId = 16,
	maxRecords = 2,
	bounds = bounds,
	copy = function(p: Profile): Profile
		return { balance = p.balance, receipts = table.clone(p.receipts) }
	end,
	receipts = function(p: Profile): Transactions.Receipts
		return p.receipts
	end,
	withReceipts = function(p: Profile, receipts: Transactions.Receipts): Profile
		return { balance = p.balance, receipts = receipts }
	end,
})

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("fingerprinted transactions", function()
		it("commits once, replays reordered payloads and refuses changed payloads after recreation", function()
			local calls = 0
			local function effect(p: Profile): (Profile?, string?)
				calls += 1
				p.balance += 3
				return p, nil
			end
			local source: Profile = { balance = 0, receipts = {} }
			local result = rules.commit(source, "first", { count = 3, item = "a" }, effect)
			expect(result.outcome):toBe("committed")
			expect(source.balance):toBe(0)
			local restored: Profile = { balance = result.state.balance, receipts = table.clone(result.state.receipts) }
			expect(rules.commit(restored, "first", { item = "a", count = 3 }, effect).outcome):toBe("replayed")
			expect(rules.commit(restored, "first", { item = "a", count = 4 }, effect).reason):toBe(
				"transaction_conflict"
			)
			expect(calls):toBe(1)
			expect(Transactions.fingerprint({ [1] = "a" }, bounds) == Transactions.fingerprint({ ["1"] = "a" }, bounds)):toBe(
				false
			)
		end)
		it("retains rejected state and receipts and permits a corrected retry", function()
			local source: Profile = { balance = 0, receipts = {} }
			local failed = rules.commit(source, "first", 3, function(p: Profile): (Profile?, string?)
				p.balance = 99
				p.receipts.injected = "bad"
				return nil, "capacity"
			end)
			expect(failed.reason):toBe("capacity")
			expect(source.balance):toBe(0)
			expect(next(source.receipts)):toBeNil()
			local function effect(p: Profile): (Profile?, string?)
				return p, nil
			end
			local first = rules.commit(source, "first", 3, effect).state
			local second = rules.commit(first, "second", 4, effect).state
			expect(rules.commit(second, "third", 5, effect).reason):toBe("receipts_full")
			expect(rules.commit(second, "first", 3, effect).outcome):toBe("replayed")
			expect(rules.commit(source, "", 3, effect).reason):toBe("transaction_id_invalid")
		end)
		it("bounds canonical decoding and refuses cycles and unsupported values", function()
			local cycle: { [string]: unknown } = {}
			cycle.self = cycle
			for _, payload in
				{
					cycle,
					{ value = math.huge },
					{ value = function() end },
					setmetatable({}, {}),
					{ a = { b = { c = {} } } },
				}
			do
				local tight = { maxDepth = 2, maxEntries = 2, maxBytes = 16 }
				expect(Transactions.fingerprint(payload, tight)):toBeNil()
			end
			expect(Transactions.fingerprint(string.rep("a", 129), bounds)):toBeNil()
			expect(Transactions.fingerprint({ a = 1, b = 2, c = 3 }, { maxDepth = 2, maxEntries = 2, maxBytes = 128 })):toBeNil()
		end)
	end)
end
