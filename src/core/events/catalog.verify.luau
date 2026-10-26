--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Catalog = require("./catalog")
local Verify = require("../../../.lute/dependencies/verify/src/core")
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("catalog", function()
		local law = Catalog.catalog({ schemaVersion = 7, contentKeys = { "maps" } })
		local function event()
			return {
				id = "event",
				title = "Event",
				realm = "realm",
				schedule = { startUnix = 5, endUnix = 10 },
				contentScale = {
					maps = { "map" },
				},
			}
		end
		it("validates supplied schema and content hooks", function()
			expect((law.validateCatalog({ schemaVersion = 7, events = { event() } }))):toBe(true)
			expect((law.validateCatalog({ schemaVersion = 1, events = { event() } }))):toBe(false)
			expect((law.validateCatalog(false))):toBe(false)
			expect((law.validateCatalog({ schemaVersion = 7 }))):toBe(false)
			expect((law.validateCatalog({ schemaVersion = 7, events = { event(), event() } }))):toBe(false)
			local other = Catalog.catalog({ schemaVersion = 7, contentKeys = { "other" } })
			expect((other.projectEvent(event()))):toBeNil()
		end)
		it("rejects missing fields, malformed times, unsupported rollout and empty hooks", function()
			local invalid: { unknown } = {
				false,
				{},
				{ id = "id" },
				{ id = "id", title = "Title" },
				{ id = "id", title = "Title", realm = "realm" },
			}
			for _, raw in invalid do
				expect((law.projectEvent(raw))):toBeNil()
			end
			local e = event()
			e.schedule.endUnix = 5
			expect((law.projectEvent(e))):toBeNil()
			e = event()
			e.schedule.startUnix = math.huge
			expect((law.projectEvent(e))):toBeNil()
			e = event()
			e.contentScale.maps = {}
			expect((law.projectEvent(e))):toBeNil()
			for _, rollout in
				{
					{ mode = "unknown" },
					{ mode = "bucket" },
					{ mode = "bucket", percent = -1 },
					{ mode = "bucket", percent = 101 },
					{ mode = "bucket", percent = math.nan },
				}
			do
				local raw = {
					id = "id",
					title = "Event",
					realm = "realm",
					schedule = { startUnix = 1, endUnix = 2 },
					contentScale = { maps = { "map" } },
					rollout = rollout,
				}
				expect((law.projectEvent(raw))):toBeNil()
			end
		end)
		it("projects detached values and ignores malformed optional reward and flag values", function()
			local e = event()
			local projected = assert(law.projectEvent(e))
			projected.contentScale.maps[1] = "changed"
			expect(projected.contentScale.maps[1]):toBe("changed")
			expect(e.contentScale.maps[1]):toBe("map")
			local p = assert(law.projectEvent({
				id = "id",
				title = "Event",
				realm = "realm",
				schedule = { startUnix = 1, endUnix = 2 },
				contentScale = { maps = { "map" } },
				rewards = { good = 2, bad = math.huge },
				flags = { good = true, bad = {} },
			}))
			expect(assert(p.rewards).good):toBe(2)
			expect(assert(p.rewards).bad):toBeNil()
			expect(assert(p.flags).good):toBe(true)
			expect(assert(p.flags).bad):toBeNil()
		end)
	end)
end
