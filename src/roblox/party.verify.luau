--!strict
local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Membership = require("../core/social/membership")
local Party = require("./party")
local Value = require("../kernel/value")
local Verify = require("../../.lute/dependencies/verify/src/core")
local Core = Membership.membership({
	maxMembers = 3,
	minimumPartyMembers = 2,
	disconnectGraceSec = 30,
	leaderSuccessionSec = 10,
	leaderTransferTtlSec = 5,
	inviteTtlSec = 10,
	maxText = 128,
	maxAt = 100000,
	realms = { realm = true },
	defaultLootMode = "need_greed",
})
local Host = Party.party({ core = Core, schemaVersion = 2, boundary = "test atomic store", maxText = 128 })
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("party atomic host", function()
		for _, mode in { "divergent_reply", "replay_shadow", "read_shadow" } do
			it("refuses speculative party authority after " .. mode, function()
				local value: unknown = nil
				local shadow: unknown = nil
				local armed = false
				local mounted = Host.mount({
					keyForParty = function(id: string): string
						return id
					end,
					readMembership = function(): unknown
						return nil
					end,
					store = {
						read = function(): Party.StoreOutcome
							return { ok = true, value = value }
						end,
						update = function(_key: string, transform: (unknown) -> unknown): Party.StoreOutcome
							local proposed = transform(if armed and mode ~= "divergent_reply" then shadow else value)
							if proposed == nil then
								return { ok = false, value = nil, reason = "callback_cancelled" }
							end
							if armed and mode == "divergent_reply" then
								local record = assert(Value.raw(proposed))
								local state = assert(Value.raw(record.party))
								state.lootMode = "round_robin"
								record.party = state
								proposed = record
							end
							value = proposed
							return { ok = true, value = value }
						end,
					},
				})
				local service = assert(mounted.service)
				expect(service.open({ partyId = "party", realmId = "realm", founderId = "a", at = 0 }).ok):toBe(true)
				armed = true
				shadow = value
				if mode ~= "divergent_reply" then
					value = nil
				end
				local outcome = if mode == "divergent_reply"
					then service.invite({
						partyId = "party",
						accountId = "b",
						invitedBy = "a",
						targetRealmId = "realm",
						at = 1,
					})
					elseif mode == "replay_shadow" then service.markPresent({
						partyId = "party",
						accountId = "a",
						at = 0,
					})
					else service.read("party")
				expect(if mode == "read_shadow" then outcome.found else outcome.ok):toBe(false)
			end)
		end
		it("retries pure transforms and refuses old schemas without rewriting them", function()
			local values: { [string]: unknown } = {}
			local writes = 0
			local mounted = Host.mount({
				keyForParty = function(id: string): string
					return id
				end,
				readMembership = function(_: string): unknown
					return nil
				end,
				store = {
					update = function(key: string, transform: (unknown) -> unknown): Party.StoreOutcome
						transform(values[key])
						local next = transform(values[key])
						if next == nil then
							return { ok = false, value = values[key], reason = "callback_cancelled" }
						end
						values[key] = next
						writes += 1
						return { ok = true, value = next }
					end,
				},
			})
			assert(mounted.ok and mounted.service)
			local service = mounted.service
			local opened = service.open({ partyId = "party", realmId = "realm", founderId = "a", at = 0 })
			expect(opened.ok):toBe(true)
			local invited =
				service.invite({ partyId = "party", accountId = "b", invitedBy = "a", targetRealmId = "realm", at = 1 })
			expect(invited.ok):toBe(true)
			expect(writes):toBe(2)
			local read = service.read("party")
			expect(read.ok):toBe(true)
			expect(writes):toBe(2)
			local legacy = { schemaVersion = 1, partyId = "party", party = opened.party }
			values.party = legacy
			local refused = service.read("party")
			expect(refused.ok):toBe(false)
			expect(refused.reason):toBe("schema_unknown")
			expect(values.party):toBe(legacy)
			expect(writes):toBe(2)
		end)
	end)
end
