--!strict

local Account = require("./account")
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Creation = require("./creation")
local Deletion = require("./deletion")
local Policy = require("../../../tools/fixtures/identity")
local Value = require("../../kernel/value")
local Verify = require("../../../.lute/dependencies/verify/src/core")

type Extra = { token: string, completed: number }
type State = Account.Account<Extra>
local creation = Creation.create(Policy)
local deletion = Deletion.create(Policy)
local aggregate = Account.create(Policy, {
	fields = { token = true, completed = true },
	project = function(base: Account.Base, raw: unknown, terminal: Account.DeletionState?): State?
		local fields = Value.raw(raw)
		if fields == nil then
			return nil
		end
		local token = fields.token or "initial"
		local completed = fields.completed or 0
		if type(token) ~= "string" or type(completed) ~= "number" then
			return nil
		end
		return {
			schemaVersion = base.schemaVersion,
			userId = base.userId,
			revision = base.revision,
			roster = base.roster,
			profiles = base.profiles,
			pendingProfile = base.pendingProfile,
			activeCreation = base.activeCreation,
			activeDeletion = base.activeDeletion,
			receipts = base.receipts,
			token = token,
			completed = completed + (if terminal ~= nil and terminal.phase == "lease_released" then 1 else 0),
		}
	end,
})

local function prepared(): Creation.State
	return assert(creation.prepare(nil, {
		userId = 101,
		operationId = "create.1",
		characterId = "character.a",
		displayName = "Example One",
		realmId = "red",
		peopleId = "first",
		classId = "fighter",
		appearancePresetId = "preset.first",
		createdAtUnix = 50,
		fence = 7,
		leaseRevision = 1,
	}).state)
end

local function phase(state: Creation.State, nextPhase: Creation.Phase): Creation.State
	local nextState = table.clone(state)
	nextState.phase = nextPhase
	nextState.revision += 1
	return assert(creation.validate(nextState))
end

local function released(): State
	local empty = table.clone(assert(aggregate.empty(101)))
	empty.token = "retained"
	local state = prepared()
	local account = assert(aggregate.transition(empty, state))
	for _, nextPhase in { "name_owned", "profile_prepared", "committed", "lease_released" } do
		state = phase(state, nextPhase)
		account = assert(aggregate.transition(account, state))
	end
	return assert(aggregate.clearTerminal(account))
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("account aggregate extension custody", function()
		it("preserves extensions through creation, roster updates, removal and detached copies", function()
			local account = released()
			expect(#account.profiles):toBe(1)
			expect(#account.receipts):toBe(1)
			account = assert(aggregate.markCharacterLevel(account, "character.a", 2))
			account = assert(aggregate.markCharacterPlayed(account, "character.a", 75))
			account = assert(aggregate.markCharacterDeparted(account, "character.a", "example.zone"))
			expect(account.token):toBe("retained")
			local copy = assert(aggregate.copy(account))
			expect(copy == account):toBe(false)
			expect(aggregate.equal(copy, account)):toBe(true)
			account = assert(aggregate.removeCharacter(copy, "character.a"))
			expect(#account.roster.characters):toBe(0)
			expect(#account.profiles):toBe(0)
			expect(#account.receipts):toBe(0)
			expect(account.token):toBe("retained")
		end)
		it("preserves extensions through deletion and signals a terminal exactly once", function()
			local account = released()
			local state = assert(deletion.prepare(nil, {
				userId = 101,
				operationId = "delete.1",
				characterId = "character.a",
				displayName = "Example One",
				requestedAtUnix = 100,
				fence = 8,
				leaseRevision = 2,
			}).state)
			account = assert(aggregate.transitionDeletion(account, state))
			for _, nextPhase in { "roster_removed", "name_released", "lease_released" } do
				local nextState = table.clone(state)
				nextState.phase = nextPhase
				nextState.revision += 1
				state = assert(deletion.validate(nextState))
				account = assert(aggregate.transitionDeletion(account, state))
				expect(account.token):toBe("retained")
			end
			account = assert(aggregate.clearDeletionTerminal(account))
			expect(account.completed):toBe(1)
			expect(account.token):toBe("retained")
			expect((aggregate.clearDeletionTerminal(account))):toBeNil()
		end)
		it("refuses malformed extensions, unknown fields, stale revisions and mismatched seeds", function()
			local empty = assert(aggregate.empty(101))
			local malformed = assert(Value.raw(empty))
			malformed.token = 42
			expect(aggregate.validate(malformed)):toBeNil()
			local raw = assert(Value.raw(empty))
			raw.foreign = true
			expect(aggregate.validate(raw)):toBeNil()
			local state = prepared()
			local pending = assert(aggregate.transition(empty, state))
			expect((aggregate.transition(pending, state))):toBeNil()
			local seeded = table.clone(released())
			seeded.profiles = {}
			expect(aggregate.validate(seeded)):toBeNil()
		end)
	end)
end
