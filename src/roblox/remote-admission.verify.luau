--!strict

local Admission = require("./remote-admission")
local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Payload = require("../core/net/payload")
local Verify = require("../../.lute/dependencies/verify/src/core")

local function fixture(capacity: number?)
	local state = { now = 0, connected = 0, disconnected = 0, notices = 0, hooks = 0, calls = 0, failConnect = false }
	local callbacks: { [string]: (string, ...unknown) -> () } = {}
	local owned: { () -> () } = {}
	local service = Admission.new({
		clock = function(): number
			return state.now
		end,
		keyFor = function(player: string): string
			return player
		end,
		budget = function(_name: string): { capacity: number, refillPerSec: number }
			return { capacity = capacity or 3, refillPerSec = 1 }
		end,
		payload = { bounds = { maxArguments = 2, maxEntries = 4, maxDepth = 2, maxString = 8, maxKey = 8 } },
		maxChannels = 2,
		maxHandlers = 4,
		maxKeys = 2,
		maxText = 16,
		refusalWindow = 2,
		connect = function(event: string, callback: (string, ...unknown) -> ()): () -> ()
			if state.failConnect then
				error("connect failed")
			end
			state.connected += 1
			callbacks[event] = callback
			return function()
				state.disconnected += 1
				callbacks[event] = nil
			end
		end,
		own = function(release: () -> ())
			table.insert(owned, release)
		end,
		notify = function(_name: string, _player: string, _reason: string)
			state.notices += 1
		end,
	})
	local function handler(_player: string, args: Payload.Arguments)
		state.calls += 1
		assert(args.n <= 2)
	end
	local function refused(_player: string, _reason: string)
		state.hooks += 1
	end
	return {
		service = service,
		state = state,
		callbacks = callbacks,
		owned = owned,
		handler = handler,
		refused = refused,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("remote admission coordinator", function()
		it("cleans refused native setup and permits a corrected registration", function()
			local f = fixture()
			f.state.failConnect = true
			local ok = pcall(function()
				f.service.serve("channel", "event", f.handler, nil)
			end)
			expect(ok):toBe(false)
			expect(f.service.served("channel")):toBe(0)
			f.state.failConnect = false
			f.service.serve("channel", "event", f.handler, nil)
			expect(f.state.connected):toBe(1)
			expect(f.service.receive("channel", "a").accepted):toBe(1)
		end)
		it("shares one native connection and charges the channel once with stricter handler lanes", function()
			local f = fixture()
			local release = f.service.serve(
				"channel",
				"event",
				f.handler,
				{ lane = { capacity = 1, refillPerSec = 0.5 }, refused = f.refused }
			)
			f.service.serve("channel", "event", f.handler, { refused = f.refused })
			expect(f.state.connected):toBe(1)
			expect(f.service.receive("channel", "a", 1).accepted):toBe(2)
			expect(f.service.receive("channel", "a", 1).accepted):toBe(1)
			expect(f.service.receive("channel", "a", 1).accepted):toBe(1)
			expect(f.service.receive("channel", "a", 1).reason):toBe("channel_limited")
			expect(f.state.notices):toBe(2)
			expect(f.state.hooks):toBe(4)
			f.state.now = 2
			expect(f.service.receive("channel", "a", 1).accepted):toBe(2)
			release()
			release()
			expect(f.service.served("channel")):toBe(1)
			expect(f.state.disconnected):toBe(0)
			f.service.dispose()
			f.service.dispose()
			expect(f.state.disconnected):toBe(1)
		end)
		it("deduplicates notifications across lanes and repeated refusals while invoking each refusal hook", function()
			local f = fixture(10)
			for _ = 1, 2 do
				f.service.serve(
					"channel",
					"event",
					f.handler,
					{ lane = { capacity = 1, refillPerSec = 1 }, refused = f.refused }
				)
			end
			f.callbacks.event("a", "ok")
			expect(f.service.receive("channel", "a").refused):toBe(2)
			expect(f.service.receive("channel", "a").refused):toBe(2)
			expect(f.state.notices):toBe(1)
			expect(f.state.hooks):toBe(4)
			f.state.now = 2
			f.service.receive("channel", "a")
			f.service.receive("channel", "a")
			expect(f.state.notices):toBe(2)
		end)
		it("bounds payload decoding and sender state and recovers through per-key forget", function()
			local f = fixture(10)
			f.service.serve("channel", "event", f.handler, { refused = f.refused })
			expect(f.service.receive("channel", "a", { a = { b = {} } }).reason):toBe("payload_invalid")
			expect(f.service.receive("channel", "a", 1, 2, 3).reason):toBe("payload_invalid")
			expect(f.state.calls):toBe(0)
			expect(f.service.receive("channel", "b", nil, true).accepted):toBe(1)
			expect(f.service.receive("channel", "c").reason):toBe("senders_full")
			f.service.forget("a")
			expect(f.service.receive("channel", "c").accepted):toBe(1)
			f.service.forget("c")
			expect(f.service.receive("channel", "a", { a = 1 }).accepted):toBe(1)
			f.state.now = -1
			expect(f.service.receive("channel", "a").reason):toBe("clock_invalid")
		end)
		it("snapshots dispatch, excludes recursive invocation and survives handler and hook failures", function()
			local f = fixture(10)
			local added = false
			f.service.serve("channel", "event", function(_player: string, _args: Payload.Arguments)
				if not added then
					added = true
					f.service.serve("channel", "event", f.handler, nil)
				end
				expect(f.service.receive("channel", "a").reason):toBe("invocation_busy")
				error("handler failed")
			end, {
				refused = function(_player: string, _reason: string)
					error("hook failed")
				end,
			})
			expect(f.service.receive("channel", "a").accepted):toBe(0)
			expect(f.state.calls):toBe(0)
			expect(f.service.receive("channel", "a").accepted):toBe(1)
			expect(f.state.calls):toBe(1)
		end)
		it("fences forgotten dispatch and rejects weaker lanes without leaking a registration", function()
			local f = fixture()
			f.service.serve("channel", "event", function(_player: string, _args: Payload.Arguments)
				f.service.forget("a")
				expect(f.service.receive("channel", "a").reason):toBe("invocation_busy")
			end, nil)
			f.service.serve("channel", "event", f.handler, nil)
			expect(f.service.receive("channel", "a").accepted):toBe(1)
			expect(f.state.calls):toBe(0)
			local ok = pcall(function()
				f.service.serve("channel", "event", f.handler, { lane = { capacity = 4, refillPerSec = 1 } })
			end)
			expect(ok):toBe(false)
			expect(f.service.served("channel")):toBe(2)
		end)
	end)
end
