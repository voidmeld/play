--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Chat = require("./chat")
local Clock = require("../test-scene/clock")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("chat", function()
		it("channel seating reports refusal and errors without stopping other seats", function()
			local visited: { string } = {}
			local refusals = Chat.seat({ "ok", "off", "throws", "last" }, 7, function(channel: string): string
				return channel
			end, function(channel: string, id: number): boolean
				expect(id):toBe(7)
				table.insert(visited, channel)
				if channel == "throws" then
					error("denied", 0)
				end
				return channel ~= "off"
			end)
			expect(visited):toEqual({ "ok", "off", "throws", "last" })
			expect(refusals):toEqual({ "off:chat_off_or_absent", "throws:denied" })
		end)
		it("platform privacy fails closed and permission retries are bounded", function()
			local clock = Clock.new()
			local calls = 0
			local function denied(): boolean
				calls += 1
				error("unavailable", 0)
			end
			expect(Chat.permission(denied, clock.advance, false, 1, 4, 0.25)):toBe("unavailable")
			expect(calls):toBe(4)
			expect(clock.clock()):toBe(1.75)
			expect(Chat.permission(denied, clock.advance, true, -1, 4, 0.25)):toBe("allowed")
			expect(Chat.permission(function(): boolean
				return false
			end, clock.advance, false, 1, 4, 0.25)):toBe("denied")
			expect(Chat.directAllowed(function(_id: number, _ids: { number }): { number }
				error("privacy unavailable", 0)
			end, 1, 2)):toBe(false)
			expect(Chat.directAllowed(function(_id: number, ids: { number }): { number }
				return ids
			end, 1, 2)):toBe(true)
		end)
		it("foreign cleanup preserves approved channels and nonchannels", function()
			local removed: { string } = {}
			local result = Chat.removeForeign({ "foreign", "keep", "folder" }, function(child: string): string
				return child
			end, function(child: string): boolean
				return child ~= "folder"
			end, function(name: string): boolean
				return name == "keep"
			end, function(child: string)
				table.insert(removed, child)
			end)
			expect(result):toEqual({ "foreign" })
			expect(removed):toEqual({ "foreign" })
		end)
	end)
end
