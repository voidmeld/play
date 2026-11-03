--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local DataStore = require("../../roblox/data-store")
local StoreHost = require("./store-host")
local Value = require("../../kernel/value")
local Verify = require("../../../.lute/dependencies/verify/src/core")
local retry = DataStore.retryPolicy({ attempts = 2, baseDelay = 0, maxDelay = 0 })
local host = StoreHost.create({
	clock = function()
		return 0
	end,
	maxKeyBytes = 50,
	maxAttempts = 2,
	backoff = retry.delay,
	retry = retry.run,
	warning = function() end,
})
local function fixture()
	local state = {
		now = 0,
		sequence = 0,
		queue = {},
		values = {},
		fail = true,
		writes = {},
	}
	local raw: StoreHost.RawStore = {
		GetAsync = function(_self, key)
			return state.values[key]
		end,
		SetAsync = function(_self, key, value)
			if state.fail and key == "a" then
				error("unavailable")
			end
			state.values[key] = value
			table.insert(state.writes, key .. ":" .. tostring(value))
		end,
		UpdateAsync = function(_self, key, transform)
			if state.fail then
				error("unavailable")
			end
			local value = transform(state.values[key])
			if value ~= nil then
				state.values[key] = value
			end
			return value
		end,
	}
	local function remove(id: string)
		for index, row in state.queue do
			if row.id == id then
				table.remove(state.queue, index)
				return
			end
		end
	end
	local circuit: StoreHost.Circuit = {
		success = function() end,
		failure = function() end,
		canAttempt = function()
			return true
		end,
		begin = function() end,
		enqueue = function(request, now)
			state.sequence += 1
			local row =
				{ id = tostring(state.sequence), storeName = request.storeName, key = request.key, nextAttemptAt = now }
			table.insert(state.queue, row)
			return true, nil, row
		end,
		markFailure = function(id, now)
			for _, row in state.queue do
				if row.id == id then
					row.nextAttemptAt = now + 1
				end
			end
		end,
		markSuccess = remove,
		hasQueued = function(name, key)
			for _, row in state.queue do
				if row.storeName == name and row.key == key then
					return true
				end
			end
			return false
		end,
		isReadOnly = function()
			return false
		end,
		list = function()
			return state.queue
		end,
	}
	local function make()
		return host.real("records", state, circuit, {
			raw = raw,
			sleep = function() end,
			jitter = function()
				return 0
			end,
			now = function()
				return state.now
			end,
			clock = function()
				return state.now
			end,
			requestBudget = function()
				return 1
			end,
			uncachedOptions = function()
				return { UseCache = false }
			end,
			validUncachedOptions = function(value)
				local fields = Value.raw(value)
				return fields ~= nil and fields.UseCache == false
			end,
		})
	end
	return state, make
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("Persistence host operations", function()
		it("preserves per-key ordering across handles while independent keys can progress", function()
			local state, make = fixture()
			local first, second = make(), make()
			expect(first.set("a", 1).ok):toBe(false)
			expect(second.set("a", 2).ok):toBe(false)
			expect(first.set("b", 3).ok):toBe(true)
			expect(state.values.a):toBeNil()
			expect(state.values.b):toBe(3)
			state.fail, state.now = false, 1
			expect(second.flushQueuedWrites()):toBe(2)
			expect(state.values.a):toBe(2)
			expect(state.writes):toEqual({ "b:3", "a:1", "a:2" })
			expect(first.hasPendingWrite("a")):toBe(false)
		end)
		it("does not retain failed atomic transforms for later accidental replay", function()
			local state, make = fixture()
			local store = make()
			local invoked = 0
			local outcome = store.updateOutcome("a", function()
				invoked += 1
				return 4
			end)
			expect(outcome.reason):toBe("retry_exhausted")
			expect(store.hasPendingWrite("a")):toBe(false)
			state.fail, state.now = false, 10
			store.flushQueuedWrites()
			expect(invoked):toBe(0)
			expect(store.updateOutcome("a", function()
				return nil
			end).reason):toBe("callback_cancelled")
			expect(store.updateOutcome("a", function()
				return 4
			end).value):toBe(4)
		end)
		it("copies memory transaction inputs and readback and rejects cyclic values", function()
			local values: { [string]: unknown } = { a = { count = 3 } }
			local memory: StoreHost.MemoryStore = {
				name = "records",
				get = function(key)
					return values[key]
				end,
				set = function(key, value)
					values[key] = value
				end,
				update = function(key, transform)
					local value = transform(values[key])
					if value ~= nil then
						values[key] = value
					end
					return value
				end,
			}
			local store = host.memory(memory, nil, function()
				return nil
			end)
			local result = store.updateOutcome("a", function(value)
				assert(type(value) == "table")
				table.clear(value)
				return nil
			end)
			expect(result.reason):toBe("callback_cancelled")
			expect(assert(Value.raw(values.a)).count):toBe(3)
			local got = store.getOutcome("a").value
			assert(type(got) == "table")
			table.clear(got)
			expect(assert(Value.raw(values.a)).count):toBe(3)
			local cyclic: { [string]: unknown } = {}
			cyclic.self = cyclic
			expect(store.updateOutcome("a", function()
				return cyclic
			end).reason):toBe("value_invalid")
		end)
		it("drains until completion or the supplied deadline without declaring pending writes durable", function()
			local now, pending = 0, 2
			local result = host.drain(
				function()
					pending -= 1
					return 1
				end,
				function()
					return pending
				end,
				1,
				function()
					return now
				end,
				function(dt)
					now += dt
				end
			)
			expect(result.ok):toBe(true)
			expect(result.flushed):toBe(2)
			pending = 1
			local expired = host.drain(
				function()
					return 0
				end,
				function()
					return pending
				end,
				0.1,
				function()
					return now
				end,
				function(dt)
					now += dt
				end
			)
			expect(expired.ok):toBe(false)
			expect(expired.remaining):toBe(1)
			expect(expired.reason):toBe("deadline_exceeded")
		end)
	end)
end
