--!strict

local ThreatScene = require("./fixtures/threat")

local scene = ThreatScene.new({ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 })
scene.add("guard", 100, true)
scene.add("ranger", 120, false)
assert(scene.snapshot().targetActorId == "guard")
scene.add("ranger", 11, false)
assert(scene.snapshot().targetActorId == "ranger")
scene.taunt("guard")
assert(scene.snapshot().targetActorId == "guard")
local pruned = scene.prune({ guard = { alive = false, eligible = true, insideLeash = true } })
assert(#pruned.removed == 2)
assert(scene.snapshot().targetActorId == "")
scene.clock.advance(1)
assert(scene.clock.clock() == 1)
print("Threat: takeover, taunt and host pruning passed at t=1")
