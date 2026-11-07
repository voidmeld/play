--!strict

local Codec = require("../../src/kernel/codec")
local Content = require("./content")
local Journal = require("../../src/core/quest/journal")
local Lock = require("../../src/core/persistence/session-lock")
local Records = require("../../src/core/persistence/record-store")
local Roster = require("../../src/core/identity/roster")
local Value = require("../../src/kernel/value")

export type Drop = { itemId: string, count: number }
export type Profile = {
	userId: number,
	characterId: string,
	roster: Roster.Roster,
	xp: number,
	coin: number,
	inventory: { [string]: number },
	equipment: { [string]: string },
	journal: Journal.Record,
	defeats: { [string]: boolean },
	loot: { [string]: Drop },
	lock: Lock.LockState,
	acquisitionId: string,
}
export type World = {
	partitionId: string,
	subjectId: string,
	revision: number,
	players: { [string]: Profile },
}

local function counts(raw: unknown): { [string]: number }?
	local row = Value.raw(raw)
	if row == nil then
		return nil
	end
	local result: { [string]: number } = {}
	for key, value in row do
		if
			(key ~= "training_sword" and key ~= "copper_ore" and key ~= "shield")
			or type(key) ~= "string"
			or type(value) ~= "number"
			or Value.whole(value, 1, 99) == nil
		then
			return nil
		end
		result[key] = value
	end
	return result
end

local function profile(raw: unknown): Profile?
	local row = Value.record(raw, {
		userId = true,
		characterId = true,
		roster = true,
		xp = true,
		coin = true,
		inventory = true,
		equipment = true,
		journal = true,
		defeats = true,
		loot = true,
		lock = true,
		acquisitionId = true,
	})
	if row == nil then
		return nil
	end
	local userId = Value.whole(row.userId, 1, 9007199254740991)
	local xp = Value.whole(row.xp, 0, 100000)
	local coin = Value.whole(row.coin, 0, 100000)
	local bag = counts(row.inventory)
	local slots = Value.record(row.equipment, { hand = true })
	local journal = Content.journal.decode(row.journal)
	local lock = Value.record(row.lock, { sessionId = true, lockExpiry = true })
	local defeats = Value.raw(row.defeats)
	local loot = Value.raw(row.loot)
	if
		userId == nil
		or row.characterId ~= "character:" .. tostring(userId)
		or xp == nil
		or coin == nil
		or bag == nil
		or slots == nil
		or journal == nil
		or lock == nil
		or defeats == nil
		or loot == nil
		or type(row.acquisitionId) ~= "string"
		or #row.acquisitionId > 64
	then
		return nil
	end
	local characterId = "character:" .. tostring(userId)
	local rosterOk, roster = pcall(Content.roster.validateStored, row.roster)
	if
		not rosterOk
		or roster.userId ~= userId
		or #roster.characters ~= 1
		or roster.characters[1].characterId ~= characterId
		or roster.characters[1].level ~= Content.levels.levelForXp(xp)
		or journal.characterId ~= characterId
		or journal.zoneId ~= "Harbor"
	then
		return nil
	end
	local equipment: { [string]: string } = {}
	local progress = journal.quests[Content.quest.id]
	if progress == nil or progress.counts == nil then
		return nil
	end
	local objectiveCounts = Value.record(progress.counts, { defeat = true, collect = true }, true)
	if objectiveCounts == nil then
		return nil
	end
	local defeatCount, collectCount = objectiveCounts.defeat, objectiveCounts.collect
	if
		type(defeatCount) ~= "number"
		or type(collectCount) ~= "number"
		or progress.step ~= defeatCount + collectCount
		or (progress.status == "offered" and progress.step ~= 0)
		or (progress.status == "completed" and progress.step ~= 2)
		or (journal.semanticEventIds["reward:Harbor Supplies"] == true) ~= (progress.status == "completed")
	then
		return nil
	end
	for id in journal.quests do
		if id ~= Content.quest.id then
			return nil
		end
	end
	for id in journal.semanticEventIds do
		if id ~= "reward:Harbor Supplies" then
			return nil
		end
	end
	if slots.hand ~= nil then
		if slots.hand ~= "training_sword" then
			return nil
		end
		equipment.hand = "training_sword"
	end
	local sessionId = lock.sessionId
	local expiry = Value.whole(lock.lockExpiry, 0, 9007199254740991)
	if expiry == nil or (sessionId ~= nil and (type(sessionId) ~= "string" or #sessionId == 0 or #sessionId > 128)) then
		return nil
	end
	local savedDefeats: { [string]: boolean } = {}
	local savedLoot: { [string]: Drop } = {}
	local total = 0
	for id, marked in defeats do
		if type(id) ~= "string" or #id == 0 or #id > 64 or marked ~= true then
			return nil
		end
		total += 1
		if total > 32 then
			return nil
		end
		savedDefeats[id] = true
	end
	for id, drop in loot do
		local fields = Value.record(drop, { itemId = true, count = true })
		if
			type(id) ~= "string"
			or not savedDefeats[id]
			or fields == nil
			or fields.itemId ~= "copper_ore"
			or fields.count ~= 1
		then
			return nil
		end
		savedLoot[id] = { itemId = "copper_ore", count = 1 }
	end
	return {
		userId = userId,
		characterId = characterId,
		roster = roster,
		xp = xp,
		coin = coin,
		inventory = bag,
		equipment = equipment,
		journal = journal,
		defeats = savedDefeats,
		loot = savedLoot,
		lock = { sessionId = if type(sessionId) == "string" then sessionId else nil, lockExpiry = expiry },
		acquisitionId = row.acquisitionId,
	}
end

local function copy(raw: unknown): (World?, string?)
	local row = Value.record(raw, { partitionId = true, subjectId = true, revision = true, players = true })
	if row == nil or row.partitionId ~= "Harbor" or row.subjectId ~= "world" then
		return nil, "world_invalid"
	end
	local revision = Value.whole(row.revision, 0, 1000000000)
	local rows = Value.raw(row.players)
	if revision == nil or rows == nil then
		return nil, "world_invalid"
	end
	local players: { [string]: Profile } = {}
	local total = 0
	for key, value in rows do
		local player = profile(value)
		if player == nil or key ~= tostring(player.userId) then
			return nil, "profile_invalid"
		end
		total += 1
		if total > Content.playerLimit then
			return nil, "world_full"
		end
		players[tostring(player.userId)] = player
	end
	return { partitionId = "Harbor", subjectId = "world", revision = revision, players = players }, nil
end

local records = Records.configure({
	codec = { copy = copy, equal = Codec.equalData },
	empty = function(_partition: string, _subject: string): (World?, string?)
		return { partitionId = "Harbor", subjectId = "world", revision = 0, players = {} }, nil
	end,
	view = function(world: World)
		return { partitionId = world.partitionId, subjectId = world.subjectId, revision = world.revision }
	end,
	withRevision = function(world: World, revision: number): World
		local nextWorld = assert(copy(world))
		nextWorld.revision = revision
		return nextWorld
	end,
	maxRevision = 1000000000,
})

local function create(userId: number, displayName: string, now: number): Profile
	local characterId = "character:" .. tostring(userId)
	local roster = Content.roster.add({ schemaVersion = 1, userId = userId, characters = {} }, {
		characterId = characterId,
		displayName = displayName,
		realmId = "harbor",
		peopleId = "traveler",
		classId = "warden",
		appearancePresetId = "default",
		createdAtUnix = now,
		lastPlayedAtUnix = now,
		level = 1,
		lastDestinationId = false,
	})
	local journal = assert(Content.journal.create("Harbor", characterId, {
		[Content.quest.id] = { status = "offered", step = 0, counts = { defeat = 0, collect = 0 } },
	}))
	return {
		userId = userId,
		characterId = characterId,
		roster = roster,
		xp = 0,
		coin = 0,
		inventory = { ["training_sword"] = 1, shield = 1 },
		equipment = {},
		journal = journal,
		defeats = {},
		loot = {},
		lock = { sessionId = nil, lockExpiry = 0 },
		acquisitionId = "",
	}
end

return table.freeze({ records = records, copy = copy, copyProfile = profile, create = create })
