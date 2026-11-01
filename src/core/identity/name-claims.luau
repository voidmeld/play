--!strict

local Policy = require("./policy")
local Value = require("../value")

export type Claim = {
	displayName: string,
	userId: number,
	characterId: string,
	claimedAtUnix: number,
	schemaVersion: number,
}
export type ClaimStatus = "claimed" | "owned" | "taken"
export type ReleaseStatus = "released" | "absent" | "mismatch"
export type Availability = "available" | "owned" | "taken"
local function create(policy: Policy.Policy)
	local SCHEMA_VERSION = 1
	local KNOWN_FIELDS: { [string]: boolean } = {
		displayName = true,
		userId = true,
		characterId = true,
		claimedAtUnix = true,
		schemaVersion = true,
	}

	local function whole(value: unknown): boolean
		return type(value) == "number"
			and value == value
			and value == math.floor(value)
			and math.abs(value) ~= math.huge
	end

	local function copyClaim(claim: Claim): Claim
		return {
			displayName = claim.displayName,
			userId = claim.userId,
			characterId = claim.characterId,
			claimedAtUnix = claim.claimedAtUnix,
			schemaVersion = claim.schemaVersion,
		}
	end

	local function validate(candidate: unknown): Claim
		if type(candidate) ~= "table" then
			error("NameRegistryKernel: " .. "claim must be a table", 2)
		end
		local raw = assert(Value.raw(candidate))
		for key in raw do
			if type(key) ~= "string" or not KNOWN_FIELDS[key] then
				error("NameRegistryKernel: " .. ("unknown claim field " .. tostring(key)), 2)
			end
		end
		if raw.schemaVersion ~= SCHEMA_VERSION then
			error("NameRegistryKernel: " .. "unsupported schemaVersion", 2)
		end
		local nameOk, displayName = policy.validateName(raw.displayName)
		if not nameOk or type(displayName) ~= "string" or displayName ~= raw.displayName then
			error("NameRegistryKernel: " .. "displayName is invalid or noncanonical", 2)
		end
		local userId, characterId, at = raw.userId, raw.characterId, raw.claimedAtUnix
		if type(userId) ~= "number" or not whole(userId) or userId <= 0 then
			error("NameRegistryKernel: " .. "userId must be a positive whole number", 2)
		end
		if type(characterId) ~= "string" or #characterId == 0 or #characterId > 64 then
			error("NameRegistryKernel: " .. "characterId must be a non-empty string of at most 64 bytes", 2)
		end
		if type(at) ~= "number" or not whole(at) or at < 0 then
			error("NameRegistryKernel: " .. "claimedAtUnix must be a non-negative whole number", 2)
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			displayName = displayName,
			userId = userId,
			characterId = characterId,
			claimedAtUnix = at,
		}
	end

	local function claim(current: unknown, requested: unknown): (Claim, ClaimStatus)
		local nextClaim = validate(requested)
		if current == nil then
			return copyClaim(nextClaim), "claimed"
		end
		local existing = validate(current)
		local existingKey = policy.registryKey(existing.displayName)
		local requestedKey = policy.registryKey(nextClaim.displayName)
		if existingKey ~= requestedKey then
			error("NameRegistryKernel: " .. "current and requested claims belong to different registry keys", 2)
		end
		if existing.userId == nextClaim.userId and existing.characterId == nextClaim.characterId then
			return copyClaim(existing), "owned"
		end
		return copyClaim(existing), "taken"
	end

	local function release(current: unknown, userId: unknown, characterId: unknown): (Claim?, ReleaseStatus)
		if current == nil then
			return nil, "absent"
		end
		local existing = validate(current)
		if
			type(userId) ~= "number"
			or not whole(userId)
			or userId <= 0
			or type(characterId) ~= "string"
			or #characterId == 0
		then
			error("NameRegistryKernel: " .. "release identity is invalid", 2)
		end
		if existing.userId ~= userId or existing.characterId ~= characterId then
			return copyClaim(existing), "mismatch"
		end
		return nil, "released"
	end

	local function availability(current: unknown, userId: unknown, characterId: unknown): Availability
		if current == nil then
			return "available"
		end
		local existing = validate(current)
		if existing.userId == userId and existing.characterId == characterId then
			return "owned"
		end
		return "taken"
	end

	return {
		validate = validate,
		claim = claim,
		release = release,
		availability = availability,
		SCHEMA_VERSION = SCHEMA_VERSION,
	}
end

return table.freeze({ create = create })
