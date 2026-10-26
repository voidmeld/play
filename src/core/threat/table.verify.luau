--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Scene = require("../../test-scene/threat")
local Threat = require("./table")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local config: Threat.Config = { meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 }

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("table", function()
		it("accumulation uses strict melee and ranged takeover boundaries", function()
			for _, inMelee in { true, false } do
				local scene = Scene.new(config)
				scene.add("holder", 10, true)
				local before = scene.snapshot()
				scene.add("challenger", if inMelee then 11 else 13, inMelee)
				expect(scene.snapshot().targetActorId):toBe("holder")
				scene.add("challenger", 0.01, inMelee)
				expect(scene.snapshot().targetActorId):toBe("challenger")
				expect(before.threat.challenger):toBeNil()
				expect(before.threat.holder):toBe(10)
				expect(scene.refreshes()):toBe(1)
			end
		end)
		it("holder additions retain selection and missing holders reselect deterministically", function()
			local law = Threat.rules(config)
			local state: Threat.State = { threat = { z = 5, a = 5 }, targetActorId = "missing" }
			local updated, refresh = law.add(state, "b", 5, false)
			expect(updated.targetActorId):toBe("a")
			expect(refresh):toBe(true)
			local held, heldRefresh = law.add(updated, "a", -5, true)
			expect(held.targetActorId):toBe("a")
			expect(held.threat.a):toBe(0)
			expect(heldRefresh):toBe(false)
			expect(Threat.targetFor({ z = 0, a = 0, negative = -1 })):toBe("a")
			expect(Threat.targetFor({ negative = -1 })):toBe("")
			expect(Threat.targetFor({})):toBe("")
			expect(state.threat.b):toBeNil()
		end)
		it("taunt raises above the whole table and repeated taunts accumulate", function()
			local scene = Scene.new(config)
			scene.add("holder", 100, true)
			scene.add("ranged", 120, false)
			local before = scene.snapshot()
			scene.taunt("tank")
			expect(scene.snapshot().threat.tank):toBe(121)
			expect(scene.snapshot().targetActorId):toBe("tank")
			scene.taunt("tank")
			expect(scene.snapshot().threat.tank):toBe(122)
			expect(before.threat.tank):toBeNil()
			expect(scene.refreshes()):toBe(1)
			local negative: Threat.State = { threat = { a = -10 }, targetActorId = "" }
			expect(Threat.rules(config).taunt(negative, "b").threat.b):toBe(1)
		end)
		it("pruning removes absent dead forbidden and outside actors in stable order", function()
			local scene = Scene.new(config)
			for _, id in { "z", "dead", "forbidden", "outside", "a" } do
				scene.add(id, 10, true)
			end
			local before = scene.snapshot()
			local result = scene.prune({
				a = { alive = true, eligible = true, insideLeash = true },
				dead = { alive = false, eligible = true, insideLeash = false },
				forbidden = { alive = true, eligible = false, insideLeash = true },
				outside = { alive = true, eligible = true, insideLeash = false },
			})
			expect(result.removed):toEqual({ "dead", "forbidden", "outside", "z" })
			expect(result.outsideLeash):toEqual({ "outside" })
			expect(result.wasEngaged):toBe(true)
			expect(scene.snapshot()):toEqual({ threat = { a = 10 }, targetActorId = "a" })
			expect(before.threat.z):toBe(10)
			local retained = scene.snapshot()
			scene.prune({ a = { alive = true, eligible = true, insideLeash = true } })
			expect(scene.snapshot() == retained):toBe(true)
			local last = scene.prune({ a = { alive = true, eligible = false, insideLeash = false } })
			expect(last.outsideLeash):toEqual({ "a" })
			expect(scene.snapshot()):toEqual(Threat.empty())
			expect(scene.prune({}).wasEngaged):toBe(false)
		end)
		it("death departure and reset clear references and owners remain isolated without decay", function()
			local scene, other = Scene.new(config), Scene.new(config)
			scene.add("holder", 10, true)
			scene.add("z", 5, true)
			scene.add("a", 5, true)
			other.add("holder", 20, true)
			scene.clock.advance(1000)
			expect(scene.snapshot().threat.holder):toBe(10)
			scene.remove("holder")
			expect(scene.snapshot().targetActorId):toBe("a")
			expect(scene.snapshot().threat.holder):toBeNil()
			local before = scene.snapshot()
			scene.reset()
			expect(scene.snapshot()):toEqual(Threat.empty())
			expect(before.threat.a):toBe(5)
			expect(other.snapshot().threat.holder):toBe(20)
		end)
		it("configuration is captured and nonfinite operations fail without mutation", function()
			local supplied = table.clone(config)
			local law = Threat.rules(supplied)
			supplied.meleeTakeover = 2
			supplied.tauntLead = 100
			local state: Threat.State = { threat = { holder = 10 }, targetActorId = "holder" }
			local updated = law.add(state, "challenger", 12, true)
			expect(updated.targetActorId):toBe("challenger")
			expect(law.taunt(state, "tank").threat.tank):toBe(11)
			for _, invalid in { math.huge, -math.huge, (math.huge - math.huge) } do
				expect((pcall(law.add, state, "a", invalid, true))):toBe(false)
			end
			for _, invalid in
				{
					{ meleeTakeover = 0, rangedTakeover = 1.3, tauntLead = 1 },
					{ meleeTakeover = 1.1, rangedTakeover = math.huge, tauntLead = 1 },
					{ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 0 },
				}
			do
				expect((pcall(Threat.rules, invalid))):toBe(false)
			end
			expect((pcall(law.add, state, "", 1, true))):toBe(false)
			expect((pcall(law.taunt, state, ""))):toBe(false)
			local huge: Threat.State = { threat = { a = 1e308 }, targetActorId = "a" }
			expect((pcall(law.add, huge, "a", 1e308, true))):toBe(false)
			expect((pcall(law.taunt, huge, "a"))):toBe(false)
			expect(state.threat.a):toBeNil()
			expect(state.threat.holder):toBe(10)
		end)
	end)
end
