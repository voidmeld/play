--!strict
local Run = require("./run")
local Value = require("../../kernel/value")
type Raw = { [unknown]: unknown }
type RunState = Run.RunState
type RunMember = Run.Member
export type Invitation = {
	userId: number,
	priorId: string,
	leaderUserId: number?,
	expectedRevision: number,
	recoveryWindowSec: number,
	realmId: string?,
	entryLevel: number?,
	roleId: string?,
}
export type ReplacementIdentity = { userId: number, priorId: string, leaderUserId: number }

export type Member = {
	userId: number,
	characterId: string,
}

export type Record = {
	schemaVersion: number,
	runId: string,
	packageId: string,
	placeId: number,
	accessCode: string,
	privateServerId: string,
	partyId: string,
	leaderUserId: number,
	request: Raw,
	rows: Raw,
	members: { Member },
	createdAtSec: number,
	expiresAtSec: number,
	stateRevision: number,
	runState: Raw?,
	replacementInvitation: Raw?,
	status: "reserved" | "active" | "closed",
	claimedByJobId: string?,
	claimedAtSec: number?,
}

export type Target = {
	placeId: number,
	accessCode: string,
	privateServerId: string,
	runId: string,
}

export type Transform = (unknown) -> Record?

export type Config = {
	recordTtlSec: number,
	claimLeaseSec: number,
	carrierContract: string,
	memberCount: number,
	maxText: number,
	retryDelaysSec: { number },
}
local System = {}
function System.claims(config: Config)
	local SCHEMA_VERSION = 1
	local RECORD_TTL_SEC = config.recordTtlSec
	local CLAIM_LEASE_SEC = config.claimLeaseSec
	local CARRIER_CONTRACT = config.carrierContract
	local RETRY_DELAYS_SEC = config.retryDelaysSec
	local MAX_TEXT = config.maxText
	local MAX_SAFE_INTEGER = 9007199254740991
	local Core = {}
	local function text(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_TEXT
	end

	local function positiveInteger(value: unknown): boolean
		return type(value) == "number"
			and value == value
			and value >= 1
			and value <= MAX_SAFE_INTEGER
			and value == math.floor(value)
	end

	local function instant(value: unknown): boolean
		return type(value) == "number" and value == value and value >= 0 and value <= MAX_SAFE_INTEGER
	end

	local function copyValue(value: unknown): unknown
		local raw = Value.raw(value)
		if raw == nil then
			return value
		end
		local result: Raw = {}
		for key, child in raw do
			result[copyValue(key)] = copyValue(child)
		end
		return table.freeze(result)
	end
	local function copyRaw(value: Raw): Raw
		local result: Raw = {}
		for key, child in value do
			result[copyValue(key)] = copyValue(child)
		end
		return table.freeze(result)
	end
	local function copyRecord(value: Record): Record
		local members: { Member } = {}
		for _, member in value.members do
			local copy: Member = { userId = member.userId, characterId = member.characterId }
			table.insert(members, Value.freezeDeep(copy))
		end
		local record: Record = {
			schemaVersion = value.schemaVersion,
			runId = value.runId,
			packageId = value.packageId,
			placeId = value.placeId,
			accessCode = value.accessCode,
			privateServerId = value.privateServerId,
			partyId = value.partyId,
			leaderUserId = value.leaderUserId,
			request = copyRaw(value.request),
			rows = copyRaw(value.rows),
			members = Value.freezeDeep(members),
			createdAtSec = value.createdAtSec,
			expiresAtSec = value.expiresAtSec,
			stateRevision = value.stateRevision,
			status = value.status,
			runState = if value.runState == nil then nil else copyRaw(value.runState),
			replacementInvitation = if value.replacementInvitation == nil
				then nil
				else copyRaw(value.replacementInvitation),
			claimedByJobId = value.claimedByJobId,
			claimedAtSec = value.claimedAtSec,
		}
		return Value.freezeDeep(record)
	end

	function Core.runKey(runId: string): string
		return "run:" .. runId
	end

	function Core.userKey(userId: number): string
		return ("user:%d"):format(userId)
	end

	function Core.serverKey(privateServerId: string): string
		return "server:" .. privateServerId
	end

	function Core.isReservedServer(privateServerId: unknown, privateServerOwnerId: unknown): boolean
		return (type(privateServerId) == "string" and text(privateServerId)) and privateServerOwnerId == 0
	end

	function Core.retryDelaysSec(): { number }
		return table.clone(RETRY_DELAYS_SEC)
	end

	local function validMembers(value: unknown): { Member }?
		local rows = Value.raw(value)
		if rows == nil or type(value) ~= "table" or #value < 1 then
			return nil
		end
		local seen: { [number]: boolean } = {}
		local characters: { [string]: boolean } = {}
		local members: { Member } = {}
		for _, candidate in rows do
			local row = Value.raw(candidate)
			if row == nil then
				return nil
			end
			local userId, characterId = row.userId, row.characterId
			if
				type(userId) ~= "number"
				or not (type(userId) == "number" and positiveInteger(userId))
				or type(characterId) ~= "string"
				or not (type(characterId) == "string" and text(characterId))
				or seen[userId]
				or characters[characterId]
			then
				return nil
			end
			seen[userId] = true
			characters[characterId] = true
			table.insert(members, { userId = userId, characterId = characterId })
		end
		return members
	end

	function Core.readRecord(value: unknown): Record?
		local raw = Value.raw(value)
		if raw == nil then
			return nil
		end
		local runId, packageId, accessCode, privateServerId, partyId =
			raw.runId, raw.packageId, raw.accessCode, raw.privateServerId, raw.partyId
		local placeId, leaderUserId, created, expires, revision =
			raw.placeId, raw.leaderUserId, raw.createdAtSec, raw.expiresAtSec, raw.stateRevision
		local status, job, claimed = raw.status, raw.claimedByJobId, raw.claimedAtSec
		local request, rows = Value.raw(raw.request), Value.raw(raw.rows)
		local members = validMembers(raw.members)
		local runState, invitation = Value.raw(raw.runState), Value.raw(raw.replacementInvitation)
		if
			raw.schemaVersion ~= SCHEMA_VERSION
			or type(runId) ~= "string"
			or not (type(runId) == "string" and text(runId))
			or type(packageId) ~= "string"
			or not (type(packageId) == "string" and text(packageId))
			or type(accessCode) ~= "string"
			or not (type(accessCode) == "string" and text(accessCode))
			or type(privateServerId) ~= "string"
			or not (type(privateServerId) == "string" and text(privateServerId))
			or type(partyId) ~= "string"
			or not (type(partyId) == "string" and text(partyId))
			or type(placeId) ~= "number"
			or not (type(placeId) == "number" and positiveInteger(placeId))
			or type(leaderUserId) ~= "number"
			or not (type(leaderUserId) == "number" and positiveInteger(leaderUserId))
			or type(created) ~= "number"
			or not (type(created) == "number" and instant(created))
			or type(expires) ~= "number"
			or not (type(expires) == "number" and instant(expires))
			or type(revision) ~= "number"
			or request == nil
			or rows == nil
			or members == nil
			or (raw.runState ~= nil and runState == nil)
			or (raw.replacementInvitation ~= nil and invitation == nil)
			or (job ~= nil and type(job) ~= "string")
			or (claimed ~= nil and type(claimed) ~= "number")
			or (status ~= "reserved" and status ~= "active" and status ~= "closed")
		then
			return nil
		end
		return {
			schemaVersion = SCHEMA_VERSION,
			runId = runId,
			packageId = packageId,
			accessCode = accessCode,
			privateServerId = privateServerId,
			partyId = partyId,
			placeId = placeId,
			leaderUserId = leaderUserId,
			createdAtSec = created,
			expiresAtSec = expires,
			stateRevision = revision,
			request = request,
			rows = rows,
			members = members,
			runState = runState,
			replacementInvitation = invitation,
			status = status,
			claimedByJobId = job,
			claimedAtSec = claimed,
		}
	end

	function Core.validRecord(value: unknown): boolean
		return Core.readRecord(value) ~= nil
	end

	function Core.newRecord(input: unknown, nowSec: number): (Record?, string?)
		local raw = Value.raw(input)
		if raw == nil or not (type(nowSec) == "number" and instant(nowSec)) then
			return nil, "record_invalid"
		end
		local state = Value.raw(raw.runState)
		if state == nil or state.runId ~= raw.runId or type(state.revision) ~= "number" or state.revision < 1 then
			return nil, "record_invalid"
		end
		local record = Core.readRecord({
			schemaVersion = SCHEMA_VERSION,
			runId = raw.runId,
			packageId = raw.packageId,
			placeId = raw.placeId,
			accessCode = raw.accessCode,
			privateServerId = raw.privateServerId,
			partyId = raw.partyId,
			leaderUserId = raw.leaderUserId,
			request = raw.request,
			rows = raw.rows,
			members = raw.members,
			createdAtSec = nowSec,
			expiresAtSec = nowSec + RECORD_TTL_SEC,
			stateRevision = state.revision,
			runState = state,
			status = "reserved",
		})
		if record == nil then
			return nil, "record_invalid"
		end
		for _, member in record.members do
			if member.userId == record.leaderUserId then
				return copyRecord(record), nil
			end
		end
		return nil, "record_invalid"
	end

	function Core.readReplacementIdentity(value: unknown): ReplacementIdentity?
		if type(value) ~= "table" then
			return nil
		end
		local row = assert(Value.raw(value))
		if type(row.userId) ~= "number" or type(row.priorId) ~= "string" or type(row.leaderUserId) ~= "number" then
			return nil
		end
		return {
			userId = row.userId,
			priorId = row.priorId,
			leaderUserId = row.leaderUserId,
		}
	end

	function Core.createTransform(record: Record): Transform
		return function(currentValue: unknown): Record?
			if currentValue ~= nil then
				return nil
			end
			return record
		end
	end

	local function claimHeld(current: Record, jobId: string, nowSec: number): boolean
		return current.claimedByJobId == jobId and nowSec <= (current.claimedAtSec or 0) + CLAIM_LEASE_SEC
	end

	function Core.claimTransform(privateServerId: string, jobId: string, nowSec: number): Transform
		return function(currentValue: unknown): Record?
			local current = Core.readRecord(currentValue)
			if
				current == nil
				or (current).privateServerId ~= privateServerId
				or (current).status == "closed"
				or not (type(jobId) == "string" and text(jobId))
				or (
					(current).claimedByJobId ~= nil
					and (current).claimedByJobId ~= jobId
					and nowSec <= ((current).claimedAtSec or 0) + CLAIM_LEASE_SEC
				)
			then
				return nil
			end
			local nextRecord = table.clone(current)
			nextRecord.claimedByJobId = jobId
			nextRecord.claimedAtSec = nowSec
			return copyRecord(nextRecord)
		end
	end

	function Core.renewTransform(runId: string, jobId: string, nowSec: number): Transform
		return function(currentValue: unknown): Record?
			local current = Core.readRecord(currentValue)
			if
				current == nil
				or (current).runId ~= runId
				or (current).status == "closed"
				or not claimHeld(current, jobId, nowSec)
			then
				return nil
			end
			local nextRecord = table.clone(current)
			nextRecord.claimedAtSec = nowSec
			return copyRecord(nextRecord)
		end
	end

	function Core.closeTransform(runId: string): Transform
		return function(currentValue: unknown): Record?
			local current = Core.readRecord(currentValue)
			if current == nil or (current).runId ~= runId or (current).status == "closed" then
				return nil
			end
			local nextRecord = table.clone(current)
			nextRecord.status = "closed"
			return copyRecord(nextRecord)
		end
	end

	function Core.writeThroughTransform(runId: string, runStateValue: unknown, jobId: string, nowSec: number): Transform
		return function(currentValue: unknown): Record?
			local runState = Value.raw(runStateValue)
			local current = Core.readRecord(currentValue)
			if
				current == nil
				or (current).runId ~= runId
				or (current).status == "closed"
				or not claimHeld(current, jobId, nowSec)
				or type(runState) ~= "table"
				or (runState).runId ~= runId
				or type((runState).revision) ~= "number"
				or (runState).revision <= (current).stateRevision
			then
				return nil
			end
			local nextRecord = table.clone(current)
			nextRecord.runState = runState
			nextRecord.stateRevision = (runState).revision
			nextRecord.status = if (runState).status == "completed" then "closed" else "active"
			nextRecord.claimedAtSec = nowSec
			return copyRecord(nextRecord)
		end
	end

	function Core.inviteReplacementTransform(invitationValue: unknown, jobId: string, nowSec: number): Transform
		return function(currentValue: unknown): Record?
			local invitation = Value.raw(invitationValue)
			local current = Core.readRecord(currentValue)
			if
				current == nil
				or not claimHeld(current, jobId, nowSec)
				or (current).status == "closed"
				or type(invitation) ~= "table"
				or not (type((invitation).userId) == "number" and positiveInteger((invitation).userId))
				or not (type((invitation).priorId) == "string" and text((invitation).priorId))
			then
				return nil
			end
			local state = current.runState
			if
				type(state) ~= "table"
				or (state).status ~= "active"
				or (state).checkpointId == nil
				or type(state.members) ~= "table"
				or (state).revision ~= (invitation).expectedRevision
				or type(invitation.recoveryWindowSec) ~= "number"
			then
				return nil
			end
			local held = false
			for _, candidate in assert(Value.raw(state.members)) do
				local member = Value.raw(candidate)
				if member == nil then
					return nil
				end
				if
					member.id == (invitation).priorId
					and not member.connected
					and type(member.disconnectedAtSec) == "number"
					and nowSec > member.disconnectedAtSec + (invitation).recoveryWindowSec
				then
					held = true
				end
			end
			for _, member in (current).members do
				if member.userId == (invitation).userId then
					return nil
				end
			end
			if not held then
				return nil
			end
			local nextRecord = table.clone(current)
			nextRecord.replacementInvitation = invitation
			return copyRecord(nextRecord)
		end
	end

	function Core.replaceRosterTransform(
		runId: string,
		rawPlan: unknown,
		rawRows: unknown,
		jobId: string,
		nowSec: number
	): Transform
		return function(currentValue: unknown): Record?
			local current = Core.readRecord(currentValue)
			if type(rawPlan) ~= "table" then
				return nil
			end
			local plan = assert(Value.raw(rawPlan))
			local state = Value.raw(plan.state)
			local acceptance = Value.raw(plan.acceptance)
			local rows = validMembers(rawRows)
			if type(state) ~= "table" or type(acceptance) ~= "table" or rows == nil then
				return nil
			end
			local nextState = state
			local accepted = acceptance
			if
				current == nil
				or (current).runId ~= runId
				or not claimHeld(current, jobId, nowSec)
				or (current).status == "closed"
				or (current).stateRevision ~= plan.expectedRevision
				or type(plan.expectedRevision) ~= "number"
				or type(nextState.revision) ~= "number"
				or nextState.revision ~= plan.expectedRevision + 1
				or type(nextState.members) ~= "table"
			then
				return nil
			end
			local invitation = (current).replacementInvitation
			if type(invitation) ~= "table" or accepted.runId ~= runId or accepted.packageId ~= (current).packageId then
				return nil
			end
			local selected = {}
			for _, value in assert(Value.raw(nextState.members)) do
				local candidate = Value.raw(value)
				if type(candidate) ~= "table" or type((candidate).id) ~= "string" then
					return nil
				end
				selected[(candidate).id] = true
			end
			local invited = false
			local members = rows
			for _, row in rows do
				if not selected[row.characterId] or row.characterId == invitation.priorId then
					return nil
				end
				invited = invited or row.userId == invitation.userId
			end
			if not invited then
				return nil
			end
			if #members ~= config.memberCount then
				return nil
			end
			local nextRecord = table.clone(current)
			nextRecord.request = {
				requestId = accepted.requestId,
				runId = runId,
				packageId = accepted.packageId,
				leaderId = accepted.leaderId,
				members = accepted.members,
			}
			nextRecord.members = members
			nextRecord.rows = assert(Value.raw(rawRows))
			nextRecord.runState = nextState
			nextRecord.stateRevision = nextState.revision
			nextRecord.replacementInvitation = nil
			nextRecord.claimedAtSec = nowSec
			return copyRecord(nextRecord)
		end
	end

	function Core.rejoinTarget(record: unknown, userId: number, nowSec: number): (Target?, string?)
		local current = Core.readRecord(record)
		if current == nil then
			return nil, "run_missing"
		end
		if nowSec > current.expiresAtSec then
			return nil, "run_expired"
		end
		if current.status == "closed" then
			return nil, "run_closed"
		end
		local characterId: string? = nil
		for _, member in current.members do
			if member.userId == userId then
				characterId = member.characterId
			end
		end
		if characterId == nil then
			local invitation = current.replacementInvitation
			if type(invitation) ~= "table" or invitation.userId ~= userId then
				return nil, "not_member"
			end
		end
		if
			characterId ~= nil
			and type(current.replacementInvitation) == "table"
			and (current.replacementInvitation).priorId == characterId
		then
			return nil, "recovery_expired"
		end
		if characterId ~= nil and type(current.runState) == "table" and type(current.runState.members) == "table" then
			local found = false
			for _, value in assert(Value.raw(current.runState.members)) do
				local member = Value.raw(value)
				if member == nil then
					return nil, "not_member"
				end
				if member.id == characterId then
					found = true
				end
				if member.id == characterId and member.departed then
					return nil, "member_departed"
				end
			end
			if not found then
				return nil, "not_member"
			end
		end
		local target: Target = {
			placeId = current.placeId,
			accessCode = current.accessCode,
			privateServerId = current.privateServerId,
			runId = current.runId,
		}
		Value.freezeDeep(target)
		return target, nil
	end

	function Core.teleportData<T>(carriers: { [number]: T }): { contract: string, carriers: { [string]: T } }
		local byUser: { [string]: T } = {}
		for userId, carrier in carriers do
			byUser[tostring(userId)] = carrier
		end
		return { contract = CARRIER_CONTRACT, carriers = byUser }
	end

	function Core.carrierFor(teleportData: unknown, userId: number): unknown
		if type(teleportData) ~= "table" then
			return nil
		end
		local data = assert(Value.raw(teleportData))
		if data.contract ~= CARRIER_CONTRACT or type(data.carriers) ~= "table" then
			return nil
		end
		return assert(Value.raw(data.carriers))[tostring(userId)]
	end

	Core.SCHEMA_VERSION = SCHEMA_VERSION
	Core.RECORD_TTL_SEC = RECORD_TTL_SEC
	Core.CARRIER_CONTRACT = CARRIER_CONTRACT
	Core.CLAIM_LEASE_SEC = CLAIM_LEASE_SEC

	return table.freeze(Core)
end
return table.freeze(System)
