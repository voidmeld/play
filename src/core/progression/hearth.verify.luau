--!strict
local Module = require("./hearth")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local Core = Module.hearth({
	cooldownSec = 600,
	bindRange = 12,
	homeZones = { team = "zone_a" },
	destinations = {
		zone_a = { { npcId = "keeper_a", name = "First" }, { npcId = "keeper_b", name = "Second" } },
		zone_b = { { npcId = "keeper_c", name = "Third" }, { npcId = "keeper_d", name = "Fourth" } },
		zone_c = { { npcId = "keeper_e", name = "Fifth" }, { npcId = "keeper_f", name = "Sixth" } },
	},
})
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

	describe("bind and hearth law", function()
		it("keeps the saved Dewmere keeper and names its actual shore", function()
			local destination = assert(Core.destination("zone_b", "keeper_d"))
			expect(destination.npcId):toBe("keeper_d")
			expect(destination.name):toBe("Fourth")
			local saved = { bind = { zoneId = "zone_b", npcId = "keeper_d" }, hearthReadyAt = 50 }
			local restored = Core.normalize(saved)
			expect(restored.bind):toEqual(saved.bind)
			expect(restored.hearthReadyAt):toBe(50)
		end)

		it("preserves both keeper identities through normalization and hearth", function()
			for _, zoneId in { "zone_a", "zone_b", "zone_c" } do
				local primary = assert(Core.destination(zoneId))
				local secondaryId = if zoneId == "zone_a"
					then "keeper_b"
					elseif zoneId == "zone_b" then "keeper_d"
					else "keeper_f"
				for _, npcId in { primary.npcId, secondaryId } do
					local saved = { bind = { zoneId = zoneId, npcId = npcId }, hearthReadyAt = 17 }
					expect(Core.normalize(saved).bind):toEqual(saved.bind)
					expect(Core.normalize(saved).hearthReadyAt):toBe(17)
					local arrived = assert(Core.hearth(saved, 18, true, false))
					expect(arrived.bind):toEqual(saved.bind)
					expect((Core.bind(saved, zoneId, npcId, 2, true)) ~= nil):toBe(true)
				end
			end
			expect(Core.destination("zone_b", "missing")):toBeNil()
			expect(Core.bind(nil, "zone_b", nil, 1, true)):toBeNil()
			expect(Core.normalize({ bind = { zoneId = "zone_b", npcId = "missing" } }).bind):toBeNil()
		end)

		it("sets an authored keeper, returns once, enforces cooldown and refuses combat", function()
			expect(Core.normalize(nil).bind):toBeNil()
			local bound, bindReason = Core.bind(nil, "zone_a", "keeper_a", 8, true)
			expect(bindReason):toBeNil()
			expect(assert(bound).bind.zoneId):toBe("zone_a")
			expect(Core.bind(bound, "zone_a", "keeper_a", 20, true)):toBeNil()
			expect(Core.bind(bound, "zone_b", "keeper_a", 2, true)):toBeNil()
			local blocked, combatReason = Core.hearth(bound, 100, true, true)
			expect(blocked):toBeNil()
			expect(combatReason):toBe("in_combat")
			local used, useReason = Core.hearth(bound, 100, true, false)
			expect(useReason):toBeNil()
			expect(assert(used).bind):toEqual(assert(bound).bind)
			expect(assert(used).returningTo):toEqual(assert(bound).bind)
			local pending, pendingReason = Core.hearth(used, 101, true, false)
			expect(pending):toBeNil()
			expect(pendingReason):toBe("return_pending")
			local arrived = Core.arrived(used)
			local cooldown, cooldownReason = Core.hearth(arrived, 101, true, false)
			expect(cooldown):toBeNil()
			expect(cooldownReason):toBe("cooldown")
			expect((Core.hearth(arrived, 100 + Core.HEARTH_COOLDOWN_SEC, true, false)) ~= nil):toBe(true)
		end)

		it("preserves one exact pending destination through rejoin and rejects a substituted return", function()
			local bound = assert(Core.bind(nil, "zone_b", "keeper_d", 3, true))
			local used = assert(Core.hearth(bound, 1000, true, false))
			local rejoined = Core.normalize(used)
			expect(rejoined.returningTo):toEqual(bound.bind)
			expect(rejoined.hearthReadyAt):toBe(1600)
			local substituted = table.clone(used)
			substituted.returningTo = { zoneId = "zone_a", npcId = "keeper_a" }
			expect(pcall(Core.normalize, substituted)):toBe(false)
			expect(Core.arrived(rejoined).returningTo):toBeNil()
			expect(Core.arrived(rejoined).hearthReadyAt):toBe(1600)
		end)
	end)
	it("uses supplied destinations, home mappings, reach and cooldown", function()
		local law = Module.hearth({
			cooldownSec = 9,
			bindRange = 2,
			homeZones = { team = "place" },
			destinations = { place = { { npcId = "keeper", name = "Home" } } },
		})
		expect(law.homeZone("team")):toBe("place")
		expect(law.homeZone("other")):toBeNil()
		expect(assert(law.destination("place")).name):toBe("Home")
		expect((law.bind(nil, "place", "keeper", 3, true))):toBeNil()
		local bound = assert(law.bind(nil, "place", "keeper", 2, true))
		local used = assert(law.hearth(bound, 10, true, false))
		expect(used.hearthReadyAt):toBe(19)
		expect((law.hearth(law.arrived(used), 19, true, false)) ~= nil):toBe(true)
	end)
end
