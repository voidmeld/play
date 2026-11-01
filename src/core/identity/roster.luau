--!strict

local Policy = require("./policy")
local Value = require("../internal/value")

export type CharacterIdentity = {
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	createdAtUnix: number,
	lastPlayedAtUnix: number,
	level: number,
	lastDestinationId: string | false,
}
export type Roster = {
	schemaVersion: number,
	userId: number,
	characters: { CharacterIdentity },
}
local function create(policy: Policy.Policy)
	local SCHEMA_VERSION = 1
	local ACCOUNT_LIMIT = policy.accountLimit
	local REALM_LIMIT = policy.realmLimit
	local MIN_LEVEL = policy.minLevel
	local MAX_LEVEL = policy.maxLevel
	local NEVER_DEPARTED: false = false
	local REALMS = policy.realms
	local PLAYABLE_PEOPLE_IDS = policy.peoples
	local KNOWN_ROSTER_FIELDS: { [string]: boolean } = { schemaVersion = true, userId = true, characters = true }
	local KNOWN_CHARACTER_FIELDS: { [string]: boolean } = {
		characterId = true,
		displayName = true,
		realmId = true,
		peopleId = true,
		classId = true,
		appearancePresetId = true,
		createdAtUnix = true,
		lastPlayedAtUnix = true,
		level = true,
		lastDestinationId = true,
	}

	local function whole(value: unknown): boolean
		return type(value) == "number"
			and value == value
			and value == math.floor(value)
			and math.abs(value) ~= math.huge
	end

	local function nonempty(value: unknown, field: string): string
		if type(value) ~= "string" or #value == 0 or #value > 64 then
			error("RosterKernel: " .. (field .. " must be a non-empty string of at most 64 bytes"), 2)
		end
		return value
	end

	local declaredDestinationShape = policy.validDestination

	local function copyCharacter(character: CharacterIdentity): CharacterIdentity
		return {
			characterId = character.characterId,
			displayName = character.displayName,
			realmId = character.realmId,
			peopleId = character.peopleId,
			classId = character.classId,
			appearancePresetId = character.appearancePresetId,
			createdAtUnix = character.createdAtUnix,
			lastPlayedAtUnix = character.lastPlayedAtUnix,
			level = character.level,
			lastDestinationId = character.lastDestinationId,
		}
	end

	local function copyRoster(roster: Roster): Roster
		local characters = {}
		for index, character in roster.characters do
			characters[index] = copyCharacter(character)
		end
		return { schemaVersion = roster.schemaVersion, userId = roster.userId, characters = characters }
	end

	local function validateCharacter(candidate: unknown, stored: boolean?): CharacterIdentity
		if type(candidate) ~= "table" then
			error("RosterKernel: " .. "character must be a table", 2)
		end
		local raw = assert(Value.raw(candidate))
		for key in raw do
			if type(key) ~= "string" or not KNOWN_CHARACTER_FIELDS[key] then
				error("RosterKernel: " .. ("unknown character field " .. tostring(key)), 2)
			end
		end
		local characterId = nonempty(raw.characterId, "characterId")
		local nameOk, displayName = policy.validateName(raw.displayName)
		if not nameOk or type(displayName) ~= "string" or displayName ~= raw.displayName then
			error("RosterKernel: " .. "displayName is invalid or noncanonical", 2)
		end
		if characterId == displayName then
			error("RosterKernel: " .. "displayName must not be reused as identity", 2)
		end
		local realmId = nonempty(raw.realmId, "realmId")
		if stored ~= true and not REALMS[realmId] then
			error("RosterKernel: " .. ("unknown realm " .. realmId), 2)
		end
		local peopleId = nonempty(raw.peopleId, "peopleId")
		if stored ~= true and not PLAYABLE_PEOPLE_IDS[peopleId] then
			error("RosterKernel: " .. ("unknown peopleId " .. peopleId), 2)
		end
		local classId = nonempty(raw.classId, "classId")
		local appearance = nonempty(raw.appearancePresetId, "appearancePresetId")
		local created, played, level, destination =
			raw.createdAtUnix, raw.lastPlayedAtUnix, raw.level, raw.lastDestinationId
		if type(created) ~= "number" or not whole(created) or created < 0 then
			error("RosterKernel: " .. "createdAtUnix must be a non-negative whole number", 2)
		end
		if type(played) ~= "number" or not whole(played) or played < created then
			error("RosterKernel: " .. "lastPlayedAtUnix must be a whole number no earlier than creation", 2)
		end
		if type(level) ~= "number" or not whole(level) or level < MIN_LEVEL or level > MAX_LEVEL then
			error("RosterKernel: " .. (("level must be a whole number within %d..%d"):format(MIN_LEVEL, MAX_LEVEL)), 2)
		end
		if destination ~= false and (type(destination) ~= "string" or not declaredDestinationShape(destination)) then
			error(
				"RosterKernel: " .. "lastDestinationId must be a namespaced destination id or the never-departed value",
				2
			)
		end
		return {
			characterId = characterId,
			displayName = displayName,
			realmId = realmId,
			peopleId = peopleId,
			classId = classId,
			appearancePresetId = appearance,
			createdAtUnix = created,
			lastPlayedAtUnix = played,
			level = level,
			lastDestinationId = destination,
		}
	end

	local function validate(candidate: unknown, stored: boolean?): Roster
		if type(candidate) ~= "table" then
			error("RosterKernel: " .. "roster must be a table", 2)
		end
		local raw = assert(Value.raw(candidate))
		for key in raw do
			if type(key) ~= "string" or not KNOWN_ROSTER_FIELDS[key] then
				error("RosterKernel: " .. ("unknown roster field " .. tostring(key)), 2)
			end
		end
		if raw.schemaVersion ~= SCHEMA_VERSION then
			error("RosterKernel: " .. "unsupported schemaVersion", 2)
		end
		local userId = raw.userId
		if type(userId) ~= "number" or not whole(userId) or userId <= 0 then
			error("RosterKernel: " .. "userId must be a positive whole number", 2)
		end
		if type(raw.characters) ~= "table" then
			error("RosterKernel: " .. "characters must be a table", 2)
		end
		local rows = Value.dense(raw.characters, math.huge, false)
		if rows == nil then
			error("RosterKernel: " .. "characters must be a dense array", 2)
		end
		if #rows > ACCOUNT_LIMIT then
			error("RosterKernel: " .. "account roster exceeds limit", 2)
		end
		local seenIds: { [string]: boolean } = {}
		local seenNames: { [string]: boolean } = {}
		local realmCounts: { [string]: number } = {}
		local characters: { CharacterIdentity } = {}
		for index, row in rows do
			local character = validateCharacter(row, stored)
			characters[index] = character
			if seenIds[character.characterId] then
				error("RosterKernel: " .. ("duplicate characterId " .. character.characterId), 2)
			end
			seenIds[character.characterId] = true
			local nameKey = policy.registryKey(character.displayName)
			if nameKey == nil then
				error("RosterKernel: " .. "displayName has no registry key", 2)
			end
			if seenNames[nameKey] then
				error("RosterKernel: " .. ("duplicate case-insensitive displayName " .. character.displayName), 2)
			end
			seenNames[nameKey] = true
			local count = (realmCounts[character.realmId] or 0) + 1
			if count > REALM_LIMIT then
				error("RosterKernel: " .. "realm roster exceeds limit", 2)
			end
			realmCounts[character.realmId] = count
		end
		return { schemaVersion = SCHEMA_VERSION, userId = userId, characters = characters }
	end

	local function add(roster: unknown, character: unknown): Roster
		local nextRoster = copyRoster(validate(roster))
		nextRoster.characters[#nextRoster.characters + 1] = copyCharacter(validateCharacter(character))
		validate(nextRoster)
		return nextRoster
	end

	local function remove(roster: unknown, characterId: unknown, stored: boolean?): (Roster, CharacterIdentity)
		local nextRoster = copyRoster(validate(roster, stored))
		if type(characterId) ~= "string" or #characterId == 0 then
			error("RosterKernel: " .. "characterId is invalid", 2)
		end
		for index, character in nextRoster.characters do
			if character.characterId == characterId then
				local removed = assert(table.remove(nextRoster.characters, index))
				return nextRoster, removed
			end
		end
		error("RosterKernel: characterId is not owned by roster", 2)
	end

	local function markPlayed(roster: unknown, characterId: unknown, playedAtUnix: unknown): Roster
		local nextRoster = copyRoster(validate(roster))
		if type(playedAtUnix) ~= "number" or not whole(playedAtUnix) or playedAtUnix < 0 then
			error("RosterKernel: " .. "playedAtUnix must be a non-negative whole number", 2)
		end
		local played = playedAtUnix
		for _, character in nextRoster.characters do
			if character.characterId == characterId then
				if played < character.lastPlayedAtUnix then
					error("RosterKernel: " .. "playedAtUnix must not move backward", 2)
				end
				character.lastPlayedAtUnix = played
				return nextRoster
			end
		end
		error("RosterKernel: characterId is not owned by roster", 2)
	end

	local function markLevel(roster: unknown, characterId: unknown, level: unknown): Roster
		local nextRoster = copyRoster(validate(roster))
		if type(level) ~= "number" or not whole(level) or level < MIN_LEVEL or level > MAX_LEVEL then
			error("RosterKernel: " .. (("level must be a whole number within %d..%d"):format(MIN_LEVEL, MAX_LEVEL)), 2)
		end
		local nextLevel = level
		for _, character in nextRoster.characters do
			if character.characterId == characterId then
				if nextLevel < character.level then
					error("RosterKernel: " .. "level must not move backward", 2)
				end
				character.level = nextLevel
				return nextRoster
			end
		end
		error("RosterKernel: characterId is not owned by roster", 2)
	end

	local function markDeparted(roster: unknown, characterId: unknown, destinationId: unknown): Roster
		local nextRoster = copyRoster(validate(roster))
		if type(destinationId) ~= "string" or not declaredDestinationShape(destinationId) then
			error("RosterKernel: " .. "lastDestinationId must be a namespaced destination id", 2)
		end
		for _, character in nextRoster.characters do
			if character.characterId == characterId then
				character.lastDestinationId = destinationId
				return nextRoster
			end
		end
		error("RosterKernel: characterId is not owned by roster", 2)
	end

	local function realmCards(roster: unknown, realmId: unknown): { CharacterIdentity }
		local current = validate(roster)
		if type(realmId) ~= "string" or not REALMS[realmId] then
			error("RosterKernel: " .. ("unknown realm " .. tostring(realmId)), 2)
		end
		local cards: { CharacterIdentity } = {}
		for _, character in current.characters do
			if character.realmId == realmId then
				cards[#cards + 1] = copyCharacter(character)
			end
		end
		table.sort(cards, function(left: CharacterIdentity, right: CharacterIdentity)
			if left.lastPlayedAtUnix ~= right.lastPlayedAtUnix then
				return left.lastPlayedAtUnix > right.lastPlayedAtUnix
			end
			return left.characterId < right.characterId
		end)
		return cards
	end

	local profilePartitionKey = policy.profilePartitionKey

	return {
		validate = function(candidate: unknown): Roster
			return validate(candidate)
		end,
		validateStored = function(candidate: unknown): Roster
			return validate(candidate, true)
		end,
		add = add,
		remove = function(roster: unknown, characterId: unknown): (Roster, CharacterIdentity)
			return remove(roster, characterId)
		end,
		removeStored = function(roster: unknown, characterId: unknown): (Roster, CharacterIdentity)
			return remove(roster, characterId, true)
		end,
		markPlayed = markPlayed,
		markLevel = markLevel,
		markDeparted = markDeparted,
		realmCards = realmCards,
		profilePartitionKey = profilePartitionKey,
		SCHEMA_VERSION = SCHEMA_VERSION,
		ACCOUNT_LIMIT = ACCOUNT_LIMIT,
		REALM_LIMIT = REALM_LIMIT,
		MIN_LEVEL = MIN_LEVEL,
		MAX_LEVEL = MAX_LEVEL,
		NEVER_DEPARTED = NEVER_DEPARTED,
		REALMS = REALMS,
	}
end

return table.freeze({ create = create })
