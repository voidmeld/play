--!strict

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
	suite:case(
		"bounds recovery pointers and rejects mismatched ids, unknown fields and partial character identity",
		function(context)
			local pointers: { [string]: Mail.Pointer } = {}
			for index = 1, 40 do
				local id = "11:pointer" .. index
				local envelope = assert(mailbox.prepare(id, 11, 20, { coin = 1, items = {} }, 100, 60))
				pointers[id] = { id = id, envelope = envelope, intent = "hold" }
			end
			context:expect(mailbox.pointers(pointers) ~= nil):toBe(true)
			local extra = assert(mailbox.prepare("11:extra", 11, 20, { coin = 1, items = {} }, 100, 60))
			pointers[extra.id] = { id = extra.id, envelope = extra, intent = "hold" }
			context:expect(mailbox.pointers(pointers)):toBeNil()
			pointers[extra.id] = nil
			pointers["11:pointer1"].id = "wrong"
			context:expect(mailbox.pointers(pointers)):toBeNil()
			local untrusted = fields(extra)
			untrusted.text = "untrusted"
			context:expect(mailbox.valid(untrusted)):toBe(false)
			extra.senderCharacterId = "character:sender"
			context:expect(mailbox.valid(extra)):toBe(false)
			extra.recipientCharacterId = "character:recipient"
			context:expect(mailbox.valid(extra)):toBe(true)
		end
	)

	suite:case("accepts only bounded item and currency attachments without player text", function(context)
		local value = { coin = 5, items = { { itemId = "ore", count = 2 } } }
		local normalized = assert(mailbox.attachments(value))
		context:expect(normalized):toEqual(value)
		context:expect(table.isfrozen(normalized)):toBe(true)
		context:expect(table.isfrozen(normalized.items)):toBe(true)
		context:expect(table.isfrozen(normalized.items[1])):toBe(true)
		value.items[1].count = 3
		context:expect(normalized.items[1].count):toBe(2)
		context:expect(mailbox.attachments({ coin = 0, items = {} })):toBeNil()
		context:expect(mailbox.attachments({ coin = 1, items = {}, message = "hi" })):toBeNil()
		context:expect(mailbox.attachments({ coin = -1, items = {} })):toBeNil()
		context:expect(mailbox.attachments({ coin = math.huge - math.huge, items = {} })):toBeNil()
		context
			:expect(mailbox.attachments({
				coin = 0,
				items = { { itemId = "ore", count = 1 }, { itemId = "ore", count = 1 } },
			}))
			:toBeNil()
	end)

	suite:case("permits only ordered dispatch, claim and return decisions", function(context)
		local initial = prepared()
		context:expect(mailbox.advance(initial, "claim")):toBeNil()
		local sent = assert(mailbox.advance(initial, "dispatch"))
		context:expect(sent.phase):toBe("in_transit")
		context:expect(initial.phase):toBe("prepared")
		local claiming = assert(mailbox.advance(sent, "claim"))
		context:expect(mailbox.advance(claiming, "return")):toBeNil()
		local claimed = assert(mailbox.advance(claiming, "deliver"))
		context:expect(claimed.phase):toBe("claimed")
		context:expect(mailbox.advance(claimed, "claim")):toBeNil()
		local returning = assert(mailbox.advance(sent, "return"))
		context:expect(mailbox.advance(returning, "claim")):toBeNil()
		local returned = assert(mailbox.advance(returning, "restore"))
		context:expect(returned.phase):toBe("returned")
		context:expect(mailbox.advance(returned, "restore")):toBeNil()
		local cancelled = assert(mailbox.advance(initial, "cancel"))
		context:expect(cancelled.phase):toBe("cancelled")
		context:expect(mailbox.advance(cancelled, "dispatch")):toBeNil()
		context:expect(mailbox.advance({}, "dispatch")):toBeNil()
	end)

	suite:case("holds expired value for return and requires an expiration timestamp", function(context)
		local sent = assert(mailbox.advance(prepared(), "dispatch"))
		context:expect(mailbox.advance(sent, "expire")):toBeNil()
		local expired = assert(mailbox.advance(sent, "expire", 160))
		context:expect(expired.phase):toBe("expired")
		context:expect(expired.returnedAt):toBe(160)
		context:expect(mailbox.valid(expired)):toBe(true)
		context:expect(mailbox.advance(expired, "claim")):toBeNil()
		context:expect(mailbox.advance(expired, "expire", 200)):toBeNil()
		context:expect(assert(mailbox.advance(expired, "return")).phase):toBe("returning")
		context:expect(assert(mailbox.advance(sent, "expire", 0)).returnedAt):toBe(0)
	end)

	suite:case("moves exact value between profile and hold without creating value", function(context)
		local attachments = assert(mailbox.attachments({ coin = 7, items = { { itemId = "ore", count = 2 } } }))
		local source = profile(20, { ore = 3 })
		local held = assert(mailbox.debit(source, attachments))
		context:expect(held.balance):toBe(13)
		context:expect(held.goods):toEqual({ ore = 1 })
		context:expect(held.label):toBe("preserved")
		context:expect(source.balance):toBe(20)
		context:expect(source.goods):toEqual({ ore = 3 })
		local restored = assert(mailbox.credit(held, attachments))
		context:expect(restored.balance):toBe(20)
		context:expect(restored.goods):toEqual({ ore = 3 })
		context:expect(assert(mailbox.debit(profile(7, { ore = 2 }), attachments)).goods):toEqual({})
	end)

	suite:case("uses configured attachment counts, currency, item bounds and identifier limits", function(context)
		local settings = config()
		settings.maxItems, settings.maxCount, settings.maxCoin, settings.itemIdLimit = 1, 3, 5, 2
		local small = Mail.mailbox(settings)
		context:expect(small.attachments({ coin = 5, items = { { itemId = "a", count = 3 } } }) ~= nil):toBe(true)
		context:expect(small.attachments({ coin = 6, items = {} })):toBeNil()
		context:expect(small.attachments({ coin = 1, items = { { itemId = "a", count = 4 } } })):toBeNil()
		context:expect(small.attachments({ coin = 1, items = { { itemId = "abc", count = 1 } } })):toBeNil()
		context
			:expect(
				small.attachments({ coin = 1, items = { { itemId = "a", count = 1 }, { itemId = "b", count = 1 } } })
			)
			:toBeNil()
		context:expect(small.attachments({ coin = 1, items = { [2] = { itemId = "a", count = 1 } } })):toBeNil()
	end)

	suite:case("uses configured identity, timestamp, lifetime and character bounds", function(context)
		local settings = config()
		settings.maxUserId, settings.requestIdLimit = 20, 2
		settings.maxTimestamp, settings.maxTtl, settings.characterIdLimit = 100, 60, 2
		local small = Mail.mailbox(settings)
		context:expect(small.id(20, "ab")):toBe("20:ab")
		context:expect(small.id(21, "ab")):toBeNil()
		context:expect(small.id(20, "abc")):toBeNil()
		context:expect(small.id(0, "ab")):toBeNil()
		context:expect(small.id(1.5, "ab")):toBeNil()
		context:expect(small.id(1, "bad text")):toBeNil()
		local initial = assert(small.prepare("11:ab", 11, 20, { coin = 1, items = {} }, 100, 60))
		context:expect(small.valid(initial)):toBe(true)
		context:expect(small.prepare("11:ab", 11, 21, initial.attachments, 100, 60)):toBeNil()
		context:expect(small.prepare("11:ab", 11, 11, initial.attachments, 100, 60)):toBeNil()
		context:expect(small.prepare("12:ab", 11, 20, initial.attachments, 100, 60)):toBeNil()
		context:expect(small.prepare("11:ab", 11, 20, initial.attachments, 101, 60)):toBeNil()
		context:expect(small.prepare("11:ab", 11, 20, initial.attachments, 100, 61)):toBeNil()
		initial.senderCharacterId, initial.recipientCharacterId = "ab", "cd"
		context:expect(small.valid(initial)):toBe(true)
		initial.senderCharacterId = "abc"
		context:expect(small.valid(initial)):toBe(false)
		initial.senderCharacterId = "ab"
		initial.returnedAt = 101
		context:expect(small.valid(initial)):toBe(false)
		initial.returnedAt = nil
		initial.expiresAt = 161
		context:expect(small.valid(initial)):toBe(false)
		initial.expiresAt = 160
		local sent = assert(small.advance(initial, "dispatch"))
		context:expect(small.advance(sent, "expire", 101)):toBeNil()
		context:expect(small.advance(sent, "expire", 100) ~= nil):toBe(true)
	end)

	suite:case("uses configured recovery capacity and copies pointer envelopes", function(context)
		local settings = config()
		settings.maxPointers = 1
		local small = Mail.mailbox(settings)
		local initial = prepared()
		local input = { [initial.id] = { id = initial.id, envelope = initial, intent = "claim" } }
		local copied = assert(small.pointers(input))
		copied[initial.id].envelope.phase = "cancelled"
		context:expect(copied[initial.id].envelope.phase):toBe("cancelled")
		context:expect(initial.phase):toBe("prepared")
		context:expect(small.pointers({ a = input[initial.id] })):toBeNil()
		local extra = assert(small.prepare("11:extra", 11, 20, initial.attachments, 100, 60))
		local two = {
			[initial.id] = input[initial.id],
			[extra.id] = { id = extra.id, envelope = extra, intent = "hold" },
		}
		context:expect(mailbox.pointers(two) ~= nil):toBe(true)
		context:expect(small.pointers(two)):toBeNil()
		context
			:expect(small.pointers({ [initial.id] = { id = initial.id, envelope = initial, intent = "other" } }))
			:toBeNil()
		context
			:expect(small.pointers({
				[initial.id] = { id = initial.id, envelope = prepared(), intent = "hold", text = "extra" },
			}))
			:toBeNil()
	end)

	suite:case("compares requests by identity and ordered value while ignoring lifecycle timestamps", function(context)
		local initial = prepared()
		local other = assert(mailbox.prepare(initial.id, 11, 20, initial.attachments, 200, 120))
		other.phase, other.returnedAt = "expired", 250
		context:expect(mailbox.sameRequest(initial, other)):toBe(true)
		other.recipientId = 21
		context:expect(mailbox.sameRequest(initial, other)):toBe(false)
		context:expect(mailbox.sameRequest(initial, {})):toBe(false)
		other.recipientId = 20
		other.senderCharacterId, other.recipientCharacterId = "a", "b"
		context:expect(mailbox.sameRequest(initial, other)):toBe(false)
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
		context:expect(mailbox.sameRequest(a, b)):toBe(true)
		b.attachments = assert(
			mailbox.attachments({ coin = 1, items = { { itemId = "b", count = 2 }, { itemId = "a", count = 1 } } })
		)
		context:expect(mailbox.sameRequest(a, b)):toBe(false)
	end)

	suite:case("rejects malformed values and metatables at durable record boundaries", function(context)
		for _, value in { false, 1, "value", {} } do
			context:expect(mailbox.valid(value)):toBe(false)
			context:expect(mailbox.attachments(value)):toBeNil()
		end
		context:expect(mailbox.attachments(setmetatable({ coin = 1, items = {} }, {}))):toBeNil()
		context
			:expect(mailbox.attachments({ coin = 1, items = { setmetatable({ itemId = "a", count = 1 }, {}) } }))
			:toBeNil()
		context:expect(mailbox.attachments({ coin = 1, items = { { itemId = "bad text", count = 1 } } })):toBeNil()
		context:expect(mailbox.attachments({ coin = 1, items = { { itemId = "a", count = 1.5 } } })):toBeNil()
		context:expect(mailbox.pointers(setmetatable({}, {}))):toBeNil()
		context:expect(mailbox.valid(setmetatable(prepared(), {}))):toBe(false)
		local invalid = fields(prepared())
		invalid.phase = "unknown"
		context:expect(mailbox.valid(invalid)):toBe(false)
	end)

	suite:case("preserves debit and credit failure reasons and leaves rejected profiles unchanged", function(context)
		local value = assert(mailbox.attachments({ coin = 7, items = { { itemId = "ore", count = 2 } } }))
		local function debitError(source: Profile): string?
			local updated, reason = mailbox.debit(source, value)
			context:expect(updated):toBeNil()
			return reason
		end
		local function creditError(source: Profile): string?
			local updated, reason = mailbox.credit(source, value)
			context:expect(updated):toBeNil()
			return reason
		end
		context:expect(debitError(profile("invalid", {}))):toBe("profile_invalid")
		context:expect(creditError(profile(0, false))):toBe("profile_invalid")
		context:expect(debitError(profile(6, { ore = 2 }))):toBe("coin_insufficient")
		context:expect(debitError(profile(7, { ore = 1 }))):toBe("goods_insufficient")
		context:expect(debitError(profile(7, { ore = "invalid" }))):toBe("goods_insufficient")
		context:expect(creditError(profile(1000000000, {}))):toBe("coin_overflow")
		context:expect(creditError(profile(0, { ore = 0 }))):toBe("inventory_invalid")
		context:expect(creditError(profile(0, { [1] = 1 }))):toBe("inventory_invalid")
		context:expect(creditError(profile(0, { ore = 9998 }))):toBe("stack_full")
		local full = profile(7, { other = 1 }, 1)
		context:expect(creditError(full)):toBe("inventory_full")
		context:expect(full.goods):toEqual({ other = 1 })
		context:expect(full.balance):toBe(7)
	end)

	suite:case("uses configured transfer limits, capacity and original inventory entry accounting", function(context)
		local settings = config()
		settings.maxCoin, settings.maxCount = 10, 3
		local small = Mail.mailbox(settings)
		local value = assert(small.attachments({ coin = 2, items = { { itemId = "ore", count = 1 } } }))
		local updated, reason = small.credit(profile(9, {}), value)
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("coin_overflow")
		updated, reason = small.credit(profile(0, { ore = 3 }), value)
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("stack_full")
		updated, reason = small.debit(profile(0, { ore = 4 }), value)
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("coin_insufficient")
		updated, reason = small.debit(profile(2, { ore = 4 }), value)
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("goods_insufficient")
		context:expect(small.credit(profile(0, {}, 1), value) ~= nil):toBe(true)
		context:expect(small.credit(profile(0, { ore = 1, other = 1 }, 1), value) ~= nil):toBe(true)
		settings.entries = function(_inventory: Mail.Inventory): number
			return 0
		end
		local excluded = Mail.mailbox(settings)
		local coin = assert(excluded.attachments({ coin = 1, items = {} }))
		updated, reason = excluded.credit(profile(0, { permanent = 1, ore = 1 }, 1), coin)
		context:expect(updated):toBeNil()
		context:expect(reason):toBe("inventory_full")
	end)
end
