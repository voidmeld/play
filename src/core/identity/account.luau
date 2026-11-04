--!strict

local Codec = require("../../kernel/codec")
local Shape = require("../social/shape")
local freeze = require("../social/shape").freezeDeep

local Creation = require("./creation")
local CreationRecord = require("./creation-record")
local Deletion = require("./deletion")
local HasMetatable = require("../../kernel/value")
local Roster = require("./roster")

type CreationState = Creation.State
export type DeletionState = Deletion.State
type Seed = CreationRecord.Seed
type Receipt = CreationRecord.Receipt
type RosterCharacter = Roster.CharacterIdentity
type RosterState = Roster.Roster

export type Base = {
	schemaVersion: number,
	userId: number,
	revision: number,
	roster: RosterState,
	profiles: { Seed },
	pendingProfile: Seed | false,
	activeCreation: CreationState | false,
	activeDeletion: DeletionState | false,
	receipts: { Receipt },
}

export type CreationReceipt = {
	characterId: string,
	displayName: string,
	realmId: string,
	peopleId: string,
	classId: string,
	appearancePresetId: string,
	receipt: Receipt,
}

type Identity = { userId: number, operationId: string, fingerprint: string, characterId: string }

export type Account<E> = Base & E
export type Extension<E> = {
	read fields: { read [string]: boolean },
	read project: (Base, unknown, DeletionState?) -> Account<E>?,
}
local Policy = require("./policy")
local function create<E>(policy: Policy.Policy, extension: Extension<E>)
	type State = Account<E>
	local Creation = Creation.create(policy)
	local CreationRecord = CreationRecord.create(policy)
	local Deletion = Deletion.create(policy)
	local Roster = Roster.create(policy)
	local Aggregate = {}

	Aggregate.SCHEMA_VERSION = 1
	Aggregate.MAX_REVISION = Creation.MAX_REVISION
	Aggregate.MAX_SAFE_INTEGER = Creation.MAX_SAFE_INTEGER
	Aggregate.ACCOUNT_LIMIT = Roster.ACCOUNT_LIMIT

	local FIELDS = {
		schemaVersion = true,
		userId = true,
		revision = true,
		roster = true,
		profiles = true,
		pendingProfile = true,
		activeCreation = true,
		activeDeletion = true,
		receipts = true,
	}

	local whole = Shape.whole

	local function noMetatables(value: unknown, seen: { [unknown]: boolean }): boolean
		if type(value) ~= "table" then
			return true
		end
		if HasMetatable.hasMetatable(value) or seen[value] then
			return false
		end
		seen[value] = true
		for key, child in value do
			if not noMetatables(key, seen) or not noMetatables(child, seen) then
				return false
			end
		end
		return true
	end

	local function exact(raw: unknown): boolean
		if type(raw) ~= "table" or HasMetatable.hasMetatable(raw) then
			return false
		end
		local view = assert(HasMetatable.raw(raw))
		for key in view do
			if type(key) ~= "string" or (FIELDS[key] ~= true and extension.fields[key] ~= true) then
				return false
			end
		end
		for key in FIELDS do
			if view[key] == nil then
				return false
			end
		end
		return true
	end

	local sameValue = Codec.equalData

	local function dense(raw: unknown): number?
		if type(raw) ~= "table" or HasMetatable.hasMetatable(raw) then
			return nil
		end
		local view = assert(HasMetatable.raw(raw))
		local count = 0
		for key in view do
			if not whole(key, 1, Aggregate.ACCOUNT_LIMIT) then
				return nil
			end
			count += 1
		end
		for index = 1, count do
			if view[index] == nil then
				return nil
			end
		end
		return count
	end

	local function frozenCharacter(raw: RosterCharacter): RosterCharacter
		local result: RosterCharacter = {
			characterId = raw.characterId,
			displayName = raw.displayName,
			realmId = raw.realmId,
			peopleId = raw.peopleId,
			classId = raw.classId,
			appearancePresetId = raw.appearancePresetId,
			createdAtUnix = raw.createdAtUnix,
			lastPlayedAtUnix = raw.lastPlayedAtUnix,
			level = raw.level,
			lastDestinationId = raw.lastDestinationId,
		}
		freeze(result)
		return result
	end

	local function frozenRoster(raw: RosterState): RosterState
		local characters: { RosterCharacter } = {}
		for index, character in raw.characters do
			characters[index] = frozenCharacter(character)
		end
		local result: RosterState = {
			schemaVersion = Roster.SCHEMA_VERSION,
			userId = raw.userId,
			characters = freeze(characters),
		}
		freeze(result)
		return result
	end

	local function sameCharacter(profile: Seed, character: RosterCharacter): boolean
		return profile.characterId == character.characterId
			and profile.displayName == character.displayName
			and profile.realmId == character.realmId
			and profile.peopleId == character.peopleId
			and profile.classId == character.classId
			and profile.appearancePresetId == character.appearancePresetId
			and profile.createdAtUnix == character.createdAtUnix
			and character.lastPlayedAtUnix >= character.createdAtUnix
	end

	local function matchesIdentity(profile: Seed, state: CreationState, stored: boolean?): boolean
		return CreationRecord.matchesTransaction(profile, state, stored)
	end

	local function committedIndex(
		profiles: { Seed },
		receipts: { Receipt },
		state: CreationState,
		stored: boolean?
	): number?
		for index, profile in profiles do
			local receipt = receipts[index]
			if
				matchesIdentity(profile, state, stored)
				and CreationRecord.receiptMatchesSeed(receipt, profile, stored)
				and state.fence >= receipt.fence
				and (
					(state.phase == "committed" and state.revision >= receipt.committedRevision)
					or (state.phase == "lease_released" and state.revision > receipt.committedRevision)
				)
			then
				return index
			end
		end
		return nil
	end

	local function sameIdentity(left: Identity, right: Identity): boolean
		return left.userId == right.userId
			and left.operationId == right.operationId
			and left.fingerprint == right.fingerprint
			and left.characterId == right.characterId
	end

	function Aggregate.transition(raw: unknown, nextRaw: unknown): (State?, string?)
		local current = Aggregate.validate(raw)
		local nextState = Creation.validate(nextRaw)
		if current == nil or nextState == nil or current.userId ~= nextState.userId then
			return nil, "transition_invalid"
		end
		local active = current.activeCreation
		if type(active) ~= "table" then
			if current.activeDeletion ~= false then
				return nil, "deletion_in_progress"
			end
			if nextState.phase ~= "prepared" or nextState.revision ~= 0 then
				return nil, "transition_order"
			end
		else
			if not sameIdentity(active, nextState) or nextState.revision ~= active.revision + 1 then
				return nil, "transition_stale"
			end
		end
		local roster = current.roster
		local profiles = table.clone(current.profiles)
		local receipts = table.clone(current.receipts)
		local pending: Seed | false = false
		if nextState.phase == "profile_prepared" then
			local prepared = CreationRecord.fromTransaction(nextState)
			if prepared == nil then
				return nil, "transition_invalid"
			end
			pending = prepared
		elseif nextState.phase == "committed" and (type(active) ~= "table" or active.phase ~= "committed") then
			local seed = current.pendingProfile
			local receipt =
				CreationRecord.receiptFromTransaction(if nextState.phase == "committed" then nextState else active)
			if type(seed) ~= "table" or receipt == nil or not matchesIdentity(seed, nextState) then
				return nil, "transition_order"
			end
			local ok, appended = pcall(Roster.add, roster, {
				characterId = seed.characterId,
				displayName = seed.displayName,
				realmId = seed.realmId,
				peopleId = seed.peopleId,
				classId = seed.classId,
				appearancePresetId = seed.appearancePresetId,
				createdAtUnix = seed.createdAtUnix,
				lastPlayedAtUnix = seed.createdAtUnix,
				level = Roster.MIN_LEVEL,
				lastDestinationId = Roster.NEVER_DEPARTED,
			})
			if not ok then
				return nil, "roster_conflict"
			end
			roster = appended
			profiles[#profiles + 1] = seed
			receipts[#receipts + 1] = receipt
		elseif nextState.phase == "lease_released" then
			if (active).phase ~= "committed" then
				return nil, "transition_order"
			end
		elseif
			nextState.phase ~= "prepared"
			and nextState.phase ~= "name_owned"
			and nextState.phase ~= "rolling_back"
			and nextState.phase ~= "aborted"
			and not (nextState.phase == "committed" and type(active) == "table" and active.phase == "committed")
		then
			return nil, "transition_order"
		end
		local value = Aggregate.validate(extension.project({
			schemaVersion = Aggregate.SCHEMA_VERSION,
			userId = current.userId,
			revision = current.revision + 1,
			roster = roster,
			profiles = profiles,
			pendingProfile = pending,
			activeCreation = nextState,
			activeDeletion = false,
			receipts = receipts,
		}, current))
		if value == nil then
			return nil, "transition_invalid"
		end
		return value, nil
	end

	local function withoutCharacter(current: State, characterId: string): (RosterState?, { Seed }?, { Receipt }?)
		local removedIndex: number? = nil
		for index, character in current.roster.characters do
			if character.characterId == characterId then
				removedIndex = index
				break
			end
		end
		if removedIndex == nil then
			return nil, nil, nil
		end
		local characters: { RosterCharacter } = {}
		local profiles: { Seed } = {}
		local receipts: { Receipt } = {}
		for index, character in current.roster.characters do
			if index ~= removedIndex then
				characters[#characters + 1] = character
				profiles[#profiles + 1] = current.profiles[index]
				receipts[#receipts + 1] = current.receipts[index]
			end
		end
		local roster = { schemaVersion = Roster.SCHEMA_VERSION, userId = current.userId, characters = characters }
		return roster, profiles, receipts
	end

	function Aggregate.transitionDeletion(raw: unknown, nextRaw: unknown): (State?, string?)
		local current = Aggregate.validateStored(raw)
		local nextState = Deletion.validate(nextRaw)
		if current == nil or nextState == nil or current.userId ~= nextState.userId then
			return nil, "transition_invalid"
		end
		local active = current.activeDeletion
		if type(active) ~= "table" then
			if current.activeCreation ~= false then
				return nil, "creation_in_progress"
			end
			if nextState.phase ~= "prepared" or nextState.revision ~= 0 then
				return nil, "transition_order"
			end
		else
			if not sameIdentity(active, nextState) or nextState.revision ~= active.revision + 1 then
				return nil, "transition_stale"
			end
		end
		local roster = current.roster
		local profiles = table.clone(current.profiles)
		local receipts = table.clone(current.receipts)
		if nextState.phase == "roster_removed" and type(active) == "table" and active.phase == "prepared" then
			local removedRoster, removedProfiles, removedReceipts = withoutCharacter(current, nextState.characterId)
			if removedRoster == nil or removedProfiles == nil or removedReceipts == nil then
				return nil, "transition_order"
			end
			roster = removedRoster
			profiles = removedProfiles
			receipts = removedReceipts
		end
		local value = Aggregate.validateStored(extension.project({
			schemaVersion = Aggregate.SCHEMA_VERSION,
			userId = current.userId,
			revision = current.revision + 1,
			roster = roster,
			profiles = profiles,
			pendingProfile = false,
			activeCreation = false,
			activeDeletion = nextState,
			receipts = receipts,
		}, current))
		if value == nil then
			return nil, "transition_invalid"
		end
		return value, nil
	end

	function Aggregate.clearDeletionTerminal(raw: unknown): (State?, string?)
		local current = Aggregate.validateStored(raw)
		if current == nil then
			return nil, "aggregate_invalid"
		end
		local active = current.activeDeletion
		if type(active) ~= "table" or (active.phase ~= "lease_released" and active.phase ~= "aborted") then
			return nil, "terminal_required"
		end
		if current.revision >= Aggregate.MAX_REVISION then
			return nil, "revision_exhausted"
		end
		local value = Aggregate.validateStored(extension.project({
			schemaVersion = Aggregate.SCHEMA_VERSION,
			userId = current.userId,
			revision = current.revision + 1,
			roster = current.roster,
			profiles = current.profiles,
			pendingProfile = false,
			activeCreation = false,
			activeDeletion = false,
			receipts = current.receipts,
		}, current, active))
		if value == nil then
			return nil, "aggregate_invalid"
		end
		return value, nil
	end

	local function validate(candidate: unknown, stored: boolean?): State?
		if not noMetatables(candidate, {}) or not exact(candidate) then
			return nil
		end
		local raw = assert(HasMetatable.raw(candidate))
		local userId, revision = raw.userId, raw.revision
		if
			raw.schemaVersion ~= Aggregate.SCHEMA_VERSION
			or type(userId) ~= "number"
			or not whole(userId, 1, Aggregate.MAX_SAFE_INTEGER)
			or type(revision) ~= "number"
			or not whole(revision, 0, Aggregate.MAX_REVISION)
		then
			return nil
		end
		local rosterOk, roster = pcall(if stored == true then Roster.validateStored else Roster.validate, raw.roster)
		if not rosterOk or roster.userId ~= raw.userId then
			return nil
		end
		for _, character in roster.characters do
			if not whole(character.lastPlayedAtUnix, 0, Aggregate.MAX_SAFE_INTEGER) then
				return nil
			end
		end
		local rawProfiles = HasMetatable.raw(raw.profiles)
		local rawReceipts = HasMetatable.raw(raw.receipts)
		local profileCount = dense(raw.profiles)
		local receiptCount = dense(raw.receipts)
		if
			rawProfiles == nil
			or rawReceipts == nil
			or profileCount == nil
			or receiptCount == nil
			or profileCount ~= #roster.characters
			or receiptCount ~= profileCount
		then
			return nil
		end
		local profiles: { Seed } = {}
		local receipts: { Receipt } = {}
		local characterIds: { [string]: boolean } = {}
		local operationIds: { [string]: boolean } = {}
		local fingerprints: { [string]: boolean } = {}
		for index = 1, profileCount do
			local profile = if stored == true
				then CreationRecord.validateStored(rawProfiles[index])
				else CreationRecord.validate(rawProfiles[index])
			local receipt = CreationRecord.validateReceipt(rawReceipts[index])
			if
				profile == nil
				or receipt == nil
				or profile.userId ~= raw.userId
				or not sameCharacter(profile, roster.characters[index])
				or not CreationRecord.receiptMatchesSeed(receipt, profile, stored)
				or characterIds[profile.characterId]
				or operationIds[profile.operationId]
				or fingerprints[profile.fingerprint]
			then
				return nil
			end
			characterIds[profile.characterId] = true
			operationIds[profile.operationId] = true
			fingerprints[profile.fingerprint] = true
			profiles[index] = profile
			receipts[index] = receipt
		end
		local pending: Seed | false = false
		if raw.pendingProfile ~= false then
			local seed = if stored == true
				then CreationRecord.validateStored(raw.pendingProfile)
				else CreationRecord.validate(raw.pendingProfile)
			if
				seed == nil
				or seed.userId ~= raw.userId
				or characterIds[seed.characterId]
				or operationIds[seed.operationId]
				or fingerprints[seed.fingerprint]
			then
				return nil
			end
			pending = seed
		end
		local active: CreationState | false = false
		if raw.activeCreation ~= false then
			local created = if stored == true
				then Creation.validateStored(raw.activeCreation)
				else Creation.validate(raw.activeCreation)
			if created == nil or created.userId ~= raw.userId then
				return nil
			end
			active = created
		end
		if type(active) ~= "table" then
			if type(pending) == "table" then
				return nil
			end
		elseif active.phase == "prepared" or active.phase == "name_owned" or active.phase == "aborted" then
			if
				type(pending) == "table"
				or characterIds[active.characterId]
				or operationIds[active.operationId]
				or fingerprints[active.fingerprint]
			then
				return nil
			end
		elseif active.phase == "profile_prepared" then
			if
				type(pending) ~= "table"
				or not matchesIdentity(pending, active, stored)
				or pending.preparedRevision ~= active.revision
				or pending.fence ~= active.initialFence
			then
				return nil
			end
		elseif active.phase == "rolling_back" then
			if
				type(pending) == "table"
				and (
					not matchesIdentity(pending, active, stored)
					or pending.preparedRevision >= active.revision
					or pending.fence > active.fence
				)
			then
				return nil
			end
			if
				characterIds[active.characterId]
				or operationIds[active.operationId]
				or fingerprints[active.fingerprint]
			then
				return nil
			end
		elseif active.phase == "committed" or active.phase == "lease_released" then
			if type(pending) == "table" or committedIndex(profiles, receipts, active, stored) == nil then
				return nil
			end
		else
			return nil
		end
		local deletion: DeletionState | false = false
		if raw.activeDeletion ~= false then
			local removal = Deletion.validate(raw.activeDeletion)
			if removal == nil or removal.userId ~= raw.userId then
				return nil
			end
			if type(active) == "table" or type(pending) == "table" then
				return nil
			end
			if operationIds[removal.operationId] or fingerprints[removal.fingerprint] then
				return nil
			end
			deletion = removal
			local present: RosterCharacter? = nil
			for _, character in roster.characters do
				if character.characterId == removal.characterId then
					present = character
					break
				end
			end
			if removal.phase == "prepared" or removal.phase == "rolling_back" or removal.phase == "aborted" then
				if present == nil or present.displayName ~= removal.displayName then
					return nil
				end
			elseif present ~= nil then
				return nil
			end
		end
		local account: Base = {
			schemaVersion = Aggregate.SCHEMA_VERSION,
			userId = userId,
			revision = revision,
			roster = frozenRoster(roster),
			profiles = freeze(profiles),
			pendingProfile = pending,
			activeCreation = if type(active) ~= "table" then false else freeze(active),
			activeDeletion = if type(deletion) ~= "table" then false else freeze(deletion),
			receipts = freeze(receipts),
		}
		local extended = extension.project(account, candidate)
		return if extended == nil then nil else freeze(extended)
	end

	function Aggregate.validate(candidate: unknown): State?
		return validate(candidate)
	end

	function Aggregate.validateStored(candidate: unknown): State?
		return validate(candidate, true)
	end

	function Aggregate.copy(raw: unknown): State?
		return Aggregate.validate(raw)
	end

	function Aggregate.clearTerminal(raw: unknown): (State?, string?)
		local current = Aggregate.validate(raw)
		if current == nil then
			return nil, "aggregate_invalid"
		end
		local active = current.activeCreation
		if type(active) ~= "table" or (active.phase ~= "lease_released" and active.phase ~= "aborted") then
			return nil, "terminal_required"
		end
		if current.revision >= Aggregate.MAX_REVISION then
			return nil, "revision_exhausted"
		end
		local value = Aggregate.validate(extension.project({
			schemaVersion = Aggregate.SCHEMA_VERSION,
			userId = current.userId,
			revision = current.revision + 1,
			roster = current.roster,
			profiles = current.profiles,
			pendingProfile = false,
			activeCreation = false,
			activeDeletion = current.activeDeletion,
			receipts = current.receipts,
		}, current))
		if value == nil then
			return nil, "aggregate_invalid"
		end
		return value, nil
	end

	function Aggregate.removeCharacter(raw: unknown, characterId: unknown): (State?, string?)
		local current = Aggregate.validate(raw)
		if current == nil then
			return nil, "aggregate_invalid"
		end
		if type(characterId) ~= "string" or #characterId == 0 then
			return nil, "character_invalid"
		end
		if current.activeCreation ~= false then
			return nil, "creation_in_progress"
		end
		if current.activeDeletion ~= false then
			return nil, "deletion_in_progress"
		end
		if current.revision >= Aggregate.MAX_REVISION then
			return nil, "revision_exhausted"
		end
		local roster, profiles, receipts = withoutCharacter(current, characterId)
		if roster == nil or profiles == nil or receipts == nil then
			return nil, "character_absent"
		end
		local value = Aggregate.validate(extension.project({
			schemaVersion = Aggregate.SCHEMA_VERSION,
			userId = current.userId,
			revision = current.revision + 1,
			roster = roster,
			profiles = profiles,
			pendingProfile = false,
			activeCreation = false,
			activeDeletion = false,
			receipts = receipts,
		}, current))
		if value == nil then
			return nil, "aggregate_invalid"
		end
		return value, nil
	end

	local function markedRoster(
		raw: unknown,
		characterId: unknown,
		mark: (unknown, unknown, unknown) -> RosterState,
		value: unknown
	): (State?, string?)
		local current = Aggregate.validate(raw)
		if current == nil then
			return nil, "aggregate_invalid"
		end
		if type(characterId) ~= "string" or #characterId == 0 then
			return nil, "character_invalid"
		end
		local present = false
		for _, character in current.roster.characters do
			if character.characterId == characterId then
				present = true
			end
		end
		if not present then
			return nil, "character_absent"
		end
		if current.revision >= Aggregate.MAX_REVISION then
			return nil, "revision_exhausted"
		end
		local ok, roster = pcall(mark, current.roster, characterId, value)
		if not ok then
			return nil, "card_refused"
		end
		local marked = Aggregate.validate(extension.project({
			schemaVersion = Aggregate.SCHEMA_VERSION,
			userId = current.userId,
			revision = current.revision + 1,
			roster = roster,
			profiles = current.profiles,
			pendingProfile = current.pendingProfile,
			activeCreation = current.activeCreation,
			activeDeletion = current.activeDeletion,
			receipts = current.receipts,
		}, current))
		if marked == nil then
			return nil, "aggregate_invalid"
		end
		return marked, nil
	end

	function Aggregate.markCharacterLevel(raw: unknown, characterId: unknown, level: unknown): (State?, string?)
		return markedRoster(raw, characterId, Roster.markLevel, level)
	end

	function Aggregate.markCharacterDeparted(
		raw: unknown,
		characterId: unknown,
		destinationId: unknown
	): (State?, string?)
		return markedRoster(raw, characterId, Roster.markDeparted, destinationId)
	end

	function Aggregate.markCharacterPlayed(raw: unknown, characterId: unknown, playedAtUnix: unknown): (State?, string?)
		return markedRoster(raw, characterId, Roster.markPlayed, playedAtUnix)
	end

	function Aggregate.characterCard(raw: unknown, characterId: unknown): RosterCharacter?
		local current = Aggregate.validate(raw)
		if current == nil or type(characterId) ~= "string" then
			return nil
		end
		for _, character in current.roster.characters do
			if character.characterId == characterId then
				return character
			end
		end
		return nil
	end

	function Aggregate.receiptFor(raw: unknown, candidate: unknown): CreationReceipt?
		local current = Aggregate.validate(raw)
		if current == nil or type(candidate) ~= "table" then
			return nil
		end
		local request = assert(HasMetatable.raw(candidate))
		for index, profile in current.profiles do
			if
				profile.displayName == request.displayName
				and profile.realmId == request.realmId
				and profile.peopleId == request.peopleId
				and profile.classId == request.classId
				and profile.appearancePresetId == request.appearancePresetId
			then
				local receipt = CreationRecord.copyReceipt(current.receipts[index])
				if receipt ~= nil and receipt.characterId == profile.characterId then
					local result: CreationReceipt = {
						characterId = profile.characterId,
						displayName = profile.displayName,
						realmId = profile.realmId,
						peopleId = profile.peopleId,
						classId = profile.classId,
						appearancePresetId = profile.appearancePresetId,
						receipt = receipt,
					}
					freeze(result)
					return result
				end
			end
		end
		return nil
	end

	function Aggregate.equal(leftRaw: unknown, rightRaw: unknown): boolean
		local left = Aggregate.validate(leftRaw)
		local right = Aggregate.validate(rightRaw)
		return left ~= nil and right ~= nil and sameValue(left, right)
	end

	function Aggregate.equalStored(leftRaw: unknown, rightRaw: unknown): boolean
		local left = Aggregate.validateStored(leftRaw)
		local right = Aggregate.validateStored(rightRaw)
		return left ~= nil and right ~= nil and sameValue(left, right)
	end

	function Aggregate.empty(userId: unknown): State?
		if not whole(userId, 1, Aggregate.MAX_SAFE_INTEGER) then
			return nil
		end
		return Aggregate.validate({
			schemaVersion = Aggregate.SCHEMA_VERSION,
			userId = userId,
			revision = 0,
			roster = { schemaVersion = Roster.SCHEMA_VERSION, userId = userId, characters = {} },
			profiles = {},
			pendingProfile = false,
			activeCreation = false,
			activeDeletion = false,
			receipts = {},
		})
	end

	return freeze(Aggregate)
end
return table.freeze({ create = create })
