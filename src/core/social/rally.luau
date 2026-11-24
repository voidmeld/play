--!strict

local Shape = require("./shape")

export type Row = {
	objectiveId: string,
	objectiveKind: string,
	titleId: string,
	landmarkId: string,
	zoneId: string,
	realmId: string,
	expiresAtSec: number,
}
export type Config = {
	maxRows: number,
	maxTime: number,
	maxId: number,
	kinds: { [string]: boolean },
	titles: { [string]: boolean },
	landmarks: { [string]: boolean },
	realms: { [string]: boolean },
	sharedRealm: string,
}
local fields = {
	objectiveId = true,
	objectiveKind = true,
	titleId = true,
	landmarkId = true,
	zoneId = true,
	realmId = true,
	active = true,
	expiresAtSec = true,
	serverAuthored = true,
}

local Boards = {}

function Boards.rally(config: Config)
	return {
		project = function(source: unknown, zone: unknown, realm: unknown, now: unknown): { Row }?
			if
				type(zone) ~= "string"
				or not Shape.opaque(zone, config.maxId)
				or type(realm) ~= "string"
				or not config.realms[realm]
				or type(now) ~= "number"
				or not Shape.whole(now, 0, config.maxTime)
				or Shape.dense(source, math.huge) == nil
			then
				return nil
			end
			local rows: { Row } = {}
			local seen: { [string]: boolean } = {}
			for _, candidate in assert(Shape.raw(source)) do
				local value = Shape.raw(candidate)
				if value == nil or not Shape.exact(candidate, fields) then
					return nil
				end
				local id, kind, title, landmark, zoneId, realmId =
					value.objectiveId, value.objectiveKind, value.titleId, value.landmarkId, value.zoneId, value.realmId
				local expiresAtSec = value.expiresAtSec
				if
					type(id) ~= "string"
					or not Shape.opaque(id, config.maxId)
					or type(kind) ~= "string"
					or config.kinds[kind] ~= true
					or type(title) ~= "string"
					or config.titles[title] ~= true
					or type(landmark) ~= "string"
					or config.landmarks[landmark] ~= true
					or type(zoneId) ~= "string"
					or not Shape.opaque(zoneId, config.maxId)
					or type(realmId) ~= "string"
					or config.realms[realmId] ~= true
					or type(value.active) ~= "boolean"
					or type(value.serverAuthored) ~= "boolean"
					or type(expiresAtSec) ~= "number"
					or not Shape.whole(expiresAtSec, 0, config.maxTime)
					or seen[id]
				then
					return nil
				end
				seen[id] = true
				if
					value.serverAuthored
					and value.active
					and zoneId == zone
					and (realmId == realm or realmId == config.sharedRealm)
					and expiresAtSec > now
				then
					table.insert(rows, {
						objectiveId = id,
						objectiveKind = kind,
						titleId = title,
						landmarkId = landmark,
						zoneId = zoneId,
						realmId = realmId,
						expiresAtSec = expiresAtSec,
					})
					if #rows == config.maxRows then
						break
					end
				end
			end
			table.sort(rows, function(left: Row, right: Row): boolean
				return if left.expiresAtSec == right.expiresAtSec
					then left.objectiveId < right.objectiveId
					else left.expiresAtSec < right.expiresAtSec
			end)
			return Shape.freezeDeep(rows)
		end,
	}
end

return Boards
