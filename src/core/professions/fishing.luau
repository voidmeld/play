--!strict
local Value = require("../../kernel/value")

local Skills = require("./skills")
local Types = require("./types")

type State = Skills.State
type FishRow = Types.FishRow

export type Phase = "idle" | "waiting" | "bite"

export type Line = {
	phase: Phase,
	castAt: number,
	biteAt: number,
	missAt: number,
}

export type Catch = {
	ok: boolean,
	reason: string?,
	state: State,
	itemId: string?,
	isFish: boolean,
	skillUp: boolean,
	color: string?,
	skill: number,
}

export type Config = {
	core: {
		read knows: (State, string) -> boolean,
		read skillOf: (State, string) -> number,
		read colorFor: (number, Types.Thresholds) -> string?,
		read rollSkillUp: (State, string, Types.Thresholds, number) -> (State, boolean, string?),
	},
	professionId: string,
	waitMin: number,
	waitMax: number,
	biteWindow: number,
	fishTable: (string) -> { FishRow },
	junk: { FishRow },
}

local System = {}

function System.create(config: Config)
	local Core = config.core
	local Fishing = {}

	function Fishing.idle(): Line
		return { phase = "idle", castAt = 0, biteAt = 0, missAt = 0 }
	end

	function Fishing.cast(line: Line, state: State, now: number, waitRoll: number): (Line?, string?)
		if line.phase ~= "idle" then
			return nil, "line_in_water"
		end
		if not Core.knows(state, config.professionId) then
			return nil, "profession_not_known"
		end
		local span = config.waitMax - config.waitMin
		local wait = config.waitMin + math.clamp(waitRoll, 0, 1) * span
		return {
			phase = "waiting",
			castAt = now,
			biteAt = now + wait,
			missAt = now + wait + config.biteWindow,
		},
			nil
	end

	function Fishing.observe(line: Line, now: number): Line
		if line.phase == "waiting" and now >= line.biteAt then
			if now >= line.missAt then
				return Fishing.idle()
			end
			return { phase = "bite", castAt = line.castAt, biteAt = line.biteAt, missAt = line.missAt }
		end
		if line.phase == "bite" and now >= line.missAt then
			return Fishing.idle()
		end
		return line
	end

	function Fishing.hook(line: Line, now: number): (boolean, string)
		local seen = Fishing.observe(line, now)
		if seen.phase == "bite" then
			return true, "bite"
		elseif seen.phase == "idle" and line.phase ~= "idle" then
			return false, "too_slow"
		end
		return false, "too_early"
	end

	function Fishing.pick(zoneId: string, skill: number, roll: number): FishRow?
		local rows: { FishRow } = {}
		local total = 0
		for _, row in config.fishTable(zoneId) do
			if row.requiredSkill <= skill then
				table.insert(rows, row)
				total += row.weight
			end
		end
		for _, row in config.junk do
			table.insert(rows, row)
			total += row.weight
		end
		if total <= 0 then
			return nil
		end
		local target = math.clamp(roll, 0, 0.999999) * total
		local running = 0
		for _, row in rows do
			running += row.weight
			if target < running then
				return row
			end
		end
		return rows[#rows]
	end

	function Fishing.isJunk(itemId: string): boolean
		for _, row in config.junk do
			if row.itemId == itemId then
				return true
			end
		end
		return false
	end

	function Fishing.reel(state: State, zoneId: string, rng: () -> number): Catch
		if not Core.knows(state, config.professionId) then
			return {
				ok = false,
				reason = "profession_not_known",
				state = state,
				itemId = nil,
				isFish = false,
				skillUp = false,
				color = nil,
				skill = 0,
			}
		end
		local skill = Core.skillOf(state, config.professionId)
		local row = Fishing.pick(zoneId, skill, rng())
		if row == nil then
			return {
				ok = false,
				reason = "nothing_biting",
				state = state,
				itemId = nil,
				isFish = false,
				skillUp = false,
				color = nil,
				skill = skill,
			}
		end
		local junk = Fishing.isJunk(row.itemId)
		local nextState, gained, color = state, false, nil
		if not junk then
			nextState, gained, color = Core.rollSkillUp(state, config.professionId, row.thresholds, rng())
		end
		return {
			ok = true,
			reason = nil,
			state = nextState,
			itemId = row.itemId,
			isFish = not junk,
			skillUp = gained,
			color = color,
			skill = Core.skillOf(nextState, config.professionId),
		}
	end

	return Value.freezeDeep(Fishing)
end

return Value.freezeDeep(System)
