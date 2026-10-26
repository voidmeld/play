--!strict

local Shape = require("./shape")

export type Slot = { id: string, hubId: string, realmId: string, label: string }
export type Config = { maxIdLength: number, maxLabelLength: number, maxSlots: number, realms: { [string]: boolean } }

local Homes = {}

function Homes.guildhome(config: Config)
	local Core = {}
	function Core.slots(catalog: unknown): { Slot }?
		local raw = Shape.raw(catalog)
		if raw == nil or Shape.dense(raw.slots, config.maxSlots) == nil then
			return nil
		end
		local slots: { Slot } = {}
		local seen: { [string]: boolean } = {}
		for _, entry in assert(Shape.raw(raw.slots)) do
			local value = Shape.raw(entry)
			if value == nil or not Shape.exact(entry, { id = true, hubId = true, realmId = true, label = true }) then
				return nil
			end
			local id, hubId, realmId, label = value.id, value.hubId, value.realmId, value.label
			if
				type(id) ~= "string"
				or not Shape.opaque(id, config.maxIdLength)
				or type(hubId) ~= "string"
				or not Shape.opaque(hubId, config.maxIdLength)
				or type(realmId) ~= "string"
				or config.realms[realmId] ~= true
				or type(label) ~= "string"
				or not Shape.opaque(label, config.maxLabelLength)
				or seen[id]
			then
				return nil
			end
			seen[id] = true
			table.insert(slots, { id = id, hubId = hubId, realmId = realmId, label = label })
		end
		return Shape.freezeDeep(slots)
	end
	function Core.slotFor(catalog: unknown, realmId: unknown): Slot?
		local slots = Core.slots(catalog)
		if slots == nil then
			return nil
		end
		for _, slot in slots do
			if slot.realmId == realmId then
				return slot
			end
		end
		return nil
	end
	return Core
end

return Homes
