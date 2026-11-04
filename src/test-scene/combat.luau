--!strict

local Combat = require("../core/combat.luau")
local Contact = require("../core/combat/contact")
local Value = require("../kernel/value")
export type Payload = { read impact: number, read tags: { [string]: number } }
type Identity = { id: string, characterId: string?, epoch: number?, contentId: string? }
local function copyPayload(raw: unknown): (Payload?, string?)
	local fields = Value.record(raw, { impact = true, tags = true }, true)
	if fields == nil or type(fields.impact) ~= "number" or not Value.finite(fields.impact) then
		return nil, "impact_invalid"
	end
	local rows = Value.raw(fields.tags)
	if rows == nil then
		return nil, "tags_invalid"
	end
	local tags: { [string]: number } = {}
	for key, value in rows do
		if type(key) ~= "string" or type(value) ~= "number" or not Value.finite(value) then
			return nil, "tags_invalid"
		end
		tags[key] = value
	end
	return { impact = fields.impact, tags = tags }, nil
end
local function new()
	local rules: Contact.API<Payload> =
		Combat.contact.configure({ copyPayload = copyPayload, epsilon = 1e-6, idLimit = 128 })
	local function admission()
		local source: Identity = { id = "sender", characterId = "body-a", epoch = 1 }
		local target: Identity = { id = "recipient", characterId = "body-b", epoch = 2, contentId = "creature-a" }
		return {
			source = source,
			target = target,
			equipmentToken = "held-a",
			sequence = 7,
			startedTick = 10,
			anticipationSec = 0.25,
			contactSec = 0.1,
			recoverySec = 0.2,
			rangeStuds = 4,
			payload = { impact = 3, tags = { glyph = 4 } },
		}
	end
	local function source()
		return { identity = admission().source, alive = true, blocked = false, equipmentToken = "held-a" }
	end
	local function observation()
		return {
			source = source(),
			target = { identity = admission().target, alive = true },
			distanceStuds = 3,
			spatial = { clear = true, distanceStuds = 3 },
			spatialExempt = false,
			allowed = true,
		}
	end
	return { rules = rules, admission = admission, source = source, observation = observation }
end
return table.freeze({ new = new })
