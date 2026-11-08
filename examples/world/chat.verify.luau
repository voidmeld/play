--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Protocol = require("./protocol")
local Scene = require("./scene")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("filtered example chat", function()
		it("refuses a native filter failure without partial delivery or raw fallback", function(own)
			local scene = Scene.new()
			own(scene.dispose)
			local sender = scene.connect(11)
			local listener = scene.connect(22)
			own(sender.dispose)
			own(listener.dispose)
			local calls = 0
			scene.control.onFilter = function(_sender: number, _text: string, _listener: number): string?
				calls += 1
				if calls == 2 then
					error("filter_unavailable", 0)
				end
				return "Filtered"
			end
			local request: Protocol.ChatRequest = { kind = "chat", text = "unfiltered fixture input" }
			sender.request(request)
			expect(assert(sender.latest()).ok):toBe(false)
			expect(assert(sender.latest()).reason):toBe("chat_unavailable")
			expect(#sender.lines()):toBe(0)
			expect(#listener.lines()):toBe(0)
			expect(scene.reports()):toEqual({ "chat_unavailable" })
			scene.control.onFilter = nil
			scene.clock.advance(1)
			sender.request(request)
			expect(assert(sender.latest()).ok):toBe(true)
			expect(sender.lines()[1].text):toBe("Hello Harbor")
			expect(listener.lines()[1].text):toBe("Hello Harbor")
			expect(scene.engine.scheduler.failures):toEqual({})
			expect(scene.mount.shutdown()):toBe(true)
		end)
		it("fences sender and recipient replacements while native filtering is suspended", function(own)
			for _, replaced in { 11, 22 } do
				local scene = Scene.new()
				own(scene.dispose)
				local sender = scene.connect(11)
				local listener = scene.connect(22)
				own(sender.dispose)
				own(listener.dispose)
				local held: thread? = nil
				scene.control.onFilter = function(_sender: number, _text: string, recipient: number): string?
					if recipient == 22 then
						scene.engine.scheduler.block(function(pending)
							held = pending
						end)
					end
					return "Filtered " .. tostring(recipient)
				end
				scene.engine.scheduler.spawn(function()
					local request: Protocol.ChatRequest = { kind = "chat", text = "unfiltered fixture input" }
					sender.request(request)
				end)
				expect(held == nil):toBe(false)
				expect(scene.disconnect(replaced)):toBe(true)
				local replacement = scene.connect(replaced)
				own(replacement.dispose)
				scene.engine.scheduler.resume(assert(held))
				scene.clock.advance(0)
				expect(#replacement.lines()):toBe(0)
				expect(#listener.lines()):toBe(0)
				expect(#sender.lines()):toBe(if replaced == 22 then 1 else 0)
				if replaced == 22 then
					expect(sender.lines()[1].text):toBe("Filtered 11")
				end
				expect(scene.engine.scheduler.failures):toEqual({})
				expect(scene.mount.shutdown()):toBe(true)
			end
		end)
	end)
end
