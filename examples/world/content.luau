--!strict

local Books = require("../../src/core/market/book")
local Equipment = require("../../src/core/inventory/equipment")
local Journal = require("../../src/core/quest/journal")
local Levels = require("../../src/core/progression/levels")
local Loot = require("../../src/core/loot/roll")
local Objectives = require("../../src/core/quest/objectives")
local Policy = require("../../src/core/identity/policy")
local Recipes = require("../../src/core/craft/recipes")
local Roster = require("../../src/core/identity/roster")
local Stacks = require("../../src/core/inventory/stacks")
local Trade = require("../../src/core/trade/exchange")

local function name(value: unknown): (boolean, string?, string?)
	if type(value) ~= "string" or #value < 2 or #value > 32 or string.match(value, "^%a[%w]+$") == nil then
		return false, nil, "name_invalid"
	end
	return true, value, nil
end

local policy: Policy.Policy = {
	validateName = name,
	registryKey = function(value: unknown): (string?, string?)
		local ok, text = name(value)
		return if ok then string.lower(assert(text)) else nil, nil
	end,
	validRegistryKey = function(value: unknown): boolean
		return type(value) == "string" and string.match(value, "^%l[%w]+$") ~= nil
	end,
	validDestination = function(value: unknown): boolean
		return value == "harbor:entry"
	end,
	profilePartitionKey = function(first: unknown, second: unknown): string
		return tostring(first) .. ":" .. tostring(second)
	end,
	realms = { harbor = true },
	peoples = { traveler = true },
	accountLimit = 1,
	realmLimit = 1,
	minLevel = 1,
	maxLevel = 3,
}

local stacks = Stacks.stacks({ maxStack = 99, baseCapacity = 8, permanentItems = {}, bagBonus = {} })
local equipment = Equipment.equipment({
	inventory = stacks,
	maxStack = 99,
	decide = function(def, level, _class, _slots, _context): Equipment.Decision
		if level < def.levelReq or def.slot == nil then
			return { equip = false, slot = nil, reason = "level_required" }
		end
		return { equip = true, slot = def.slot, reason = nil }
	end,
	resolveSlot = function(slot, _slots)
		return if slot == "hand" then slot else nil
	end,
	equipDenial = function(def, level, _class, _context)
		return if level < def.levelReq then "level_required" else nil
	end,
})
local function item(id: string): Equipment.ItemDef?
	return if id == "training_sword" then { slot = "hand", levelReq = 1 } else nil
end

local objectives = Objectives.catalog({
	order = { "defeat", "collect" },
	kinds = {
		defeat = { event = "enemy_defeated", required = { "enemyId" } },
		collect = { event = "item_collected", required = { "itemId" } },
	},
})
local quest: Objectives.Quest = {
	id = "Harbor Supplies",
	objectives = {
		{ id = "defeat", kind = "defeat", targets = { enemyId = "Warden" } },
		{ id = "collect", kind = "collect", targets = { itemId = "copper_ore" } },
	},
}
local journal = Journal.journal({
	version = 1,
	maxIdLength = 64,
	maxCharacterIdLength = 64,
	maxEventIdLength = 128,
	maxEvents = 64,
	maxQuests = 2,
	maxCounts = 2,
	maxStep = 2,
	maxCount = 1,
	eventPrefix = "reward:",
	statuses = { offered = true, active = true, completed = true },
	claimableStatuses = { active = true },
	receiptStatus = "completed",
	eventIdAllowed = function(_id)
		return true
	end,
})
local levels = Levels.levels({
	curveId = "fixture",
	maxLevel = 3,
	curve = {
		id = "fixture",
		maxLevel = 3,
		rows = {
			{ level = 1, totalXp = 0 },
			{ level = 2, totalXp = 100 },
			{ level = 3, totalXp = 300 },
		},
	},
})
local exchange = Trade.exchange({
	maxItems = 8,
	maxCount = 99,
	maxCoin = 100000,
	maxUserId = 9007199254740991,
	maxRevision = 10000,
	idLimit = 64,
})

local recipes =
	Recipes.catalog({ sources = { carried = true }, rungs = { basic = { carried = { min = 1, max = 1 } } } })
local recipe = assert(recipes.projectRecipe({
	id = "shield",
	rung = "basic",
	outputItemId = "shield",
	inputs = { { materialId = "copper_ore", source = "carried", quantity = 1 } },
}))
local market = Books.book({
	listingTtlSec = 3600,
	minFeeBps = 500,
	maxFeeBps = 500,
	defaultFeeBps = 500,
	maxListings = 32,
	maxReceipts = 128,
	operationRetentionSec = 86400,
	actorWindowSec = 3600,
	maxReceiptsPerOwner = 32,
	maxOperations = 512,
	maxOperationsPerActor = 64,
	maxListingsPerSeller = 8,
	maxCount = 99,
	maxPrice = 1000,
	maxId = 128,
	maxTime = 1000000000000,
	maxCoin = 100000,
	categoryPrefix = "category.",
	maxSearch = 16,
	realms = { Harbor = true },
})

return table.freeze({
	roster = Roster.create(policy),
	stacks = stacks,
	equipment = equipment,
	item = item,
	objectives = objectives,
	quest = quest,
	journal = journal,
	levels = levels,
	exchange = exchange,
	recipe = recipe,
	market = market,
	loot = Loot.roll({ receiptPrefix = "loot:" }),
	lootTables = {
		{
			id = "Warden Supplies",
			mobIds = { "Warden" },
			rolls = { { itemId = "copper_ore", weight = 1, minCount = 1, maxCount = 1 } },
		},
	},
	leaseSeconds = 60,
	playerLimit = 8,
})
