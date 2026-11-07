--!strict

local Value = require("../../kernel/value")
type Raw = Value.Raw

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Policy = require("../../../tools/fixtures/identity")
local Roster = require("./roster")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local PEOPLE: { [string]: string } = { red = "first", green = "second", blue = "third" }
local CLASSES: { [string]: { string } } = {
	red = { "fighter", "healer", "monk", "caster" },
	green = { "guard", "shifter", "rogue", "weaver" },
	blue = { "soldier", "speaker", "seer", "binder" },
}

local roster = Roster.create(Policy)
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	local function emptyRoster(): { schemaVersion: number, userId: number, characters: { unknown } }
		return { schemaVersion = roster.SCHEMA_VERSION, userId = 101, characters = {} }
	end

	local function character(realmId: string, index: number, lastPlayedAtUnix: number?): Raw
		local characterId = ("chr_%s_%d"):format(realmId, index)
		return {
			characterId = characterId,
			displayName = ("Hero %s%d"):format(string.upper(string.sub(realmId, 1, 1)), index),
			realmId = realmId,
			peopleId = PEOPLE[realmId],
			classId = CLASSES[realmId][index],
			appearancePresetId = "preset." .. PEOPLE[realmId] .. ".issued",
			createdAtUnix = index,
			lastPlayedAtUnix = lastPlayedAtUnix or index,
			level = roster.MIN_LEVEL,
			lastDestinationId = roster.NEVER_DEPARTED,
		}
	end

	local function fullRoster(): Roster.Roster
		local value: Roster.Roster = { schemaVersion = roster.SCHEMA_VERSION, userId = 101, characters = {} }
		for _, realmId in { "red", "green", "blue" } do
			for index = 1, 4 do
				value = roster.add(value, character(realmId, index))
			end
		end
		return value
	end

	describe("RosterKernel capacity and identity", function()
		it("accepts exactly twelve characters with at most four in every realm", function()
			local value = fullRoster()
			expect(#roster.validate(value).characters):toBe(12)
			for realmId in roster.REALMS do
				expect(#roster.realmCards(value, realmId)):toBe(4)
			end
		end)

		it("rejects a thirteenth account character and a fifth realm character", function()
			local value = fullRoster()
			local extra = character("red", 1)
			extra.characterId = "chr_extra"
			extra.displayName = "Extra Hero"
			expect(function()
				roster.add(value, extra)
			end):toThrowMatching("exceeds limit")

			local oneRealm = emptyRoster()
			for index = 1, 4 do
				oneRealm = roster.add(oneRealm, character("red", index))
			end
			expect(function()
				roster.add(oneRealm, extra)
			end):toThrowMatching("exceeds limit")
		end)

		it("rejects duplicate immutable ids and case-insensitive names", function()
			local value = emptyRoster()
			value = roster.add(value, character("red", 1))
			local duplicateId = character("green", 1)
			duplicateId.characterId = value.characters[1].characterId
			expect(function()
				roster.add(value, duplicateId)
			end):toThrowMatching("duplicate characterId")
			local duplicateName = character("green", 1)
			duplicateName.displayName = string.lower(value.characters[1].displayName)
			expect(function()
				roster.add(value, duplicateName)
			end):toThrowMatching("duplicate case%-insensitive displayName")
		end)

		it("fails closed on unknown fields, realms, and noncanonical display names", function()
			local unknownField = character("red", 1)
			local unknownFieldRaw = unknownField
			unknownFieldRaw.runtimeMounted = true
			expect(function()
				roster.add(emptyRoster(), unknownField)
			end):toThrowMatching("unknown character field")
			local unknownRealm = character("red", 1)
			unknownRealm.realmId = "elsewhere"
			expect(function()
				roster.add(emptyRoster(), unknownRealm)
			end):toThrowMatching("unknown realm")
			local untrimmed = character("red", 1)
			untrimmed.displayName = "  Valid Hero  "
			expect(function()
				roster.add(emptyRoster(), untrimmed)
			end):toThrowMatching("noncanonical")
			local sparse = emptyRoster()
			sparse.characters[2] = character("red", 1)
			expect(function()
				roster.validate(sparse)
			end):toThrowMatching("dense array")
		end)

		it("rejects noncanonical playable ids and empty ids at their distinct validation boundaries", function()
			for _, peopleId in { "unknown", "UnknownPeople" } do
				local source = emptyRoster()
				local candidate = character("blue", 1)
				candidate.peopleId = peopleId
				source.characters[1] = candidate
				expect(function()
					roster.validate(source)
				end):toThrowMatching("unknown peopleId")
			end
			local empty = emptyRoster()
			local candidate = character("blue", 1)
			candidate.peopleId = ""
			empty.characters[1] = candidate
			expect(function()
				roster.validate(empty)
			end):toThrowMatching("peopleId must be a non%-empty string")
		end)
	end)

	describe("RosterKernel deterministic projections and partitions", function()
		it("returns all four realm cards in recent-play order with an immutable-id tie break", function()
			local value = emptyRoster()
			value = roster.add(value, character("red", 3, 30))
			value = roster.add(value, character("red", 2, 50))
			value = roster.add(value, character("red", 1, 50))
			value = roster.add(value, character("red", 4, 10))
			local cards = roster.realmCards(value, "red")
			expect(#cards):toBe(4)
			expect(cards[1].characterId):toBe("chr_red_1")
			expect(cards[2].characterId):toBe("chr_red_2")
			expect(cards[3].characterId):toBe("chr_red_3")
			expect(cards[4].characterId):toBe("chr_red_4")
		end)

		it("does not mutate input or leak mutable projection rows", function()
			local original = roster.add(emptyRoster(), character("red", 1))
			local added = roster.add(original, character("green", 1))
			expect(#original.characters):toBe(1)
			expect(#added.characters):toBe(2)
			local cards = roster.realmCards(original, "red")
			cards[1].displayName = "Changed"
			expect(original.characters[1].displayName):toBe("Hero R1")
		end)

		it("moves recency only forward and leaves the source unchanged", function()
			local original = roster.add(emptyRoster(), character("red", 1, 10))
			local updated = roster.markPlayed(original, "chr_red_1", 20)
			expect(original.characters[1].lastPlayedAtUnix):toBe(10)
			expect(updated.characters[1].lastPlayedAtUnix):toBe(20)
			expect(function()
				roster.markPlayed(updated, "chr_red_1", 19)
			end):toThrowMatching("must not move backward")
		end)

		it("removes exactly one owned identity and returns the name-release input", function()
			local original = roster.add(emptyRoster(), character("red", 1))
			local updated, removed = roster.remove(original, "chr_red_1")
			expect(#updated.characters):toBe(0)
			expect(#original.characters):toBe(1)
			expect(removed.characterId):toBe("chr_red_1")
			expect(removed.displayName):toBe("Hero R1")
		end)

		it("derives a stable per-character profile partition without roster position or display name", function()
			expect(roster.profilePartitionKey(101, "chr_red_1")):toBe("profile/101/chr_red_1")
		end)
	end)

	describe("RosterKernel card level and last destination", function()
		it("carries a never-departed value and the first level, and refuses a hole where either belongs", function()
			local value = roster.add(emptyRoster(), character("red", 1))
			local card = roster.realmCards(value, "red")[1]
			expect(card.lastDestinationId):toBe(roster.NEVER_DEPARTED)
			expect(card.lastDestinationId):toBe(false)
			expect(card.level):toBe(roster.MIN_LEVEL)

			local holedDestination = character("red", 1)
			local holedDestinationRaw = holedDestination
			holedDestinationRaw.lastDestinationId = nil
			expect(function()
				roster.add(emptyRoster(), holedDestination)
			end):toThrowMatching("lastDestinationId must be")
			local holedLevel = character("red", 1)
			local holedLevelRaw = holedLevel
			holedLevelRaw.level = nil
			expect(function()
				roster.add(emptyRoster(), holedLevel)
			end):toThrowMatching("level must be")
		end)

		it("refuses every level outside the progression's own range", function()
			for _, hostile in { 0, -1, 1.5, roster.MAX_LEVEL + 1, "3", math.huge, math.nan } do
				local outside = character("red", 1)
				local outsideRaw = outside
				outsideRaw.level = hostile
				expect(function()
					roster.add(emptyRoster(), outside)
				end):toThrowMatching("level must be")
			end
			local capped = character("red", 1)
			capped.level = roster.MAX_LEVEL
			expect(roster.realmCards(roster.add(emptyRoster(), capped), "red")[1].level):toBe(roster.MAX_LEVEL)
		end)

		it("moves a level forward only, and never past the range", function()
			local value = roster.add(emptyRoster(), character("red", 1))
			local raised = roster.markLevel(value, "chr_red_1", 7)
			expect(value.characters[1].level):toBe(roster.MIN_LEVEL)
			expect(raised.characters[1].level):toBe(7)
			expect(roster.markLevel(raised, "chr_red_1", 7).characters[1].level):toBe(7)
			expect(function()
				roster.markLevel(raised, "chr_red_1", 6)
			end):toThrowMatching("must not move backward")
			expect(function()
				roster.markLevel(raised, "chr_red_1", roster.MAX_LEVEL + 1)
			end):toThrowMatching("level must be")
			expect(function()
				roster.markLevel(raised, "chr_red_2", 7)
			end):toThrowMatching("not owned by roster")
		end)

		it("records only a namespaced destination id and never un-departs a character", function()
			local value = roster.add(emptyRoster(), character("red", 1))
			local departed = roster.markDeparted(value, "chr_red_1", "lobby.destination_forest")
			expect(value.characters[1].lastDestinationId):toBe(false)
			expect(departed.characters[1].lastDestinationId):toBe("lobby.destination_forest")
			expect(
				roster.markDeparted(departed, "chr_red_1", "lobby.destination_meadow").characters[1].lastDestinationId
			):toBe("lobby.destination_meadow")
			for _, hostile in { "", "Frontdoor.Destination", "forest", 7, {}, string.rep("d", 129) } do
				expect(function()
					roster.markDeparted(value, "chr_red_1", hostile)
				end):toThrowMatching("lastDestinationId must be")
				local forged = character("red", 2)
				local forgedRaw = forged
				forgedRaw.lastDestinationId = hostile
				expect(function()
					roster.add(value, forged)
				end):toThrowMatching("lastDestinationId must be")
			end
			expect(function()
				roster.markDeparted(value, "chr_red_1", roster.NEVER_DEPARTED)
			end):toThrowMatching("lastDestinationId must be")
			expect(function()
				roster.markDeparted(value, "chr_red_2", "lobby.destination_forest")
			end):toThrowMatching("not owned by roster")
		end)
	end)
end
