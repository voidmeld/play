--!strict
local Module = require("./recovery")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local Core = Module.recovery({ coordinateLimit = 1000000, lowHealthRatio = 0.25, defaultCause = "defeat" })
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

	local corpse = { x = 22, y = 4, z = 30 }
	local anchor = { x = 2, y = 5, z = 3 }

	describe("DeathRecoveryCore", function()
		it("carries the recovery echo without accepting malformed or non-finite points", function()
			expect(Core.decodeEcho(Core.encodeEcho(corpse))):toEqual(corpse)
			expect(Core.decodeEcho("nan,0,0")):toBe(nil)
			expect(Core.decodeEcho("1,2,3,4")):toBe(nil)
			expect(Core.decodeEcho({ x = 1, y = 2, z = 3 })):toBe(nil)
			expect(pcall(Core.encodeEcho, { x = math.huge, y = 0, z = 0 })):toBe(false)
		end)
		it("warns before defeat and keeps the echo distance tied to the place the player fell", function()
			expect(Core.lowHealth(25, 100)):toBe(true)
			expect(Core.lowHealth(26, 100)):toBe(false)
			expect(Core.lowHealth(0, 100)):toBe(false)
			expect(Core.lowHealth(1, 0)):toBe(false)
			expect(Core.echoDistance({ x = 0, y = 0, z = 0 }, { x = 3, y = 0, z = 4 })):toBe(5)
		end)
		it("records one death, releases, and resolves at a safe anchor with the declared time cost only", function()
			local death = assert(Core.die(nil, "wolf", "lightwood", corpse, anchor, 1.5))
			expect(death.generation):toBe(1)
			expect(death.cause):toBe("wolf")
			expect(death.corpse):toEqual(corpse)
			expect(death.cost):toEqual({ items = 0, currency = 0, experience = 0, durability = 0, delaySec = 1.5 })
			expect(Core.die(death, "duplicate", "lightwood", corpse, anchor, 1.5)):toBe(death)
			local released = assert(Core.release(death, death.generation))
			expect(released.phase):toBe("released")
			local recovered, point = Core.recover(released, death.generation)
			local resolved = assert(recovered)
			expect(resolved.phase):toBe("resolved")
			expect(point):toEqual(anchor)
			local duplicate = Core.recover(resolved, death.generation)
			expect(duplicate):toBeNil()
		end)
		it("anchors trusted positions while retaining the typed travel value and cloned extra fields", function()
			local death = assert(Core.die(nil, "fall", "lightwood", corpse, anchor, 2))
			local travel = { bind = { zoneId = "dewmere", npcId = "hearth" }, hearthReadyAt = 42 }
			local current: Module.Position<typeof(travel)> & { extra: string } =
				{ x = 9, y = 8, z = 7, yaw = 3, saved = false, travel = travel, extra = "retained" }
			local nextPosition = Core.anchorPosition(current, death)
			local destination: string = assert(nextPosition.travel).bind.zoneId
			expect(destination):toBe("dewmere")
			expect(nextPosition.travel):toBe(travel)
			expect(nextPosition):toEqual({
				x = 2,
				y = 5,
				z = 3,
				yaw = 0,
				saved = true,
				travel = travel,
				extra = "retained",
				recoveryZoneId = "lightwood",
			})
			expect(current.x):toBe(9)
			expect(current.saved):toBe(false)
			expect(Core.anchoredLastPosition(current, death)):toEqual(nextPosition)
			local malformedPositions: { unknown } = { false, 0, "not-a-position" }
			for _, malformed in malformedPositions do
				expect(Core.anchoredLastPosition(malformed, death)):toEqual({
					x = 2,
					y = 5,
					z = 3,
					yaw = 0,
					saved = true,
					recoveryZoneId = "lightwood",
				})
			end
			expect(Core.anchoredLastPosition(nil, death)):toEqual({
				x = 2,
				y = 5,
				z = 3,
				yaw = 0,
				saved = true,
				recoveryZoneId = "lightwood",
			})
		end)

		it("refuses stale release generations", function()
			local death = assert(Core.die(nil, "fall", "lightwood", corpse, anchor, 2))
			expect(Core.release(death, 2)):toBeNil()
			local released = assert(Core.release(death, 1))
			local stale = Core.recover(released, 2)
			expect(stale):toBeNil()
		end)

		it("starts another generation only after one recovery resolves", function()
			local dead = assert(Core.die(nil, "enemy", "dewmere", corpse, anchor, 1))
			local released = assert(Core.release(dead, 1))
			local recovered, point = Core.recover(released, 1)
			local resolved = assert(recovered)
			expect(resolved.phase):toBe("resolved")
			expect(point):toEqual(anchor)
			local nextDeath = assert(Core.die(resolved, "enemy", "dewmere", corpse, anchor, 1))
			expect(nextDeath.generation):toBe(2)
		end)
	end)
	it("uses supplied coordinate bounds, warning ratio and fallback cause", function()
		local law = Module.recovery({ coordinateLimit = 10, lowHealthRatio = 0.5, defaultCause = "unknown" })
		expect(law.lowHealth(50, 100)):toBe(true)
		expect(law.lowHealth(51, 100)):toBe(false)
		expect(law.decodeEcho("10,0,0")):toBeNil()
		local death = assert(law.die(nil, "", "zone", { x = 0, y = 0, z = 0 }, { x = 1, y = 0, z = 0 }, -1))
		expect(death.cause):toBe("unknown")
		expect(death.cost.delaySec):toBe(0)
	end)
end
