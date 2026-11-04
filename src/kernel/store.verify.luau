--!strict

local Backend = require("../core/persistence/store-host")
local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Codec = require("./codec")
local Native = require("../roblox/persistence/store")
local Result = require("./result")
local Scene = require("../test-scene/persistence/store")
local Store = require("./store")
local Value = require("./value")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Record = { revision: number, payload: string }
local function copy(value: unknown): (Record?, string?)
	local fields = Value.record(value, { revision = true, payload = true }, true)
	if fields == nil or type(fields.payload) ~= "string" then
		return nil, "record_invalid"
	end
	local revision = Value.whole(fields.revision, 0, 100)
	if revision == nil then
		return nil, "record_invalid"
	end
	return { revision = revision, payload = fields.payload }, nil
end
local codec: Store.Codec<Record> = {
	copy = copy,
	equal = function(left: Record, right: Record): boolean
		return left.revision == right.revision and left.payload == right.payload
	end,
}
local function clock(): number
	return 0
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("atomic store port", function()
		it("confirms exact absence and refuses divergent or unavailable replay readback", function()
			local scene = Scene.new(clock)
			expect(Store.confirm(scene.store, "record", Result.ok(nil)).ok):toBe(true)
			local expected = Codec.copyData({ revision = 1, payload = "one" })
			scene.seed("record", { revision = 1, payload = "two" })
			expect(Result.reason(Store.confirm(scene.store, "record", expected))):toBe("readback_mismatch")
			scene.seed("record", { revision = 1, payload = "one" })
			expect(Store.confirm(scene.store, "record", expected).ok):toBe(true)
			local unreadable: Store.Reader = {
				read = function(): Result.Result<unknown>
					return Result.fail("offline")
				end,
			}
			expect(Result.reason(Store.confirm(unreadable, "record", expected))):toBe("offline")
			expect(Result.reason(Store.confirm(unreadable, "record", Result.fail("value_invalid")))):toBe(
				"value_invalid"
			)
			expect(scene.writes()):toBe(2)
		end)
		it("refuses malformed backend envelopes at both boundaries", function()
			local function malformed(): Backend.Outcome
				local outcome: Backend.Outcome = { ok = true, value = "untrusted" }
				return setmetatable(outcome, {})
			end
			local store = Native.new({
				getUncachedOutcome = malformed,
				updateOutcome = malformed,
			})
			expect(Result.reason(store.read("record"))):toBe("read_failed")
			expect(Result.reason(store.update("record", function(): unknown
				return nil
			end))):toBe("store_failure")
		end)
		it("distinguishes missing reads and compares the complete expected record", function()
			local scene = Scene.new(clock)
			expect(Result.unwrap(scene.store.read("record"))):toBeNil()
			local expected: Record = { revision = 0, payload = "one" }
			local desired: Record = { revision = 1, payload = "two" }
			scene.seed("record", { revision = 0, payload = "foreign" })
			local refused = scene.store.update("record", Store.compareAndSwap(true, expected, desired, codec))
			expect(Result.reason(refused)):toBe("callback_cancelled")
			expect(scene.writes()):toBe(1)
			scene.seed("record", expected)
			local saved =
				Result.unwrap(scene.store.update("record", Store.compareAndSwap(true, expected, desired, codec)))
			expect(Result.unwrap(Store.committed(saved, desired, codec))):toEqual(desired)
		end)
		it("never commits an earlier callback after the final comparison refuses", function()
			local scene = Scene.new(clock, { rerun = true })
			local empty: Record = { revision = 0, payload = "empty" }
			local desired: Record = { revision = 1, payload = "next" }
			local result = scene.store.update("record", Store.compareAndSwap(false, empty, desired, codec))
			expect(Result.reason(result)):toBe("callback_cancelled")
			expect(scene.writes()):toBe(0)
			expect(scene.updates()):toBe(1)
			expect(Result.unwrap(scene.store.read("record"))):toBeNil()
		end)
		it("retains uncertainty after a committed write until a successful readback", function()
			local offline = true
			local scene = Scene.new(clock, {
				fault = function(): string?
					return if offline then "offline" else nil
				end,
			})
			local desired: Record = { revision = 1, payload = "saved" }
			local result = scene.store.update("record", function(): unknown
				return desired
			end)
			expect(Result.reason(result)):toBe("offline")
			expect(scene.writes()):toBe(1)
			offline = false
			local read = Result.unwrap(scene.store.read("record"))
			expect(Result.unwrap(Store.committed(read, desired, codec))):toEqual(desired)
		end)
		it("rejects valid divergent readback and detaches successful values from storage", function()
			local scene = Scene.new(clock)
			local desired: Record = { revision = 1, payload = "saved" }
			scene.seed("record", desired)
			local raw = Result.unwrap(scene.store.read("record"))
			assert(type(raw) == "table")
			table.clear(raw)
			expect(Result.unwrap(scene.store.read("record"))):toEqual(desired)
			local mismatch = Store.committed({ revision = 1, payload = "different" }, desired, codec)
			expect(Result.reason(mismatch)):toBe("readback_conflict")
		end)
	end)
end
