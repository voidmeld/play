--!strict

local Policy = require("./policy")
local Registry = require("./name-claims")
local Value = require("../value")

export type Record = NameRecord
export type Claim = Registry.Claim
type NameRecord = { schemaVersion: number, revision: number, registryKey: string, claim: Claim | false }

local function create(policy: Policy.Policy)
	local registry = Registry.create(policy)

	local Record = {}

	Record.SCHEMA_VERSION = 1
	Record.MAX_REVISION = 1000000000
	Record.MAX_SAFE_INTEGER = 9007199254740991
	Record.MAX_CHARACTER_ID_BYTES = 64

	local FIELDS: { [string]: boolean } = { schemaVersion = true, revision = true, registryKey = true, claim = true }

	local function whole(value: unknown, minimum: number, maximum: number): boolean
		return type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value >= minimum
			and value <= maximum
			and value % 1 == 0
	end

	local function copiedClaim(raw: unknown): Claim?
		if type(raw) ~= "table" or getmetatable(raw) ~= nil then
			return nil
		end
		local ok, claim = pcall(registry.validate, raw)
		if not ok then
			return nil
		end
		if
			not whole(claim.userId, 1, Record.MAX_SAFE_INTEGER)
			or not whole(claim.claimedAtUnix, 0, Record.MAX_SAFE_INTEGER)
		then
			return nil
		end
		local value: Claim = {
			displayName = claim.displayName,
			userId = claim.userId,
			characterId = claim.characterId,
			claimedAtUnix = claim.claimedAtUnix,
			schemaVersion = claim.schemaVersion,
		}
		return Value.freezeDeep(value)
	end

	function Record.validate(raw: unknown): NameRecord?
		local source = Value.record(raw, FIELDS, true)
		if source == nil or source.schemaVersion ~= Record.SCHEMA_VERSION then
			return nil
		end
		local revision = Value.whole(source.revision, 0, Record.MAX_REVISION)
		local key = source.registryKey
		if revision == nil or type(key) ~= "string" or not policy.validRegistryKey(key) then
			return nil
		end
		local claim: Claim | false
		if source.claim == false then
			claim = false
		else
			local found = copiedClaim(source.claim)
			if found == nil or policy.registryKey(found.displayName) ~= key then
				return nil
			end
			claim = found
		end
		local value: NameRecord =
			{ schemaVersion = Record.SCHEMA_VERSION, revision = revision, registryKey = key, claim = claim }
		return Value.freezeDeep(value)
	end

	function Record.copy(raw: unknown): NameRecord?
		return Record.validate(raw)
	end

	function Record.empty(displayNameRaw: unknown): NameRecord?
		local key = policy.registryKey(displayNameRaw)
		if key == nil then
			return nil
		end
		return Record.validate({
			schemaVersion = Record.SCHEMA_VERSION,
			revision = 0,
			registryKey = key,
			claim = false,
		})
	end

	function Record.equal(leftRaw: unknown, rightRaw: unknown): boolean
		local left = Record.validate(leftRaw)
		local right = Record.validate(rightRaw)
		if left == nil or right == nil then
			return false
		end
		if
			left.schemaVersion ~= right.schemaVersion
			or left.revision ~= right.revision
			or left.registryKey ~= right.registryKey
			or type(left.claim) ~= type(right.claim)
		then
			return false
		end
		if left.claim == false or right.claim == false then
			return left.claim == right.claim
		end
		return left.claim.schemaVersion == (right.claim).schemaVersion
			and left.claim.displayName == (right.claim).displayName
			and left.claim.userId == (right.claim).userId
			and left.claim.characterId == (right.claim).characterId
			and left.claim.claimedAtUnix == (right.claim).claimedAtUnix
	end

	local function nextRecord(raw: NameRecord, revision: number, claim: Claim | false): NameRecord?
		return Record.validate({
			schemaVersion = Record.SCHEMA_VERSION,
			revision = revision,
			registryKey = raw.registryKey,
			claim = claim,
		})
	end

	function Record.claim(currentRaw: unknown, requestedRaw: unknown): (NameRecord?, string)
		local requested = copiedClaim(requestedRaw)
		if requested == nil then
			return nil, "invalid"
		end
		local key = (policy.registryKey(requested.displayName))
		local current = if currentRaw == nil then nil else Record.validate(currentRaw)
		if currentRaw ~= nil and (current == nil or current.registryKey ~= key) then
			return nil, "invalid"
		end
		if current ~= nil and current.claim == false and current.revision >= Record.MAX_REVISION then
			return current, "exhausted"
		end
		local kernelCurrent = if current == nil or current.claim == false then nil else current.claim
		local ok, nextClaim, status = pcall(registry.claim, kernelCurrent, requested)
		if not ok then
			return nil, "invalid"
		end
		if status == "owned" then
			return current, "owned"
		end
		if status == "taken" then
			return current, "taken"
		end
		return Record.validate({
			schemaVersion = Record.SCHEMA_VERSION,
			revision = if current == nil then 0 else current.revision + 1,
			registryKey = key,
			claim = nextClaim,
		}),
			"claimed"
	end

	function Record.release(
		currentRaw: unknown,
		displayNameRaw: unknown,
		userId: unknown,
		characterId: unknown
	): (NameRecord?, string)
		local key = policy.registryKey(displayNameRaw)
		if
			key == nil
			or not whole(userId, 1, Record.MAX_SAFE_INTEGER)
			or type(characterId) ~= "string"
			or #characterId == 0
			or #characterId > Record.MAX_CHARACTER_ID_BYTES
		then
			return nil, "invalid"
		end
		local current = if currentRaw == nil then nil else Record.validate(currentRaw)
		if currentRaw ~= nil and (current == nil or current.registryKey ~= key) then
			return nil, "invalid"
		end
		local kernelCurrent = if current == nil or current.claim == false then nil else current.claim
		local ok, _, status = pcall(registry.release, kernelCurrent, userId, characterId)
		if not ok then
			return nil, "invalid"
		end
		if status == "absent" then
			return current, "absent"
		end
		if status == "mismatch" then
			return current, "mismatch"
		end
		if current == nil or current.revision >= Record.MAX_REVISION then
			return current, "exhausted"
		end
		return nextRecord(current, current.revision + 1, false), "released"
	end

	function Record.availability(
		currentRaw: unknown,
		displayNameRaw: unknown,
		userId: unknown,
		characterId: unknown
	): string
		local key = policy.registryKey(displayNameRaw)
		if
			key == nil
			or not whole(userId, 1, Record.MAX_SAFE_INTEGER)
			or type(characterId) ~= "string"
			or #characterId == 0
			or #characterId > Record.MAX_CHARACTER_ID_BYTES
		then
			return "invalid"
		end
		local current = if currentRaw == nil then nil else Record.validate(currentRaw)
		if currentRaw ~= nil and (current == nil or current.registryKey ~= key) then
			return "invalid"
		end
		local kernelCurrent = if current == nil or current.claim == false then nil else current.claim
		local ok, status = pcall(registry.availability, kernelCurrent, userId, characterId)
		if not ok then
			return "invalid"
		end
		return status
	end

	return table.freeze(Record)
end

return table.freeze({ create = create })
