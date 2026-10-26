--!strict

local Scene = require("../../test-scene/threat")
local Threat = require("./table")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local config: Threat.Config = { meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 }

return function(suite: Verify.Harness)
	suite:case("accumulation uses strict melee and ranged takeover boundaries", function(t)
		for _, inMelee in { true, false } do
			local scene = Scene.new(config)
			scene.add("holder", 10, true)
			local before = scene.snapshot()
			scene.add("challenger", if inMelee then 11 else 13, inMelee)
			t:expect(scene.snapshot().targetActorId):toBe("holder")
			scene.add("challenger", 0.01, inMelee)
			t:expect(scene.snapshot().targetActorId):toBe("challenger")
			t:expect(before.threat.challenger):toBeNil()
			t:expect(before.threat.holder):toBe(10)
			t:expect(scene.refreshes()):toBe(1)
		end
	end)
	suite:case("holder additions retain selection and missing holders reselect deterministically", function(t)
		local law = Threat.rules(config)
		local state: Threat.State = { threat = { z = 5, a = 5 }, targetActorId = "missing" }
		local updated, refresh = law.add(state, "b", 5, false)
		t:expect(updated.targetActorId):toBe("a")
		t:expect(refresh):toBe(true)
		local held, heldRefresh = law.add(updated, "a", -5, true)
		t:expect(held.targetActorId):toBe("a")
		t:expect(held.threat.a):toBe(0)
		t:expect(heldRefresh):toBe(false)
		t:expect(Threat.targetFor({ z = 0, a = 0, negative = -1 })):toBe("a")
		t:expect(Threat.targetFor({ negative = -1 })):toBe("")
		t:expect(Threat.targetFor({})):toBe("")
		t:expect(state.threat.b):toBeNil()
	end)
	suite:case("taunt raises above the whole table and repeated taunts accumulate", function(t)
		local scene = Scene.new(config)
		scene.add("holder", 100, true)
		scene.add("ranged", 120, false)
		local before = scene.snapshot()
		scene.taunt("tank")
		t:expect(scene.snapshot().threat.tank):toBe(121)
		t:expect(scene.snapshot().targetActorId):toBe("tank")
		scene.taunt("tank")
		t:expect(scene.snapshot().threat.tank):toBe(122)
		t:expect(before.threat.tank):toBeNil()
		t:expect(scene.refreshes()):toBe(1)
		local negative: Threat.State = { threat = { a = -10 }, targetActorId = "" }
		t:expect(Threat.rules(config).taunt(negative, "b").threat.b):toBe(1)
	end)
	suite:case("pruning removes absent dead forbidden and outside actors in stable order", function(t)
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
		t:expect(result.removed):toEqual({ "dead", "forbidden", "outside", "z" })
		t:expect(result.outsideLeash):toEqual({ "outside" })
		t:expect(result.wasEngaged):toBe(true)
		t:expect(scene.snapshot()):toEqual({ threat = { a = 10 }, targetActorId = "a" })
		t:expect(before.threat.z):toBe(10)
		local retained = scene.snapshot()
		scene.prune({ a = { alive = true, eligible = true, insideLeash = true } })
		t:expect(scene.snapshot() == retained):toBe(true)
		local last = scene.prune({ a = { alive = true, eligible = false, insideLeash = false } })
		t:expect(last.outsideLeash):toEqual({ "a" })
		t:expect(scene.snapshot()):toEqual(Threat.empty())
		t:expect(scene.prune({}).wasEngaged):toBe(false)
	end)
	suite:case("death departure and reset clear references and owners remain isolated without decay", function(t)
		local scene, other = Scene.new(config), Scene.new(config)
		scene.add("holder", 10, true)
		scene.add("z", 5, true)
		scene.add("a", 5, true)
		other.add("holder", 20, true)
		scene.clock.advance(1000)
		t:expect(scene.snapshot().threat.holder):toBe(10)
		scene.remove("holder")
		t:expect(scene.snapshot().targetActorId):toBe("a")
		t:expect(scene.snapshot().threat.holder):toBeNil()
		local before = scene.snapshot()
		scene.reset()
		t:expect(scene.snapshot()):toEqual(Threat.empty())
		t:expect(before.threat.a):toBe(5)
		t:expect(other.snapshot().threat.holder):toBe(20)
	end)
	suite:case("configuration is captured and nonfinite operations fail without mutation", function(t)
		local supplied = table.clone(config)
		local law = Threat.rules(supplied)
		supplied.meleeTakeover = 2
		supplied.tauntLead = 100
		local state: Threat.State = { threat = { holder = 10 }, targetActorId = "holder" }
		local updated = law.add(state, "challenger", 12, true)
		t:expect(updated.targetActorId):toBe("challenger")
		t:expect(law.taunt(state, "tank").threat.tank):toBe(11)
		for _, invalid in { math.huge, -math.huge, (math.huge - math.huge) } do
			t:expect((pcall(law.add, state, "a", invalid, true))):toBe(false)
		end
		for _, invalid in
			{
				{ meleeTakeover = 0, rangedTakeover = 1.3, tauntLead = 1 },
				{ meleeTakeover = 1.1, rangedTakeover = math.huge, tauntLead = 1 },
				{ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 0 },
			}
		do
			t:expect((pcall(Threat.rules, invalid))):toBe(false)
		end
		t:expect((pcall(law.add, state, "", 1, true))):toBe(false)
		t:expect((pcall(law.taunt, state, ""))):toBe(false)
		local huge: Threat.State = { threat = { a = 1e308 }, targetActorId = "a" }
		t:expect((pcall(law.add, huge, "a", 1e308, true))):toBe(false)
		t:expect((pcall(law.taunt, huge, "a"))):toBe(false)
		t:expect(state.threat.a):toBeNil()
		t:expect(state.threat.holder):toBe(10)
	end)
end
