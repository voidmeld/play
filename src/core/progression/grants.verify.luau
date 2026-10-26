--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./grants")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local KITS: Module.ProductionRegistry = {
	class02 = {
		{ abilityId = "ability1", level = 1 },
		{ abilityId = "ability2", level = 2 },
		{ abilityId = "ability3", level = 3 },
		{ abilityId = "ability4", level = 4 },
		{ abilityId = "ability5", level = 5 },
	},
	class06 = {
		{ abilityId = "ability1", level = 1 },
		{ abilityId = "ability2", level = 3 },
		{ abilityId = "ability4", level = 5 },
		{ abilityId = "ability3", level = 7 },
		{ abilityId = "ability5", level = 10 },
	},
	class05 = {
		{ abilityId = "ability6", level = 1 },
		{ abilityId = "ability7", level = 3 },
		{ abilityId = "ability8", level = 5 },
		{ abilityId = "ability9", level = 7 },
		{ abilityId = "ability10", level = 10 },
	},
	class08 = {
		{ abilityId = "ability11", level = 1 },
		{ abilityId = "ability12", level = 3 },
		{ abilityId = "ability13", level = 5 },
		{ abilityId = "ability14", level = 7 },
		{ abilityId = "ability15", level = 10 },
	},
	class04 = {
		{ abilityId = "ability11", level = 1 },
		{ abilityId = "ability12", level = 3 },
		{ abilityId = "ability13", level = 5 },
		{ abilityId = "ability14", level = 7 },
		{ abilityId = "ability15", level = 10 },
	},
	class03 = {
		{ abilityId = "ability11", level = 1 },
		{ abilityId = "ability12", level = 3 },
		{ abilityId = "ability13", level = 5 },
		{ abilityId = "ability14", level = 7 },
		{ abilityId = "ability15", level = 10 },
	},
}

local AbilityGrants = Module.grants({ slotCount = 5, maxLevel = 10, kits = KITS })

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	local RELEASE_CURVE: { Module.Grant } = {
		{ abilityId = "ability11", level = 1 },
		{ abilityId = "ability12", level = 3 },
		{ abilityId = "ability13", level = 5 },
		{ abilityId = "ability14", level = 7 },
		{ abilityId = "ability15", level = 10 },
	}

	local function copyGrants(value: { Module.Grant }): { Module.Grant }
		local out: { Module.Grant } = {}
		for i, row in value do
			out[i] = table.clone(row)
		end
		return out
	end
	local function copyRegistry(value: Module.ProductionRegistry): Module.ProductionRegistry
		local out: Module.ProductionRegistry = {}
		for id, rows in value do
			out[id] = copyGrants(rows)
		end
		return out
	end
	type Authority = { grantsByClass: Module.ProductionRegistry }
	local ids = {
		"class01",
		"class02",
		"class03",
		"class04",
		"class05",
		"class06",
		"class07",
		"class08",
		"extra1",
		"extra2",
		"extra3",
		"extra4",
	}
	local function expectedClassIds(): { string }
		return table.clone(ids)
	end
	local function canonicalAuthorities(): { Authority }
		local out: { Authority } = { { grantsByClass = {} }, { grantsByClass = {} }, { grantsByClass = {} } }
		for i, id in ids do
			local grants: { Module.Grant } = {}
			for level = 1, 5 do
				grants[level] = { abilityId = id .. "_" .. level, level = level }
			end
			if id == "class02" then
				grants = copyGrants(KITS.class02)
			end
			local bucket = if id == "class02" or id == "class01" then 1 elseif id == "class07" then 3 else (i % 3) + 1
			out[bucket].grantsByClass[id] = grants
		end
		return out
	end
	local function mutableAuthorities(): { Authority }
		return canonicalAuthorities()
	end
	local function copyAuthorities(value: { Authority }): { Authority }
		local out: { Authority } = {}
		for i, row in value do
			out[i] = { grantsByClass = copyRegistry(row.grantsByClass) }
		end
		return out
	end
	local function sourceGrants(classId: string): { Module.Grant }?
		for _, authority in canonicalAuthorities() do
			if authority.grantsByClass[classId] ~= nil then
				return authority.grantsByClass[classId]
			end
		end
		return nil
	end

	local function hasProblem(problems: { string }, fragment: string): boolean
		for _, problem in problems do
			if string.find(problem, fragment, 1, true) ~= nil then
				return true
			end
		end
		return false
	end

	local function isSorted(values: { string }): boolean
		for index = 2, #values do
			if values[index - 1] > values[index] then
				return false
			end
		end
		return true
	end

	local function reversed<T>(values: { T }): { T }
		local result: { T } = {}
		for index = #values, 1, -1 do
			result[#result + 1] = values[index]
		end
		return result
	end

	local function reorderedMap<T>(source: { [string]: T }): { [string]: T }
		local ids: { string } = {}
		for classId in source do
			ids[#ids + 1] = classId
		end
		table.sort(ids, function(left: string, right: string)
			return left > right
		end)
		local result: { [string]: T } = {}
		for _, classId in ids do
			result[classId] = source[classId]
		end
		return result
	end

	describe("AbilityGrants", function()
		it("holds the live slice kit and every authored release kit", function()
			expect(AbilityGrants.forClass("class02")):toEqual(KITS.class02)
			expect(AbilityGrants.SLOT_COUNT):toBe(5)
			expect(AbilityGrants.MAX_LEVEL):toBe(10)
			local ids: { string } = {}
			for classId in AbilityGrants.CLASS_KITS do
				ids[#ids + 1] = classId
			end
			table.sort(ids)
			expect(ids):toEqual({ "class02", "class03", "class04", "class05", "class06", "class08" })
			expect(AbilityGrants.forClass("unknown")):toBeNil()
		end)

		it("preserves every legacy class kit exactly", function()
			expect(AbilityGrants.CLASS_KITS):toEqual({
				class02 = {
					{ abilityId = "ability1", level = 1 },
					{ abilityId = "ability2", level = 2 },
					{ abilityId = "ability3", level = 3 },
					{ abilityId = "ability4", level = 4 },
					{ abilityId = "ability5", level = 5 },
				},
				class06 = {
					{ abilityId = "ability1", level = 1 },
					{ abilityId = "ability2", level = 3 },
					{ abilityId = "ability4", level = 5 },
					{ abilityId = "ability3", level = 7 },
					{ abilityId = "ability5", level = 10 },
				},
				class05 = {
					{ abilityId = "ability6", level = 1 },
					{ abilityId = "ability7", level = 3 },
					{ abilityId = "ability8", level = 5 },
					{ abilityId = "ability9", level = 7 },
					{ abilityId = "ability10", level = 10 },
				},
				class08 = {
					{ abilityId = "ability11", level = 1 },
					{ abilityId = "ability12", level = 3 },
					{ abilityId = "ability13", level = 5 },
					{ abilityId = "ability14", level = 7 },
					{ abilityId = "ability15", level = 10 },
				},
				class04 = {
					{ abilityId = "ability11", level = 1 },
					{ abilityId = "ability12", level = 3 },
					{ abilityId = "ability13", level = 5 },
					{ abilityId = "ability14", level = 7 },
					{ abilityId = "ability15", level = 10 },
				},
				class03 = {
					{ abilityId = "ability11", level = 1 },
					{ abilityId = "ability12", level = 3 },
					{ abilityId = "ability13", level = 5 },
					{ abilityId = "ability14", level = 7 },
					{ abilityId = "ability15", level = 10 },
				},
			})
		end)

		it("compiles all twelve canonical production curves without copying them into shared source", function()
			local result = AbilityGrants.compileProductionRegistry(canonicalAuthorities(), expectedClassIds())
			expect(result.ok):toBe(true)
			expect(result.problems):toEqual({})
			expect(result.registry ~= nil):toBe(true)
			local registry = assert(result.registry)
			local count = 0
			for _, classId in expectedClassIds() do
				count += 1
				expect(registry[classId]):toEqual(sourceGrants(classId))
				expect(AbilityGrants.problemsForClassSchema(registry[classId])):toEqual({})
			end
			expect(count):toBe(12)
		end)

		it("fails closed on malformed grants, a missing class, and a duplicate provider", function()
			local malformed = mutableAuthorities()
			malformed[1].grantsByClass.class02[3].abilityId = ""
			local malformedBefore = copyAuthorities(malformed)
			local malformedResult = AbilityGrants.compileProductionRegistry(malformed, expectedClassIds())
			expect(malformedResult.ok):toBe(false)
			expect(malformedResult.registry):toBeNil()
			expect(hasProblem(malformedResult.problems, "abilityId must be a nonempty string")):toBe(true)
			expect(malformed):toEqual(malformedBefore)

			local repeated = mutableAuthorities()
			repeated[1].grantsByClass.class02[3].abilityId = repeated[1].grantsByClass.class02[2].abilityId
			local repeatedResult = AbilityGrants.compileProductionRegistry(repeated, expectedClassIds())
			expect(repeatedResult.ok):toBe(false)
			expect(repeatedResult.registry):toBeNil()
			expect(hasProblem(repeatedResult.problems, 'class "class02" repeats abilityId "ability2"')):toBe(true)

			local missing = mutableAuthorities()
			missing[1].grantsByClass.class02 = nil
			local missingResult = AbilityGrants.compileProductionRegistry(missing, expectedClassIds())
			expect(missingResult.ok):toBe(false)
			expect(missingResult.registry):toBeNil()
			expect(hasProblem(missingResult.problems, 'class "class02" is missing a provider')):toBe(true)

			local duplicate = mutableAuthorities()
			duplicate[2].grantsByClass.class02 = copyGrants(duplicate[1].grantsByClass.class02)
			local duplicateResult = AbilityGrants.compileProductionRegistry(duplicate, expectedClassIds())
			expect(duplicateResult.ok):toBe(false)
			expect(duplicateResult.registry):toBeNil()
			expect(hasProblem(duplicateResult.problems, 'class "class02" has 2 providers')):toBe(true)
		end)

		it("fails closed on unexpected classes, duplicate expectations, and cross-class ability collisions", function()
			local unexpected = mutableAuthorities()
			unexpected[1].grantsByClass.intruder = copyGrants(unexpected[1].grantsByClass.class02)
			local unexpectedResult = AbilityGrants.compileProductionRegistry(unexpected, expectedClassIds())
			expect(unexpectedResult.ok):toBe(false)
			expect(unexpectedResult.registry):toBeNil()
			expect(hasProblem(unexpectedResult.problems, 'unexpected class "intruder"')):toBe(true)

			local duplicateIds = expectedClassIds()
			duplicateIds[#duplicateIds + 1] = duplicateIds[1]
			local duplicateIdsResult = AbilityGrants.compileProductionRegistry(canonicalAuthorities(), duplicateIds)
			expect(duplicateIdsResult.ok):toBe(false)
			expect(duplicateIdsResult.registry):toBeNil()
			expect(hasProblem(duplicateIdsResult.problems, "is repeated")):toBe(true)

			local blankId = expectedClassIds()
			blankId[1] = ""
			local blankIdResult = AbilityGrants.compileProductionRegistry(canonicalAuthorities(), blankId)
			expect(blankIdResult.ok):toBe(false)
			expect(blankIdResult.registry):toBeNil()
			expect(hasProblem(blankIdResult.problems, "expected class id must be a nonempty string")):toBe(true)

			local collision = mutableAuthorities()
			collision[1].grantsByClass.class01[1].abilityId = collision[1].grantsByClass.class02[1].abilityId
			local collisionResult = AbilityGrants.compileProductionRegistry(collision, expectedClassIds())
			expect(collisionResult.ok):toBe(false)
			expect(collisionResult.registry):toBeNil()
			expect(hasProblem(collisionResult.problems, 'abilityId "ability1" collides across classes class01,class02')):toBe(
				true
			)
		end)

		it("rejects empty expectations, reordered curves, and every nonfinite level", function()
			local empty = AbilityGrants.compileProductionRegistry(canonicalAuthorities(), {})
			expect(empty.ok):toBe(false)
			expect(empty.registry):toBeNil()
			expect(hasProblem(empty.problems, "expected class ids must not be empty")):toBe(true)

			local reordered = mutableAuthorities()
			reordered[1].grantsByClass.class02[2], reordered[1].grantsByClass.class02[3] =
				reordered[1].grantsByClass.class02[3], reordered[1].grantsByClass.class02[2]
			local reorderedResult = AbilityGrants.compileProductionRegistry(reordered, expectedClassIds())
			expect(reorderedResult.ok):toBe(false)
			expect(reorderedResult.registry):toBeNil()
			expect(hasProblem(reorderedResult.problems, "must unlock at level")):toBe(true)

			for _, level in { math.nan, math.huge, -math.huge } do
				local authorities = mutableAuthorities()
				authorities[1].grantsByClass.class02[2].level = level
				local result = AbilityGrants.compileProductionRegistry(authorities, expectedClassIds())
				expect(result.ok):toBe(false)
				expect(result.registry):toBeNil()
				expect(hasProblem(result.problems, "level must be a finite whole number")):toBe(true)
			end
		end)

		it("keeps success and canonically sorted problems independent of authority and map order", function()
			local forward = AbilityGrants.compileProductionRegistry(canonicalAuthorities(), expectedClassIds())
			local reverseAuthorities = reversed(canonicalAuthorities())
			local reverse = AbilityGrants.compileProductionRegistry(reverseAuthorities, reversed(expectedClassIds()))
			expect(reverse):toEqual(forward)

			local malformed = mutableAuthorities()
			for _, authority in malformed do
				authority.grantsByClass = reorderedMap(authority.grantsByClass)
			end
			malformed[1].grantsByClass.class02[2].level = math.huge
			malformed[3].grantsByClass.class07[5].abilityId = ""
			local first = AbilityGrants.compileProductionRegistry(malformed, expectedClassIds())
			local second = AbilityGrants.compileProductionRegistry(reversed(malformed), reversed(expectedClassIds()))
			expect(first):toEqual(second)
			expect(isSorted(first.problems)):toBe(true)
		end)

		it("leaves inputs unchanged and returns deeply detached registries across calls", function()
			local authorities = mutableAuthorities()
			local ids = expectedClassIds()
			local authorityBefore = copyAuthorities(authorities)
			local idsBefore = table.clone(ids)
			local first = AbilityGrants.compileProductionRegistry(authorities, ids)
			local second = AbilityGrants.compileProductionRegistry(authorities, ids)
			expect(authorities):toEqual(authorityBefore)
			expect(ids):toEqual(idsBefore)
			local firstRegistry = assert(first.registry)
			local secondRegistry = assert(second.registry)
			firstRegistry.class02[1].abilityId = "changed"
			firstRegistry.class02[2].level = 5
			expect(firstRegistry.class02[1].abilityId):toBe("changed")
			expect(authorities):toEqual(authorityBefore)
			expect(secondRegistry.class02):toEqual(authorityBefore[1].grantsByClass.class02)
		end)

		it("reads a level-one grant as an ungated slot", function()
			local index = AbilityGrants.indexOf(RELEASE_CURVE)
			expect(AbilityGrants.gateFor(index, "ability11")):toBeNil()
			expect(AbilityGrants.gateFor(index, "ability12")):toBe(3)
			expect(AbilityGrants.gateFor(index, "ability15")):toBe(10)
		end)

		it("leaves an ability the class does not govern ungated", function()
			local index = AbilityGrants.indexOf(RELEASE_CURVE)
			expect(AbilityGrants.gateFor(index, "basicAttack")):toBeNil()
			expect(AbilityGrants.isGranted(index, "basicAttack", 1)):toBe(true)
		end)

		it("grants a kit progressively across ten levels", function()
			expect(AbilityGrants.grantedIds(RELEASE_CURVE, 1)):toEqual({ "ability11" })
			expect(AbilityGrants.grantedIds(RELEASE_CURVE, 4)):toEqual({ "ability11", "ability12" })
			expect(AbilityGrants.grantedIds(RELEASE_CURVE, 9)):toEqual({
				"ability11",
				"ability12",
				"ability13",
				"ability14",
			})
			expect(AbilityGrants.grantedIds(RELEASE_CURVE, 10)):toEqual({
				"ability11",
				"ability12",
				"ability13",
				"ability14",
				"ability15",
			})
		end)

		it("accepts the release curve and the shipped slice curve", function()
			expect(AbilityGrants.problemsFor(RELEASE_CURVE, "release")):toEqual({})
			expect(AbilityGrants.problemsFor(AbilityGrants.CLASS_KITS.class02, "slice")):toEqual({})
			for classId, grants in AbilityGrants.CLASS_KITS do
				if classId ~= "class02" then
					expect(AbilityGrants.problemsFor(grants, "release")):toEqual({})
				end
			end
		end)

		it("requires one grant at each of levels one through five in the class schema curve", function()
			local curve = {
				{ abilityId = "one", level = 1 },
				{ abilityId = "two", level = 2 },
				{ abilityId = "three", level = 3 },
				{ abilityId = "four", level = 4 },
				{ abilityId = "five", level = 5 },
			}
			expect(AbilityGrants.problemsForClassSchema(curve)):toEqual({})
			curve[2] = { abilityId = "two", level = 1 }
			expect(AbilityGrants.problemsForClassSchema(curve)[1]):toBe("class schema grant 2 must unlock at level 2")
			curve[2] = { abilityId = "two", level = 2 }
			curve[5] = { abilityId = "five", level = 4 }
			expect(AbilityGrants.problemsForClassSchema(curve)[1]):toBe("class schema grant 5 must unlock at level 5")
		end)

		it("uses Dewmere's authored Defender vocabulary for the Veilward", function()
			expect(AbilityGrants.CLASS_KITS.class05):toEqual({
				{ abilityId = "ability6", level = 1 },
				{ abilityId = "ability7", level = 3 },
				{ abilityId = "ability8", level = 5 },
				{ abilityId = "ability9", level = 7 },
				{ abilityId = "ability10", level = 10 },
			})
		end)

		it("refuses a slice curve dressed up as a release curve", function()
			local problems = AbilityGrants.problemsFor(AbilityGrants.CLASS_KITS.class02, "release")
			expect(#problems):toBe(1)
			expect(problems[1]):toBe("a release curve must grant its final slot at level 10")
		end)

		it("refuses a sixth slot, a repeat, a regression, and an out-of-range level", function()
			local sixth = table.clone(RELEASE_CURVE)
			sixth[6] = { abilityId = "extra", level = 10 }
			expect(AbilityGrants.problemsFor(sixth, "release")[1]):toBe("kit must grant exactly 5 abilities; found 6")

			local repeated = table.clone(RELEASE_CURVE)
			repeated[3] = { abilityId = "ability12", level = 5 }
			expect(AbilityGrants.problemsFor(repeated, "release")[1]):toBe('grant 3 repeats abilityId "ability12"')

			local regressed = table.clone(RELEASE_CURVE)
			regressed[4] = { abilityId = "ability14", level = 2 }
			expect(AbilityGrants.problemsFor(regressed, "release")[1]):toBe(
				"grant 4 lowers the unlock level below its predecessor"
			)

			local beyond = table.clone(RELEASE_CURVE)
			beyond[5] = { abilityId = "ability15", level = 11 }
			expect(AbilityGrants.problemsFor(beyond, "release")[1]):toBe(
				"grant 5 level must be a whole number within 1..10"
			)
		end)

		it("refuses a kit that cannot be played at level one", function()
			local late = table.clone(RELEASE_CURVE)
			late[1] = { abilityId = "ability11", level = 2 }
			expect(AbilityGrants.problemsFor(late, "release")[1]):toBe("the first kit slot must be granted at level 1")
		end)

		it("refuses an unknown curve", function()
			expect(AbilityGrants.problemsFor(RELEASE_CURVE, "talents")):toEqual({ "unknown grant curve: talents" })
		end)
	end)
	it("uses supplied kits, slot count and level cap", function()
		local kit = { { abilityId = "first", level = 1 }, { abilityId = "last", level = 4 } }
		local law = Module.grants({ slotCount = 2, maxLevel = 4, kits = { custom = kit } })
		expect(law.forClass("custom")):toBe(kit)
		expect(law.forClass("class02")):toBeNil()
		expect(law.problemsFor(kit, "release")):toEqual({})
		expect(law.problemsFor({ { abilityId = "first", level = 1 } }, "slice")[1]):toBe(
			"kit must grant exactly 2 abilities; found 1"
		)
		expect(law.compileProductionRegistry({
			{
				grantsByClass = {
					custom = { { abilityId = "first", level = 1 }, { abilityId = "last", level = 2 } },
				},
			},
		}, { "custom" }).ok):toBe(true)
	end)
end
