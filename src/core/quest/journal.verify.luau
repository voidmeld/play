--!strict

local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Journal = require("./journal")
local Verify = require("../../../.lute/dependencies/verify/src/core")

local core = Journal.journal({
	version = 7,
	maxIdLength = 32,
	maxCharacterIdLength = 40,
	maxEventIdLength = 16,
	maxEvents = 2,
	maxQuests = 3,
	maxCounts = 2,
	maxStep = 5,
	maxCount = 10,
	eventPrefix = "receipt[",
	statuses = { Active = true, Done = true },
	claimableStatuses = { Active = true },
	receiptStatus = "Done",
	eventIdAllowed = function(id: string): boolean
		return string.match(id, "^event_%a+$") ~= nil
	end,
})
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("saved quest journal", function()
		it("round trips progress and semantic receipts through a literal namespace", function()
			local source = { q = { status = "Active", step = 1, counts = { objective = 2 } } }
			local record = assert(core.create("zone", "character", source, { event_a = true }))
			local stored = assert(core.storageQuests(record))
			expect(stored["receipt[event_a"].status):toBe("Done")
			local restored = assert(core.fromStorageQuests("zone", "character", stored, { q = true }))
			expect(restored.quests):toEqual(source)
			expect(restored.semanticEventIds):toEqual({ event_a = true })
			assert(restored.quests.q.counts ~= nil)
			restored.quests.q.counts.objective = 3
			expect(source.q.counts.objective):toBe(2)
			expect(record.version):toBe(7)
		end)
		it("refuses unsupported versions and malformed or over-budget progress", function()
			local bad, version = core.decode({ version = 8, zoneId = "zone", characterId = "character", quests = {} })
			expect(bad):toBeNil()
			expect(version):toBe("unsupported_version:8")
			local step = core.copyQuests({ q = { status = "Active", step = 6 } })
			local counts = core.copyQuests({ q = { status = "Active", step = 0, counts = { objective = 11 } } })
			expect(step):toBeNil()
			expect(counts):toBeNil()
			local record, reason = core.create(
				"zone",
				"character",
				{ a = { status = "Done", step = 0 }, b = { status = "Done", step = 0 } },
				{ event_a = true, event_b = true }
			)
			expect(record):toBeNil()
			expect(reason):toBe("too_many_quest_records")
		end)
		it("validates semantic receipt shape separately from quest progress", function()
			local identity = core.copySemanticEventIds({ private = true })
			local receipt = core.copySemanticEventIds({ event_a = false })
			expect(identity):toBeNil()
			expect(receipt):toBeNil()
			local record, reason = core.fromStorageQuests(
				"zone",
				"character",
				{ ["receipt[event_a"] = { status = "Active", step = 0 } },
				{}
			)
			expect(record):toBeNil()
			expect(reason):toBe("invalid_stored_semantic_event")
		end)
		it("requires known quest identities and counts for resumed active steps", function()
			local missing, reason = core.fromStorageQuests(
				"zone",
				"character",
				{ q = { status = "Active", step = 1 } },
				{ q = true }
			)
			expect(missing):toBeNil()
			expect(reason):toBe("quest_progress_counts_missing:q")
			local unknown, identity = core.fromStorageQuests(
				"zone",
				"character",
				{ q = { status = "Done", step = 0 } },
				{}
			)
			expect(unknown):toBeNil()
			expect(identity):toBe("unknown_quest_id:q")
			expect(core.key("a", "bc") == core.key("ab", "c")):toBe(false)
		end)
	end)
end
