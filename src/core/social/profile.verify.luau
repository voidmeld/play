--!strict

local Allies = require("./allies")
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Chronicles = require("./chronicle")
local Profiles = require("./profile")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local allies = Allies.allies({
	retentionSec = 10,
	maxAllies = 2,
	maxRevision = 10,
	maxTime = 100,
	maxId = 20,
	maxFingerprint = 100,
	qualificationKinds = { helped = true },
})
local chronicle = Chronicles.chronicle({
	offerTtlSec = 2,
	swornTtlSec = 5,
	chronicleLimit = 2,
	maxRevision = 10,
	maxTime = 100,
	maxId = 20,
	maxCharacterId = 5,
	maxFingerprint = 100,
})
local definitions: { Chronicles.Definition } = {
	{
		id = "v",
		witnessedOutcomeId = "v.seen",
		contestedOutcomeId = "v.contested",
		fulfilledOutcomeId = "v.done",
		expiredOutcomeId = "v.expired",
		abandonedOutcomeId = "v.left",
	},
}
local settings: Profiles.Config = {
	maxId = 2,
	realms = { zone = true },
	nameIds = { label = true },
	definitions = definitions,
	emptyAllies = allies.emptyState,
	projectAllies = allies.projectState,
	emptyChronicle = chronicle.emptyState,
	projectChronicle = chronicle.projectState,
}
local profile = Profiles.profile(settings)

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("profile", function()
		it("composes configured allies and vow history and rejects mismatched owners", function()
			local source = assert(profile.default(1, "me"))
			expect(source.fellowship):toBe(false)
			expect(profile.project(source, 1, "me")):toEqual(source)
			expect(profile.project(source, 2, "me")):toBeNil()
			expect(profile.project(source, 1, "other")):toBeNil()
			expect(profile.default(0, "me")):toBeNil()
			expect(profile.default(1, "toolong")):toBeNil()
			expect(table.isfrozen(source.recentAllies)):toBe(true)
		end)

		it("projects only configured fellowship identities within the configured length", function()
			local source = assert(profile.default(1, "me"))
			local identity: Profiles.FellowshipIdentity = {
				fellowshipId = "ab",
				nameId = "label",
				realmId = "zone",
				memberUserId = 1,
				lastKnownStewardUserId = 2,
				observedRevision = 1,
			}
			local raw: Profiles.State =
				{ fellowship = identity, recentAllies = source.recentAllies, vowChronicle = source.vowChronicle }
			expect(profile.project(raw, 1, "me") ~= nil):toBe(true)
			identity.fellowshipId = "abc"
			expect(profile.project(raw, 1, "me")):toBeNil()
			identity.fellowshipId, identity.nameId = "ab", "unknown"
			expect(profile.project(raw, 1, "me")):toBeNil()
			identity.nameId, identity.realmId = "label", "unknown"
			expect(profile.project(raw, 1, "me")):toBeNil()
			identity.realmId, identity.memberUserId = "zone", 2
			expect(profile.project(raw, 1, "me")):toBeNil()
		end)

		it("uses supplied definitions and projectors and rejects unknown fields", function()
			local source = assert(profile.default(1, "me"))
			local cfg = table.clone(settings)
			cfg.definitions = {}
			expect(Profiles.profile(cfg).project(source, 1, "me")):toBeNil()
			cfg = table.clone(settings)
			cfg.emptyAllies = function(_value: unknown): Allies.State?
				return nil
			end
			expect(Profiles.profile(cfg).default(1, "me")):toBeNil()
			cfg = table.clone(settings)
			cfg.projectChronicle = function(_value: unknown, _definitions: unknown): Chronicles.State?
				return nil
			end
			expect(Profiles.profile(cfg).project(source, 1, "me")):toBeNil()
			expect(profile.project({
				fellowship = false,
				recentAllies = source.recentAllies,
				vowChronicle = source.vowChronicle,
				extra = true,
			}, 1, "me")):toBeNil()
		end)
	end)
end
