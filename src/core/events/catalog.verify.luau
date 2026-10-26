--!strict
local Catalog = require("./catalog")
local Verify = require("../../../.lute/dependencies/verify/src/core")
return function(suite: Verify.Harness)
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
	suite:case("validates supplied schema and content hooks", function(t)
		t:expect((law.validateCatalog({ schemaVersion = 7, events = { event() } }))):toBe(true)
		t:expect((law.validateCatalog({ schemaVersion = 1, events = { event() } }))):toBe(false)
		t:expect((law.validateCatalog(false))):toBe(false)
		t:expect((law.validateCatalog({ schemaVersion = 7 }))):toBe(false)
		t:expect((law.validateCatalog({ schemaVersion = 7, events = { event(), event() } }))):toBe(false)
		local other = Catalog.catalog({ schemaVersion = 7, contentKeys = { "other" } })
		t:expect((other.projectEvent(event()))):toBeNil()
	end)
	suite:case("rejects missing fields, malformed times, unsupported rollout and empty hooks", function(t)
		local invalid: { unknown } = {
			false,
			{},
			{ id = "id" },
			{ id = "id", title = "Title" },
			{ id = "id", title = "Title", realm = "realm" },
		}
		for _, raw in invalid do
			t:expect((law.projectEvent(raw))):toBeNil()
		end
		local e = event()
		e.schedule.endUnix = 5
		t:expect((law.projectEvent(e))):toBeNil()
		e = event()
		e.schedule.startUnix = math.huge
		t:expect((law.projectEvent(e))):toBeNil()
		e = event()
		e.contentScale.maps = {}
		t:expect((law.projectEvent(e))):toBeNil()
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
			t:expect((law.projectEvent(raw))):toBeNil()
		end
	end)
	suite:case("projects detached values and ignores malformed optional reward and flag values", function(t)
		local e = event()
		local projected = assert(law.projectEvent(e))
		projected.contentScale.maps[1] = "changed"
		t:expect(projected.contentScale.maps[1]):toBe("changed")
		t:expect(e.contentScale.maps[1]):toBe("map")
		local p = assert(law.projectEvent({
			id = "id",
			title = "Event",
			realm = "realm",
			schedule = { startUnix = 1, endUnix = 2 },
			contentScale = { maps = { "map" } },
			rewards = { good = 2, bad = math.huge },
			flags = { good = true, bad = {} },
		}))
		t:expect(assert(p.rewards).good):toBe(2)
		t:expect(assert(p.rewards).bad):toBeNil()
		t:expect(assert(p.flags).good):toBe(true)
		t:expect(assert(p.flags).bad):toBeNil()
	end)
end
