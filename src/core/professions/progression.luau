--!strict

local Milestones = require("./milestones")
local Tokens = require("./tokens")
local Value = require("../../kernel/value")
local WorkOrders = require("../orders/work")

export type Tokens = { craft: string, equip: string, order: string }
export type WorkOrder = { orderId: string, capabilityRank: number, state: WorkOrders.State }
export type State = {
	revision: number,
	gatherSlots: { [string]: number },
	milestones: Milestones.State,
	tokens: Tokens,
	workOrder: WorkOrder,
}
export type Config = {
	nodeIds: { [string]: boolean },
	milestones: Milestones.Config,
	orders: { [string]: WorkOrders.WorkOrder },
	maxTokenLength: number,
}

local MAX_INTEGER = 9007199254740991
local Progression = {}

function Progression.create(config: Config)
	local nodes = table.clone(config.nodeIds)
	local milestones = Milestones.create(config.milestones)
	local tokens = Tokens.create({ names = { "craft", "equip", "order" }, maxLength = config.maxTokenLength })
	local orders: { [string]: WorkOrders.WorkOrder } = {}
	for id, raw in config.orders do
		local order = assert(WorkOrders.projectOrder(raw), "invalid work order")
		assert(order.id == id, "work order key mismatch")
		orders[id] = order
	end
	local emptyOrder: WorkOrders.WorkOrder = {
		id = "empty",
		rewardId = "empty",
		repeatable = false,
		steps = { { id = "empty", tag = "empty", targetCount = 1 } },
	}
	local function default(): State
		return {
			revision = 0,
			gatherSlots = {},
			milestones = {},
			tokens = { craft = "", equip = "", order = "" },
			workOrder = { orderId = "", capabilityRank = 0, state = WorkOrders.emptyState() },
		}
	end
	local function normalize(raw: unknown, characterId: unknown): (State?, string?)
		local fields = Value.record(
			raw,
			{ revision = true, gatherSlots = true, milestones = true, tokens = true, workOrder = true },
			true
		)
		if fields == nil or type(characterId) ~= "string" or characterId == "" then
			return nil, "state_invalid"
		end
		local revision = Value.whole(fields.revision, 0, MAX_INTEGER)
		local savedTokens = tokens.normalize(fields.tokens, true)
		local slots = Value.record(fields.gatherSlots, nodes)
		if revision == nil or savedTokens == nil or slots == nil then
			return nil, "state_invalid"
		end
		local gatherSlots: { [string]: number } = {}
		for id, rawSlot in slots do
			local slot = Value.whole(rawSlot, 0, MAX_INTEGER)
			if type(id) ~= "string" or slot == nil then
				return nil, "gather_slot_invalid"
			end
			gatherSlots[id] = slot
		end
		local savedMilestones = milestones.normalize(fields.milestones, characterId)
		if savedMilestones == nil then
			return nil, "milestone_invalid"
		end
		local orderFields =
			Value.record(fields.workOrder, { orderId = true, capabilityRank = true, state = true }, true)
		if orderFields == nil then
			return nil, "work_order_invalid"
		end
		local id = orderFields.orderId
		local rank = Value.whole(orderFields.capabilityRank, 0, 1)
		if type(id) ~= "string" or rank == nil then
			return nil, "work_order_invalid"
		end
		local order = if id == "" then emptyOrder else orders[id]
		local state = if order ~= nil then WorkOrders.projectState(orderFields.state, order) else nil
		if
			state == nil
			or (state.claimed and rank ~= 1)
			or (not state.claimed and rank ~= 0)
			or (id == "" and state.phase ~= "unaccepted")
		then
			return nil, "work_order_invalid"
		end
		local selected = assert(order)
		for _, step in selected.steps do
			if state.phase == "completed" and state.stepProgress[step.id] ~= step.targetCount then
				return nil, "work_order_invalid"
			end
		end
		for _, reward in state.claims do
			if reward ~= selected.rewardId then
				return nil, "work_order_invalid"
			end
		end
		if
			(id == "" and next(state.claims) ~= nil)
			or (state.claimed and next(state.claims) == nil)
			or (not selected.repeatable and not state.claimed and next(state.claims) ~= nil)
		then
			return nil, "work_order_invalid"
		end
		return {
			revision = revision,
			gatherSlots = gatherSlots,
			milestones = savedMilestones,
			tokens = { craft = savedTokens.craft, equip = savedTokens.equip, order = savedTokens.order },
			workOrder = { orderId = id, capabilityRank = rank, state = state },
		},
			nil
	end
	local function projectTokens(raw: unknown): (Tokens?, string?)
		local valid = tokens.normalize(raw)
		if valid == nil then
			return nil, "tokens_invalid"
		end
		return { craft = valid.craft, equip = valid.equip, order = valid.order }, nil
	end
	return table.freeze({
		default = default,
		normalize = normalize,
		tokens = projectTokens,
		milestone = milestones.receipt,
	})
end

Progression.MAX_INTEGER = MAX_INTEGER

return table.freeze(Progression)
