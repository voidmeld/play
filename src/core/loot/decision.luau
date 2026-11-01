--!strict

export type Choice = "need" | "greed" | "pass"
export type Seat = { userId: string, needLegal: boolean }
export type Result = {
	winner: string?,
	by: "need" | "greed" | "round_robin",
	rolls: { [string]: number },
	cursorAfter: number,
}
export type Decision = {
	id: string,
	itemId: string,
	openedAt: number,
	deadline: number,
	seats: { Seat },
	declarations: { [string]: Choice },
	cursor: number,
	result: Result?,
}
export type Refusal =
	"settled"
	| "closed"
	| "not_eligible"
	| "need_not_legal"
	| "already_declared"
	| "bad_choice"
	| "not_due"

export type Config = { windowSeconds: number }

local HASH_MODULUS = 2147483647

local System = {}
function System.decision(config: Config)
	assert(config.windowSeconds > 0, "decision window must be positive")

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function seatOf(decision: Decision, userId: string): Seat?
		for _, seat in decision.seats do
			if seat.userId == userId then
				return seat
			end
		end
		return nil
	end

	local function roll(decisionId: string, userId: string): number
		local hash = 7
		for _, text in { decisionId, "\0", userId } do
			for index = 1, #text do
				hash = (hash * 31 + string.byte(text, index)) % HASH_MODULUS
			end
		end
		return hash % 100 + 1
	end

	local function open(id: string, itemId: string, seats: { Seat }, now: number, cursor: number): Decision?
		if id == "" or itemId == "" or #seats == 0 or not finite(now) or not finite(cursor) or cursor < 0 then
			return nil
		end
		local seen: { [string]: boolean } = {}
		local copied: { Seat } = {}
		for _, seat in seats do
			if type(seat.userId) ~= "string" or seat.userId == "" or seen[seat.userId] then
				return nil
			end
			seen[seat.userId] = true
			table.insert(copied, { userId = seat.userId, needLegal = seat.needLegal == true })
		end
		local decision: Decision = {
			id = id,
			itemId = itemId,
			openedAt = now,
			deadline = now + config.windowSeconds,
			seats = copied,
			declarations = {},
			cursor = math.floor(cursor),
			result = nil,
		}
		return decision
	end

	local function declare(decision: Decision, userId: string, choice: unknown, now: number): (Decision?, Refusal?)
		if decision.result ~= nil then
			return nil, "settled"
		end
		if not finite(now) or now >= decision.deadline then
			return nil, "closed"
		end
		if choice ~= "need" and choice ~= "greed" and choice ~= "pass" then
			return nil, "bad_choice"
		end
		local seat = seatOf(decision, userId)
		if seat == nil then
			return nil, "not_eligible"
		end
		if decision.declarations[userId] ~= nil then
			return nil, "already_declared"
		end
		if choice == "need" and not seat.needLegal then
			return nil, "need_not_legal"
		end
		local declarations = table.clone(decision.declarations)
		declarations[userId] = choice
		local next: Decision = table.clone(decision)
		next.declarations = declarations
		return next, nil
	end

	local function due(decision: Decision, now: number): boolean
		if decision.result ~= nil then
			return false
		end
		if finite(now) and now >= decision.deadline then
			return true
		end
		for _, seat in decision.seats do
			if decision.declarations[seat.userId] == nil then
				return false
			end
		end
		return true
	end

	local function contest(decision: Decision, choice: Choice): (string?, { [string]: number })
		local rolls: { [string]: number } = {}
		local winner: string? = nil
		local best = -1
		for _, seat in decision.seats do
			if decision.declarations[seat.userId] == choice then
				local value = roll(decision.id, seat.userId)
				rolls[seat.userId] = value
				if value > best then
					best = value
					winner = seat.userId
				end
			end
		end
		return winner, rolls
	end

	local function settle(decision: Decision, now: number): (Decision?, Refusal?)
		if decision.result ~= nil then
			return nil, "settled"
		end
		if not due(decision, now) then
			return nil, "not_due"
		end
		local by: "need" | "greed" | "round_robin" = "need"
		local cursorAfter = decision.cursor
		local winner, rolls = contest(decision, "need")
		if winner == nil then
			by = "greed"
			winner, rolls = contest(decision, "greed")
		end
		if winner == nil then
			by = "round_robin"
			winner = decision.seats[decision.cursor % #decision.seats + 1].userId
			cursorAfter += 1
		end
		local result: Result = { winner = winner, by = by, rolls = rolls, cursorAfter = cursorAfter }
		local next: Decision = table.clone(decision)
		next.result = result
		return next, nil
	end

	return table.freeze({ open = open, declare = declare, due = due, settle = settle })
end
return System
