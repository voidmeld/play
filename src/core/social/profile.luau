--!strict

local Allies = require("./allies")
local Chronicle = require("./chronicle")
local Shape = require("./shape")

export type FellowshipIdentity = {
	fellowshipId: string,
	nameId: string,
	realmId: string,
	memberUserId: number,
	lastKnownStewardUserId: number,
	observedRevision: number,
}
export type State =
	{ fellowship: FellowshipIdentity | false, recentAllies: Allies.State, vowChronicle: Chronicle.State }
export type Config = {
	maxId: number,
	realms: { [string]: boolean },
	nameIds: { [string]: boolean },
	definitions: { Chronicle.Definition },
	emptyAllies: (unknown) -> Allies.State?,
	projectAllies: (unknown) -> Allies.State?,
	emptyChronicle: (unknown) -> Chronicle.State?,
	projectChronicle: (unknown, unknown) -> Chronicle.State?,
}
local identityFields = {
	fellowshipId = true,
	nameId = true,
	realmId = true,
	memberUserId = true,
	lastKnownStewardUserId = true,
	observedRevision = true,
}
local fields = { fellowship = true, recentAllies = true, vowChronicle = true }

local Profiles = {}

function Profiles.profile(config: Config)
	local function identity(value: unknown, userId: unknown): FellowshipIdentity?
		local raw = Shape.raw(value)
		if raw == nil or not Shape.exact(value, identityFields) then
			return nil
		end
		local fellowshipId, nameId, realmId = raw.fellowshipId, raw.nameId, raw.realmId
		local memberUserId, steward, revision = raw.memberUserId, raw.lastKnownStewardUserId, raw.observedRevision
		if
			type(fellowshipId) ~= "string"
			or not Shape.opaque(fellowshipId, config.maxId)
			or type(nameId) ~= "string"
			or not config.nameIds[nameId]
			or type(realmId) ~= "string"
			or not config.realms[realmId]
			or type(memberUserId) ~= "number"
			or memberUserId ~= userId
			or type(steward) ~= "number"
			or steward < 1
			or type(revision) ~= "number"
			or revision < 0
			or revision ~= math.floor(revision)
		then
			return nil
		end
		return {
			fellowshipId = fellowshipId,
			nameId = nameId,
			realmId = realmId,
			memberUserId = memberUserId,
			lastKnownStewardUserId = steward,
			observedRevision = revision,
		}
	end
	local function frozen(value: State): State
		return Shape.freezeDeep(value)
	end
	return {
		default = function(userId: unknown, characterId: unknown): State?
			local recent, chronicle = config.emptyAllies(userId), config.emptyChronicle(characterId)
			if recent == nil or chronicle == nil then
				return nil
			end
			return frozen({ fellowship = false, recentAllies = recent, vowChronicle = chronicle })
		end,
		project = function(value: unknown, userId: unknown, characterId: unknown): State?
			local raw = Shape.raw(value)
			if raw == nil or not Shape.exact(value, fields) then
				return nil
			end
			local fellowship: (FellowshipIdentity | false)? = if raw.fellowship == false
				then false
				else identity(raw.fellowship, userId)
			local recent, chronicle =
				config.projectAllies(raw.recentAllies), config.projectChronicle(raw.vowChronicle, config.definitions)
			if
				fellowship == nil
				or recent == nil
				or chronicle == nil
				or recent.userId ~= userId
				or chronicle.characterId ~= characterId
			then
				return nil
			end
			return frozen({ fellowship = fellowship, recentAllies = recent, vowChronicle = chronicle })
		end,
	}
end

return Profiles
