--!strict

local Module = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local current: Verify.Context? = nil
	local function expect(value: unknown): Verify.Expectation
		return assert(current):expect(value)
	end
	local function it(name: string, body: () -> ())
		suite:case(name, function(context)
			current = context
			body()
		end)
	end
	local function describe(_name: string, body: () -> ())
		body()
	end
	local Shape = Module
	describe("shape", function()
		it("keeps optional allowed fields distinct from exact plain records", function()
			local fields = { id = true, active = true }
			expect((Shape.onlyFields({}, fields))):toBe(true)
			expect((Shape.exact({}, fields))):toBe(false)
			expect((Shape.onlyFields({ id = "x" }, fields))):toBe(true)
			expect((Shape.exact({ id = "x" }, fields))):toBe(false)
			expect((Shape.exact({ id = "x", active = false }, fields))):toBe(true)
			expect((Shape.onlyFields({ extra = true }, fields))):toBe(false)
			expect((Shape.onlyFields({ [1] = "x" }, fields))):toBe(false)
			expect((Shape.onlyFields(false, fields))):toBe(false)
			local virtual = setmetatable({ id = "x" }, { __index = { active = true } })
			expect((Shape.onlyFields(virtual, fields))):toBe(true)
			expect((Shape.exact(virtual, fields))):toBe(false)
			local guarded = setmetatable({}, {
				__iter = function(): never
					error("exact records must reject metatables before iteration")
				end,
			})
			expect((Shape.exact(guarded, fields))):toBe(false)
		end)

		it("recognizes every dense prefix and refuses holes and invalid keys", function()
			for mask = 0, 255 do
				local rows: { [number]: boolean } = {}
				local expected = 0
				for index = 1, 8 do
					if bit32.band(mask, bit32.lshift(1, index - 1)) ~= 0 then
						rows[index] = false
						expected += 1
					end
				end
				local length = if mask == 2 ^ expected - 1 then expected else nil
				expect((Shape.denseLength(rows))):toBe(length)
				for maximum = 0, 8 do
					expect((Shape.dense(rows, maximum))):toBe(
						if length ~= nil and length <= maximum then length else nil
					)
				end
			end
			local invalidKeys: { string | number } = { "1", 0, -1, 1.5, math.huge }
			for _, key in invalidKeys do
				expect((Shape.denseLength({ [key] = true }))):toBe(nil)
				expect((Shape.dense({ [key] = true }, 8))):toBe(nil)
			end
			expect((Shape.denseLength(false))):toBe(nil)
			local virtual = setmetatable({ [1] = true, [3] = true }, {
				__index = function(): boolean
					return false
				end,
			})
			expect((Shape.denseLength(virtual))):toBe(2)
			expect((Shape.dense(virtual, 8))):toBe(nil)
		end)

		it("preserves value-only freezing while the key-aware variant freezes both", function()
			local key = { nested = {} }
			local child = { nested = {} }
			local root = { [key] = child, alias = child }
			expect((Shape.freezeDeep(root))):toBe(root)
			expect((table.isfrozen(root))):toBe(true)
			expect((table.isfrozen(child.nested))):toBe(true)
			expect((table.isfrozen(key))):toBe(false)
			expect((table.isfrozen(key.nested))):toBe(false)
			local keyed = { [key] = child }
			expect((Shape.freezeDeepWithKeys(keyed))):toBe(keyed)
			expect((table.isfrozen(keyed))):toBe(true)
			expect((table.isfrozen(key))):toBe(true)
			expect((table.isfrozen(key.nested))):toBe(true)
			expect(keyed[key]):toBe(child)
		end)

		it("returns scalars and frozen roots unchanged without walking their children", function()
			type Freeze = (unknown) -> unknown
			local freezers: { Freeze } = {
				function(value: unknown): unknown
					return Shape.freezeDeep(value)
				end,
				function(value: unknown): unknown
					return Shape.freezeDeepWithKeys(value)
				end,
			}
			for _, freeze in freezers do
				expect((freeze(nil))):toBeNil()
				expect((freeze(false))):toBe(false)
				expect((freeze("value"))):toBe("value")
				local key, child = {}, {}
				local root = table.freeze({ [key] = child })
				expect((freeze(root))):toBe(root)
				expect((table.isfrozen(key))):toBe(false)
				expect((table.isfrozen(child))):toBe(false)
			end
		end)

		it("keeps iterator behavior and does not freeze the metatable", function()
			local key, child = {}, {}
			local visits = 0
			local meta = {
				__iter = function()
					visits += 1
					return next, { [key] = child }
				end,
			}
			local root = setmetatable({}, meta)
			Shape.freezeDeepWithKeys(root)
			expect(visits):toBe(1)
			expect((table.isfrozen(key))):toBe(true)
			expect((table.isfrozen(child))):toBe(true)
			expect((table.isfrozen(meta))):toBe(false)
			Shape.freezeDeepWithKeys(root)
			expect(visits):toBe(1)
		end)
	end)
end
