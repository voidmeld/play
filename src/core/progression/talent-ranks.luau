--!strict

local Talents = require("./talents")

export type Loadout = Talents.Loadout
export type Result = Talents.Result
export type Node = { read id: string, read lineId: string, read tier: number, read ranks: number }
export type Tier = { read tier: number, read gate: number, read costPerRank: number }
export type Line = { read id: string }
type List<T> = { read [number]: T }
export type Spec = { read class: string, read lines: List<Line>, read tiers: List<Tier>, read nodes: List<Node> }
export type Bucket = { ranks: { [string]: number }, respecCount: number }
export type RoleReason = "ambiguous role" | "unknown role"

local UNKNOWN_TALENT = "unknown talent"
local FULL_RANK = "talent at full rank"
local TIER_LOCKED = "tier locked"
local NO_POINTS = "no talent points available"
local INVALID_STATE = "invalid talent state"

local function whole(value: unknown): boolean
	return type(value) == "number" and value == value and value == math.floor(value) and value < math.huge
end

local function specForRole<S>(specs: List<S & Spec>, role: string): ((S & Spec)?, RoleReason?)
	local found: (S & Spec)? = nil
	for _, spec in specs do
		if spec.class == role then
			if found ~= nil then
				return nil, "ambiguous role"
			end
			found = spec
		end
	end
	if found == nil then
		return nil, "unknown role"
	end
	return found, nil
end

local function nodeById(spec: Spec, talentId: string): Node?
	for _, node in spec.nodes do
		if node.id == talentId then
			return node
		end
	end
	return nil
end

local function tierRow(spec: Spec, tier: number): Tier?
	for _, row in spec.tiers do
		if row.tier == tier then
			return row
		end
	end
	return nil
end

local function emptyBucket(): Bucket
	return { ranks = {}, respecCount = 0 }
end

local function cloneLoadout(loadout: Talents.Loadout?): Talents.Loadout
	local roles: { [string]: Bucket } = {}
	if loadout ~= nil then
		for role, bucket in loadout.roles do
			roles[role] = { ranks = table.clone(bucket.ranks), respecCount = bucket.respecCount }
		end
	end
	return { roles = roles }
end

local function bucketOf(loadout: Talents.Loadout?, role: string): Bucket
	local bucket = if loadout ~= nil then loadout.roles[role] else nil
	return bucket or emptyBucket()
end

local function cost(spec: Spec, node: Node, rank: number): number
	local row = tierRow(spec, node.tier)
	return rank * (if row ~= nil then row.costPerRank else math.huge)
end

local function spendByLine(spec: Spec, ranks: { [string]: number }, belowTier: number?): { [string]: number }
	local spend: { [string]: number } = {}
	for _, line in spec.lines do
		spend[line.id] = 0
	end
	for _, node in spec.nodes do
		local rank = ranks[node.id]
		if rank ~= nil and (belowTier == nil or node.tier < belowTier) then
			spend[node.lineId] = (spend[node.lineId] or 0) + cost(spec, node, rank)
		end
	end
	return spend
end

local function spentTotal(spec: Spec, ranks: { [string]: number }): number
	local total = 0
	for _, spent in spendByLine(spec, ranks) do
		total += spent
	end
	return total
end

local function stateProblem(spec: Spec, bucket: Bucket, points: number): string?
	if not whole(points) or points < 0 or not whole(bucket.respecCount) or bucket.respecCount < 0 then
		return INVALID_STATE
	end
	for talentId, rank in bucket.ranks do
		local node = nodeById(spec, talentId)
		if node == nil or not whole(rank) or rank < 1 or rank > node.ranks then
			return INVALID_STATE
		end
		local row = tierRow(spec, node.tier)
		if row == nil then
			return INVALID_STATE
		end
		local below = spendByLine(spec, bucket.ranks, node.tier)
		if (below[node.lineId] or 0) < row.gate then
			return INVALID_STATE
		end
	end
	if spentTotal(spec, bucket.ranks) > points then
		return INVALID_STATE
	end
	return nil
end

local function rankRefusal(
	loadout: Talents.Loadout?,
	specs: List<Spec>,
	role: string,
	points: number,
	talentId: string
): string?
	local spec, roleReason = specForRole(specs, role)
	if spec == nil then
		return roleReason
	end
	local bucket = bucketOf(loadout, role)
	if stateProblem(spec, bucket, points) ~= nil then
		return INVALID_STATE
	end
	local node = nodeById(spec, talentId)
	if node == nil then
		return UNKNOWN_TALENT
	end
	local rank = bucket.ranks[talentId] or 0
	if rank >= node.ranks then
		return FULL_RANK
	end
	local row = tierRow(spec, node.tier)
	if row == nil then
		return UNKNOWN_TALENT
	end
	if (spendByLine(spec, bucket.ranks, node.tier)[node.lineId] or 0) < row.gate then
		return TIER_LOCKED
	end
	if points - spentTotal(spec, bucket.ranks) < row.costPerRank then
		return NO_POINTS
	end
	return nil
end

local function addRank(
	loadout: Talents.Loadout?,
	specs: List<Spec>,
	role: string,
	points: number,
	talentId: string
): Talents.Result
	local refusal = rankRefusal(loadout, specs, role, points, talentId)
	local nextLoadout = cloneLoadout(loadout)
	if refusal ~= nil then
		return { ok = false, state = nextLoadout, reason = refusal }
	end
	local bucket = nextLoadout.roles[role]
	if bucket == nil then
		bucket = emptyBucket()
		nextLoadout.roles[role] = bucket
	end
	bucket.ranks[talentId] = (bucket.ranks[talentId] or 0) + 1
	return { ok = true, state = nextLoadout, reason = nil }
end

local function respecRole(loadout: Talents.Loadout?, specs: List<Spec>, role: string): Talents.Result
	local spec, roleReason = specForRole(specs, role)
	local nextLoadout = cloneLoadout(loadout)
	if spec == nil then
		return { ok = false, state = nextLoadout, reason = roleReason }
	end
	local previous = bucketOf(loadout, role)
	if not whole(previous.respecCount) or previous.respecCount < 0 then
		return { ok = false, state = nextLoadout, reason = INVALID_STATE }
	end
	nextLoadout.roles[role] = { ranks = {}, respecCount = previous.respecCount + 1 }
	return { ok = true, state = nextLoadout, reason = nil }
end

local function spentPoints(loadout: Talents.Loadout?, specs: List<Spec>, role: string): number
	local spec = specForRole(specs, role)
	if spec == nil then
		return 0
	end
	return spentTotal(spec, bucketOf(loadout, role).ranks)
end

local function availablePoints(loadout: Talents.Loadout?, specs: List<Spec>, role: string, points: number): number
	return math.max(0, points - spentPoints(loadout, specs, role))
end

return table.freeze({
	UNKNOWN_TALENT = UNKNOWN_TALENT,
	FULL_RANK = FULL_RANK,
	TIER_LOCKED = TIER_LOCKED,
	NO_POINTS = NO_POINTS,
	INVALID_STATE = INVALID_STATE,
	specForRole = specForRole,
	bucketOf = bucketOf,
	spendByLine = spendByLine,
	stateProblem = stateProblem,
	rankRefusal = rankRefusal,
	addRank = addRank,
	respecRole = respecRole,
	spentPoints = spentPoints,
	availablePoints = availablePoints,
})
