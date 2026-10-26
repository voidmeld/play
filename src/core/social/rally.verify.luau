--!strict

local Boards = require("./rally")
local Shape = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local settings: Boards.Config = {
	maxRows = 2,
	maxTime = 20,
	maxId = 2,
	kinds = { watch = true },
	titles = { call = true },
	landmarks = { gate = true },
	realms = { zone = true, shared = true },
	sharedRealm = "shared",
}
local board = Boards.rally(settings)

local function row(id: string, expires: number): Shape.Raw
	return {
		objectiveId = id,
		objectiveKind = "watch",
		titleId = "call",
		landmarkId = "gate",
		zoneId = "z",
		realmId = "zone",
		expiresAtSec = expires,
		active = true,
		serverAuthored = true,
	}
end

return function(suite: Verify.Harness)
	suite:case("filters authored live rows and sorts the configured source prefix", function(context)
		local a, b, c = row("a", 10), row("b", 8), row("c", 7)
		local rows = assert(board.project({ a, b, c }, "z", "zone", 5))
		context:expect(#rows):toBe(2)
		context:expect(rows[1].objectiveId):toBe("b")
		context:expect(rows[2].objectiveId):toBe("a")
		context:expect(table.isfrozen(rows[1])):toBe(true)
		a.active, b.serverAuthored = false, false
		context:expect(#assert(board.project({ a, b, c }, "z", "zone", 7))):toBe(0)
		c.realmId = "shared"
		context:expect(#assert(board.project({ c }, "z", "zone", 6))):toBe(1)
		context:expect(#assert(board.project({ c }, "x", "zone", 6))):toBe(0)
	end)

	suite:case("uses configured kinds, titles, landmarks, realms and numeric bounds", function(context)
		local invalid: { [string]: unknown } = {
			objectiveId = "abc",
			objectiveKind = "other",
			titleId = "other",
			landmarkId = "other",
			realmId = "other",
			expiresAtSec = 21,
		}
		for field, value in invalid do
			local candidate = row("a", 10)
			candidate[field] = value
			context:expect(board.project({ candidate }, "z", "zone", 0)):toBeNil()
		end
		context:expect(board.project({ row("a", 10) }, "z", "other", 0)):toBeNil()
		context:expect(board.project({ row("a", 10) }, "z", "zone", 21)):toBeNil()
		local cfg = table.clone(settings)
		cfg.maxRows = 1
		context:expect(#assert(Boards.rally(cfg).project({ row("a", 10), row("b", 10) }, "z", "zone", 0))):toBe(1)
	end)

	suite:case("rejects holes, duplicate identities, metatables and unknown fields", function(context)
		context:expect(board.project({ [2] = row("a", 10) }, "z", "zone", 0)):toBeNil()
		context:expect(board.project({ row("a", 10), row("a", 11) }, "z", "zone", 0)):toBeNil()
		context:expect(board.project(setmetatable({}, {}), "z", "zone", 0)):toBeNil()
		local candidate = row("a", 10)
		candidate.extra = true
		context:expect(board.project({ candidate }, "z", "zone", 0)):toBeNil()
	end)
end
