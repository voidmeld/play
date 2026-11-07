--!strict

local Value = require("../../kernel/value")
type Raw = Value.Raw

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Policy = require("../../../tools/fixtures/identity")
local Registry = require("./name-claims")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local registry = Registry.create(Policy)
local function claim(displayName: string, userId: number, characterId: string, claimedAtUnix: number): Raw
	return {
		displayName = displayName,
		userId = userId,
		characterId = characterId,
		claimedAtUnix = claimedAtUnix,
		schemaVersion = registry.SCHEMA_VERSION,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("NameRegistryKernel atomic transforms", function()
		it("admits exactly one winner under interleaved case-colliding claims", function()
			local first = claim("Alden Vale", 101, "chr_a", 10)
			local second = claim("alden vale", 202, "chr_b", 11)
			local stored, firstStatus = registry.claim(nil, first)
			local afterSecond, secondStatus = registry.claim(stored, second)
			expect(firstStatus):toBe("claimed")
			expect(secondStatus):toBe("taken")
			expect(afterSecond):toEqual(stored)
			expect(afterSecond.userId):toBe(101)
		end)

		it("makes exact self-reclaim idempotent without replacing original display case or timestamp", function()
			local stored = claim("Alden Vale", 101, "chr_a", 10)
			local nextClaim, status = registry.claim(stored, claim("alden vale", 101, "chr_a", 99))
			expect(status):toBe("owned")
			expect(nextClaim):toEqual(stored)
		end)

		it("does not let another character on the same account reuse an identity", function()
			local stored = claim("Alden Vale", 101, "chr_a", 10)
			local nextClaim, status = registry.claim(stored, claim("Alden Vale", 101, "chr_b", 11))
			expect(status):toBe("taken")
			expect(nextClaim.characterId):toBe("chr_a")
		end)

		it("keeps availability advisory and the claim transform authoritative", function()
			expect(registry.availability(nil, 101, "chr_a")):toBe("available")
			local stored = registry.claim(nil, claim("Alden Vale", 101, "chr_a", 10))
			expect(registry.availability(stored, 101, "chr_a")):toBe("owned")
			expect(registry.availability(stored, 202, "chr_b")):toBe("taken")
		end)

		it("releases only the exact user and immutable character identity", function()
			local stored = claim("Alden Vale", 101, "chr_a", 10)
			local wrongUser, wrongUserStatus = registry.release(stored, 202, "chr_a")
			local wrongCharacter, wrongCharacterStatus = registry.release(stored, 101, "chr_b")
			local released, releasedStatus = registry.release(stored, 101, "chr_a")
			expect(wrongUserStatus):toBe("mismatch")
			expect(wrongUser):toEqual(stored)
			expect(wrongCharacterStatus):toBe("mismatch")
			expect(wrongCharacter):toEqual(stored)
			expect(releasedStatus):toBe("released")
			expect(released):toBe(nil)
		end)

		it("makes a stale reset harmless after a newer owner exists", function()
			local newer = claim("Alden Vale", 202, "chr_b", 20)
			local retained, status = registry.release(newer, 101, "chr_a")
			expect(status):toBe("mismatch")
			expect(retained):toEqual(newer)
		end)

		it("fails closed on malformed records and cross-key callback state", function()
			local malformed = claim("Alden Vale", 101, "chr_a", 10)
			local rawMalformed = malformed
			rawMalformed.clientOwned = true
			expect(function()
				registry.validate(malformed)
			end):toThrowMatching("unknown claim field")
			expect(function()
				registry.claim(claim("Alden Vale", 101, "chr_a", 10), claim("Brynn Stone", 202, "chr_b", 11))
			end):toThrowMatching("different registry keys")
		end)
	end)
end
