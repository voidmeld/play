--!strict

local Creation = require("./creation")
local HasMetatable = require("./value")
local Policy = require("./policy")
local Roster = require("./roster")
local Value = require("../value")

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

	local SEED_FIELDS: { [string]: boolean } = {
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

	local RECEIPT_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		userId = true,
		operationId = true,
		fingerprint = true,
		characterId = true,
		committedRevision = true,
		fence = true,
		leaseRevision = true,
	}

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
		return Value.freezeDeep(value)
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
		return Value.freezeDeep(value)
	end

	local function validate(candidate: unknown, stored: boolean?): Seed?
		local raw = Value.record(candidate, SEED_FIELDS, true)
		if raw == nil or raw.schemaVersion ~= Record.SCHEMA_VERSION then
			return nil
		end
		local userId = Value.whole(raw.userId, 1, Record.MAX_SAFE_INTEGER)
		local createdAtUnix = Value.whole(raw.createdAtUnix, 0, Record.MAX_SAFE_INTEGER)
		local preparedRevision = Value.whole(raw.preparedRevision, 0, Record.MAX_REVISION)
		local fence = Value.whole(raw.fence, 1, Record.MAX_FENCE)
		local leaseRevision = Value.whole(raw.leaseRevision, 1, Record.MAX_REVISION)
		local operationId = Value.opaque(raw.operationId, Record.MAX_ID_BYTES)
		local characterId = Value.opaque(raw.characterId, Record.MAX_ID_BYTES)
		local realmId = Value.opaque(raw.realmId, Record.MAX_ID_BYTES)
		local peopleId = Value.opaque(raw.peopleId, Record.MAX_ID_BYTES)
		local classId = Value.opaque(raw.classId, Record.MAX_ID_BYTES)
		local appearance = Value.opaque(raw.appearancePresetId, Record.MAX_ID_BYTES)
		local displayName, fingerprint = raw.displayName, raw.fingerprint
		if
			userId == nil
			or createdAtUnix == nil
			or preparedRevision == nil
			or fence == nil
			or leaseRevision == nil
			or operationId == nil
			or characterId == nil
			or realmId == nil
			or peopleId == nil
			or classId == nil
			or appearance == nil
			or type(displayName) ~= "string"
			or type(fingerprint) ~= "string"
		then
			return nil
		end
		local seed: Seed = {
			schemaVersion = Record.SCHEMA_VERSION,
			userId = userId,
			operationId = operationId,
			characterId = characterId,
			realmId = realmId,
			peopleId = peopleId,
			classId = classId,
			appearancePresetId = appearance,
			displayName = displayName,
			fingerprint = fingerprint,
			createdAtUnix = createdAtUnix,
			preparedRevision = preparedRevision,
			fence = fence,
			leaseRevision = leaseRevision,
		}
		if creation.fingerprint(seed) ~= fingerprint then
			return nil
		end
		local ok = pcall(if stored == true then rosterRules.validateStored else rosterRules.validate, {
			schemaVersion = rosterRules.SCHEMA_VERSION,
			userId = userId,
			characters = { character(seed) },
		})
		return if ok then frozenSeed(seed) else nil
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
		local raw = Value.record(candidate, RECEIPT_FIELDS, true)
		if raw == nil or raw.schemaVersion ~= Record.SCHEMA_VERSION then
			return nil
		end
		local userId = Value.whole(raw.userId, 1, Record.MAX_SAFE_INTEGER)
		local committedRevision = Value.whole(raw.committedRevision, 0, Record.MAX_REVISION)
		local fence = Value.whole(raw.fence, 1, Record.MAX_FENCE)
		local leaseRevision = Value.whole(raw.leaseRevision, 1, Record.MAX_REVISION)
		local operationId = Value.opaque(raw.operationId, Record.MAX_ID_BYTES)
		local characterId = Value.opaque(raw.characterId, Record.MAX_ID_BYTES)
		local fingerprint = Value.opaque(raw.fingerprint, Record.MAX_FINGERPRINT_BYTES)
		if
			userId == nil
			or committedRevision == nil
			or fence == nil
			or leaseRevision == nil
			or operationId == nil
			or characterId == nil
			or fingerprint == nil
		then
			return nil
		end
		local receipt: Receipt = {
			schemaVersion = Record.SCHEMA_VERSION,
			userId = userId,
			committedRevision = committedRevision,
			fence = fence,
			leaseRevision = leaseRevision,
			operationId = operationId,
			characterId = characterId,
			fingerprint = fingerprint,
		}
		return frozenReceipt(receipt)
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
		local state = Value.raw(candidate)
		return seed ~= nil
			and state ~= nil
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

	return table.freeze(Record)
end

return table.freeze({ create = create })
