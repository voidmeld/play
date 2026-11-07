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
		it("preserves canonical saved bytes and typed receipt shapes with an injected encoder", function()
			type Receipt = { canonicalPayload: string, version: number }
			type Stored = { balance: number, receipts: { [string]: Receipt } }
			local configured = Transactions.createWithReceipts({
				fingerprint = function(raw: unknown): (string?, string?)
					if type(raw) ~= "string" then
						return nil, "encoding_refused"
					end
					return #raw .. ":" .. raw, nil
				end,
				copy = function(p: Stored): Stored
					return { balance = p.balance, receipts = table.clone(p.receipts) }
				end,
				receipts = function(p: Stored): { [string]: Receipt }
					return p.receipts
				end,
				withReceipts = function(p: Stored, receipts: { [string]: Receipt }): Stored
					return { balance = p.balance, receipts = receipts }
				end,
			}, {
				fingerprint = function(receipt: Receipt): string
					return receipt.canonicalPayload
				end,
				create = function(stamp: string): Receipt
					return { canonicalPayload = stamp, version = 1 }
				end,
			})
			local source: Stored = { balance = 0, receipts = { saved = { canonicalPayload = "3:abc", version = 1 } } }
			local calls = 0
			local function effect(p: Stored): (Stored?, string?)
				calls += 1
				p.balance += 1
				return p, nil
			end
			expect(configured.commit(source, "saved", "abc", effect).outcome):toBe("replayed")
			expect(configured.commit(source, "saved", "abd", effect).reason):toBe("transaction_conflict")
			expect(configured.commit(source, "new", 1, effect).reason):toBe("encoding_refused")
			local id = string.rep("x", 1000001)
			local committed = configured.commit(source, id, "abc", effect)
			expect(committed.state.receipts[id].canonicalPayload):toBe("3:abc")
			expect(committed.state.receipts.saved):toBe(source.receipts.saved)
			expect(source.receipts[id]):toBeNil()
			expect(calls):toBe(1)
		end)
		it("uses injected encodings with string receipts and refuses empty or throwing encoders", function()
			local config: Transactions.Config<Profile> = {
				copy = function(p: Profile): Profile
					return { balance = p.balance, receipts = table.clone(p.receipts) }
				end,
				receipts = function(p: Profile): Transactions.Receipts
					return p.receipts
				end,
				withReceipts = function(p: Profile, receipts: Transactions.Receipts): Profile
					return { balance = p.balance, receipts = receipts }
				end,
				fingerprint = function(raw: unknown): (string?, string?)
					return if type(raw) == "string" then raw else nil, nil
				end,
			}
			local source: Profile = { balance = 0, receipts = {} }
			local function effect(p: Profile): (Profile?, string?)
				return p, nil
			end
			expect(Transactions.create(config).commit(source, "id", "3:abc", effect).state.receipts.id):toBe("3:abc")
			expect(Transactions.create(config).commit(source, "id", "", effect).reason):toBe("payload_invalid")
			config.fingerprint = function(_raw: unknown): (string?, string?)
				error("encoder failed")
			end
			expect(Transactions.create(config).commit(source, "id", "x", effect).reason):toBe("payload_invalid")
			expect(Transactions.fingerprint({ a = 1 }, bounds)):toBe("{s1:an1;}")
			config.fingerprint = nil
			config.bounds = { maxDepth = -1, maxEntries = 1, maxBytes = 1 }
			expect(pcall(function()
				Transactions.create(config).commit(source, "id", "x", effect)
			end)):toBe(false)
		end)
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
