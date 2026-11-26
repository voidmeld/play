--!strict

local Bdd = require("@verify/src/bdd")
local Roster = require("./roster")
local Verify = require("@verify/src/core")

type Member = { accountId: string, absentSince: number? }
local origin = { x = 0, y = 0, z = 0 }

local function sharing(members: { Member })
	return Roster.sharing({
		projectParty = function(value: unknown): (Roster.RewardParty?, string?)
			if value ~= "live" and value ~= "closed" then
				return nil, "roster_invalid"
			end
			return { realmId = "north", members = members, disbandedAt = if value == "closed" then 10 else nil }, nil
		end,
		contributionKind = function(kind: string): string?
			return if kind == "delivery" then kind else nil
		end,
		eventIdFor = function(id: string, accountId: string): string
			return id .. "/" .. accountId
		end,
		radius = 5,
		maxCoordinate = 50,
		maxText = 16,
		maxAt = 100,
		maxAmount = 1000,
		maxUnits = 10,
	})
end

local function xp(amount: number, bonus: number?): Roster.XpEvent
	return { eventId = "e", at = 1.5, amount = amount, origin = origin, groupBonus = bonus }
end

local function contribution(units: number): Roster.ContributionEvent<string>
	return { eventId = "e", at = 1.5, kind = "delivery", units = units, origin = origin }
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("party reward sharing", function()
		it("keeps roster order across missing, absent, foreign and out-of-range observations", function()
			local rewards = sharing({
				{ accountId = "z" },
				{ accountId = "far" },
				{ accountId = "missing" },
				{ accountId = "away", absentSince = 1 },
				{ accountId = "a" },
			})
			local edge = { x = 0, y = 3, z = 4 }
			local presence = { z = edge, far = { x = 0, y = 5.1, z = 0 }, away = origin, a = origin, other = origin }
			local points = assert(rewards.projectPresence(presence))
			local ids = assert(rewards.eligible("live", origin, points))
			expect(ids):toEqual({ "z", "a" })
			edge.y = 50
			expect(points.z.y):toBe(3)
			expect(table.isfrozen(points) and table.isfrozen(points.z) and table.isfrozen(ids)):toBe(true)
			local rows = assert(rewards.shareXp("live", xp(9, 0.5), points))
			expect(rows):toEqual({ { accountId = "z", amount = 7 }, { accountId = "a", amount = 7 } })
			expect(table.isfrozen(rows) and table.isfrozen(rows[1])):toBe(true)
			expect(assert(rewards.splitContribution("live", contribution(3), points))[1].units):toBe(2)
		end)

		it("conserves XP for every group size and gives the remainder to earliest eligible members", function()
			for size = 1, 6 do
				local members: { Member } = {}
				local presence: Roster.Presence = {}
				for i = 1, size do
					local id = tostring(i)
					table.insert(members, { accountId = id })
					presence[id] = origin
				end
				local rewards = sharing(members)
				for _, amount in { 0, 1, 7, 100, 999, 1000 } do
					local rows = assert(rewards.shareXp("live", xp(amount), presence))
					expect(#rows):toBe(size)
					local sum = 0
					for i, row in rows do
						expect(row.accountId):toBe(tostring(i))
						if i > 1 then
							expect(row.amount <= rows[i - 1].amount and row.amount >= rows[1].amount - 1):toBe(true)
						end
						sum += row.amount
					end
					expect(sum):toBe(amount)
				end
			end
		end)

		it("emits positive replayable contribution rows or refuses the whole split", function()
			local rewards = sharing({ { accountId = "z" }, { accountId = "long" }, { accountId = "a" } })
			local presence = { z = origin, long = origin, a = origin }
			local event = contribution(2)
			local rows = assert(rewards.splitContribution("live", event, presence))
			expect(rows):toEqual({
				{ accountId = "z", eventId = "e/z", kind = "delivery", at = 1.5, units = 1, realmId = "north" },
				{ accountId = "long", eventId = "e/long", kind = "delivery", at = 1.5, units = 1, realmId = "north" },
			})
			expect(assert(rewards.splitContribution("live", event, presence))):toEqual(rows)
			expect(table.isfrozen(rows) and table.isfrozen(rows[2])):toBe(true)
			event.eventId = string.rep("x", 13)
			local partial, reason = rewards.splitContribution("live", event, presence)
			expect(partial):toBeNil()
			expect(reason):toBe("event_id_invalid")
			event.kind = "other"
			local _, kind = rewards.splitContribution("live", event, presence)
			expect(kind):toBe("kind_invalid")
			local _, units = rewards.splitContribution("live", contribution(0), presence)
			expect(units):toBe("units_invalid")
		end)

		it("passes projection refusals through and validates event, position and reward bounds", function()
			local rewards = sharing({ { accountId = "z" } })
			local presence = { z = origin }
			local function refused(expected: string, value: unknown, reason: string?)
				expect(value):toBeNil()
				expect(reason):toBe(expected)
			end
			refused("roster_invalid", rewards.shareXp(false, false, false))
			refused("party_disbanded", rewards.splitContribution("closed", false, false))
			refused("event_shape_invalid", rewards.shareXp("live", { extra = 1 }, presence))
			refused("event_id_invalid", rewards.shareXp("live", { eventId = "" }, presence))
			for _, amount in { -1, 0.5, 1001, math.huge } do
				refused("amount_invalid", rewards.shareXp("live", xp(amount), presence))
			end
			local event = xp(1)
			event.at = 101
			refused("time_invalid", rewards.shareXp("live", event, presence))
			refused("event_shape_invalid", rewards.eligible("live", { x = 0, y = 0 }, presence))
			refused("presence_invalid", rewards.projectPresence({ z = { x = 0, y = 51, z = 0 } }))
			refused("presence_invalid", rewards.projectPresence({ [1] = origin }))
			refused("presence_invalid", rewards.shareXp("live", xp(1), { stranger = { x = math.huge, y = 0, z = 0 } }))
			refused("bonus_invalid", rewards.shareXp("live", xp(1, 1.1), presence))
			expect(assert(rewards.shareXp("live", xp(1, -1), {}))):toEqual({})
			expect(assert(rewards.splitContribution("live", contribution(1), {}))):toEqual({})
		end)
	end)
end
