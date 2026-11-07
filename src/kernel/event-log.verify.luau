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
local config: Log.Config<Event, Balances> = {
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
}
local log = Log.create(config)

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("typed event log", function()
		it("refuses every duplicate stored ID only when configured and keeps append retries", function()
			local options = table.clone(config)
			options.duplicateIds = "refuse"
			local strict = Log.create(options)
			local event: Event = { id = "first", actor = "a", delta = 1, at = 1 }
			local conflict: Event = { id = "first", actor = "a", delta = 2, at = 1 }
			for _, duplicate in { event, conflict } do
				local refused = strict.project({ events = { event, duplicate } })
				expect(refused.ok):toBe(false)
				if not refused.ok then
					expect(refused.reason):toBe("state_invalid")
				end
			end
			local state = Result.unwrap(strict.replay({ event })).state
			expect(Result.unwrap(strict.append(state, event)).replayed):toBe(true)
			expect(strict.append(state, conflict).ok):toBe(false)
			expect(Result.unwrap(log.replay({ event, event })).value.a):toBe(1)
		end)
		it("projects metatable records and lists into detached frozen events without stored metadata", function()
			local options = table.clone(config)
			options.projectRecord = function(raw: unknown): unknown
				if type(raw) ~= "table" then
					return raw
				end
				local owned: Value.Raw = {}
				for key, value in next, raw do
					if key ~= "metadata" then
						owned[key] = value
					end
				end
				return owned
			end
			options.decode = function(raw: unknown): (Event?, string?)
				local event, reason = decode(raw)
				if event == nil then
					return nil, reason
				end
				Value.freezeDeep(event)
				return event, nil
			end
			local projected = Log.create(options)
			local event = setmetatable({ id = "first", actor = "a", delta = 1, at = 1, metadata = "extra" }, {})
			local events = setmetatable({ event }, {})
			local stored = setmetatable({ events = events, metadata = "extra" }, {})
			expect(log.project(stored).ok):toBe(false)
			local result = Result.unwrap(projected.project(stored))
			expect(result.value.a):toBe(1)
			expect(table.isfrozen(result.state.events[1])):toBe(true)
			expect(getmetatable(result.state.events[1])):toBeNil()
			event.delta = 5
			expect(result.state.events[1].delta):toBe(1)
			expect(projected.replay({ [2] = event }).ok):toBe(false)
			options.projectRecord = function(_raw: unknown): unknown
				error("projection failed")
			end
			expect(Log.create(options).project(stored).ok):toBe(false)
		end)
		it("permits omitted or larger event ceilings while retaining configured bounds", function()
			local options = table.clone(config)
			options.maxEvents = nil
			local unbounded = Log.create(options)
			local events = {}
			for index = 1, 4 do
				table.insert(events, { id = tostring(index), actor = "a", delta = 1, at = index })
			end
			expect(log.replay(events).ok):toBe(false)
			expect(#Result.unwrap(unbounded.replay(events)).state.events):toBe(4)
			local before = Result.unwrap(unbounded.replay({ events[1], events[2], events[3] })).state
			expect(#Result.unwrap(unbounded.append(before, events[4])).state.events):toBe(4)
			options.maxEvents = 1000001
			expect(Log.create(options).replay(events).ok):toBe(true)
		end)
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
