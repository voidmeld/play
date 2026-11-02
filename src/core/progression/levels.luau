--!strict
local Value = require("../value")
export type CurveRow = { level: number, totalXp: number }
export type Curve = { id: string, maxLevel: number, rows: { CurveRow } }
export type Config = { curve: unknown, curveId: string, maxLevel: number }
export type Progression = {
	read xp: number?,
	read level: number?,
}
export type Snapshot = {
	level: number,
	experience: number,
}
export type RewardProjection = {
	previousLevel: number,
	currentLevel: number,
	leveledUp: boolean,
}
local System = {}
function System.levels(config: Config)
	local CURVE_ID = config.curveId
	local EXPECTED_MAX_LEVEL = config.maxLevel
	local function validWhole(value: unknown): boolean
		return type(value) == "number"
			and value == math.floor(value)
			and value == value
			and value ~= math.huge
			and value ~= -math.huge
	end

	local function validateCurve(candidate: unknown): Curve
		if type(candidate) ~= "table" then
			error("Play levels: invalid authored curve id")
		end
		local curve = assert(Value.raw(candidate))
		if curve.id ~= CURVE_ID then
			error("Play levels: invalid authored curve id")
		end
		if curve.maxLevel ~= EXPECTED_MAX_LEVEL then
			error("Play levels: invalid authored curve max level")
		end
		local maxLevel = EXPECTED_MAX_LEVEL
		if type(curve.rows) ~= "table" then
			error("Play levels: invalid authored curve row count")
		end
		local rows = assert(Value.raw(curve.rows))
		local out: { CurveRow } = {}
		if #curve.rows ~= maxLevel then
			error("Play levels: invalid authored curve row count")
		end
		local previousXp = -1
		for index, entry in rows do
			local row = Value.raw(entry)
			if row == nil or not validWhole(row.level) or row.level ~= index then
				error("Play levels: invalid authored curve level sequence")
			end
			local totalXp = row.totalXp
			if type(totalXp) ~= "number" or not validWhole(totalXp) or totalXp < 0 or totalXp <= previousXp then
				error("Play levels: invalid authored curve thresholds")
			end
			if index == 1 and totalXp ~= 0 then
				error("Play levels: invalid authored curve first threshold")
			end
			previousXp = totalXp
			assert(type(row.level) == "number" and type(index) == "number")
			out[index] = { level = row.level, totalXp = totalXp }
		end
		if out[maxLevel] == nil or out[maxLevel].level ~= maxLevel then
			error("Play levels: invalid authored curve terminal row")
		end
		return { id = CURVE_ID, maxLevel = maxLevel, rows = out }
	end

	local CURVE = validateCurve(config.curve)
	local MAX_LEVEL = CURVE.maxLevel

	local function resolveLevel(rows: { CurveRow }, maxLevel: number, xp: number): number
		local clampedXp = math.max(0, xp)
		local level = 1
		for _, row in rows do
			if clampedXp >= row.totalXp then
				level = row.level
			end
		end
		return math.min(level, maxLevel)
	end

	local function thresholdForLevel(level: number): number
		for _, row in CURVE.rows do
			if row.level == level then
				return row.totalXp
			end
		end
		return CURVE.rows[#CURVE.rows].totalXp
	end

	local function levelForXp(xp: number): number
		return resolveLevel(CURVE.rows, MAX_LEVEL, xp)
	end

	local function xpBracket(xp: number): (number, number)
		local clampedXp = math.max(0, xp)
		local level = levelForXp(clampedXp)
		local floor = thresholdForLevel(level)
		if level >= MAX_LEVEL then
			return clampedXp - floor, 0
		end
		return clampedXp - floor, thresholdForLevel(level + 1) - floor
	end

	local function rewardProjection(xpAfter: number, rewardXp: number): RewardProjection
		local previousLevel = levelForXp(math.max(0, xpAfter - rewardXp))
		local currentLevel = levelForXp(xpAfter)
		return {
			previousLevel = previousLevel,
			currentLevel = currentLevel,
			leveledUp = currentLevel > previousLevel,
		}
	end

	local function normalizedXp(xp: unknown): number
		return if type(xp) == "number" then math.max(0, math.floor(xp)) else 0
	end

	local function awardXp<T>(progression: T & Progression, amount: number): T & Progression
		local next = table.clone(progression)
		local xp = normalizedXp(progression.xp) + math.max(0, math.floor(amount))
		rawset(next, "xp", xp)
		rawset(next, "level", levelForXp(xp))
		return next
	end

	local function snapshotFromValues(_level: unknown, experience: unknown): Snapshot
		local xp = normalizedXp(experience)
		return { level = levelForXp(xp), experience = xp }
	end

	return {
		levelForXp = levelForXp,
		xpForLevel = thresholdForLevel,
		resolveLevel = resolveLevel,
		validateCurve = validateCurve,
		awardXp = awardXp,
		xpBracket = xpBracket,
		rewardProjection = rewardProjection,
		snapshotFromValues = snapshotFromValues,
		MAX_LEVEL = MAX_LEVEL,
	}
end
return System
