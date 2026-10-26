--!strict

local Chat = require("./chat")
local Clock = require("../test-scene/clock")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	suite:case("channel seating reports refusal and errors without stopping other seats", function(t)
		local visited: { string } = {}
		local refusals = Chat.seat({ "ok", "off", "throws", "last" }, 7, function(channel: string): string
			return channel
		end, function(channel: string, id: number): boolean
			t:expect(id):toBe(7)
			table.insert(visited, channel)
			if channel == "throws" then
				error("denied", 0)
			end
			return channel ~= "off"
		end)
		t:expect(visited):toEqual({ "ok", "off", "throws", "last" })
		t:expect(refusals):toEqual({ "off:chat_off_or_absent", "throws:denied" })
	end)
	suite:case("platform privacy fails closed and permission retries are bounded", function(t)
		local clock = Clock.new()
		local calls = 0
		local function denied(): boolean
			calls += 1
			error("unavailable", 0)
		end
		t:expect(Chat.permission(denied, clock.advance, false, 1, 4, 0.25)):toBe("unavailable")
		t:expect(calls):toBe(4)
		t:expect(clock.clock()):toBe(1.75)
		t:expect(Chat.permission(denied, clock.advance, true, -1, 4, 0.25)):toBe("allowed")
		t:expect(Chat.permission(function(): boolean
			return false
		end, clock.advance, false, 1, 4, 0.25)):toBe("denied")
		t:expect(Chat.directAllowed(function(_id: number, _ids: { number }): { number }
			error("privacy unavailable", 0)
		end, 1, 2)):toBe(false)
		t:expect(Chat.directAllowed(function(_id: number, ids: { number }): { number }
			return ids
		end, 1, 2)):toBe(true)
	end)
	suite:case("foreign cleanup preserves approved channels and nonchannels", function(t)
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
		t:expect(result):toEqual({ "foreign" })
		t:expect(removed):toEqual({ "foreign" })
	end)
end
