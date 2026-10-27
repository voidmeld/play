--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Queue = require("./equipment-queue")
local Verify = require("../../.lute/dependencies/verify/src/core")

local function fixture()
	local threads: { thread } = {}
	local active = true
	local traces: { { character: string, before: boolean, after: boolean? } } = {}
	local warnings: { string } = {}
	local queue = Queue.create({
		spawn = function(body: () -> ())
			local co = coroutine.create(body)
			table.insert(threads, co)
			local ok, reason = coroutine.resume(co)
			assert(ok, tostring(reason))
		end,
		active = function()
			return active
		end,
		current = function(_player: string, _character: string)
			return true
		end,
		perform = function(_player: string, character: string, fence: () -> boolean)
			if character == "broken" then
				error("mesh service threw")
			end
			local trace: { character: string, before: boolean, after: boolean? } =
				{ character = character, before = fence() }
			table.insert(traces, trace)
			coroutine.yield()
			trace.after = fence()
		end,
		warn = function(message: string)
			table.insert(warnings, message)
		end,
	})
	local function resolve()
		for _, co in threads do
			if coroutine.status(co) == "suspended" then
				local ok, reason = coroutine.resume(co)
				assert(ok, tostring(reason))
			end
		end
	end
	return queue, traces, warnings, resolve, function(value: boolean)
		active = value
	end
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("equipment application queue", function()
		it("returns before stalled gear resolves and fences a stale request", function()
			local queue, traces, _warnings, resolve = fixture()
			queue.request("a", "first")
			expect(traces[1].before):toBe(true)
			expect(traces[1].after):toBeNil()
			expect(queue.running("a")):toBe(true)
			queue.invalidate("a")
			resolve()
			expect(traces[1].after):toBe(false)
			expect(queue.running("a")):toBe(false)
		end)
		it("drains only the newest pending body while keeping players independent", function()
			local queue, traces, _warnings, resolve = fixture()
			queue.request("a", "first")
			queue.request("a", "second")
			queue.request("a", "third")
			queue.request("b", "other")
			expect(queue.generation("a")):toBe(3)
			expect(#traces):toBe(2)
			resolve()
			resolve()
			expect(#traces):toBe(3)
			expect(traces[1].after):toBe(false)
			expect(traces[3].character):toBe("third")
			expect(traces[3].after):toBe(true)
			expect(queue.running("a")):toBe(false)
		end)
		it("keeps draining after a failed apply and forgets departed players when the service stops", function()
			local queue, traces, warnings, resolve, setActive = fixture()
			queue.request("a", "broken")
			queue.request("a", "first")
			queue.request("a", "second")
			expect(#warnings):toBe(1)
			expect(warnings[1]):toContain("mesh service threw")
			setActive(false)
			resolve()
			expect(#traces):toBe(1)
			queue.forget("a")
			expect(queue.generation("a")):toBeNil()
			expect(queue.running("a")):toBe(false)
			queue.dispose()
		end)
	end)
end
