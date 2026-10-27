--!strict

local Policy = require("./policy")

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
type RawClaim = {
	displayName: unknown,
	userId: unknown,
	characterId: unknown,
	claimedAtUnix: unknown,
	schemaVersion: unknown,
}

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

	local function reject(reason: string): never
		error("NameRegistryKernel: " .. reason, 3)
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
			reject("claim must be a table")
		end
		local claim = candidate :: RawClaim
		for key in claim :: { [unknown]: unknown } do
			if type(key) ~= "string" or not KNOWN_FIELDS[key] then
				reject("unknown claim field " .. tostring(key))
			end
		end
		if claim.schemaVersion ~= SCHEMA_VERSION then
			reject("unsupported schemaVersion")
		end
		local nameOk, displayName = policy.validateName(claim.displayName)
		if not nameOk or displayName ~= claim.displayName then
			reject("displayName is invalid or noncanonical")
		end
		if not whole(claim.userId) or (claim.userId :: number) <= 0 then
			reject("userId must be a positive whole number")
		end
		if type(claim.characterId) ~= "string" or #claim.characterId == 0 or #claim.characterId > 64 then
			reject("characterId must be a non-empty string of at most 64 bytes")
		end
		if not whole(claim.claimedAtUnix) or (claim.claimedAtUnix :: number) < 0 then
			reject("claimedAtUnix must be a non-negative whole number")
		end
		return claim :: Claim
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
			reject("current and requested claims belong to different registry keys")
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
		if not whole(userId) or (userId :: number) <= 0 or type(characterId) ~= "string" or #characterId == 0 then
			reject("release identity is invalid")
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
		Types = (nil :: unknown) :: { Claim: Claim, ClaimStatus: ClaimStatus, ReleaseStatus: ReleaseStatus },
	}
end

return table.freeze({ create = create })
