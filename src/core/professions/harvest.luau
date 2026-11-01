--!strict
local Value = require("../value")

local Skills = require("./skills")
local Types = require("./types")

type State = Skills.State
type NodeKind = Types.NodeKind
type SkinRow = Types.SkinRow

export type Yield = { itemId: string, quantity: number }

export type Outcome = {
	ok: boolean,
	reason: string?,
	state: State,
	yields: { Yield },
	skillUp: boolean,
	color: string?,
	skill: number,
}

export type Config = {
	core: {
		read profession: (unknown) -> Skills.Profession?,
		read knows: (State, string) -> boolean,
		read skillOf: (State, string) -> number,
		read colorFor: (number, Types.Thresholds) -> string?,
		read rollSkillUp: (State, string, Types.Thresholds, number) -> (State, boolean, string?),
	},
	skinningId: string,
}

local System = {}

function System.create(config: Config)
	local Core = config.core
	local Gather = {}

	local function refuse(state: State, reason: string): Outcome
		return { ok = false, reason = reason, state = state, yields = {}, skillUp = false, color = nil, skill = 0 }
	end

	local function rollCount(minYield: number, maxYield: number, rng: () -> number): number
		if maxYield <= minYield then
			return minYield
		end
		return minYield + math.min(maxYield - minYield, math.floor(rng() * (maxYield - minYield + 1)))
	end

	local function resolve(state: State, professionId: string, row: NodeKind | SkinRow, rng: () -> number): Outcome
		if Core.profession(professionId) == nil then
			return refuse(state, "unknown_profession")
		end
		if not Core.knows(state, professionId) then
			return refuse(state, "profession_not_known")
		end
		local skill = Core.skillOf(state, professionId)
		if skill < row.requiredSkill then
			return refuse(state, "skill_too_low")
		end
		local yields: { Yield } = {}
		table.insert(yields, { itemId = row.itemId, quantity = rollCount(row.minYield, row.maxYield, rng) })
		local extras: { Types.Extra } = row.extras
		for _, extra in extras do
			if rng() < extra.chance then
				table.insert(yields, { itemId = extra.itemId, quantity = extra.quantity })
			end
		end
		local nextState, gained, color = Core.rollSkillUp(state, professionId, row.thresholds, rng())
		return {
			ok = true,
			reason = nil,
			state = nextState,
			yields = yields,
			skillUp = gained,
			color = color,
			skill = Core.skillOf(nextState, professionId),
		}
	end

	function Gather.canAttempt(state: State, professionId: string, row: NodeKind | SkinRow): (boolean, string?)
		if not Core.knows(state, professionId) then
			return false, "profession_not_known"
		end
		if Core.skillOf(state, professionId) < row.requiredSkill then
			return false, "skill_too_low"
		end
		return true, nil
	end

	function Gather.harvestNode(state: State, nodeKind: NodeKind, rng: () -> number): Outcome
		return resolve(state, nodeKind.profession, nodeKind, rng)
	end

	function Gather.skinCorpse(state: State, skinRow: SkinRow, rng: () -> number): Outcome
		return resolve(state, config.skinningId, skinRow, rng)
	end

	return Value.freezeDeep(Gather)
end

return Value.freezeDeep(System)
