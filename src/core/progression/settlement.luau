--!strict
local Run = require("../quest/run")
local Value = require("../internal/value")
type RunState = Run.RunState
type Member = Run.Member
export type RewardReceipt<Q> = {
	requestFingerprint: string,
	runId: string,
	roleId: string,
	itemId: string,
	quality: Q,
	clearNumber: number,
}

export type RewardHistory<Q> = {
	schemaVersion: number,
	expeditionId: string,
	characterId: string,
	revision: number,
	eligibleClears: number,
	receipts: { [string]: RewardReceipt<Q> },
	rewardedRuns: { [string]: string },
}

export type RewardRequest = {
	transactionId: string,
	expectedRevision: number,
	characterId: string,
	roleId: string,
}

export type RewardGrant<Q> = {
	transactionId: string,
	itemId: string,
	quality: Q,
	clearNumber: number,
	roleUpgrade: boolean,
}

export type RewardApplied<S, Q> = {
	ok: true,
	history: RewardHistory<Q>,
	personalState: S,
	reward: RewardGrant<Q>,
	replayed: boolean,
}

export type RewardRejected<S, Q> = {
	ok: false,
	history: RewardHistory<Q>?,
	personalState: S?,
	reason: string,
}

export type RewardResult<S, Q> = RewardApplied<S, Q> | RewardRejected<S, Q>

export type GrantResult<S> = { ok: true, state: S, replayed: boolean } | { ok: false, reason: string }
export type Config<P, S, C, Q> = {
	readPackage: (unknown) -> P?,
	packageId: (P) -> string,
	readRunState: (unknown, P) -> RunState?,
	copyPersonalState: (unknown) -> S?,
	readQuality: (unknown) -> Q?,
	roleUpgrade: (Q) -> boolean,
	knownRole: (P, string) -> boolean,
	rewardForClear: (P, string, number) -> RewardGrant<Q>?,
	hasReceipt: (S, string) -> boolean,
	grant: (S, string, string, C) -> GrantResult<S>,
}
local System = {}
function System.settlement<P, S, C, Q>(config: Config<P, S, C, Q>)
	local SCHEMA_VERSION = 1
	local HISTORY_FIELDS: { [string]: boolean } = {
		schemaVersion = true,
		expeditionId = true,
		characterId = true,
		revision = true,
		eligibleClears = true,
		receipts = true,
		rewardedRuns = true,
	}

	local REWARD_RECEIPT_FIELDS: { [string]: boolean } = {
		requestFingerprint = true,
		runId = true,
		roleId = true,
		itemId = true,
		quality = true,
		clearNumber = true,
	}

	local REWARD_REQUEST_FIELDS: { [string]: boolean } = {
		transactionId = true,
		expectedRevision = true,
		characterId = true,
		roleId = true,
	}

	local Reason = table.freeze({
		invalidPackage = "invalid_package",
		invalidState = "invalid_state",
		invalidEvent = "invalid_event",
		invalidClock = "invalid_clock",
		missingState = "missing_state",
		runAlreadyStarted = "run_already_started",
		receiptConflict = "receipt_conflict",
		revisionConflict = "revision_conflict",
		runNotActive = "run_not_active",
		phaseConflict = "phase_conflict",
		unknownMember = "unknown_member",
		alreadyDisconnected = "already_disconnected",
		alreadyConnected = "already_connected",
		memberDeparted = "member_departed",
		recoveryWindowExpired = "recovery_window_expired",
		leaderDepartureRequired = "leader_departure_required",
		leaderMismatch = "leader_mismatch",
		noConnectedSuccessor = "no_connected_successor",
		wipeRosterMismatch = "wipe_roster_mismatch",
		invalidHistory = "invalid_history",
		invalidPersonalState = "invalid_personal_state",
		invalidRewardRequest = "invalid_reward_request",
		runNotCompleted = "run_not_completed",
		characterNotInRun = "character_not_in_run",
		unknownRole = "unknown_role",
		runAlreadyRewarded = "run_already_rewarded",
		receiptStateMismatch = "receipt_state_mismatch",
		personalTransactionRejected = "personal_transaction_rejected",
	})

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function whole(value: unknown): boolean
		return (type(value) == "number" and finite(value)) and value >= 0 and value == math.floor(value)
	end

	local function nonempty(value: unknown): boolean
		return type(value) == "string" and #value > 0
	end

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" then
			return false
		end
		for key in value do
			if type(key) ~= "string" or not fields[key] then
				return false
			end
		end
		return true
	end

	local function segment(value: string): string
		return ("%d:%s"):format(#value, value)
	end

	local function memberIndex(members: { Member }, memberId: string): number?
		for index, member in members do
			if member.id == memberId then
				return index
			end
		end
		return nil
	end

	local function copyRewardReceipt(value: unknown): RewardReceipt<Q>?
		if not hasOnlyFields(value, REWARD_RECEIPT_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		local quality = config.readQuality(source.quality)
		if
			not (type(source.requestFingerprint) == "string" and nonempty(source.requestFingerprint))
			or not (type(source.runId) == "string" and nonempty(source.runId))
			or not (type(source.roleId) == "string" and nonempty(source.roleId))
			or not (type(source.itemId) == "string" and nonempty(source.itemId))
			or quality == nil
			or not (type(source.clearNumber) == "number" and whole(source.clearNumber))
			or source.clearNumber < 1
		then
			return nil
		end
		return {
			requestFingerprint = source.requestFingerprint,
			runId = source.runId,
			roleId = source.roleId,
			itemId = source.itemId,
			quality = quality,
			clearNumber = source.clearNumber,
		}
	end

	local function copyRewardHistory(value: unknown, package: P): RewardHistory<Q>?
		if not hasOnlyFields(value, HISTORY_FIELDS) then
			return nil
		end
		local source = assert(Value.raw(value))
		if
			source.schemaVersion ~= SCHEMA_VERSION
			or type(source.expeditionId) ~= "string"
			or source.expeditionId ~= config.packageId(package)
			or not (type(source.characterId) == "string" and nonempty(source.characterId))
			or not (type(source.revision) == "number" and whole(source.revision))
			or not (type(source.eligibleClears) == "number" and whole(source.eligibleClears))
			or source.revision ~= source.eligibleClears
			or type(source.receipts) ~= "table"
			or type(source.rewardedRuns) ~= "table"
		then
			return nil
		end
		local receipts: { [string]: RewardReceipt<Q> } = {}
		local clearNumbers: { [number]: boolean } = {}
		local receiptCount = 0
		local eligibleClears = source.eligibleClears
		for transactionId, valueReceipt in source.receipts do
			local receipt = copyRewardReceipt(valueReceipt)
			if
				not (type(transactionId) == "string" and nonempty(transactionId))
				or receipt == nil
				or receipt.clearNumber > eligibleClears
				or clearNumbers[receipt.clearNumber]
			then
				return nil
			end
			local acceptedReceipt = receipt
			local transactionIdString = transactionId
			clearNumbers[acceptedReceipt.clearNumber] = true
			receiptCount += 1
			receipts[transactionIdString] = acceptedReceipt
		end
		if receiptCount ~= source.revision then
			return nil
		end
		local rewardedRuns: { [string]: string } = {}
		local runCount = 0
		for runId, transactionId in source.rewardedRuns do
			local transactionIdString = transactionId
			local receipt = if type(transactionIdString) == "string" then receipts[transactionIdString] else nil
			if
				not (type(runId) == "string" and nonempty(runId))
				or not (type(transactionId) == "string" and nonempty(transactionId))
				or receipt == nil
				or receipt.runId ~= runId
			then
				return nil
			end
			local runIdString = runId
			runCount += 1
			rewardedRuns[runIdString] = transactionId
		end
		if runCount ~= receiptCount then
			return nil
		end
		for clearNumber = 1, eligibleClears do
			if not clearNumbers[clearNumber] then
				return nil
			end
		end
		local expeditionId = source.expeditionId
		local characterId = source.characterId
		local revision = source.revision
		return {
			schemaVersion = SCHEMA_VERSION,
			expeditionId = expeditionId,
			characterId = characterId,
			revision = revision,
			eligibleClears = eligibleClears,
			receipts = receipts,
			rewardedRuns = rewardedRuns,
		}
	end

	local function readRewardRequest(value: unknown): RewardRequest?
		local raw = Value.record(value, REWARD_REQUEST_FIELDS, false, false)
		if raw == nil then
			return nil
		end
		local transactionId, characterId, roleId = raw.transactionId, raw.characterId, raw.roleId
		local revision = Value.whole(raw.expectedRevision, 0, math.huge)
		if
			type(transactionId) ~= "string"
			or transactionId == ""
			or type(characterId) ~= "string"
			or characterId == ""
			or type(roleId) ~= "string"
			or roleId == ""
			or revision == nil
		then
			return nil
		end
		return { transactionId = transactionId, characterId = characterId, roleId = roleId, expectedRevision = revision }
	end

	local function requestFingerprint(runId: string, request: RewardRequest): string
		return segment(runId) .. segment(request.characterId) .. segment(request.roleId)
	end

	local function rewardRejected(history: RewardHistory<Q>?, personalState: S?, reason: string): RewardRejected<S, Q>
		local result: RewardRejected<S, Q> = {
			ok = false,
			history = history,
			personalState = personalState,
			reason = reason,
		}
		return Value.freezeDeep(result)
	end

	local function rewardApplied(
		history: RewardHistory<Q>,
		personalState: S,
		reward: RewardGrant<Q>,
		replayed: boolean
	): RewardResult<S, Q>
		local copied = config.copyPersonalState(personalState)
		local quality = config.readQuality(reward.quality)
		if copied == nil or quality == nil then
			return rewardRejected(history, nil, Reason.invalidPersonalState)
		end
		local ownedReward = table.clone(reward)
		ownedReward.quality = quality
		local result: RewardApplied<S, Q> = {
			ok = true,
			history = history,
			personalState = copied,
			reward = ownedReward,
			replayed = replayed,
		}
		return Value.freezeDeep(result)
	end

	local function applyPersonalReward(
		packageValue: unknown,
		runStateValue: unknown,
		historyValue: unknown,
		personalStateValue: unknown,
		catalogs: C,
		requestValue: unknown
	): RewardResult<S, Q>
		local package = config.readPackage(packageValue)
		if package == nil then
			return rewardRejected(nil, nil, Reason.invalidPackage)
		end
		local runState = config.readRunState(runStateValue, package)
		if runState == nil then
			return rewardRejected(nil, nil, Reason.invalidState)
		end
		local history = copyRewardHistory(historyValue, package)
		if history == nil then
			return rewardRejected(nil, nil, Reason.invalidHistory)
		end
		local personalState = config.copyPersonalState(personalStateValue)
		if personalState == nil then
			return rewardRejected(history, nil, Reason.invalidPersonalState)
		end
		local request = readRewardRequest(requestValue)
		if request == nil then
			return rewardRejected(history, personalState, Reason.invalidRewardRequest)
		end
		if runState.status ~= "completed" then
			return rewardRejected(history, personalState, Reason.runNotCompleted)
		end
		local memberAt = memberIndex(runState.members, request.characterId)
		if history.characterId ~= request.characterId or memberAt == nil then
			return rewardRejected(history, personalState, Reason.characterNotInRun)
		end
		if runState.members[memberAt].departed then
			return rewardRejected(history, personalState, Reason.memberDeparted)
		end
		if not config.knownRole(package, request.roleId) then
			return rewardRejected(history, personalState, Reason.unknownRole)
		end
		local fingerprint = requestFingerprint(runState.runId, request)
		local prior = history.receipts[request.transactionId]
		if prior ~= nil then
			if prior.requestFingerprint ~= fingerprint then
				return rewardRejected(history, personalState, Reason.receiptConflict)
			end
			local transaction = config.grant(personalState, request.transactionId, prior.itemId, catalogs)
			if not transaction.ok or not transaction.replayed then
				return rewardRejected(history, personalState, Reason.receiptStateMismatch)
			end
			return rewardApplied(history, transaction.state, {
				transactionId = request.transactionId,
				itemId = prior.itemId,
				quality = prior.quality,
				clearNumber = prior.clearNumber,
				roleUpgrade = config.roleUpgrade(prior.quality),
			}, true)
		end
		if config.hasReceipt(personalState, request.transactionId) then
			return rewardRejected(history, personalState, Reason.receiptStateMismatch)
		end
		if request.expectedRevision ~= history.revision then
			return rewardRejected(history, personalState, Reason.revisionConflict)
		end
		if history.rewardedRuns[runState.runId] ~= nil then
			return rewardRejected(history, personalState, Reason.runAlreadyRewarded)
		end
		local clearNumber = history.eligibleClears + 1
		local reward = config.rewardForClear(package, request.roleId, clearNumber)
		if reward == nil then
			return rewardRejected(history, personalState, Reason.unknownRole)
		end
		reward.transactionId = request.transactionId
		local transaction = config.grant(personalState, request.transactionId, reward.itemId, catalogs)
		if not transaction.ok then
			return rewardRejected(
				history,
				personalState,
				Reason.personalTransactionRejected .. ":" .. transaction.reason
			)
		end
		if transaction.replayed then
			return rewardRejected(history, personalState, Reason.receiptStateMismatch)
		end
		history.revision += 1
		history.eligibleClears = clearNumber
		history.receipts[request.transactionId] = {
			requestFingerprint = fingerprint,
			runId = runState.runId,
			roleId = request.roleId,
			itemId = reward.itemId,
			quality = reward.quality,
			clearNumber = clearNumber,
		}
		history.rewardedRuns[runState.runId] = request.transactionId
		return rewardApplied(history, transaction.state, reward, false)
	end

	local function emptyRewardHistory(expeditionId: unknown, characterId: unknown): RewardHistory<Q>?
		if
			not (type(expeditionId) == "string" and nonempty(expeditionId))
			or not (type(characterId) == "string" and nonempty(characterId))
		then
			return nil
		end
		local history: RewardHistory<Q> = {
			schemaVersion = SCHEMA_VERSION,
			expeditionId = expeditionId,
			characterId = characterId,
			revision = 0,
			eligibleClears = 0,
			receipts = {},
			rewardedRuns = {},
		}
		return Value.freezeDeep(history)
	end

	return table.freeze({ emptyRewardHistory = emptyRewardHistory, applyPersonalReward = applyPersonalReward })
end
return table.freeze(System)
