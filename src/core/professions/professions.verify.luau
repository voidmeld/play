--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Crafting = require("./crafting")
local Fishing = require("./fishing")
local Gathering = require("./gathering")
local Harvest = require("./harvest")
local Host = require("../../roblox/professions")
local Session = require("./session")
local Skills = require("./skills")
local Stacks = require("../inventory/stacks")
local Types = require("./types")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local thresholds: Types.Thresholds = { orange = 1, yellow = 3, green = 5, grey = 7 }
local recipe: Types.Recipe = {
	id = "recipe",
	profession = "primary",
	slug = "recipe",
	name = "Craft",
	requiredSkill = 1,
	thresholds = thresholds,
	reagents = { { itemId = "ore", quantity = 2 } },
	output = { itemId = "bar", quantity = 1 },
	source = "trainer",
	rung = "pve",
	station = "bench",
	trainerCost = 2,
	item = { kind = "material", name = "Bar", lore = "", rarity = "normal", levelReq = 1, stack = 10 },
}
local recipes = {
	all = { recipe },
	get = function(id: unknown): Types.Recipe?
		return if id == recipe.id then recipe else nil
	end,
	forProfession = function(id: string): { Types.Recipe }
		return if id == "primary" then { recipe } else {}
	end,
	forRecipeItem = function(_id: unknown): Types.Recipe?
		return nil
	end,
	isGear = function(_recipe: Types.Recipe): boolean
		return false
	end,
	rollQuality = function(_color: string?, _roll: number?): string
		return "normal"
	end,
	qualityItemId = function(id: string, _quality: string): string
		return id
	end,
}
local core = Skills.create({
	catalogue = {
		{ id = "primary", name = "Primary", kind = "primary_craft", primary = true, order = 1 },
		{ id = "other", name = "Other", kind = "gathering", primary = true, order = 2 },
		{ id = "fish", name = "Fish", kind = "secondary", primary = false, order = 3 },
	},
	skillCap = 8,
	primarySlots = 1,
	startSkill = 1,
	skillUpChance = { orange = 1, yellow = 0.5, green = 0.1, grey = 0 },
	recipes = recipes,
	questInputs = function(_raw: unknown): { [string]: boolean }?
		return nil
	end,
})
local craft = Crafting.create({ core = core, recipes = recipes, maxStack = 10 })
local harvest = Harvest.create({ core = core, skinningId = "other" })
local node: Types.NodeKind = {
	id = "node",
	profession = "primary",
	name = "Node",
	itemId = "ore",
	requiredSkill = 1,
	thresholds = thresholds,
	minYield = 2,
	maxYield = 2,
	gatherSec = 1,
	respawnSec = 10,
	extras = { { itemId = "extra", chance = 0.5, quantity = 1 } },
}
local fish = Fishing.create({
	core = core,
	professionId = "fish",
	waitMin = 2,
	waitMax = 4,
	biteWindow = 1,
	fishTable = function(_zone: string): { Types.FishRow }
		return { { itemId = "catch", weight = 1, requiredSkill = 1, thresholds = thresholds } }
	end,
	junk = { { itemId = "junk", weight = 1, requiredSkill = 0, thresholds = thresholds } },
})
local session = Session.create({
	moveTolerance = 3,
	blocked = function(_kind, sample): string?
		return if sample.arrivalProtected then "protected" else nil
	end,
})
local function learned(): Skills.State
	return { skills = { primary = 1, fish = 1 }, recipes = { recipe = true } }
end
type Profile = {
	inventory: { [string]: number },
	gold: number,
	faction: "team",
	bagItem: string,
	professions: Skills.State,
	retained: string,
}

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("profession transactions", function()
		it("admits configured skills and releases recipes without changing the prior snapshot", function()
			local first = assert(core.learn(core.default(), "primary"))
			local refused, reason = core.learn(first, "other")
			expect(refused):toBeNil()
			expect(reason):toBe("primary_slots_full")
			local second = assert(core.learnRecipe(first, "recipe", "trainer"))
			local removed = assert(core.unlearn(second, "primary"))
			expect(removed.recipes.recipe):toBeNil()
			expect(second.recipes.recipe):toBe(true)
			expect(first.recipes.recipe):toBeNil()
			local normalized =
				core.normalize({ skills = { primary = 1, other = 2, fish = math.huge }, recipes = { recipe = true } })
			expect(normalized):toEqual(second)
			expect(core.normalize(false)):toEqual(core.default())
		end)
		it("preserves reagents on refusal and frees a consumed slot before admitting output", function()
			local before = { ore = 2 }
			local unavailable = craft.craft(learned(), "recipe", before, {}, 0, 0, 1)
			expect(unavailable.reason):toBe("needs_bench")
			expect(unavailable.inventory):toBe(before)
			local full = craft.craft(learned(), "recipe", { ore = 2, bar = 10 }, { bench = true }, 0, 0, 2)
			expect(full.reason):toBe("inventory_full")
			local done = craft.craft(learned(), "recipe", before, { bench = true }, 0, 0, 1)
			expect(done.ok):toBe(true)
			expect(done.inventory):toEqual({ bar = 1 })
			expect(before):toEqual({ ore = 2 })
			expect(done.skill):toBe(2)
		end)
		it("gates harvesting and uses the supplied yield and advancement rolls", function()
			expect(harvest.harvestNode(core.default(), node, function()
				return 0
			end).reason):toBe("profession_not_known")
			local before = learned()
			local result = harvest.harvestNode(before, node, function()
				return 0
			end)
			expect(result.yields):toEqual({ { itemId = "ore", quantity = 2 }, { itemId = "extra", quantity = 1 } })
			expect(result.skill):toBe(2)
			expect(before.skills.primary):toBe(1)
			local capped = learned()
			capped.skills.primary = 8
			expect((select(2, core.rollSkillUp(capped, "primary", thresholds, 0)))):toBe(false)
		end)
		it("interrupts work on damage, movement and host policy before completion", function()
			local sample: Session.Sample = { now = 0, x = 0, z = 0, health = 10, alive = true, inCombat = false }
			local active = assert(session.begin("gather", "node", 1, sample))
			local nextSample = table.clone(sample)
			nextSample.now, nextSample.health = 2, 9
			expect(select(2, session.check(active, nextSample))):toBe("damaged")
			nextSample.health, nextSample.x = 10, 4
			expect(select(2, session.check(active, nextSample))):toBe("moved")
			nextSample.x, nextSample.arrivalProtected = 0, true
			expect(select(2, session.check(active, nextSample))):toBe("protected")
			nextSample.arrivalProtected = false
			expect((session.check(active, nextSample))):toBe("complete")
		end)
		it("retains the claimed amount on replay and refuses clock regression and missing scaling policy", function()
			local kernel = Gathering.create({
				realms = { team = true },
				minYieldMultiplier = 1,
				maxYieldMultiplier = 4,
				resolveYield = function(row, realm, multiplier): number?
					if row.spaceKind == "pve" then
						return if realm == nil and multiplier == nil then row.baseYield else nil
					end
					return if realm == "team" and type(multiplier) == "number"
						then math.floor(row.baseYield * multiplier + 0.5)
						else nil
				end,
			})
			local row: Gathering.Node = {
				id = "node",
				materialId = "ore",
				spaceKind = "contested",
				gatherDurationSec = 1,
				respawnPeriodSec = 10,
				baseYield = 2,
			}
			local before = kernel.emptyState()
			local started = assert(kernel.step(before, row, { kind = "start" }, 1))
			expect(kernel.step(started.state, row, { kind = "complete", eventId = "claim" }, 2)):toBeNil()
			local done = assert(
				kernel.step(
					started.state,
					row,
					{ kind = "complete", eventId = "claim", gatheringRealmId = "team", populationMultiplier = 2 },
					2
				)
			)
			local replay = assert(
				kernel.step(
					done.state,
					row,
					{ kind = "complete", eventId = "claim", gatheringRealmId = "team", populationMultiplier = 1 },
					12
				)
			)
			expect(replay.replayed):toBe(true)
			expect(replay.yieldAmount):toBe(4)
			expect(before.claims.claim):toBeNil()
			expect(kernel.step(done.state, row, { kind = "start" }, 1)):toBeNil()
		end)
		it("admits a hook only within the bite window and gives junk no advancement", function()
			local line = assert(fish.cast(fish.idle(), learned(), 0, 0))
			expect(select(2, fish.hook(line, 1))):toBe("too_early")
			expect((fish.hook(line, 2))):toBe(true)
			expect(select(2, fish.hook(line, 3))):toBe("too_slow")
			local junk = fish.reel(learned(), "zone", function()
				return 0.9
			end)
			expect(junk.itemId):toBe("junk")
			expect(junk.skillUp):toBe(false)
			local caught = fish.reel(learned(), "zone", function()
				return 0
			end)
			expect(caught.itemId):toBe("catch")
			expect(caught.skill):toBe(2)
		end)
		it("keeps a failed craft save pending and settles it before another public action", function()
			local profile: Profile = {
				retained = "kept",
				inventory = { ore = 4, rod = 1 },
				gold = 10,
				faction = "team",
				bagItem = "",
				professions = learned(),
			}
			local at, serial, saves, durable = 0, 0, 0, false
			local messages: { Host.Message<number> } = {}
			local function save(_context: number): boolean
				saves += 1
				return durable
			end
			local policy: Host.Policy<Profile, number> = {
				core = core,
				crafting = craft,
				fishing = fish,
				gather = harvest,
				session = session,
				nodes = {
					available = function(held, id, now, period)
						return held[id] == nil or math.floor(now / period) > held[id]
					end,
					slotAt = function(now, period)
						return math.floor(now / period)
					end,
					kind = function(id)
						return if id == "node" then node else nil
					end,
					skinFor = function(_id)
						return nil
					end,
					GATHER_RANGE_STUDS = 4,
					CORPSE_RANGE_STUDS = 4,
					CRAFT_SEC = 1,
				},
				recipes = recipes,
				trainers = {
					LEARN_COST = 2,
					group = function(_id)
						return nil
					end,
					groupOfProfession = function(_id)
						return nil
					end,
					supplyPrice = function(_group, _id)
						return nil
					end,
				},
				inventory = Stacks.stacks({ maxStack = 10, baseCapacity = 5, permanentItems = {}, bagBonus = {} }),
				maxStack = 10,
				maxIdLength = 80,
				vendorWindow = 10,
				repairGroup = "repair",
				fishingTool = "rod",
				fishingId = "fish",
				skinningId = "other",
				itemName = function(id)
					return id
				end,
				recipeAllowed = function(_profile, _recipe)
					return true
				end,
				recordProgress = function(_profile, _kind, _receipt, _color)
					return 0
				end,
				progress = function(_profile)
					return 0
				end,
				repairQuote = function(_profile)
					return 0
				end,
				repair = function(current, _price)
					return current, nil
				end,
				earnQuestInputs = function(state, bag, _counts)
					return state, bag, false
				end,
			}
			local deps: Host.Deps<number, number, Profile, number> = {
				profiles = {
					read = function(_context: number): Profile?
						return profile
					end,
					updateProfile = function(_context: number, change: (Profile) -> Profile)
						profile = change(profile)
					end,
					removeGold = function(_context: number, amount: number)
						profile.gold -= amount
						return true
					end,
					addGold = function(_context: number, amount: number)
						profile.gold += amount
					end,
					saveProfile = save,
				},
				context = function(_player: number)
					return 1
				end,
				zoneId = "zone",
				clock = function()
					return at
				end,
				rng = function()
					return 0
				end,
				world = {
					node = function(_id)
						return { kindId = "node", x = 0, z = 0 }
					end,
					sample = function(_player)
						return { now = at, x = 0, z = 0, health = 10, alive = true, inCombat = false }
					end,
					stations = function(_player)
						return { bench = true }
					end,
					trainerGroup = function(_player)
						return nil
					end,
					nearWater = function(_player)
						return true
					end,
					corpse = function(_player)
						return nil
					end,
				},
				send = function(_player: number, message: Host.Message<number>)
					table.insert(messages, message)
				end,
				eventId = function()
					serial += 1
					return tostring(serial)
				end,
				commit = function(
					context: number,
					_receipt: string,
					effect: (Profile) -> (Profile?, string?)
				): Host.CommitResult
					local updated, reason = effect(profile)
					if updated == nil then
						return { ok = false, outcome = "rejected", reason = reason }
					end
					profile = updated
					return if save(context)
						then { ok = true, outcome = "committed" }
						else { ok = false, outcome = "not_durable", reason = "failed" }
				end,
			}
			local host = Host.new(deps, policy)
			host.handle(1, "craft", "recipe", nil)
			at = 1
			host.step()
			expect(profile.inventory.ore):toBe(2)
			expect(profile.inventory.bar):toBe(1)
			host.handle(1, "craft", "recipe", nil)
			at = 2
			host.step()
			expect(profile.inventory.bar):toBe(1)
			durable = true
			host.handle(1, "craft", "recipe", nil)
			at = 3
			host.step()
			expect(profile.inventory.bar):toBe(2)
			expect(profile.retained):toBe("kept")
			expect(saves):toBe(4)
			host.handle(1, "cast", nil, nil)
			at = 5
			host.step()
			host.handle(1, "hook", nil, nil)
			expect(profile.inventory.catch):toBe(1)
			host.handle(1, "gather", "node", nil)
			at = 6
			host.step()
			expect(profile.inventory.ore):toBe(2)
			expect(host.harvestedSlots().node):toBe(0)
			host.forget(1)
			expect(#messages > 0):toBe(true)
		end)
	end)
end
