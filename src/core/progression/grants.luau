--!strict
local SocialShape = require("../social/shape")

export type Grant = {
	abilityId: string,
	level: number,
}

export type GrantIndex = { [string]: number }

export type ProductionRegistry = { [string]: { Grant } }

export type ProductionRegistryResult = {
	ok: boolean,
	registry: ProductionRegistry?,
	problems: { string },
}

export type Config = { slotCount: number, maxLevel: number, kits: ProductionRegistry }
local System = {}
function System.grants(config: Config)
	local SLOT_COUNT = config.slotCount
	local MAX_LEVEL = config.maxLevel
	local CLASS_KITS = config.kits
	local function forClass(classId: string): { Grant }?
		return CLASS_KITS[classId]
	end

	local function indexOf(grants: { Grant }): GrantIndex
		local out: GrantIndex = {}
		for _, grant in grants do
			out[grant.abilityId] = grant.level
		end
		return out
	end

	local function gateFor(index: GrantIndex, abilityId: string): number?
		local level = index[abilityId]
		if level == nil or level <= 1 then
			return nil
		end
		return level
	end

	local function isGranted(index: GrantIndex, abilityId: string, level: number): boolean
		return level >= (index[abilityId] or 1)
	end

	local function grantedIds(grants: { Grant }, level: number): { string }
		local out: { string } = {}
		for _, grant in grants do
			if level >= grant.level then
				out[#out + 1] = grant.abilityId
			end
		end
		return out
	end

	local function isWholeLevel(value: number): boolean
		return value == value and value == math.floor(value) and math.abs(value) ~= math.huge
	end

	local function problemsFor(grants: { Grant }, curve: string): { string }
		local out: { string } = {}
		if #grants ~= SLOT_COUNT then
			out[#out + 1] = ("kit must grant exactly %d abilities; found %d"):format(SLOT_COUNT, #grants)
		end
		local seen: { [string]: boolean } = {}
		local previous = 0
		local levels: { [number]: boolean } = {}
		local distinct = 0
		for i, grant in grants do
			if grant.abilityId == "" then
				out[#out + 1] = ("grant %d has an empty abilityId"):format(i)
			end
			if seen[grant.abilityId] then
				out[#out + 1] = ("grant %d repeats abilityId %q"):format(i, grant.abilityId)
			end
			seen[grant.abilityId] = true
			if not isWholeLevel(grant.level) or grant.level < 1 or grant.level > MAX_LEVEL then
				out[#out + 1] = ("grant %d level must be a whole number within 1..%d"):format(i, MAX_LEVEL)
			elseif grant.level < previous then
				out[#out + 1] = ("grant %d lowers the unlock level below its predecessor"):format(i)
			end
			if not levels[grant.level] then
				levels[grant.level] = true
				distinct += 1
			end
			previous = grant.level
		end
		if #grants > 0 and grants[1].level ~= 1 then
			out[#out + 1] = "the first kit slot must be granted at level 1"
		end
		if curve == "release" then
			if distinct ~= #grants then
				out[#out + 1] = "a release curve must grant each slot at a distinct level"
			end
			if #grants > 0 and grants[#grants].level ~= MAX_LEVEL then
				out[#out + 1] = ("a release curve must grant its final slot at level %d"):format(MAX_LEVEL)
			end
		elseif curve == "class_schema" then
			for index, grant in grants do
				local expectedLevel = index
				if grant.level ~= expectedLevel then
					out[#out + 1] = ("class schema grant %d must unlock at level %d"):format(index, expectedLevel)
				end
			end
		elseif curve ~= "slice" then
			out[#out + 1] = "unknown grant curve: " .. curve
		end
		return out
	end

	local function problemsForClassSchema(grants: { Grant }): { string }
		return problemsFor(grants, "class_schema")
	end

	local function compileProductionRegistry(
		authoritiesValue: unknown,
		expectedClassIds: { string }
	): ProductionRegistryResult
		local authorities = SocialShape.raw(authoritiesValue) or {}
		local problemSet: { [string]: boolean } = {}
		local expected: { [string]: boolean } = {}
		local providers: { [string]: { unknown } } = {}
		local abilityOwners: { [string]: { [string]: boolean } } = {}

		local function addProblem(problem: string)
			problemSet[problem] = true
		end

		if #expectedClassIds == 0 then
			addProblem("expected class ids must not be empty")
		end
		for _, classId in expectedClassIds do
			if type(classId) ~= "string" or classId == "" then
				addProblem("expected class id must be a nonempty string")
			elseif expected[classId] then
				addProblem(("expected class id %q is repeated"):format(classId))
			else
				expected[classId] = true
			end
		end

		for _, authority in authorities do
			local authorityFields = SocialShape.raw(authority)
			local grantsByClass = if authorityFields ~= nil then SocialShape.raw(authorityFields.grantsByClass) else nil
			if type(grantsByClass) ~= "table" then
				addProblem("authority must expose a grantsByClass table")
			else
				for rawClassId, grants in grantsByClass do
					if type(rawClassId) ~= "string" or rawClassId == "" then
						addProblem("authority grantsByClass must use nonempty string class ids")
					else
						local classId = rawClassId
						local bucket = providers[classId]
						if bucket == nil then
							bucket = {}
							providers[classId] = bucket
						end
						bucket[#bucket + 1] = grants
						if not expected[classId] then
							addProblem(("unexpected class %q"):format(classId))
						end
					end
				end
			end
		end

		local providerClassIds: { string } = {}
		for classId in providers do
			providerClassIds[#providerClassIds + 1] = classId
		end
		table.sort(providerClassIds)

		for _, classId in providerClassIds do
			local classProviders = providers[classId]
			if #classProviders > 1 then
				addProblem(("class %q has %d providers"):format(classId, #classProviders))
			end
			for _, grants in classProviders do
				if type(grants) ~= "table" then
					addProblem(("class %q grants must be an array table"):format(classId))
					continue
				end
				local entryCount = 0
				local hasNonArrayKey = false
				for key in assert(SocialShape.raw(grants)) do
					entryCount += 1
					if type(key) ~= "number" or key ~= math.floor(key) or key < 1 then
						hasNonArrayKey = true
					end
				end
				if entryCount ~= SLOT_COUNT then
					addProblem(
						("class %q must contain exactly %d grants; found %d"):format(classId, SLOT_COUNT, entryCount)
					)
				end
				if hasNonArrayKey then
					addProblem(("class %q grants must use positive whole array indexes"):format(classId))
				end
				local seenAbilityIds: { [string]: boolean } = {}
				for index = 1, SLOT_COUNT do
					local grant = SocialShape.raw(assert(SocialShape.raw(grants))[index])
					if grant == nil then
						addProblem(("class %q grant %d must be a table"):format(classId, index))
						continue
					end
					local abilityId = grant.abilityId
					if type(abilityId) ~= "string" or abilityId == "" then
						addProblem(("class %q grant %d abilityId must be a nonempty string"):format(classId, index))
					elseif seenAbilityIds[abilityId] then
						addProblem(("class %q repeats abilityId %q"):format(classId, abilityId))
					else
						seenAbilityIds[abilityId] = true
						local owners = abilityOwners[abilityId]
						if owners == nil then
							owners = {}
							abilityOwners[abilityId] = owners
						end
						owners[classId] = true
					end
					local level = grant.level
					if type(level) ~= "number" or not isWholeLevel(level) then
						addProblem(("class %q grant %d level must be a finite whole number"):format(classId, index))
					elseif level ~= index then
						addProblem(
							("class %q grant %d must unlock at level %d; found %d"):format(classId, index, index, level)
						)
					end
				end
			end
		end

		local expectedIds: { string } = {}
		for classId in expected do
			expectedIds[#expectedIds + 1] = classId
		end
		table.sort(expectedIds)
		for _, classId in expectedIds do
			local count = if providers[classId] ~= nil then #providers[classId] else 0
			if count == 0 then
				addProblem(("class %q is missing a provider"):format(classId))
			end
		end

		local abilityIds: { string } = {}
		for abilityId in abilityOwners do
			abilityIds[#abilityIds + 1] = abilityId
		end
		table.sort(abilityIds)
		for _, abilityId in abilityIds do
			local ownerIds: { string } = {}
			for classId in abilityOwners[abilityId] do
				ownerIds[#ownerIds + 1] = classId
			end
			table.sort(ownerIds)
			if #ownerIds > 1 then
				addProblem(("abilityId %q collides across classes %s"):format(abilityId, table.concat(ownerIds, ",")))
			end
		end

		local problems: { string } = {}
		for problem in problemSet do
			problems[#problems + 1] = problem
		end
		table.sort(problems)
		if #problems > 0 then
			return { ok = false, registry = nil, problems = problems }
		end

		local registry: ProductionRegistry = {}
		for _, classId in expectedIds do
			local source = assert(SocialShape.raw(providers[classId][1]))
			local grants: { Grant } = {}
			for index = 1, SLOT_COUNT do
				local row = assert(SocialShape.raw(source[index]))
				grants[index] = {
					abilityId = assert(SocialShape.string(row.abilityId)),
					level = assert(SocialShape.number(row.level)),
				}
			end
			registry[classId] = grants
		end
		return { ok = true, registry = registry, problems = {} }
	end

	return {
		SLOT_COUNT = SLOT_COUNT,
		MAX_LEVEL = MAX_LEVEL,
		CLASS_KITS = CLASS_KITS,
		forClass = forClass,
		indexOf = indexOf,
		gateFor = gateFor,
		isGranted = isGranted,
		grantedIds = grantedIds,
		problemsFor = problemsFor,
		problemsForClassSchema = problemsForClassSchema,
		compileProductionRegistry = compileProductionRegistry,
	}
end
return System
