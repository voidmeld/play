--!strict
local Value = require("../../kernel/value")

export type Kind = "gather" | "skin" | "craft" | "fish"

export type Session = {
	kind: Kind,
	key: string,
	startedAt: number,
	endsAt: number,
	startX: number,
	startZ: number,
	startHealth: number,
}

export type Sample = {
	now: number,
	x: number,
	z: number,
	health: number,
	alive: boolean,
	inCombat: boolean,
	arrivalProtected: boolean?,
}

local System = {}

function System.create(config: { moveTolerance: number, blocked: (Kind, Sample) -> string? })
	local Session = {}
	local MOVE_TOLERANCE = config.moveTolerance

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	function Session.begin(kind: Kind, key: string, durationSec: number, sample: Sample): (Session?, string?)
		if
			not finite(durationSec)
			or durationSec <= 0
			or not finite(sample.now)
			or not finite(sample.x)
			or not finite(sample.z)
			or not finite(sample.health)
		then
			return nil, "invalid_sample"
		end
		if not sample.alive then
			return nil, "dead"
		end
		local blocked = config.blocked(kind, sample)
		if blocked ~= nil then
			return nil, blocked
		end
		if sample.inCombat then
			return nil, "in_combat"
		end
		return {
			kind = kind,
			key = key,
			startedAt = sample.now,
			endsAt = sample.now + durationSec,
			startX = sample.x,
			startZ = sample.z,
			startHealth = sample.health,
		},
			nil
	end

	function Session.check(session: Session, sample: Sample): (string, string?)
		if not sample.alive then
			return "interrupt", "dead"
		end
		local blocked = config.blocked(session.kind, sample)
		if blocked ~= nil then
			return "interrupt", blocked
		end
		if sample.inCombat then
			return "interrupt", "in_combat"
		end
		if sample.health < session.startHealth then
			return "interrupt", "damaged"
		end
		local dx = sample.x - session.startX
		local dz = sample.z - session.startZ
		if dx * dx + dz * dz > MOVE_TOLERANCE * MOVE_TOLERANCE then
			return "interrupt", "moved"
		end
		if sample.now >= session.endsAt then
			return "complete", nil
		end
		return "continue", nil
	end

	Session.MOVE_TOLERANCE = MOVE_TOLERANCE

	return Value.freezeDeep(Session)
end

return Value.freezeDeep(System)
