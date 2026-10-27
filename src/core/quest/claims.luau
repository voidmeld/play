--!strict
local Run = require("./run")
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

	local function deepFreezeCopy<T>(value: T): T
		local probe: unknown = value
		if type(probe) ~= "table" then
			return value
		end
		local copy: { [unknown]: unknown } = {}
		for key, child in (value :: unknown) :: { [unknown]: unknown } do
			copy[deepFreezeCopy(key)] = deepFreezeCopy(child)
		end
		return (table.freeze(copy) :: unknown) :: T
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
		return text(privateServerId) and privateServerOwnerId == 0
	end

	function Core.retryDelaysSec(): { number }
		return table.clone(RETRY_DELAYS_SEC)
	end

	local function validMembers(value: unknown): { Member }?
		if type(value) ~= "table" or #(value :: Raw) < 1 then
			return nil
		end
		local seen: { [number]: boolean } = {}
		local characters: { [string]: boolean } = {}
		local members: { Member } = {}
		for _, candidate in value :: Raw do
			local row = candidate :: Raw
			if
				type(row) ~= "table"
				or not positiveInteger(row.userId)
				or not text(row.characterId)
				or seen[row.userId :: number]
				or characters[row.characterId :: string]
			then
				return nil
			end
			seen[row.userId :: number] = true
			characters[row.characterId :: string] = true
			members[#members + 1] = { userId = row.userId :: number, characterId = row.characterId :: string }
		end
		return members
	end

	function Core.newRecord(input: unknown, nowSec: number): (Record?, string?)
		if
			type(input) ~= "table"
			or not text((input :: Raw).runId)
			or not text((input :: Raw).packageId)
			or not positiveInteger((input :: Raw).placeId)
			or not text((input :: Raw).accessCode)
			or not text((input :: Raw).privateServerId)
			or not text((input :: Raw).partyId)
			or not positiveInteger((input :: Raw).leaderUserId)
			or type((input :: Raw).request) ~= "table"
			or type((input :: Raw).rows) ~= "table"
			or type((input :: Raw).runState) ~= "table"
			or ((input :: Raw).runState :: Raw).runId ~= (input :: Raw).runId
			or type(((input :: Raw).runState :: Raw).revision) ~= "number"
			or (((input :: Raw).runState :: Raw).revision :: number) < 1
			or not instant(nowSec)
		then
			return nil, "record_invalid"
		end
		local members = validMembers((input :: Raw).members)
		if members == nil then
			return nil, "record_invalid"
		end
		local leaderSeen = false
		for _, member in members do
			leaderSeen = leaderSeen or member.userId == (input :: Raw).leaderUserId
		end
		if not leaderSeen then
			return nil, "record_invalid"
		end
		local record: Record = {
			schemaVersion = SCHEMA_VERSION,
			runId = (input :: Raw).runId :: string,
			packageId = (input :: Raw).packageId :: string,
			placeId = (input :: Raw).placeId :: number,
			accessCode = (input :: Raw).accessCode :: string,
			privateServerId = (input :: Raw).privateServerId :: string,
			partyId = (input :: Raw).partyId :: string,
			leaderUserId = (input :: Raw).leaderUserId :: number,
			request = (input :: Raw).request :: Raw,
			rows = (input :: Raw).rows :: Raw,
			members = members,
			createdAtSec = nowSec,
			expiresAtSec = nowSec + RECORD_TTL_SEC,
			stateRevision = ((input :: Raw).runState :: Raw).revision :: number,
			runState = (input :: Raw).runState :: Raw,
			status = "reserved" :: "reserved",
		}
		return deepFreezeCopy(record), nil
	end

	function Core.validRecord(value: unknown): boolean
		if type(value) ~= "table" then
			return false
		end
		local record = value :: Raw
		return record.schemaVersion == SCHEMA_VERSION
			and text(record.runId)
			and text(record.packageId)
			and positiveInteger(record.placeId)
			and text(record.accessCode)
			and text(record.privateServerId)
			and text(record.partyId)
			and positiveInteger(record.leaderUserId)
			and type(record.request) == "table"
			and type(record.rows) == "table"
			and validMembers(record.members) ~= nil
			and instant(record.createdAtSec)
			and instant(record.expiresAtSec)
			and type(record.stateRevision) == "number"
			and (record.runState == nil or type(record.runState) == "table")
			and (record.replacementInvitation == nil or type(record.replacementInvitation) == "table")
			and (record.claimedByJobId == nil or type(record.claimedByJobId) == "string")
			and (record.claimedAtSec == nil or type(record.claimedAtSec) == "number")
			and (record.status == "reserved" or record.status == "active" or record.status == "closed")
	end

	function Core.readRecord(value: unknown): Record?
		return if Core.validRecord(value) then value :: Record else nil
	end

	function Core.readReplacementIdentity(value: unknown): ReplacementIdentity?
		if type(value) ~= "table" then
			return nil
		end
		local row = value :: Raw
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
		return function(current: unknown): Record?
			if current ~= nil then
				return nil
			end
			return record
		end
	end

	local function claimHeld(current: Record, jobId: string, nowSec: number): boolean
		return current.claimedByJobId == jobId and nowSec <= (current.claimedAtSec or 0) + CLAIM_LEASE_SEC
	end

	function Core.claimTransform(privateServerId: string, jobId: string, nowSec: number): Transform
		return function(current: unknown): Record?
			if
				not Core.validRecord(current)
				or (current :: Record).privateServerId ~= privateServerId
				or (current :: Record).status == "closed"
				or not text(jobId)
				or (
					(current :: Record).claimedByJobId ~= nil
					and (current :: Record).claimedByJobId ~= jobId
					and nowSec <= ((current :: Record).claimedAtSec or 0) + CLAIM_LEASE_SEC
				)
			then
				return nil
			end
			local nextRecord = table.clone(current :: Record)
			nextRecord.claimedByJobId = jobId
			nextRecord.claimedAtSec = nowSec
			return deepFreezeCopy(nextRecord)
		end
	end

	function Core.renewTransform(runId: string, jobId: string, nowSec: number): Transform
		return function(current: unknown): Record?
			if
				not Core.validRecord(current)
				or (current :: Record).runId ~= runId
				or (current :: Record).status == "closed"
				or not claimHeld(current :: Record, jobId, nowSec)
			then
				return nil
			end
			local nextRecord = table.clone(current :: Record)
			nextRecord.claimedAtSec = nowSec
			return deepFreezeCopy(nextRecord)
		end
	end

	function Core.closeTransform(runId: string): Transform
		return function(current: unknown): Record?
			if
				not Core.validRecord(current)
				or (current :: Record).runId ~= runId
				or (current :: Record).status == "closed"
			then
				return nil
			end
			local nextRecord = table.clone(current :: Record)
			nextRecord.status = "closed"
			return deepFreezeCopy(nextRecord)
		end
	end

	function Core.writeThroughTransform(runId: string, runState: unknown, jobId: string, nowSec: number): Transform
		return function(current: unknown): Record?
			if
				not Core.validRecord(current)
				or (current :: Record).runId ~= runId
				or (current :: Record).status == "closed"
				or not claimHeld(current :: Record, jobId, nowSec)
				or type(runState) ~= "table"
				or (runState :: Raw).runId ~= runId
				or type((runState :: Raw).revision) ~= "number"
				or ((runState :: Raw).revision :: number) <= (current :: Record).stateRevision
			then
				return nil
			end
			local nextRecord = table.clone(current :: Record)
			nextRecord.runState = runState :: Raw
			nextRecord.stateRevision = (runState :: Raw).revision :: number
			nextRecord.status = if (runState :: Raw).status == "completed" then "closed" else "active"
			nextRecord.claimedAtSec = nowSec
			return deepFreezeCopy(nextRecord)
		end
	end

	function Core.inviteReplacementTransform(invitation: unknown, jobId: string, nowSec: number): Transform
		return function(current: unknown): Record?
			if
				current == nil
				or not Core.validRecord(current)
				or not claimHeld(current :: Record, jobId, nowSec)
				or (current :: Record).status == "closed"
				or type(invitation) ~= "table"
				or not positiveInteger((invitation :: Raw).userId)
				or not text((invitation :: Raw).priorId)
			then
				return nil
			end
			local state = (current :: Record).runState
			if
				type(state) ~= "table"
				or (state :: RunState).status ~= "active"
				or (state :: RunState).checkpointId == nil
				or (state :: RunState).revision ~= (invitation :: Raw).expectedRevision
			then
				return nil
			end
			local held = false
			for _, member in (state :: RunState).members do
				if
					member.id == (invitation :: Raw).priorId
					and not member.connected
					and type(member.disconnectedAtSec) == "number"
					and nowSec > member.disconnectedAtSec + ((invitation :: Raw).recoveryWindowSec :: number)
				then
					held = true
				end
			end
			for _, member in (current :: Record).members do
				if member.userId == (invitation :: Raw).userId then
					return nil
				end
			end
			if not held then
				return nil
			end
			local nextRecord = table.clone(current :: Record)
			nextRecord.replacementInvitation = invitation :: Raw
			return deepFreezeCopy(nextRecord)
		end
	end

	function Core.replaceRosterTransform(
		runId: string,
		rawPlan: unknown,
		rawRows: unknown,
		jobId: string,
		nowSec: number
	): Transform
		return function(current: unknown): Record?
			if type(rawPlan) ~= "table" then
				return nil
			end
			local plan = rawPlan :: Raw
			local state = plan.state
			local acceptance = plan.acceptance
			local rows = validMembers(rawRows)
			if type(state) ~= "table" or type(acceptance) ~= "table" or rows == nil then
				return nil
			end
			local nextState = state :: Raw
			local accepted = acceptance :: Raw
			if
				current == nil
				or not Core.validRecord(current)
				or (current :: Record).runId ~= runId
				or not claimHeld(current :: Record, jobId, nowSec)
				or (current :: Record).status == "closed"
				or (current :: Record).stateRevision ~= plan.expectedRevision
				or type(plan.expectedRevision) ~= "number"
				or nextState.revision ~= plan.expectedRevision + 1
				or type(nextState.members) ~= "table"
			then
				return nil
			end
			local invitation = (current :: Record).replacementInvitation
			if
				type(invitation) ~= "table"
				or accepted.runId ~= runId
				or accepted.packageId ~= (current :: Record).packageId
			then
				return nil
			end
			local selected = {}
			for _, candidate in nextState.members :: Raw do
				if type(candidate) ~= "table" or type((candidate :: Raw).id) ~= "string" then
					return nil
				end
				selected[(candidate :: Raw).id :: string] = true
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
			local nextRecord = table.clone(current :: Record)
			nextRecord.request = {
				requestId = accepted.requestId,
				runId = runId,
				packageId = accepted.packageId,
				leaderId = accepted.leaderId,
				members = accepted.members,
			}
			nextRecord.members = members
			nextRecord.rows = rawRows :: Raw
			nextRecord.runState = nextState
			nextRecord.stateRevision = nextState.revision :: number
			nextRecord.replacementInvitation = nil
			nextRecord.claimedAtSec = nowSec
			return deepFreezeCopy(nextRecord)
		end
	end

	function Core.rejoinTarget(record: unknown, userId: number, nowSec: number): (Target?, string?)
		if not Core.validRecord(record) then
			return nil, "run_missing"
		end
		local current = record :: Record
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
			and (current.replacementInvitation :: Raw).priorId == characterId
		then
			return nil, "recovery_expired"
		end
		if characterId ~= nil and type(current.runState) == "table" and type(current.runState.members) == "table" then
			local found = false
			for _, member in current.runState.members :: { RunMember } do
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
		table.freeze(target)
		return target :: Target?, nil
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
		local data = teleportData :: Raw
		if data.contract ~= CARRIER_CONTRACT or type(data.carriers) ~= "table" then
			return nil
		end
		return (data.carriers :: Raw)[tostring(userId)]
	end

	Core.Types = (nil :: unknown) :: { Record: Record, Member: Member, Target: Target, Transform: Transform }

	Core.SCHEMA_VERSION = SCHEMA_VERSION
	Core.RECORD_TTL_SEC = RECORD_TTL_SEC
	Core.CARRIER_CONTRACT = CARRIER_CONTRACT
	Core.CLAIM_LEASE_SEC = CLAIM_LEASE_SEC

	return table.freeze(Core)
end
return table.freeze(System)
