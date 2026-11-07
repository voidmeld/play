--!strict

local Admission = require("./remote-admission")
local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Payload = require("../core/net/payload")
local Result = require("../kernel/result")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Policies = {
	noticePolicy: ("window" | "streak")?,
	retainBudgets: boolean?,
	spawn: ((() -> ()) -> ())?,
	decode: ((...unknown) -> Result.Result<Payload.Arguments>)?,
	unbounded: boolean?,
	externalPayload: boolean?,
}
local function fixture(capacity: number?, supplied: Policies?)
	local policies: Policies = supplied or {}
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
		payload = if policies.externalPayload
			then nil
			else { bounds = { maxArguments = 2, maxEntries = 4, maxDepth = 2, maxString = 8, maxKey = 8 } },
		maxChannels = if policies.unbounded then nil else 2,
		maxHandlers = if policies.unbounded then nil else 4,
		maxKeys = if policies.unbounded then nil else 2,
		maxText = if policies.unbounded then nil else 16,
		refusalWindow = if policies.unbounded then nil else 2,
		noticePolicy = policies.noticePolicy,
		retainBudgets = policies.retainBudgets,
		spawn = policies.spawn,
		decode = policies.decode,
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
		it("isolates structured hook and injected decoder failures and releases invocation exclusion", function()
			local f = fixture(10, {
				decode = function(...: unknown): Result.Result<Payload.Arguments>
					local args = table.pack(...)
					if args[1] == "refuse" then
						return Result.fail("custom_refusal")
					elseif args[1] == "throw" then
						error("decoder failed")
					end
					return Result.ok(args)
				end,
			})
			f.service.register("channel", f.handler, {
				refused = f.refused,
				refusedRecord = function(_record: Admission.Refusal<string>)
					error("record hook failed")
				end,
				refusedArgs = function(_player: string, ...: unknown)
					error("argument hook failed")
				end,
			})
			expect(f.service.receive("channel", "a", "refuse").reason):toBe("payload_invalid")
			expect(f.service.receive("channel", "a", "throw").reason):toBe("dispatch_failed")
			expect(f.state.hooks):toBe(2)
			expect(f.service.receive("channel", "a", "ok").accepted):toBe(1)
		end)
		it("admits standalone lanes without consuming aggregate tokens or registering handlers", function()
			local f = fixture(1, { noticePolicy = "streak" })
			local lane = f.service.lane("channel", { lane = { capacity = 1, refillPerSec = 0 }, refused = f.refused })
			expect(f.service.served("channel")):toBe(0)
			expect(lane.admit("a")):toBe(true)
			expect(lane.admit("a")):toBe(false)
			expect(f.state.hooks):toBe(1)
			f.service.register("channel", f.handler, nil)
			expect(f.service.receive("channel", "a").accepted):toBe(1)
			f.service.forget("a")
			expect(lane.admit("a")):toBe(true)
			lane.remove()
			lane.remove()
			expect(lane.admit("a")):toBe(false)
			local unlimited = f.service.lane("channel", nil)
			expect(unlimited.admit("a")):toBe(true)
			expect(unlimited.admit("a")):toBe(true)
			f.service.dispose()
			expect(unlimited.admit("a")):toBe(false)
		end)
		it("returns aggregate admission even when every handler lane refuses", function()
			local f = fixture(2)
			f.service.register("channel", f.handler, { lane = { capacity = 1, refillPerSec = 0 } })
			expect(f.service.dispatch("channel", "a")):toBe(true)
			expect(f.service.dispatch("channel", "a")):toBe(true)
			expect(f.state.calls):toBe(1)
			expect(f.service.dispatch("channel", "a")):toBe(false)
		end)
		it("schedules raw event handlers and refusal arguments while keeping invoke replies synchronous", function()
			local pending: { () -> () } = {}
			local f = fixture(1, {
				spawn = function(run: () -> ())
					table.insert(pending, run)
				end,
			})
			local received: Payload.Arguments? = nil
			local refused: Payload.Arguments? = nil
			f.service.registerRaw("channel", function(_player: string, ...: unknown)
				received = table.pack(...)
			end, {
				refusedArgs = function(_player: string, ...: unknown)
					refused = table.pack(...)
				end,
			})
			f.service.receive("channel", "a", nil, "x")
			f.service.receive("channel", "a", nil, "y")
			expect(received):toBeNil()
			expect(refused):toBeNil()
			expect(#pending):toBe(2)
			for _, run in pending do
				run()
			end
			assert(received ~= nil and refused ~= nil)
			expect(received.n):toBe(2)
			expect(received[2]):toBe("x")
			expect(refused[2]):toBe("y")
			local invoke = f.service.serveInvoke("request", function(_player: string): string
				return "reply"
			end, nil)
			expect(invoke.call("a")):toBe("reply")
			expect(#pending):toBe(2)
		end)
		it("registers invoke lanes, preserves nil response slots and fences removal and duplicate setup", function()
			local f = fixture()
			local invoke = f.service.serveInvoke("request", function(player: string, ...: unknown): ...unknown
				return player, select("#", ...), ...
			end, nil)
			local reply = table.pack(invoke.call("a", nil, "x"))
			expect(reply.n):toBe(4)
			expect(reply[1]):toBe("a")
			expect(reply[2]):toBe(2)
			expect(reply[3]):toBeNil()
			expect(reply[4]):toBe("x")
			expect(f.state.connected):toBe(0)
			expect(pcall(function()
				f.service.serveInvoke("request", function(_player: string): nil
					return nil
				end, nil)
			end)):toBe(false)
			expect(f.service.served("request")):toBe(1)
			invoke.remove()
			invoke.remove()
			f.service.serveInvoke("request", function(_player: string): string
				return "replacement"
			end, nil)
			expect(invoke.call("a")):toBeNil()
			expect(f.service.served("request")):toBe(1)
			f.service.dispose()
			expect(f.service.served("request")):toBe(0)
		end)
		it("reports frozen structured refusals alongside legacy and original argument hooks", function()
			local f = fixture(1)
			local records: { Admission.Refusal<string> } = {}
			local function handler(_player: string, ...: unknown): number
				return select("#", ...)
			end
			local invoke = f.service.serveInvoke("request", handler, {
				refused = f.refused,
				refusedRecord = function(record: Admission.Refusal<string>)
					table.insert(records, record)
				end,
				refusedArgs = function(player: string, ...: unknown): ...unknown
					return "refused", player, select("#", ...), ...
				end,
			})
			expect(invoke.call("a")):toBe(0)
			local reply = table.pack(invoke.call("a", nil, "x"))
			expect(reply.n):toBe(5)
			expect(reply[1]):toBe("refused")
			expect(reply[4]):toBeNil()
			expect(reply[5]):toBe("x")
			expect(f.state.hooks):toBe(1)
			expect(records[1].handler):toBe(handler)
			expect(records[1].player):toBe("a")
			expect(records[1].reason):toBe("channel_limited")
			expect(records[1].payloadSize):toBe(2)
			expect(table.isfrozen(records[1])):toBe(true)
		end)
		it("shares invoke aggregate and handler budgets, forgets keys and recovers after handler errors", function()
			local f = fixture(3)
			local calls = 0
			local invoke = f.service.serveInvoke("request", function(_player: string): string
				calls += 1
				if calls == 1 then
					error("failed")
				end
				return "ok"
			end, { lane = { capacity = 1, refillPerSec = 0 }, refused = f.refused })
			expect(invoke.call("a")):toBeNil()
			expect(invoke.call("a")):toBeNil()
			expect(calls):toBe(1)
			expect(f.state.hooks):toBe(2)
			f.service.forget("a")
			expect(invoke.call("a")):toBe("ok")
			f.service.dispose()
			expect(invoke.call("a")):toBeNil()
		end)
		it("retains aggregate budgets after removal only when configured", function()
			for _, retain in { false, true } do
				local f = fixture(1, { retainBudgets = retain })
				local remove = f.service.register("channel", f.handler, nil)
				expect(f.service.receive("channel", "a").accepted):toBe(1)
				remove()
				f.service.register("channel", f.handler, nil)
				expect(f.service.receive("channel", "a").accepted):toBe(if retain then 0 else 1)
				f.service.forget("a")
				expect(f.service.receive("channel", "a").accepted):toBe(1)
			end
		end)
		it("deduplicates channel and handler refusal streaks until successful consumption", function()
			local f = fixture(1, { noticePolicy = "streak" })
			f.service.register("channel", f.handler, nil)
			f.service.receive("channel", "a")
			f.service.receive("channel", "a")
			f.state.now = 0.5
			f.service.receive("channel", "a")
			expect(f.state.notices):toBe(1)
			f.state.now = 1
			f.service.receive("channel", "a")
			f.service.receive("channel", "a")
			expect(f.state.notices):toBe(2)
			local lanes = fixture(10, { noticePolicy = "streak" })
			for _ = 1, 2 do
				lanes.service.register("channel", lanes.handler, { lane = { capacity = 1, refillPerSec = 1 } })
			end
			lanes.service.receive("channel", "a")
			lanes.service.receive("channel", "a")
			lanes.service.receive("channel", "a")
			expect(lanes.state.notices):toBe(2)
			lanes.state.now = 1
			lanes.service.receive("channel", "a")
			lanes.service.receive("channel", "a")
			expect(lanes.state.notices):toBe(4)
		end)
		it("accepts an injected decoder and spawn seam with omitted admission ceilings", function()
			local pending: { () -> () } = {}
			local f = fixture(10, {
				unbounded = true,
				externalPayload = true,
				decode = function(...: unknown): Result.Result<Payload.Arguments>
					return Result.ok(table.pack(...))
				end,
				spawn = function(run: () -> ())
					table.insert(pending, run)
				end,
			})
			for index = 1, 5 do
				f.service.register("channel", function(_player: string, args: Payload.Arguments)
					expect(args.n):toBe(3)
					f.state.calls += 1
				end, nil)
				f.service.register("channel" .. index, f.handler, nil)
			end
			expect(
				f.service.receive("channel", string.rep("a", 17), setmetatable({}, {}), nil, "long payload").accepted
			):toBe(5)
			expect(f.state.calls):toBe(0)
			for _, run in pending do
				run()
			end
			expect(f.state.calls):toBe(5)
		end)
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
