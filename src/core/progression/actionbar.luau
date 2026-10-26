--!strict
local SocialShape = require("../social/shape")

type Raw = { [unknown]: unknown }
type RawState = { custom: unknown, slots: Raw, level: unknown }

export type State = { custom: boolean, level: number, slots: { [string]: string } }
export type Context = {
	authored: { [number]: string },
	owned: { [string]: boolean },
	required: { [string]: number },
	level: number,
	carried: { [string]: boolean }?,
}
export type Layout = { [number]: string }
export type Intent = {
	op: string?,
	slot: number?,
	from: number?,
	actionId: string?,
}

export type Config = { barSize: number, barCount: number, maxActionId: number, maxLevel: number, itemPrefix: string }
local System = {}
function System.actionbar(config: Config)
	local BAR_SIZE = config.barSize
	local BAR_COUNT = config.barCount
	local SLOT_COUNT = BAR_SIZE * BAR_COUNT
	local MAX_ACTION_ID = config.maxActionId
	local MAX_WIRE_BYTES = SLOT_COUNT * MAX_ACTION_ID + SLOT_COUNT - 1
	local WIRE_EMPTY = "-"

	local function itemId(actionId: string): string?
		local id = if string.sub(actionId, 1, #config.itemPrefix) == config.itemPrefix
			then string.match(string.sub(actionId, #config.itemPrefix + 1), "^([%w_%.%-]+)$")
			else nil
		return if id ~= nil and #actionId <= MAX_ACTION_ID then assert(SocialShape.string(id)) else nil
	end

	local function itemAction(id: string): string
		assert(string.match(id, "^[%w_%.%-]+$") and #id + #config.itemPrefix <= MAX_ACTION_ID, "item_action_invalid")
		return config.itemPrefix .. id
	end

	local function validAction(id: unknown): boolean
		return type(id) == "string"
			and #id <= MAX_ACTION_ID
			and (itemId(id) ~= nil or string.match(id, "^[%w_%.%-]+$") ~= nil)
	end

	local function whole(value: unknown): boolean
		return type(value) == "number" and value == value and value == math.floor(value)
	end

	local function validSlot(slot: unknown): boolean
		return type(slot) == "number" and whole(slot) and slot >= 1 and slot <= SLOT_COUNT
	end

	local function default(): State
		return { custom = false, level = 0, slots = {} }
	end

	local function copy(state: State): State
		local slots: { [string]: string } = {}
		for key, id in state.slots do
			slots[key] = id
		end
		return { custom = state.custom, level = state.level, slots = slots }
	end

	local function contextFor(loadout: unknown, level: unknown, items: { [string]: boolean }?): Context
		local authored: { [number]: string } = {}
		local owned: { [string]: boolean } = {}
		local required: { [string]: number } = {}
		local ctx: Context = { authored = authored, owned = owned, required = required, level = 0 }
		if type(loadout) ~= "table" or type(level) ~= "number" or not whole(level) then
			return ctx
		end
		local slots = assert(SocialShape.raw(loadout)).slots
		if type(slots) ~= "table" then
			return ctx
		end
		ctx.level = level
		for _, row in assert(SocialShape.raw(slots)) do
			if type(row) ~= "table" then
				continue
			end
			local fields = assert(SocialShape.raw(row))
			local slot, abilityId, requiredLevel = fields.slot, fields.abilityId, fields.requiredLevel
			if
				type(slot) == "number"
				and validSlot(slot)
				and type(abilityId) == "string"
				and type(requiredLevel) == "number"
				and whole(requiredLevel)
				and level >= requiredLevel
			then
				authored[slot] = abilityId
				owned[abilityId] = true
				required[abilityId] = requiredLevel
			end
		end
		if items ~= nil then
			local carried: { [string]: boolean } = {}
			for id, present in items do
				local action = itemAction(id)
				owned[action], required[action], carried[action] = true, 0, present
			end
			ctx.carried = carried
		end
		return ctx
	end

	local function placed(layout: Layout, abilityId: string): number?
		for slot = 1, SLOT_COUNT do
			if layout[slot] == abilityId then
				return slot
			end
		end
		return nil
	end

	local function effective(state: unknown, ctx: Context): Layout
		local layout: Layout = {}
		if
			type(state) ~= "table"
			or assert(SocialShape.raw(state)).custom ~= true
			or type(assert(SocialShape.raw(state)).slots) ~= "table"
		then
			for slot = 1, SLOT_COUNT do
				local id = ctx.authored[slot]
				if id ~= nil and ctx.owned[id] == true then
					layout[slot] = id
				end
			end
			return layout
		end
		local stateFields = assert(SocialShape.raw(state))
		local stateSlots = assert(SocialShape.raw(stateFields.slots))
		for slot = 1, SLOT_COUNT do
			local id = stateSlots[tostring(slot)]
			if type(id) == "string" and ctx.owned[id] == true and placed(layout, id) == nil then
				layout[slot] = id
			end
		end
		local seen = if whole(stateFields.level) then assert(SocialShape.number(stateFields.level)) else 0
		for slot = 1, SLOT_COUNT do
			local id = ctx.authored[slot]
			if
				id ~= nil
				and ctx.owned[id] == true
				and ctx.required[id] > seen
				and layout[slot] == nil
				and placed(layout, id) == nil
			then
				layout[slot] = id
			end
		end
		return layout
	end

	local function stateOf(layout: Layout, ctx: Context): State
		local slots: { [string]: string } = {}
		for slot = 1, SLOT_COUNT do
			if layout[slot] ~= nil then
				slots[tostring(slot)] = layout[slot]
			end
		end
		return { custom = true, level = ctx.level, slots = slots }
	end

	local function normalize(raw: unknown, ctx: Context): State
		if
			type(raw) ~= "table"
			or assert(SocialShape.raw(raw)).custom ~= true
			or type(assert(SocialShape.raw(raw)).slots) ~= "table"
		then
			return default()
		end
		local fields = assert(SocialShape.raw(raw))
		local fieldSlots = SocialShape.raw(fields.slots)
		local layout: Layout = {}
		for slot = 1, SLOT_COUNT do
			local id = assert(fieldSlots)[tostring(slot)]
			if type(id) == "string" and validAction(id) and ctx.owned[id] == true and placed(layout, id) == nil then
				layout[slot] = id
			end
		end
		local state = stateOf(layout, ctx)
		state.level = if whole(fields.level)
				and (assert(SocialShape.number(fields.level))) >= 0
				and (assert(SocialShape.number(fields.level))) <= ctx.level
			then assert(SocialShape.number(fields.level))
			else ctx.level
		return state
	end

	local function shapeValid(raw: unknown): boolean
		local fields = SocialShape.raw(raw)
		if fields == nil then
			return false
		end
		local fieldSlots = SocialShape.raw(fields.slots)
		if
			type(raw) ~= "table"
			or type(fields.custom) ~= "boolean"
			or not whole(fields.level)
			or (assert(SocialShape.number(fields.level))) < 0
			or (assert(SocialShape.number(fields.level))) > config.maxLevel
			or type(fields.slots) ~= "table"
		then
			return false
		end
		for key in assert(SocialShape.raw(raw)) do
			if key ~= "custom" and key ~= "level" and key ~= "slots" then
				return false
			end
		end
		for key, id in assert(fieldSlots) do
			local slot = if type(key) == "string" then tonumber(key) else nil
			if slot == nil or not validSlot(slot) or tostring(slot) ~= key or not validAction(id) then
				return false
			end
		end
		return true
	end

	local function assign(state: unknown, ctx: Context, slot: unknown, abilityId: unknown): (State?, string?)
		if not validSlot(slot) then
			return nil, "slot_invalid"
		end
		if type(abilityId) ~= "string" or ctx.owned[abilityId] ~= true then
			return nil, "ability_not_owned"
		end
		if itemId(abilityId) ~= nil and (ctx.carried == nil or ctx.carried[abilityId] ~= true) then
			return nil, "item_not_carried"
		end
		local validIndex = assert(SocialShape.number(slot))
		local layout = effective(state, ctx)
		local displaced = layout[validIndex]
		local origin = placed(layout, abilityId)
		layout[validIndex] = abilityId
		if origin ~= nil and origin ~= validIndex then
			layout[origin] = displaced
		end
		return stateOf(layout, ctx), nil
	end

	local function swap(state: unknown, ctx: Context, first: unknown, second: unknown): (State?, string?)
		if not validSlot(first) or not validSlot(second) then
			return nil, "slot_invalid"
		end
		local fromSlot, toSlot = assert(SocialShape.number(first)), assert(SocialShape.number(second))
		local layout = effective(state, ctx)
		layout[fromSlot], layout[toSlot] = layout[toSlot], layout[fromSlot]
		return stateOf(layout, ctx), nil
	end

	local function clear(state: unknown, ctx: Context, slot: unknown): (State?, string?)
		if not validSlot(slot) then
			return nil, "slot_invalid"
		end
		local validIndex = assert(SocialShape.number(slot))
		local layout = effective(state, ctx)
		layout[validIndex] = nil
		return stateOf(layout, ctx), nil
	end

	local function apply(state: unknown, ctx: Context, intent: unknown): (State?, string?)
		if type(intent) ~= "table" then
			return nil, "intent_invalid"
		end
		local fields = assert(SocialShape.raw(intent))
		local op = fields.op
		if op == "assign" then
			return assign(state, ctx, fields.slot, fields.actionId)
		elseif op == "swap" then
			return swap(state, ctx, fields.from, fields.slot)
		elseif op == "clear" then
			return clear(state, ctx, fields.slot)
		elseif op == "reset" then
			return default(), nil
		end
		return nil, "op_invalid"
	end

	local function encodeWire(layout: Layout): string
		local out = {}
		for slot = 1, SLOT_COUNT do
			local id = layout[slot]
			assert(id == nil or validAction(id), "action_wire_invalid")
			out[slot] = id or WIRE_EMPTY
		end
		return table.concat(out, "|")
	end

	local function decodeWire(wire: unknown, ctx: Context): Layout?
		if type(wire) ~= "string" or #wire > MAX_WIRE_BYTES then
			return nil
		end
		local fields = string.split(wire, "|")
		if #fields ~= SLOT_COUNT then
			return nil
		end
		local layout: Layout = {}
		for slot = 1, SLOT_COUNT do
			local id = fields[slot]
			if id ~= WIRE_EMPTY then
				if not validAction(id) or ctx.owned[id] ~= true or placed(layout, id) ~= nil then
					return nil
				end
				layout[slot] = id
			end
		end
		return layout
	end

	local function slotFor(position: unknown, layer: unknown): number?
		if
			type(position) ~= "number"
			or not whole(position)
			or position < 1
			or position > BAR_SIZE
			or type(layer) ~= "number"
			or not whole(layer)
			or layer < 1
			or layer > BAR_COUNT
		then
			return nil
		end
		return (layer - 1) * BAR_SIZE + position
	end

	local function layerEntries(
		layout: Layout,
		layer: unknown
	): { { position: number, slot: number, actionId: string } }
		local out = {}
		for position = 1, BAR_SIZE do
			local slot = slotFor(position, layer)
			local id = if slot ~= nil then layout[slot] else nil
			if slot ~= nil and id ~= nil then
				table.insert(out, { position = position, slot = slot, actionId = id })
			end
		end
		return out
	end

	local function resolvePress(layout: Layout, position: unknown, layer: unknown): string?
		local slot = slotFor(position, layer)
		return if slot ~= nil then layout[slot] else nil
	end

	return table.freeze({
		BAR_SIZE = BAR_SIZE,
		BAR_COUNT = BAR_COUNT,
		SLOT_COUNT = SLOT_COUNT,
		MAX_WIRE_BYTES = MAX_WIRE_BYTES,
		itemId = itemId,
		itemAction = itemAction,
		default = default,
		copy = copy,
		contextFor = contextFor,
		effective = effective,
		normalize = normalize,
		shapeValid = shapeValid,
		assign = assign,
		swap = swap,
		clear = clear,
		apply = apply,
		placed = placed,
		encodeWire = encodeWire,
		decodeWire = decodeWire,
		slotFor = slotFor,
		resolvePress = resolvePress,
		layerEntries = layerEntries,
	})
end
return System
