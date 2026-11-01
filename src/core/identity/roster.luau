--!strict

local Policy = require("./policy")

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
type RawCharacter = {
	characterId: unknown,
	displayName: unknown,
	realmId: unknown,
	peopleId: unknown,
	classId: unknown,
	appearancePresetId: unknown,
	createdAtUnix: unknown,
	lastPlayedAtUnix: unknown,
	level: unknown,
	lastDestinationId: unknown,
}
type RawRoster = {
	schemaVersion: unknown,
	userId: unknown,
	characters: unknown,
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

	local function reject(reason: string): never
		error("RosterKernel: " .. reason, 3)
	end

	local function nonempty(value: unknown, field: string): string
		if type(value) ~= "string" or #value == 0 or #value > 64 then
			reject(field .. " must be a non-empty string of at most 64 bytes")
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
			reject("character must be a table")
		end
		local character = candidate
		for key in character do
			if type(key) ~= "string" or not KNOWN_CHARACTER_FIELDS[key] then
				reject("unknown character field " .. tostring(key))
			end
		end
		local characterId = nonempty(character.characterId, "characterId")
		local nameOk, displayName = policy.validateName(character.displayName)
		if not nameOk or displayName ~= character.displayName then
			reject("displayName is invalid or noncanonical")
		end
		if characterId == displayName then
			reject("displayName must not be reused as identity")
		end
		local realmId = nonempty(character.realmId, "realmId")
		if stored ~= true and not REALMS[realmId] then
			reject("unknown realm " .. tostring(character.realmId))
		end
		local peopleId = nonempty(character.peopleId, "peopleId")
		if stored ~= true and PLAYABLE_PEOPLE_IDS[peopleId] ~= true then
			reject("unknown peopleId " .. tostring(peopleId))
		end
		nonempty(character.classId, "classId")
		local appearancePresetId = nonempty(character.appearancePresetId, "appearancePresetId")
		if not whole(character.createdAtUnix) or character.createdAtUnix < 0 then
			reject("createdAtUnix must be a non-negative whole number")
		end
		if not whole(character.lastPlayedAtUnix) or character.lastPlayedAtUnix < character.createdAtUnix then
			reject("lastPlayedAtUnix must be a whole number no earlier than creation")
		end
		if not whole(character.level) or character.level < MIN_LEVEL or character.level > MAX_LEVEL then
			reject(("level must be a whole number within %d..%d"):format(MIN_LEVEL, MAX_LEVEL))
		end
		if
			character.lastDestinationId ~= NEVER_DEPARTED and not declaredDestinationShape(character.lastDestinationId)
		then
			reject("lastDestinationId must be a namespaced destination id or the never-departed value")
		end
		local normalized = table.clone(character)
		normalized.peopleId = peopleId
		normalized.appearancePresetId = appearancePresetId
		return normalized
	end

	local function validate(candidate: unknown, stored: boolean?): Roster
		if type(candidate) ~= "table" then
			reject("roster must be a table")
		end
		local roster = candidate
		for key in roster do
			if type(key) ~= "string" or not KNOWN_ROSTER_FIELDS[key] then
				reject("unknown roster field " .. tostring(key))
			end
		end
		if roster.schemaVersion ~= SCHEMA_VERSION then
			reject("unsupported schemaVersion")
		end
		if not whole(roster.userId) or roster.userId <= 0 then
			reject("userId must be a positive whole number")
		end
		if type(roster.characters) ~= "table" then
			reject("characters must be a table")
		end
		local rawCharacters = roster.characters
		local characterCount = 0
		for index in rawCharacters do
			if not whole(index) or index < 1 then
				reject("characters must be a dense array")
			end
			characterCount += 1
		end
		for index = 1, characterCount do
			if rawCharacters[index] == nil then
				reject("characters must be a dense array")
			end
		end
		if characterCount > ACCOUNT_LIMIT then
			reject("account roster exceeds limit")
		end
		local seenIds: { [string]: boolean } = {}
		local seenNames: { [string]: boolean } = {}
		local realmCounts: { [string]: number } = {}
		local characters: { CharacterIdentity } = {}
		for index, rawCharacter in rawCharacters do
			local character = validateCharacter(rawCharacter, stored)
			characters[index] = character
			if seenIds[character.characterId] then
				reject("duplicate characterId " .. character.characterId)
			end
			seenIds[character.characterId] = true
			local nameKey = (policy.registryKey(character.displayName))
			if seenNames[nameKey] then
				reject("duplicate case-insensitive displayName " .. character.displayName)
			end
			seenNames[nameKey] = true
			local count = (realmCounts[character.realmId] or 0) + 1
			if count > REALM_LIMIT then
				reject("realm roster exceeds limit")
			end
			realmCounts[character.realmId] = count
		end
		return {
			schemaVersion = roster.schemaVersion,
			userId = roster.userId,
			characters = characters,
		}
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
			reject("characterId is invalid")
		end
		for index, character in nextRoster.characters do
			if character.characterId == characterId then
				local removed = (table.remove(nextRoster.characters, index))
				return nextRoster, removed
			end
		end
		error("RosterKernel: characterId is not owned by roster", 2)
	end

	local function markPlayed(roster: unknown, characterId: unknown, playedAtUnix: unknown): Roster
		local nextRoster = copyRoster(validate(roster))
		if not whole(playedAtUnix) or playedAtUnix < 0 then
			reject("playedAtUnix must be a non-negative whole number")
		end
		local played = playedAtUnix
		for _, character in nextRoster.characters do
			if character.characterId == characterId then
				if played < character.lastPlayedAtUnix then
					reject("playedAtUnix must not move backward")
				end
				character.lastPlayedAtUnix = played
				return nextRoster
			end
		end
		error("RosterKernel: characterId is not owned by roster", 2)
	end

	local function markLevel(roster: unknown, characterId: unknown, level: unknown): Roster
		local nextRoster = copyRoster(validate(roster))
		if not whole(level) or level < MIN_LEVEL or level > MAX_LEVEL then
			reject(("level must be a whole number within %d..%d"):format(MIN_LEVEL, MAX_LEVEL))
		end
		local nextLevel = level
		for _, character in nextRoster.characters do
			if character.characterId == characterId then
				if nextLevel < character.level then
					reject("level must not move backward")
				end
				character.level = nextLevel
				return nextRoster
			end
		end
		error("RosterKernel: characterId is not owned by roster", 2)
	end

	local function markDeparted(roster: unknown, characterId: unknown, destinationId: unknown): Roster
		local nextRoster = copyRoster(validate(roster))
		if not declaredDestinationShape(destinationId) then
			reject("lastDestinationId must be a namespaced destination id")
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
			reject("unknown realm " .. tostring(realmId))
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
