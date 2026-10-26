--!strict
local Module = require("./schedule")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local settings: Module.Config = {
	catalog = { schemaVersion = 1, events = {} },
	schemaVersion = 1,
	maxRewardMultiplier = 3,
	multiplierKeys = { "xpMultiplier", "coinMultiplier" },
	bonusKeys = { "recognition" },
	contentKeys = { "questIds", "npcIds", "assetBundleIds", "journeyIds" },
	killSwitch = "events",
	enabledFlag = "enabled",
}
local LiveEvents = Module.schedule(settings)
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

	describe("LiveEvents content resolution", function()
		it("merges unique hooks in event priority order without sharing content lists", function()
			local lower = { "shared", "lower", "", "lower" }
			local higher = { "higher", "shared", "", "higher" }
			local catalog: Module.Catalog = {
				schemaVersion = 1,
				events = {
					{
						id = "lower",
						title = "Lower",
						realm = "realm-a",
						priority = 1,
						schedule = { startUnix = 1, endUnix = 10 },
						contentScale = { questIds = lower, journeyIds = lower },
					},
					{
						id = "higher",
						title = "Higher",
						realm = "realm-a",
						priority = 2,
						schedule = { startUnix = 1, endUnix = 10 },
						contentScale = {
							questIds = higher,
							npcIds = higher,
							assetBundleIds = higher,
							journeyIds = higher,
						},
					},
				},
			}
			local effect = LiveEvents.resolve(catalog, { nowUnix = 5 }).effect
			expect(effect.contentScale.questIds):toEqual({ "higher", "shared", "lower" })
			expect(effect.contentScale.journeyIds):toEqual(effect.contentScale.questIds)
			expect(effect.contentScale.npcIds):toEqual({ "higher", "shared" })
			expect(effect.contentScale.assetBundleIds):toEqual(effect.contentScale.npcIds)
			effect.contentScale.questIds[1] = "changed"
			effect.contentScale.npcIds[1] = "changed"
			effect.contentScale.assetBundleIds[1] = "changed"
			effect.contentScale.journeyIds[1] = "changed"
			expect(lower):toEqual({ "shared", "lower", "", "lower" })
			expect(higher):toEqual({ "higher", "shared", "", "higher" })
			expect(LiveEvents.resolve(catalog, { nowUnix = 5 }).effect.contentScale.questIds):toEqual({
				"higher",
				"shared",
				"lower",
			})
		end)
	end)
	it("composes configured rewards, flags and content with capped multipliers and additive bonuses", function()
		local config = table.clone(settings)
		config.maxRewardMultiplier = 2
		config.multiplierKeys = { "power" }
		config.bonusKeys = { "marks" }
		config.contentKeys = { "maps" }
		config.killSwitch = "stop"
		config.enabledFlag = "go"
		local first: Module.Event = {
			id = "first",
			title = "First",
			realm = "realm",
			priority = 2,
			schedule = { startUnix = 1, endUnix = 10 },
			contentScale = { maps = { "a", "shared" } },
			rewards = { power = 9, marks = 2.9 },
			flags = { owner = "first" },
		}
		local second: Module.Event = {
			id = "second",
			title = "Second",
			realm = "realm",
			priority = 1,
			schedule = { startUnix = 1, endUnix = 10 },
			contentScale = { maps = { "shared", "b" } },
			rewards = { power = 2, marks = -0.1 },
			flags = { owner = "second" },
		}
		config.catalog = { schemaVersion = 1, events = { second, first } }
		local law = Module.schedule(config)
		local result = law.resolve(nil, { nowUnix = 5 })
		expect(result.events[1].id):toBe("first")
		expect(result.effect.rewards):toEqual({ power = 2, marks = 1 })
		expect(result.effect.flags.owner):toBe("second")
		expect(result.effect.contentScale.maps):toEqual({ "a", "shared", "b" })
		expect(#law.resolve(nil, { nowUnix = 10 }).events):toBe(0)
		expect(#law.resolve(nil, { nowUnix = 0 }).events):toBe(0)
		expect(#law.resolve(nil, { nowUnix = 1 }).events):toBe(2)
		expect(#law.resolve(nil, { nowUnix = 5, liveConfig = { flags = {}, killSwitches = { stop = true } } }).events):toBe(
			0
		)
		expect(#law.resolve(nil, { nowUnix = 5, liveConfig = { flags = { go = false }, killSwitches = {} } }).events):toBe(
			0
		)
		expect(#law.resolve(nil, { nowUnix = 5, liveConfig = { flags = { go = true }, killSwitches = {} } }).events):toBe(
			2
		)
	end)
	it("uses stable bucket rollout with salt and player identity before shard identity", function()
		local e: Module.Event = {
			id = "bucket",
			title = "Bucket",
			realm = "realm",
			schedule = { startUnix = 1, endUnix = 10 },
			contentScale = { questIds = { "q" } },
			rollout = { mode = "bucket", percent = 25, salt = "salt" },
		}
		local c = table.clone(settings)
		c.catalog = { schemaVersion = 1, events = { e } }
		local law = Module.schedule(c)
		expect(#law.resolve(nil, { nowUnix = 5 }).events):toBe(0)
		for id = 1, 100 do
			local one = law.resolve(nil, { nowUnix = 5, playerId = id, shardId = "a" })
			local two = law.resolve(nil, { nowUnix = 5, playerId = id, shardId = "b" })
			expect(#one.events):toBe(#two.events)
			expect(#one.events):toBe(if law.stableBucket("salt:" .. id) < 25 then 1 else 0)
		end
		assert(e.rollout).percent = 100
		expect(#law.resolve(nil, { nowUnix = 5 }).events):toBe(1)
		assert(e.rollout).percent = 0
		expect(#law.resolve(nil, { nowUnix = 5, playerId = 1 }).events):toBe(0)
	end)
	it("breaks priority ties by start time then identity", function()
		local function e(id: string, start: number): Module.Event
			return {
				id = id,
				title = id,
				realm = "r",
				schedule = { startUnix = start, endUnix = 20 },
				contentScale = {
					questIds = { id },
				},
			}
		end
		local c: Module.Catalog = { schemaVersion = 1, events = { e("b", 1), e("a", 1), e("early", 0) } }
		local result = LiveEvents.resolve(c, { nowUnix = 5 })
		expect(result.events[1].id):toBe("early")
		expect(result.events[2].id):toBe("a")
		expect(result.events[3].id):toBe("b")
	end)
end
