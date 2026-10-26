--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Chat = require("./channels")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("channels", function()
		local function member(id: number, realm: string, group: unknown): Chat.Member
			return { id = id, realm = realm, party = group, guild = group, warband = group }
		end
		it("membership preserves proximity, realm, group and private pair boundaries", function()
			local speaker = member(1, "realm", "group")
			local listener = member(2, "realm", "group")
			local stranger = member(3, "other", "other")
			for _, audience in { "say", "realm", "party", "guild", "warband", "whisper" } do
				local rule: Chat.Rule = { audience = audience, sameRealm = true, selfDelivery = false }
				expect(Chat.allows(rule, speaker, listener, true, { 1, 2 })):toBe(true)
				expect(Chat.allows(rule, speaker, stranger, true, { 1, 2 })):toBe(false)
				listener.realm = ""
				expect(Chat.allows(rule, speaker, listener, true, { 1, 2 })):toBe(false)
				listener.realm = "realm"
			end
			expect(
				Chat.allows({ audience = "say", sameRealm = true, selfDelivery = false }, speaker, listener, false, nil)
			):toBe(false)
			for _, audience in { "party", "guild", "warband" } do
				local rule: Chat.Rule = { audience = audience, sameRealm = true, selfDelivery = false }
				expect(Chat.allows(rule, member(1, "r", nil), member(2, "r", nil), true, nil)):toBe(false)
				expect(Chat.allows(rule, member(1, "r", ""), member(2, "r", ""), true, nil)):toBe(false)
			end
			expect(
				Chat.allows(
					{ audience = "whisper", sameRealm = false, selfDelivery = false },
					speaker,
					stranger,
					false,
					{ 1, 3 }
				)
			):toBe(true)
			expect(
				Chat.allows(
					{ audience = "whisper", sameRealm = false, selfDelivery = false },
					speaker,
					listener,
					true,
					nil
				)
			):toBe(false)
		end)
		it("history windows and count bounds preserve ordering", function()
			local lines = { 1, 2, 3, 4 }
			expect(Chat.trim(lines, 2)):toEqual({ 1, 2 })
			expect(lines):toEqual({ 3, 4 })
			expect(Chat.window({ 1, 2, 3, 4, 5 }, 4, 2, function(line: number): number
				return line
			end)):toEqual({ 2, 3, 4 })
		end)
		it("sender budget rejects bursts and refills against the supplied clock", function()
			local budget = { capacity = 2, refillPerSec = 1 }
			local allowed, bucket = Chat.consume(nil, budget, 1)
			expect(allowed):toBe(true)
			allowed, bucket = Chat.consume(bucket, budget, 1)
			expect(allowed):toBe(true)
			allowed, bucket = Chat.consume(bucket, budget, 1)
			expect(allowed):toBe(false)
			local before = bucket.tokens
			allowed, bucket = Chat.consume(bucket, budget, 0)
			expect(allowed):toBe(false)
			expect(bucket.tokens):toBe(before)
			allowed, bucket = Chat.consume(bucket, budget, 3)
			expect(allowed):toBe(true)
		end)
		it("commands and private channel names use supplied vocabulary", function()
			local scope, text = Chat.parse(" /P hello ", { p = "party" })
			expect(scope):toBe("party")
			expect(text):toBe("hello")
			scope, text = Chat.parse("/unknown hello", { p = "party" })
			expect(scope):toBeNil()
			expect(text):toBe("/unknown hello")
			expect(Chat.pairName("private_", 9, 2)):toBe("private_2_9")
		end)
	end)
end
