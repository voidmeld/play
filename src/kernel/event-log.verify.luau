--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Log = require("./event-log")
local Result = require("./result")
local Value = require("./value")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Event = { id: string, actor: string, delta: number, at: number }
type Balances = { [string]: number }
local function decode(raw: unknown): (Event?, string?)
	local row = Value.record(raw, { id = true, actor = true, delta = true, at = true }, true)
	if row == nil then
		return nil, "event_invalid"
	end
	local id, actor = Value.opaque(row.id, 16), Value.opaque(row.actor, 16)
	local delta, at = Value.whole(row.delta, -10, 10), Value.whole(row.at, 0, 100)
	if id == nil or actor == nil or delta == nil or at == nil then
		return nil, "event_invalid"
	end
	return { id = id, actor = actor, delta = delta, at = at }, nil
end
local log = Log.create({
	maxEvents = 3,
	maxId = 16,
	decode = decode,
	identity = function(event: Event): string
		return event.id
	end,
	equal = function(a: Event, b: Event): boolean
		return a.id == b.id and a.actor == b.actor and a.delta == b.delta and a.at == b.at
	end,
	seed = function(): Balances
		return {}
	end,
	apply = function(balances: Balances, event: Event, prior: { read [number]: Event }): (Balances?, string?)
		if #prior > 0 and event.at < prior[#prior].at then
			return nil, "time_regressed"
		end
		local total = (balances[event.actor] or 0) + event.delta
		if total < 0 then
			return nil, "balance_negative"
		end
		local nextBalances = table.clone(balances)
		nextBalances[event.actor] = total
		return nextBalances, nil
	end,
})

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("typed event log", function()
		it("appends typed events, projects balances and replays snapshots without aliasing", function()
			local initial: Log.State<Event> = { events = {} }
			local event: Event = { id = "first", actor = "a", delta = 3, at = 1 }
			local first = Result.unwrap(log.append(initial, event))
			local nextEvent: Event = { id = "second", actor = "a", delta = -1, at = 2 }
			local second = Result.unwrap(log.append(first.state, nextEvent))
			expect(#initial.events):toBe(0)
			expect(first.value.a):toBe(3)
			expect(second.value.a):toBe(2)
			local saved = Result.unwrap(log.snapshot(second.state))
			saved.events[1].delta = 4
			expect(second.state.events[1].delta):toBe(3)
			expect(event.delta):toBe(3)
			expect(Result.unwrap(log.project(saved)).value.a):toBe(3)
			expect(Result.unwrap(log.replay(second.state.events)).value.a):toBe(2)
			expect(Result.unwrap(log.append(second.state, event)).replayed):toBe(true)
		end)
		it("refuses conflicts, ordered-context violations and invalid stored records, then retries", function()
			local first = Result.unwrap(log.replay({ { id = "first", actor = "a", delta = 2, at = 3 } }))
			expect(log.append(first.state, { id = "first", actor = "a", delta = 3, at = 3 }).ok):toBe(false)
			expect(log.append(first.state, { id = "second", actor = "a", delta = -3, at = 4 }).ok):toBe(false)
			expect(log.append(first.state, { id = "second", actor = "a", delta = 1, at = 2 }).ok):toBe(false)
			expect(log.project({ events = {}, extra = true }).ok):toBe(false)
			expect(log.replay({ [2] = {} }).ok):toBe(false)
			expect(log.replay({ { id = "bad" } }).ok):toBe(false)
			expect(Result.unwrap(log.append(first.state, { id = "second", actor = "a", delta = 1, at = 4 })).value.a):toBe(
				3
			)
			expect(first.value.a):toBe(2)
		end)
		it("bounds history while retaining full-log replay and refusing corrupted recovery", function()
			local events = {
				{ id = "first", actor = "a", delta = 1, at = 1 },
				{ id = "second", actor = "b", delta = 2, at = 2 },
				{ id = "third", actor = "b", delta = 3, at = 3 },
			}
			local full = Result.unwrap(log.replay(events))
			expect(log.append(full.state, { id = "fourth", actor = "a", delta = 1, at = 4 }).ok):toBe(false)
			expect(Result.unwrap(log.append(full.state, events[1])).replayed):toBe(true)
			expect(Result.unwrap(log.replay({ events[1], events[1] })).value.a):toBe(1)
			expect(log.replay({ events[1], events[2], events[3], events[1] }).ok):toBe(false)
			expect(log.replay({ events[1], { id = "first", actor = "a", delta = 2, at = 1 } }).ok):toBe(false)
		end)
	end)
end
