--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Reference = require("./api-reference")
local Verify = require("../../.lute/dependencies/verify/src/core")

local source = [[
export type State<T> = {
    values: { T },
}
local function hiddenImplementation(value: number): number
    return value + 1
end
local function build<T>(value: T)
    local function read(): T
        return value
    end
    return table.freeze({ read = read })
end
local function named()
    local Operations = {}
    function Operations.reset(value: number): boolean
        return value > 0
    end
    return table.freeze(Operations)
end
return table.freeze({ create = build, named = named })
]]

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("API declarations", function()
		it("preserves generics, multiline types, exported aliases and factory operations", function()
			local docs = Reference.renderSource(source, "fixture", "fixture.luau", { "named", "create" })
			expect(string.find(docs, "export type State<T> = {\n    values: { T },\n}", 1, true) ~= nil):toBe(true)
			expect(string.find(docs, "function build<T>(value: T)", 1, true) ~= nil):toBe(true)
			expect(string.find(docs, "read = function read(): T", 1, true) ~= nil):toBe(true)
			expect(string.find(docs, "reset = function Operations.reset(value: number): boolean", 1, true) ~= nil):toBe(
				true
			)
			expect((string.find(docs, "hiddenImplementation", 1, true))):toBeNil()
			local createAt = assert(string.find(docs, "fixture.create", 1, true))
			local namedAt = assert(string.find(docs, "fixture.named", 1, true))
			expect(createAt < namedAt):toBe(true)
		end)
		it("normalizes line endings and changes when an exported declaration changes", function()
			local before = Reference.renderSource(source, "fixture", "fixture.luau", { "create" })
			local windows =
				Reference.renderSource(string.gsub(source, "\n", "\r\n"), "fixture", "fixture.luau", { "create" })
			expect(windows):toBe(before)
			local changed = Reference.renderSource(
				string.gsub(source, "values: { T }", "values: { T? }", 1),
				"fixture",
				"fixture.luau",
				{ "create" }
			)
			expect(changed == before):toBe(false)
		end)
	end)
end
