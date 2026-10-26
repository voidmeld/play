--!strict

local Chat = require("./channels")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local function member(id: number, realm: string, group: unknown): Chat.Member
		return { id = id, realm = realm, party = group, guild = group, warband = group }
	end
	suite:case("membership preserves proximity, realm, group and private pair boundaries", function(t)
		local speaker = member(1, "realm", "group")
		local listener = member(2, "realm", "group")
		local stranger = member(3, "other", "other")
		for _, audience in { "say", "realm", "party", "guild", "warband", "whisper" } do
			local rule: Chat.Rule = { audience = audience, sameRealm = true, selfDelivery = false }
			t:expect(Chat.allows(rule, speaker, listener, true, { 1, 2 })):toBe(true)
			t:expect(Chat.allows(rule, speaker, stranger, true, { 1, 2 })):toBe(false)
			listener.realm = ""
			t:expect(Chat.allows(rule, speaker, listener, true, { 1, 2 })):toBe(false)
			listener.realm = "realm"
		end
		t:expect(
			Chat.allows({ audience = "say", sameRealm = true, selfDelivery = false }, speaker, listener, false, nil)
		):toBe(false)
		for _, audience in { "party", "guild", "warband" } do
			local rule: Chat.Rule = { audience = audience, sameRealm = true, selfDelivery = false }
			t:expect(Chat.allows(rule, member(1, "r", nil), member(2, "r", nil), true, nil)):toBe(false)
			t:expect(Chat.allows(rule, member(1, "r", ""), member(2, "r", ""), true, nil)):toBe(false)
		end
		t:expect(
			Chat.allows(
				{ audience = "whisper", sameRealm = false, selfDelivery = false },
				speaker,
				stranger,
				false,
				{ 1, 3 }
			)
		):toBe(true)
		t
			:expect(
				Chat.allows(
					{ audience = "whisper", sameRealm = false, selfDelivery = false },
					speaker,
					listener,
					true,
					nil
				)
			)
			:toBe(false)
	end)
	suite:case("history windows and count bounds preserve ordering", function(t)
		local lines = { 1, 2, 3, 4 }
		t:expect(Chat.trim(lines, 2)):toEqual({ 1, 2 })
		t:expect(lines):toEqual({ 3, 4 })
		t:expect(Chat.window({ 1, 2, 3, 4, 5 }, 4, 2, function(line: number): number
			return line
		end)):toEqual({ 2, 3, 4 })
	end)
	suite:case("sender budget rejects bursts and refills against the supplied clock", function(t)
		local budget = { capacity = 2, refillPerSec = 1 }
		local allowed, bucket = Chat.consume(nil, budget, 1)
		t:expect(allowed):toBe(true)
		allowed, bucket = Chat.consume(bucket, budget, 1)
		t:expect(allowed):toBe(true)
		allowed, bucket = Chat.consume(bucket, budget, 1)
		t:expect(allowed):toBe(false)
		local before = bucket.tokens
		allowed, bucket = Chat.consume(bucket, budget, 0)
		t:expect(allowed):toBe(false)
		t:expect(bucket.tokens):toBe(before)
		allowed, bucket = Chat.consume(bucket, budget, 3)
		t:expect(allowed):toBe(true)
	end)
	suite:case("commands and private channel names use supplied vocabulary", function(t)
		local scope, text = Chat.parse(" /P hello ", { p = "party" })
		t:expect(scope):toBe("party")
		t:expect(text):toBe("hello")
		scope, text = Chat.parse("/unknown hello", { p = "party" })
		t:expect(scope):toBeNil()
		t:expect(text):toBe("/unknown hello")
		t:expect(Chat.pairName("private_", 9, 2)):toBe("private_2_9")
	end)
end
