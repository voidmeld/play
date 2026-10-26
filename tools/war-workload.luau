--!strict

local Diminishing = require("../src/core/control/diminishing")
local Queue = require("../src/core/cast/queue")
local Recovery = require("../src/core/progression/recovery")
local Threat = require("../src/core/threat/table")
local Timed = require("../src/core/effects/timed")

type Phase = { name: string, run: () -> () }

local function create(): { Phase }
	local ids: { string } = {}
	local totals: { [string]: number } = {}
	local candidates: { [string]: Threat.Candidate } = {}
	for index = 1, 200 do
		local id = string.format("actor-%03d", index)
		ids[index] = id
		totals[id] = index * 10
		candidates[id] = { alive = true, eligible = true, insideLeash = index % 20 ~= 0 }
	end
	local state: Threat.State = { threat = totals, targetActorId = ids[200] }
	local threat = Threat.rules({ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 })
	local effects: { Timed.Entry } = {}
	for index = 1, 20 do
		effects[index] = { remainingSec = index, totalSec = 20, stacks = 3, tickInSec = 0.5 }
	end
	local dr = Diminishing.rules({
		resetSec = 18,
		multipliers = { 1, 0.5, 0.25, 0 },
		categories = {
			stun = { family = "control", durationCapSec = 6, immunityPrice = 1, immunityMinSec = 0, immunityMaxSec = 6 },
		},
	})
	local drState: Diminishing.State = { stun = { count = 1, windowExpiry = 18 } }
	local recovery = Recovery.recovery({ coordinateLimit = 100000, lowHealthRatio = 0.2, defaultCause = "damage" })
	local point = { x = 100, y = 10, z = 200 }
	local echo = { x = 110, y = 20, z = 180 }
	local checksum = 0
	return {
		{
			name = "threat-select",
			run = function()
				for _ = 1, 200 do
					checksum += #Threat.targetFor(totals)
				end
			end,
		},
		{
			name = "threat-transitions",
			run = function()
				for index, id in ids do
					local nextState = threat.add(state, id, 25, index % 2 == 0)
					if index % 20 == 0 then
						nextState = threat.taunt(nextState, id)
					end
					local pruned, removed = Threat.prune(nextState, candidates)
					checksum += #pruned.targetActorId + #removed.removed
				end
			end,
		},
		{
			name = "effects-advance",
			run = function()
				for _ = 1, 200 do
					for _, effect in effects do
						local nextEffect = Timed.advance(effect, 1 / 30)
						checksum += nextEffect.remainingSec
					end
				end
			end,
		},
		{
			name = "cast-windows",
			run = function()
				for _ = 1, 200 do
					local windows = Queue.windows(10, 1.5, 2, 3)
					local gcd, cast, channel = Queue.remaining(windows, 10 + 1 / 30)
					checksum += gcd + cast + channel
				end
			end,
		},
		{
			name = "control-apply",
			run = function()
				for _ = 1, 200 do
					checksum += dr.apply(drState, "stun", 4, 10).grantedSec
				end
			end,
		},
		{
			name = "recovery-numeric",
			run = function()
				for _ = 1, 200 do
					checksum += recovery.echoDistance(point, echo)
					if recovery.lowHealth(10, 100) then
						checksum += 1
					end
				end
				assert(checksum > 0)
			end,
		},
	}
end

return create
