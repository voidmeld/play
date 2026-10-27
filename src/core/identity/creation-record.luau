--!strict

local Creation = require("./creation")
local HasMetatable = require("./value")
local Policy = require("./policy")
local Roster = require("./roster")

type CreationState = Creation.State
type RosterCharacter = Roster.CharacterIdentity
export type Seed = {
	schemaVersion: number,
	userId: number,
	operationId: string,
	fingerprint: string,
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	createdAtUnix: number,
	preparedRevision: number,
	fence: number,
	leaseRevision: number,
}
export type Receipt = {
	schemaVersion: number,
	userId: number,
	operationId: string,
	fingerprint: string,
	characterId: string,
	committedRevision: number,
	fence: number,
	leaseRevision: number,
}

local function create(policy: Policy.Policy)
	local rosterRules = Roster.create(policy)
	local creation = Creation.create(policy)

	local Record = {}

	Record.SCHEMA_VERSION = 1
	Record.MAX_SAFE_INTEGER = creation.MAX_SAFE_INTEGER
	Record.MAX_REVISION = creation.MAX_REVISION
	Record.MAX_FENCE = creation.MAX_FENCE
	Record.MAX_ID_BYTES = 128
	Record.MAX_FINGERPRINT_BYTES = 2048

	local SEED_FIELDS = {
		schemaVersion = true,
		userId = true,
		operationId = true,
		fingerprint = true,
		characterId = true,
		displayName = true,
		realmId = true,
		peopleId = true,
		classId = true,
		appearancePresetId = true,
		createdAtUnix = true,
		preparedRevision = true,
		fence = true,
		leaseRevision = true,
	}

	local RECEIPT_FIELDS = {
		schemaVersion = true,
		userId = true,
		operationId = true,
		fingerprint = true,
		characterId = true,
		committedRevision = true,
		fence = true,
		leaseRevision = true,
	}

	local function exact(raw: unknown, fields: { [string]: boolean }): boolean
		if type(raw) ~= "table" or HasMetatable.check(raw) then
			return false
		end
		local view = raw :: { [unknown]: unknown }
		for key in view do
			if type(key) ~= "string" or fields[key] ~= true then
				return false
			end
		end
		for key in fields do
			if view[key] == nil then
				return false
			end
		end
		return true
	end

	local function whole(value: unknown, minimum: number, maximum: number): boolean
		return type(value) == "number"
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
			and value >= minimum
			and value <= maximum
			and value % 1 == 0
	end

	local function character(seed: Seed): RosterCharacter
		return {
			characterId = seed.characterId,
			displayName = seed.displayName,
			realmId = seed.realmId,
			peopleId = seed.peopleId,
			classId = seed.classId,
			appearancePresetId = seed.appearancePresetId,
			createdAtUnix = seed.createdAtUnix,
			lastPlayedAtUnix = seed.createdAtUnix,
			level = rosterRules.MIN_LEVEL,
			lastDestinationId = rosterRules.NEVER_DEPARTED,
		}
	end

	local function frozenSeed(seed: Seed): Seed
		local value: Seed = {
			schemaVersion = Record.SCHEMA_VERSION,
			userId = seed.userId,
			operationId = seed.operationId,
			fingerprint = seed.fingerprint,
			characterId = seed.characterId,
			displayName = seed.displayName,
			realmId = seed.realmId,
			peopleId = seed.peopleId,
			classId = seed.classId,
			appearancePresetId = seed.appearancePresetId,
			createdAtUnix = seed.createdAtUnix,
			preparedRevision = seed.preparedRevision,
			fence = seed.fence,
			leaseRevision = seed.leaseRevision,
		}
		return table.freeze(value) :: Seed
	end

	local function frozenReceipt(receipt: Receipt): Receipt
		local value: Receipt = {
			schemaVersion = Record.SCHEMA_VERSION,
			userId = receipt.userId,
			operationId = receipt.operationId,
			fingerprint = receipt.fingerprint,
			characterId = receipt.characterId,
			committedRevision = receipt.committedRevision,
			fence = receipt.fence,
			leaseRevision = receipt.leaseRevision,
		}
		return table.freeze(value) :: Receipt
	end

	local function validate(candidate: unknown, stored: boolean?): Seed?
		if not exact(candidate, SEED_FIELDS) then
			return nil
		end
		local raw = candidate :: Seed
		if
			raw.schemaVersion ~= Record.SCHEMA_VERSION
			or not whole(raw.userId, 1, Record.MAX_SAFE_INTEGER)
			or not whole(raw.createdAtUnix, 0, Record.MAX_SAFE_INTEGER)
			or not whole(raw.preparedRevision, 0, Record.MAX_REVISION)
			or not whole(raw.fence, 1, Record.MAX_FENCE)
			or not whole(raw.leaseRevision, 1, Record.MAX_REVISION)
		then
			return nil
		end
		local fingerprint = creation.fingerprint({
			userId = raw.userId,
			operationId = raw.operationId,
			characterId = raw.characterId,
			displayName = raw.displayName,
			realmId = raw.realmId,
			peopleId = raw.peopleId,
			classId = raw.classId,
			appearancePresetId = raw.appearancePresetId,
			createdAtUnix = raw.createdAtUnix,
			fence = raw.fence,
			leaseRevision = raw.leaseRevision,
		})
		if fingerprint == nil or fingerprint ~= raw.fingerprint then
			return nil
		end
		local ok = pcall(if stored == true then rosterRules.validateStored else rosterRules.validate, {
			schemaVersion = rosterRules.SCHEMA_VERSION,
			userId = raw.userId,
			characters = { character(raw) },
		})
		return if ok then frozenSeed(raw) else nil
	end

	function Record.validate(candidate: unknown): Seed?
		return validate(candidate)
	end

	function Record.validateStored(candidate: unknown): Seed?
		return validate(candidate, true)
	end

	function Record.copy(raw: unknown): Seed?
		return Record.validate(raw)
	end

	function Record.fromTransaction(raw: unknown): Seed?
		if type(raw) ~= "table" or HasMetatable.check(raw) then
			return nil
		end
		local state = creation.validate(raw)
		if state == nil or state.phase ~= "profile_prepared" then
			return nil
		end
		return Record.validate({
			schemaVersion = Record.SCHEMA_VERSION,
			userId = state.userId,
			operationId = state.operationId,
			fingerprint = state.fingerprint,
			characterId = state.characterId,
			displayName = state.displayName,
			realmId = state.realmId,
			peopleId = state.peopleId,
			classId = state.classId,
			appearancePresetId = state.appearancePresetId,
			createdAtUnix = state.createdAtUnix,
			preparedRevision = state.revision,
			fence = state.initialFence,
			leaseRevision = state.initialLeaseRevision,
		})
	end

	function Record.validateReceipt(candidate: unknown): Receipt?
		if not exact(candidate, RECEIPT_FIELDS) then
			return nil
		end
		local raw = candidate :: Receipt
		if
			raw.schemaVersion ~= Record.SCHEMA_VERSION
			or not whole(raw.userId, 1, Record.MAX_SAFE_INTEGER)
			or not whole(raw.committedRevision, 0, Record.MAX_REVISION)
			or not whole(raw.fence, 1, Record.MAX_FENCE)
			or not whole(raw.leaseRevision, 1, Record.MAX_REVISION)
			or type(raw.operationId) ~= "string"
			or #raw.operationId == 0
			or #raw.operationId > Record.MAX_ID_BYTES
			or type(raw.fingerprint) ~= "string"
			or #raw.fingerprint == 0
			or #raw.fingerprint > Record.MAX_FINGERPRINT_BYTES
			or type(raw.characterId) ~= "string"
			or #raw.characterId == 0
			or #raw.characterId > Record.MAX_ID_BYTES
		then
			return nil
		end
		return frozenReceipt(raw)
	end

	function Record.copyReceipt(raw: unknown): Receipt?
		return Record.validateReceipt(raw)
	end

	function Record.receiptFromTransaction(raw: unknown): Receipt?
		if type(raw) ~= "table" or HasMetatable.check(raw) then
			return nil
		end
		local state = creation.validate(raw)
		if state == nil or state.phase ~= "committed" then
			return nil
		end
		return Record.validateReceipt({
			schemaVersion = Record.SCHEMA_VERSION,
			userId = state.userId,
			operationId = state.operationId,
			fingerprint = state.fingerprint,
			characterId = state.characterId,
			committedRevision = state.revision,
			fence = state.initialFence,
			leaseRevision = state.initialLeaseRevision,
		})
	end

	function Record.receiptMatchesSeed(receiptRaw: unknown, seedRaw: unknown, stored: boolean?): boolean
		local receipt = Record.validateReceipt(receiptRaw)
		local seed = validate(seedRaw, stored)
		return receipt ~= nil
			and seed ~= nil
			and receipt.userId == seed.userId
			and receipt.operationId == seed.operationId
			and receipt.fingerprint == seed.fingerprint
			and receipt.characterId == seed.characterId
			and receipt.fence == seed.fence
			and receipt.leaseRevision == seed.leaseRevision
			and seed.preparedRevision < Record.MAX_REVISION
			and receipt.committedRevision == seed.preparedRevision + 1
	end

	function Record.matchesTransaction(seedRaw: unknown, candidate: unknown, stored: boolean?): boolean
		local seed = validate(seedRaw, stored)
		local state = candidate :: CreationState
		return seed ~= nil
			and type(state) == "table"
			and seed.userId == state.userId
			and seed.operationId == state.operationId
			and seed.fingerprint == state.fingerprint
			and seed.characterId == state.characterId
			and seed.displayName == state.displayName
			and seed.realmId == state.realmId
			and seed.peopleId == state.peopleId
			and seed.classId == state.classId
			and seed.appearancePresetId == state.appearancePresetId
			and seed.createdAtUnix == state.createdAtUnix
	end

	function Record.seedMatchesReceipt(seedRaw: unknown, receiptRaw: unknown): boolean
		return Record.receiptMatchesSeed(receiptRaw, seedRaw)
	end

	Record.Types = (nil :: unknown) :: { Seed: Seed, Receipt: Receipt }

	return table.freeze(Record)
end

return table.freeze({ create = create })
