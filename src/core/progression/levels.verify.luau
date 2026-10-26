--!strict
local Module = require("./levels")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local rows: { Module.CurveRow } = {}
for i, xp in { 0, 250, 600, 1100, 1800, 2700, 3850, 5250, 7000, 9200 } do
	rows[i] = { level = i, totalXp = xp }
end
local ProfileProgression =
	Module.levels({ curve = { id = "curve", maxLevel = 10, rows = rows }, curveId = "curve", maxLevel = 10 })
return function(suite: Verify.Harness)
	local current: Verify.Context? = nil
	local function expect(value: unknown): Verify.Expectation
		return assert(current):expect(value)
	end
	local function it(name: string, body: () -> ())
		suite:case(name, function(context)
			current = context
			body()
		end)
	end
	local function describe(_name: string, body: () -> ())
		body()
	end

	local function curve(maxLevel: number, rows: unknown)
		return { id = "curve", maxLevel = maxLevel, rows = rows }
	end

	local function validRows(): { Module.CurveRow }
		local rows: { Module.CurveRow } = {}
		for level = 1, 10 do
			rows[level] = { level = level, totalXp = (level - 1) * 100 }
		end
		return rows
	end

	local function expectInvalidCurve(rows: unknown, expected: string)
		local ok, message = pcall(ProfileProgression.validateCurve, curve(10, rows))
		expect(ok):toBe(false)
		expect(tostring(message)):toContain(expected)
	end

	describe("ProfileProgression", function()
		describe("validateCurve", function()
			it("rejects a duplicate level after the valid full-length baseline", function()
				local rows = validRows()
				rows[5].level = 4
				expectInvalidCurve(rows, "invalid authored curve level sequence")
			end)

			it("rejects an equal threshold after the valid full-length baseline", function()
				local rows = validRows()
				rows[5].totalXp = 300
				expectInvalidCurve(rows, "invalid authored curve thresholds")
			end)

			it("rejects an invalid first threshold after the valid full-length baseline", function()
				local rows = validRows()
				rows[1].totalXp = 1
				expectInvalidCurve(rows, "invalid authored curve first threshold")
			end)

			it("rejects a wrong maximum level before accepting the valid full-length baseline", function()
				local ok, message = pcall(ProfileProgression.validateCurve, curve(9, validRows()))
				expect(ok):toBe(false)
				expect(tostring(message)):toContain("invalid authored curve max level")
			end)

			it("rejects a missing terminal row despite a malformed full-length table", function()
				local rows = validRows()
				rows = {}
				for i = 1, 9 do
					rows[i] = { level = i, totalXp = (i - 1) * 100 }
				end
				setmetatable(rows, {
					__len = function()
						return 10
					end,
				})
				expectInvalidCurve(rows, "invalid authored curve terminal row")
			end)
		end)

		describe("snapshotFromValues", function()
			it("fails closed while replication is absent or malformed", function()
				local absent = ProfileProgression.snapshotFromValues(nil, nil)
				expect(absent.level):toBe(1)
				expect(absent.experience):toBe(0)
				local malformed = ProfileProgression.snapshotFromValues("3", -20)
				expect(malformed.level):toBe(1)
				expect(malformed.experience):toBe(0)
			end)

			it("projects only whole non-negative values", function()
				local snapshot = ProfileProgression.snapshotFromValues(2.9, 299.8)
				expect(snapshot.level):toBe(2)
				expect(snapshot.experience):toBe(299)
			end)
		end)

		describe("resolveLevel", function()
			it("derives level purely from the given curve's authored thresholds", function()
				local rows = {
					{ level = 1, totalXp = 0 },
					{ level = 2, totalXp = 50 },
				}
				expect(ProfileProgression.resolveLevel(rows, 2, 49)):toBe(1)
				expect(ProfileProgression.resolveLevel(rows, 2, 50)):toBe(2)
			end)
		end)

		describe("xpBracket", function()
			it("reports xp into the current level and the span to the next threshold", function()
				local intoLevel, span = ProfileProgression.xpBracket(700)
				expect(intoLevel):toBe(100)
				expect(span):toBe(500)
			end)

			it("reports a zero span once the authored max level is reached", function()
				local intoLevel, span = ProfileProgression.xpBracket(9250)
				expect(intoLevel):toBe(50)
				expect(span):toBe(0)
			end)
		end)

		describe("rewardProjection", function()
			it("never reports a level-up once both sides of the grant clamp at the authored max", function()
				local projection = ProfileProgression.rewardProjection(9350, 150)
				expect(projection.previousLevel):toBe(10)
				expect(projection.currentLevel):toBe(10)
				expect(projection.leveledUp):toBe(false)
			end)
		end)

		describe("actor progression", function()
			it("derives earned levels from whole XP while retaining actor state", function()
				local actor = table.freeze({ xp = 599.9, level = 9, id = "actor", xpCredit = 0.75 })
				local normalized = ProfileProgression.awardXp(actor, 0)
				expect(normalized.xp):toBe(599)
				expect(normalized.level):toBe(2)
				local awarded = ProfileProgression.awardXp(actor, 1.9)
				expect(awarded.xp):toBe(600)
				expect(awarded.level):toBe(3)
				expect(awarded.id):toBe("actor")
				expect(awarded.xpCredit):toBe(0.75)
				expect(actor.xp):toBe(599.9)
				expect(actor.level):toBe(9)
			end)

			it("normalizes missing and negative XP before ignoring a negative grant", function()
				local blank: Module.Progression = {}
				expect(ProfileProgression.awardXp(blank, 0)):toEqual({ xp = 0, level = 1 })
				expect(ProfileProgression.awardXp(blank, 250)):toEqual({ xp = 250, level = 2 })
				expect(ProfileProgression.awardXp({ xp = -50, level = 10 }, -100)):toEqual({ xp = 0, level = 1 })
			end)
		end)
	end)
	it("selects supplied curve identity, length and thresholds", function()
		local supplied = {
			id = "small",
			maxLevel = 3,
			rows = {
				{ level = 1, totalXp = 0 },
				{ level = 2, totalXp = 10 },
				{ level = 3, totalXp = 25 },
			},
		}
		local law = Module.levels({ curve = supplied, curveId = "small", maxLevel = 3 })
		expect(law.levelForXp(24)):toBe(2)
		expect(law.levelForXp(25)):toBe(3)
		expect(law.xpForLevel(2)):toBe(10)
		expect(law.xpForLevel(99)):toBe(25)
		expect(law.rewardProjection(25, 1).leveledUp):toBe(true)
		local wrongId: Module.Config = { curve = supplied, curveId = "missing", maxLevel = 3 }
		expect(pcall(Module.levels, wrongId)):toBe(false)
		local wrongLength: Module.Config = { curve = supplied, curveId = "small", maxLevel = 2 }
		expect(pcall(Module.levels, wrongLength)):toBe(false)
	end)
end
