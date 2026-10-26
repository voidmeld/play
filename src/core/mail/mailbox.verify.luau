--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Mail = require("./mailbox")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type Profile = { balance: unknown, goods: unknown, slots: number, label: string }

local function profile(coin: unknown, inventory: unknown, slots: number?): Profile
	return { balance = coin, goods = inventory, slots = slots or 24, label = "preserved" }
end

local function config(): Mail.Config<Profile>
	return {
		maxItems = 8,
		maxCount = 9999,
		maxCoin = 1000000000,
		maxUserId = 9007199254740991,
		maxTimestamp = 10000000000000,
		maxTtl = 31536000,
		itemIdLimit = 64,
		requestIdLimit = 40,
		characterIdLimit = 64,
		maxPointers = 40,
		readAccount = function(value: Profile): unknown
			return { coin = value.balance, inventory = value.goods }
		end,
		writeAccount = function(value: Profile, account: Mail.Account): Profile
			local updated = table.clone(value)
			updated.balance = account.coin
			updated.goods = account.inventory
			return updated
		end,
		capacity = function(value: Profile): number
			return value.slots
		end,
		entries = function(inventory: Mail.Inventory): number
			local count = 0
			for _ in inventory do
				count += 1
			end
			return count
		end,
	}
end

local mailbox = Mail.mailbox(config())

local function prepared(): Mail.Envelope
	return assert(mailbox.prepare("11:send1", 11, 20, { coin = 5, items = {} }, 100, 60))
end

local function fields(value: unknown): Mail.Inventory
	assert(type(value) == "table")
	local out: Mail.Inventory = {}
	for key, entry in value do
		out[key] = entry
	end
	return out
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("mailbox", function()
		it(
			"bounds recovery pointers and rejects mismatched ids, unknown fields and partial character identity",
			function(own)
				local pointers: { [string]: Mail.Pointer } = {}
				for index = 1, 40 do
					local id = "11:pointer" .. index
					local envelope = assert(mailbox.prepare(id, 11, 20, { coin = 1, items = {} }, 100, 60))
					pointers[id] = { id = id, envelope = envelope, intent = "hold" }
				end
				expect(mailbox.pointers(pointers) ~= nil):toBe(true)
				local extra = assert(mailbox.prepare("11:extra", 11, 20, { coin = 1, items = {} }, 100, 60))
				pointers[extra.id] = { id = extra.id, envelope = extra, intent = "hold" }
				expect(mailbox.pointers(pointers)):toBeNil()
				pointers[extra.id] = nil
				pointers["11:pointer1"].id = "wrong"
				expect(mailbox.pointers(pointers)):toBeNil()
				local untrusted = fields(extra)
				untrusted.text = "untrusted"
				expect(mailbox.valid(untrusted)):toBe(false)
				extra.senderCharacterId = "character:sender"
				expect(mailbox.valid(extra)):toBe(false)
				extra.recipientCharacterId = "character:recipient"
				expect(mailbox.valid(extra)):toBe(true)
			end
		)

		it("accepts only bounded item and currency attachments without player text", function()
			local value = { coin = 5, items = { { itemId = "ore", count = 2 } } }
			local normalized = assert(mailbox.attachments(value))
			expect(normalized):toEqual(value)
			expect(table.isfrozen(normalized)):toBe(true)
			expect(table.isfrozen(normalized.items)):toBe(true)
			expect(table.isfrozen(normalized.items[1])):toBe(true)
			value.items[1].count = 3
			expect(normalized.items[1].count):toBe(2)
			expect(mailbox.attachments({ coin = 0, items = {} })):toBeNil()
			expect(mailbox.attachments({ coin = 1, items = {}, message = "hi" })):toBeNil()
			expect(mailbox.attachments({ coin = -1, items = {} })):toBeNil()
			expect(mailbox.attachments({ coin = math.huge - math.huge, items = {} })):toBeNil()
			expect(mailbox.attachments({
				coin = 0,
				items = { { itemId = "ore", count = 1 }, { itemId = "ore", count = 1 } },
			})):toBeNil()
		end)

		it("permits only ordered dispatch, claim and return decisions", function()
			local initial = prepared()
			expect(mailbox.advance(initial, "claim")):toBeNil()
			local sent = assert(mailbox.advance(initial, "dispatch"))
			expect(sent.phase):toBe("in_transit")
			expect(initial.phase):toBe("prepared")
			local claiming = assert(mailbox.advance(sent, "claim"))
			expect(mailbox.advance(claiming, "return")):toBeNil()
			local claimed = assert(mailbox.advance(claiming, "deliver"))
			expect(claimed.phase):toBe("claimed")
			expect(mailbox.advance(claimed, "claim")):toBeNil()
			local returning = assert(mailbox.advance(sent, "return"))
			expect(mailbox.advance(returning, "claim")):toBeNil()
			local returned = assert(mailbox.advance(returning, "restore"))
			expect(returned.phase):toBe("returned")
			expect(mailbox.advance(returned, "restore")):toBeNil()
			local cancelled = assert(mailbox.advance(initial, "cancel"))
			expect(cancelled.phase):toBe("cancelled")
			expect(mailbox.advance(cancelled, "dispatch")):toBeNil()
			expect(mailbox.advance({}, "dispatch")):toBeNil()
		end)

		it("holds expired value for return and requires an expiration timestamp", function()
			local sent = assert(mailbox.advance(prepared(), "dispatch"))
			expect(mailbox.advance(sent, "expire")):toBeNil()
			local expired = assert(mailbox.advance(sent, "expire", 160))
			expect(expired.phase):toBe("expired")
			expect(expired.returnedAt):toBe(160)
			expect(mailbox.valid(expired)):toBe(true)
			expect(mailbox.advance(expired, "claim")):toBeNil()
			expect(mailbox.advance(expired, "expire", 200)):toBeNil()
			expect(assert(mailbox.advance(expired, "return")).phase):toBe("returning")
			expect(assert(mailbox.advance(sent, "expire", 0)).returnedAt):toBe(0)
		end)

		it("moves exact value between profile and hold without creating value", function()
			local attachments = assert(mailbox.attachments({ coin = 7, items = { { itemId = "ore", count = 2 } } }))
			local source = profile(20, { ore = 3 })
			local held = assert(mailbox.debit(source, attachments))
			expect(held.balance):toBe(13)
			expect(held.goods):toEqual({ ore = 1 })
			expect(held.label):toBe("preserved")
			expect(source.balance):toBe(20)
			expect(source.goods):toEqual({ ore = 3 })
			local restored = assert(mailbox.credit(held, attachments))
			expect(restored.balance):toBe(20)
			expect(restored.goods):toEqual({ ore = 3 })
			expect(assert(mailbox.debit(profile(7, { ore = 2 }), attachments)).goods):toEqual({})
		end)

		it("uses configured attachment counts, currency, item bounds and identifier limits", function()
			local settings = config()
			settings.maxItems, settings.maxCount, settings.maxCoin, settings.itemIdLimit = 1, 3, 5, 2
			local small = Mail.mailbox(settings)
			expect(small.attachments({ coin = 5, items = { { itemId = "a", count = 3 } } }) ~= nil):toBe(true)
			expect(small.attachments({ coin = 6, items = {} })):toBeNil()
			expect(small.attachments({ coin = 1, items = { { itemId = "a", count = 4 } } })):toBeNil()
			expect(small.attachments({ coin = 1, items = { { itemId = "abc", count = 1 } } })):toBeNil()
			expect(
				small.attachments({ coin = 1, items = { { itemId = "a", count = 1 }, { itemId = "b", count = 1 } } })
			):toBeNil()
			expect(small.attachments({ coin = 1, items = { [2] = { itemId = "a", count = 1 } } })):toBeNil()
		end)

		it("uses configured identity, timestamp, lifetime and character bounds", function()
			local settings = config()
			settings.maxUserId, settings.requestIdLimit = 20, 2
			settings.maxTimestamp, settings.maxTtl, settings.characterIdLimit = 100, 60, 2
			local small = Mail.mailbox(settings)
			expect(small.id(20, "ab")):toBe("20:ab")
			expect(small.id(21, "ab")):toBeNil()
			expect(small.id(20, "abc")):toBeNil()
			expect(small.id(0, "ab")):toBeNil()
			expect(small.id(1.5, "ab")):toBeNil()
			expect(small.id(1, "bad text")):toBeNil()
			local initial = assert(small.prepare("11:ab", 11, 20, { coin = 1, items = {} }, 100, 60))
			expect(small.valid(initial)):toBe(true)
			expect(small.prepare("11:ab", 11, 21, initial.attachments, 100, 60)):toBeNil()
			expect(small.prepare("11:ab", 11, 11, initial.attachments, 100, 60)):toBeNil()
			expect(small.prepare("12:ab", 11, 20, initial.attachments, 100, 60)):toBeNil()
			expect(small.prepare("11:ab", 11, 20, initial.attachments, 101, 60)):toBeNil()
			expect(small.prepare("11:ab", 11, 20, initial.attachments, 100, 61)):toBeNil()
			initial.senderCharacterId, initial.recipientCharacterId = "ab", "cd"
			expect(small.valid(initial)):toBe(true)
			initial.senderCharacterId = "abc"
			expect(small.valid(initial)):toBe(false)
			initial.senderCharacterId = "ab"
			initial.returnedAt = 101
			expect(small.valid(initial)):toBe(false)
			initial.returnedAt = nil
			initial.expiresAt = 161
			expect(small.valid(initial)):toBe(false)
			initial.expiresAt = 160
			local sent = assert(small.advance(initial, "dispatch"))
			expect(small.advance(sent, "expire", 101)):toBeNil()
			expect(small.advance(sent, "expire", 100) ~= nil):toBe(true)
		end)

		it("uses configured recovery capacity and copies pointer envelopes", function()
			local settings = config()
			settings.maxPointers = 1
			local small = Mail.mailbox(settings)
			local initial = prepared()
			local input = { [initial.id] = { id = initial.id, envelope = initial, intent = "claim" } }
			local copied = assert(small.pointers(input))
			copied[initial.id].envelope.phase = "cancelled"
			expect(copied[initial.id].envelope.phase):toBe("cancelled")
			expect(initial.phase):toBe("prepared")
			expect(small.pointers({ a = input[initial.id] })):toBeNil()
			local extra = assert(small.prepare("11:extra", 11, 20, initial.attachments, 100, 60))
			local two = {
				[initial.id] = input[initial.id],
				[extra.id] = { id = extra.id, envelope = extra, intent = "hold" },
			}
			expect(mailbox.pointers(two) ~= nil):toBe(true)
			expect(small.pointers(two)):toBeNil()
			expect(small.pointers({ [initial.id] = { id = initial.id, envelope = initial, intent = "other" } })):toBeNil()
			expect(small.pointers({
				[initial.id] = { id = initial.id, envelope = prepared(), intent = "hold", text = "extra" },
			})):toBeNil()
		end)

		it("compares requests by identity and ordered value while ignoring lifecycle timestamps", function()
			local initial = prepared()
			local other = assert(mailbox.prepare(initial.id, 11, 20, initial.attachments, 200, 120))
			other.phase, other.returnedAt = "expired", 250
			expect(mailbox.sameRequest(initial, other)):toBe(true)
			other.recipientId = 21
			expect(mailbox.sameRequest(initial, other)):toBe(false)
			expect(mailbox.sameRequest(initial, {})):toBe(false)
			other.recipientId = 20
			other.senderCharacterId, other.recipientCharacterId = "a", "b"
			expect(mailbox.sameRequest(initial, other)):toBe(false)
			local a = assert(
				mailbox.prepare(
					"11:items",
					11,
					20,
					{ coin = 1, items = { { itemId = "a", count = 1 }, { itemId = "b", count = 2 } } },
					0,
					1
				)
			)
			local b = table.clone(a)
			expect(mailbox.sameRequest(a, b)):toBe(true)
			b.attachments = assert(
				mailbox.attachments({ coin = 1, items = { { itemId = "b", count = 2 }, { itemId = "a", count = 1 } } })
			)
			expect(mailbox.sameRequest(a, b)):toBe(false)
		end)

		it("rejects malformed values and metatables at durable record boundaries", function()
			for _, value in { false, 1, "value", {} } do
				expect(mailbox.valid(value)):toBe(false)
				expect(mailbox.attachments(value)):toBeNil()
			end
			expect(mailbox.attachments(setmetatable({ coin = 1, items = {} }, {}))):toBeNil()
			expect(mailbox.attachments({ coin = 1, items = { setmetatable({ itemId = "a", count = 1 }, {}) } })):toBeNil()
			expect(mailbox.attachments({ coin = 1, items = { { itemId = "bad text", count = 1 } } })):toBeNil()
			expect(mailbox.attachments({ coin = 1, items = { { itemId = "a", count = 1.5 } } })):toBeNil()
			expect(mailbox.pointers(setmetatable({}, {}))):toBeNil()
			expect(mailbox.valid(setmetatable(prepared(), {}))):toBe(false)
			local invalid = fields(prepared())
			invalid.phase = "unknown"
			expect(mailbox.valid(invalid)):toBe(false)
		end)

		it("preserves debit and credit failure reasons and leaves rejected profiles unchanged", function()
			local value = assert(mailbox.attachments({ coin = 7, items = { { itemId = "ore", count = 2 } } }))
			local function debitError(source: Profile): string?
				local updated, reason = mailbox.debit(source, value)
				expect(updated):toBeNil()
				return reason
			end
			local function creditError(source: Profile): string?
				local updated, reason = mailbox.credit(source, value)
				expect(updated):toBeNil()
				return reason
			end
			expect(debitError(profile("invalid", {}))):toBe("profile_invalid")
			expect(creditError(profile(0, false))):toBe("profile_invalid")
			expect(debitError(profile(6, { ore = 2 }))):toBe("coin_insufficient")
			expect(debitError(profile(7, { ore = 1 }))):toBe("goods_insufficient")
			expect(debitError(profile(7, { ore = "invalid" }))):toBe("goods_insufficient")
			expect(creditError(profile(1000000000, {}))):toBe("coin_overflow")
			expect(creditError(profile(0, { ore = 0 }))):toBe("inventory_invalid")
			expect(creditError(profile(0, { [1] = 1 }))):toBe("inventory_invalid")
			expect(creditError(profile(0, { ore = 9998 }))):toBe("stack_full")
			local full = profile(7, { other = 1 }, 1)
			expect(creditError(full)):toBe("inventory_full")
			expect(full.goods):toEqual({ other = 1 })
			expect(full.balance):toBe(7)
		end)

		it("uses configured transfer limits, capacity and original inventory entry accounting", function()
			local settings = config()
			settings.maxCoin, settings.maxCount = 10, 3
			local small = Mail.mailbox(settings)
			local value = assert(small.attachments({ coin = 2, items = { { itemId = "ore", count = 1 } } }))
			local updated, reason = small.credit(profile(9, {}), value)
			expect(updated):toBeNil()
			expect(reason):toBe("coin_overflow")
			updated, reason = small.credit(profile(0, { ore = 3 }), value)
			expect(updated):toBeNil()
			expect(reason):toBe("stack_full")
			updated, reason = small.debit(profile(0, { ore = 4 }), value)
			expect(updated):toBeNil()
			expect(reason):toBe("coin_insufficient")
			updated, reason = small.debit(profile(2, { ore = 4 }), value)
			expect(updated):toBeNil()
			expect(reason):toBe("goods_insufficient")
			expect(small.credit(profile(0, {}, 1), value) ~= nil):toBe(true)
			expect(small.credit(profile(0, { ore = 1, other = 1 }, 1), value) ~= nil):toBe(true)
			settings.entries = function(_inventory: Mail.Inventory): number
				return 0
			end
			local excluded = Mail.mailbox(settings)
			local coin = assert(excluded.attachments({ coin = 1, items = {} }))
			updated, reason = excluded.credit(profile(0, { permanent = 1, ore = 1 }, 1), coin)
			expect(updated):toBeNil()
			expect(reason):toBe("inventory_full")
		end)
	end)
end
