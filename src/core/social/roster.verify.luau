--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Roster = require("./roster")
local Shape = require("./shape")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type Party = {
	partyId: string,
	realmId: string,
	members: { Roster.Member },
	disbandedAt: number?,
	lootCursor: string?,
	revision: number,
}
type Actor = { id: string, characterId: string?, realm: string?, partyId: string?, xp: number }
local function project(value: unknown): Party?
	local raw = Shape.raw(value)
	if
		raw == nil
		or type(raw.partyId) ~= "string"
		or type(raw.realmId) ~= "string"
		or type(raw.revision) ~= "number"
	then
		return nil
	end
	local members = Shape.array(raw.members, function(value: unknown): Roster.Member?
		local row = Shape.raw(value)
		if row == nil or type(row.accountId) ~= "string" then
			return nil
		end
		local characterId = row.characterId
		if characterId ~= nil and type(characterId) ~= "string" then
			return nil
		end
		return { accountId = row.accountId, characterId = characterId }
	end)
	if members == nil then
		return nil
	end
	local disbandedAt = Shape.number(raw.disbandedAt)
	local lootCursor = Shape.string(raw.lootCursor)
	return {
		partyId = raw.partyId,
		realmId = raw.realmId,
		members = members,
		disbandedAt = disbandedAt,
		lootCursor = lootCursor,
		revision = raw.revision,
	}
end
local function settings(): Roster.Config<Party, Actor>
	return {
		project = project,
		party = function(p: Party): Roster.Party
			return { partyId = p.partyId, realmId = p.realmId, members = p.members, disbandedAt = p.disbandedAt }
		end,
		lootCursor = function(p: Party): string?
			return p.lootCursor
		end,
		withLootCursor = function(p: Party, cursor: string?): Party
			local out = table.clone(p)
			out.lootCursor = cursor
			return out
		end,
		actor = function(a: Actor): Roster.Actor
			return { id = a.id, characterId = a.characterId, realm = a.realm, partyId = a.partyId }
		end,
		withParty = function(a: Actor, partyId: string?): Actor
			local out = table.clone(a)
			out.partyId = partyId
			return out
		end,
		subject = function(id: string): string
			return id
		end,
	}
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("roster", function()
		local law = Roster.roster(settings())
		local function party(): Party
			return {
				partyId = "party",
				realmId = "realm",
				revision = 1,
				members = {
					{ accountId = "a", characterId = "char-a" },
					{ accountId = "b", characterId = "char-b" },
					{ accountId = "c", characterId = "char-c" },
				},
			}
		end
		local function actor(id: string, characterId: string?, realm: string?, partyId: string?): Actor
			return { id = id, characterId = characterId, realm = realm, partyId = partyId, xp = 12 }
		end
		it("projects admission from account, character and case-normalized realm", function()
			local actors: { [string]: Actor } = {
				a = actor("a", "char-a", "Realm", nil),
				b = actor("b", "wrong", "realm", "party"),
				c = actor("c", "char-c", "other", "other-party"),
				bystander = actor("other", "char-other", "realm", nil),
				blank = actor("a", nil, "realm", nil),
			}
			local incoming = party()
			local result = assert(law.reduce({}, actors, incoming, 42))
			expect(result.actors.a.partyId):toBe("party")
			expect(result.actors.b.partyId):toBeNil()
			expect(result.actors.c.partyId):toBe("other-party")
			expect(result.actors.bystander.partyId):toBeNil()
			expect(result.actors.blank.partyId):toBeNil()
			expect(result.parties.party.tick):toBe(42)
			expect(result.actors.a.xp):toBe(12)
			expect(actors.a.partyId):toBeNil()
			expect(actors.b.partyId):toBe("party")
			expect(result.actors.c):toBe(actors.c)
			expect(incoming.lootCursor):toBeNil()
		end)
		it("keeps the local loot cursor across snapshots and strips untrusted incoming cursors", function()
			local prior = party()
			prior.lootCursor = "b"
			local parties: { [string]: Roster.Runtime<Party> } = { party = { state = prior, tick = 1 } }
			local incoming = party()
			incoming.revision = 2
			incoming.lootCursor = "c"
			local result = assert(law.reduce(parties, {}, incoming, 2))
			expect(result.parties.party.state.lootCursor):toBe("b")
			expect(result.parties.party.state.revision):toBe(2)
			expect(result.parties.party.tick):toBe(2)
			expect(parties.party.state.revision):toBe(1)
			expect(incoming.lootCursor):toBe("c")
			expect(assert(law.reduce({}, {}, incoming, 3)).parties.party.state.lootCursor):toBeNil()
		end)
		it("disbands only this party, clears stale members and preserves other party records", function()
			local parties: { [string]: Roster.Runtime<Party> } =
				{ party = { state = party(), tick = 1 }, other = { state = party(), tick = 7 } }
			local actors: { [string]: Actor } = {
				a = actor("a", "char-a", "realm", "party"),
				b = actor("b", "char-b", "realm", "other"),
				missingRealm = actor("c", "char-c", nil, "party"),
			}
			local disbanded = party()
			disbanded.disbandedAt = 0
			local result = assert(law.reduce(parties, actors, disbanded, 9))
			expect(result.parties.party):toBeNil()
			expect(result.parties.other):toBe(parties.other)
			expect(result.actors.a.partyId):toBeNil()
			expect(result.actors.b.partyId):toBe("other")
			expect(result.actors.missingRealm.partyId):toBeNil()
			expect(parties.party.tick):toBe(1)
			expect(actors.a.partyId):toBe("party")
		end)
		it("rejects failed projections without changing either input map", function()
			local parties: { [string]: Roster.Runtime<Party> } = { party = { state = party(), tick = 1 } }
			local actors: { [string]: Actor } = { a = actor("a", "char-a", "realm", nil) }
			for _, raw in { false, {}, { partyId = "party" } } do
				expect(law.reduce(parties, actors, raw, 2)):toBeNil()
			end
			expect(parties.party.tick):toBe(1)
			expect(actors.a.partyId):toBeNil()
		end)
		it("uses supplied identity mapping while keeping party records unchanged", function()
			local config = settings()
			config.subject = function(id: string): string
				return if id == "seat-a" then "a" else id
			end
			local mapped = Roster.roster(config)
			local actors: { [string]: Actor } = { seat = actor("seat-a", "char-a", "REALM", nil) }
			local incoming = party()
			local result = assert(mapped.reduce({}, actors, incoming, 5))
			expect(result.actors.seat.partyId):toBe("party")
			expect(mapped.subject("seat-a")):toBe("a")
			expect(incoming.members[1].accountId):toBe("a")
			expect(actors.seat.partyId):toBeNil()
		end)
	end)
end
