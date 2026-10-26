--!strict
local Bdd = require("../../../.lute/dependencies/verify/src/bdd")
local Module = require("./transactions")
local Verify = require("../../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	type Profile = {
		ledgerMissing: boolean?,
		gold: number,
		inventory: { [string]: number },
		collections: Module.CollectionSet,
		pendingTrades: { [string]: boolean }?,
		pendingMail: { [string]: boolean }?,
	}

	type Overrides = {
		gold: number?,
		inventory: { [string]: number }?,
		collections: Module.CollectionSet?,
		pendingTrades: { [string]: boolean }?,
		pendingMail: { [string]: boolean }?,
	}

	local function profile(overrides: Overrides?): Profile
		local o: Overrides = overrides or {}
		return {
			gold = o.gold or 0,
			inventory = o.inventory or {},
			collections = o.collections or {},
			pendingTrades = o.pendingTrades,
			pendingMail = o.pendingMail,
		}
	end
	local Ledger = Module.transactions({
		ledgerPrefix = "tx:",
		orderPrefix = "tx:__order|",
		maxTransactionId = 96,
		maxRecords = 512,
		copy = function(p: Profile): Profile
			local out = table.clone(p)
			out.inventory = table.clone(p.inventory)
			out.collections = table.clone(p.collections)
			return out
		end,
		collections = function(p: Profile): Module.CollectionSet?
			return if p.ledgerMissing then nil else p.collections
		end,
		withCollections = function(p: Profile, c: Module.CollectionSet): Profile
			local out = table.clone(p)
			out.collections = c
			return out
		end,
		pinned = function(p: Profile, key: string): boolean
			for id in p.pendingTrades or {} do
				if string.sub(key, 1, #("tx:trade:" .. id .. ":")) == "tx:trade:" .. id .. ":" then
					return true
				end
			end
			for id in p.pendingMail or {} do
				if string.sub(key, 1, #("tx:mail:" .. id .. ":")) == "tx:mail:" .. id .. ":" then
					return true
				end
			end
			return false
		end,
	})
	local function grant(gold: number, itemId: string, count: number)
		return function(source: Profile): (Profile?, string?)
			local updated = table.clone(source)
			updated.gold = source.gold + gold
			local inventory = table.clone(source.inventory)
			inventory[itemId] = (inventory[itemId] or 0) + count
			updated.inventory = inventory
			return updated, nil
		end
	end

	local function purchase(price: number, itemId: string)
		return function(source: Profile): (Profile?, string?)
			if source.gold < price then
				return nil, "insufficient_gold"
			end
			local updated = table.clone(source)
			updated.gold = source.gold - price
			local inventory = table.clone(source.inventory)
			inventory[itemId] = (inventory[itemId] or 0) + 1
			updated.inventory = inventory
			return updated, nil
		end
	end

	describe("staged transaction effects", function()
		it("rejects nested mutation and preserves aliases in an accepted private copy", function()
			local shared = { quantity = 1 }
			type NestedProfile = {
				gold: number,
				inventory: { first: { quantity: number }, second: { quantity: number } },
				collections: Module.CollectionSet,
			}
			local Nested = Module.transactions({
				ledgerPrefix = "tx:",
				orderPrefix = "tx:__order|",
				maxTransactionId = 96,
				maxRecords = 512,
				copy = function(p: NestedProfile): NestedProfile
					local first = table.clone(p.inventory.first)
					return {
						gold = p.gold,
						inventory = {
							first = first,
							second = if p.inventory.first == p.inventory.second
								then first
								else table.clone(p.inventory.second),
						},
						collections = table.clone(p.collections),
					}
				end,
				collections = function(p: NestedProfile): Module.CollectionSet?
					return p.collections
				end,
				withCollections = function(p: NestedProfile, c: Module.CollectionSet): NestedProfile
					local out = table.clone(p)
					out.collections = c
					return out
				end,
				pinned = function(_p: NestedProfile, _key: string): boolean
					return false
				end,
			})
			local original = { gold = 0, inventory = { first = shared, second = shared }, collections = {} }
			local rejected = Nested.commit(original, "reject-copy", function(source)
				source.inventory.first.quantity = 99
				return nil, "refused"
			end)
			expect(rejected.state):toBe(original)
			expect(shared.quantity):toBe(1)
			local accepted = Nested.commit(original, "accept-copy", function(source)
				expect(source.inventory.first):toBe(source.inventory.second)
				source.inventory.first.quantity += 1
				return source, nil
			end)
			expect(accepted.outcome):toBe("committed")
			expect(shared.quantity):toBe(1)
			expect(accepted.state.inventory.first.quantity):toBe(2)
			expect(accepted.state.inventory.first):toBe(accepted.state.inventory.second)
		end)
	end)

	describe("ProfileTransactionLedger", function()
		describe("ledger keys", function()
			it("namespaces every transaction id away from the collection namespace", function()
				expect(Ledger.ledgerKey("quest-reward:vigil")):toBe("tx:quest-reward:vigil")
				expect(Ledger.LEDGER_PREFIX):toBe("tx:")
			end)

			it("refuses malformed transaction ids", function()
				expect(Ledger.ledgerKey("")):toBeNil()
				expect(Ledger.ledgerKey(string.rep("a", Ledger.MAX_TRANSACTION_ID + 1))):toBeNil()
				expect(Ledger.ledgerKey("has space")):toBeNil()
				expect(Ledger.ledgerKey(7)):toBeNil()
				expect(Ledger.ledgerKey(nil)):toBeNil()
				expect((Ledger.ledgerKey(string.rep("a", Ledger.MAX_TRANSACTION_ID))) ~= nil):toBe(true)
			end)

			it("does not read a same-named collection id as a recorded transaction", function()
				local held = profile({ collections = { ["vigil-offhand"] = true } })
				expect(Ledger.isRecorded(held.collections, "vigil-offhand")):toBe(false)
				local result = Ledger.commit(held, "vigil-offhand", grant(10, "warband_signet", 1))
				expect(result.outcome):toBe("committed")
				expect(result.state.gold):toBe(10)
				expect(result.state.collections["vigil-offhand"]):toBe(true)
				expect(result.state.collections["tx:vigil-offhand"]):toBe(true)
			end)
		end)

		describe("commit", function()
			it("marks the ledger on the effect's own output, never on the untouched profile", function()
				local before = profile()
				local result = Ledger.commit(before, "k.grant.1", grant(25, "warband_signet", 2))
				expect(result.outcome):toBe("committed")
				expect(result.reason):toBeNil()
				expect(result.state.gold):toBe(25)
				expect(result.state.inventory.warband_signet):toBe(2)
				expect(Ledger.isRecorded(result.state.collections, "k.grant.1")):toBe(true)
				expect(before.gold):toBe(0)
				expect(Ledger.isRecorded(before.collections, "k.grant.1")):toBe(false)
			end)

			it("replays a recorded transaction id as a no-op on the identical state", function()
				local before = profile()
				local first = Ledger.commit(before, "k.grant.2", grant(25, "warband_signet", 1))
				local second = Ledger.commit(first.state, "k.grant.2", grant(25, "warband_signet", 1))
				expect(second.state.gold):toBe(25)
				expect(second.state.inventory.warband_signet):toBe(1)
				expect(second.state):toBe(first.state)
				expect(second.outcome):toBe("replayed")
			end)

			it("rejects a malformed transaction id without running the effect", function()
				local ran = false
				local before = profile()
				local result = Ledger.commit(before, "", function(source: Profile): (Profile?, string?)
					ran = true
					return source, nil
				end)
				expect(result.outcome):toBe("rejected")
				expect(result.reason):toBe(Ledger.Reason.malformedTransactionId)
				expect(result.state):toBe(before)
				expect(ran):toBe(false)
			end)

			it("carries the effect's own rejection reason and leaves no mark", function()
				local before = profile({ gold = 10 })
				local result = Ledger.commit(before, "k.buy.1", purchase(40, "warband_signet"))
				expect(result.outcome):toBe("rejected")
				expect(result.reason):toBe("insufficient_gold")
				expect(result.state):toBe(before)
				expect(Ledger.isRecorded(result.state.collections, "k.buy.1")):toBe(false)
			end)

			it("debits and marks a solvent purchase in one state", function()
				local before = profile({ gold = 100 })
				local result = Ledger.commit(before, "k.buy.2", purchase(40, "warband_signet"))
				expect(result.outcome):toBe("committed")
				expect(result.state.gold):toBe(60)
				expect(result.state.inventory.warband_signet):toBe(1)
				expect(Ledger.isRecorded(result.state.collections, "k.buy.2")):toBe(true)
				local replayed = Ledger.commit(result.state, "k.buy.2", purchase(40, "warband_signet"))
				expect(replayed.state.gold):toBe(60)
				expect(replayed.outcome):toBe("replayed")
			end)

			it("rejects an effect that drops an earlier transaction mark", function()
				local first = Ledger.commit(profile(), "k.grant.3", grant(25, "warband_signet", 1))
				local result = Ledger.commit(first.state, "k.grant.4", function(source: Profile): (Profile?, string?)
					local updated = table.clone(source)
					updated.gold = source.gold + 5
					updated.collections = {}
					return updated, nil
				end)
				expect(Ledger.isRecorded(result.state.collections, "k.grant.3")):toBe(true)
				expect(result.state.gold):toBe(25)
				expect(result.state):toBe(first.state)
				expect(result.outcome):toBe("rejected")
				expect(result.reason):toBe(Ledger.Reason.ledgerDropped)
			end)

			it("rejects an effect whose output carries no ledger at all", function()
				local before = profile()
				local result = Ledger.commit(before, "k.grant.5", function(_source: Profile): (Profile?, string?)
					return { gold = 99, inventory = {}, collections = {}, ledgerMissing = true }, nil
				end)
				expect(result.outcome):toBe("rejected")
				expect(result.reason):toBe(Ledger.Reason.ledgerDropped)
				expect(result.state):toBe(before)
			end)

			it("rejects a profile that carries no ledger", function()
				local before: Profile = { gold = 0, inventory = {}, collections = {}, ledgerMissing = true }
				local result = Ledger.commit(before, "k.grant.6", grant(25, "warband_signet", 1))
				expect(result.outcome):toBe("rejected")
				expect(result.reason):toBe(Ledger.Reason.profileNotLedgered)
			end)

			it("keeps distinct transaction ids independent", function()
				local first = Ledger.commit(profile(), "k.grant.7", grant(25, "warband_signet", 1))
				local second = Ledger.commit(first.state, "k.grant.8", grant(25, "warband_signet", 1))
				expect(second.outcome):toBe("committed")
				expect(second.state.gold):toBe(50)
				expect(second.state.inventory.warband_signet):toBe(2)
				expect(Ledger.recordedKeys(second.state.collections)):toContain("tx:k.grant.7")
				expect(Ledger.recordedKeys(second.state.collections)):toContain("tx:k.grant.8")
			end)

			it("bounds history while retaining pending trade and mail recovery marks", function()
				local current = profile({
					pendingTrades = { exchange = true },
					pendingMail = { letter = true },
				})
				for _, id in { "trade:exchange:hold:11", "mail:letter:hold" } do
					local result = Ledger.commit(current, id, grant(0, "token", 0))
					current = result.state
				end
				for index = 1, Ledger.MAX_RECORDS + 20 do
					local result = Ledger.commit(current, "ordinary:" .. index, grant(0, "token", 0))
					current = result.state
				end
				expect(#Ledger.recordedKeys(current.collections)):toBe(Ledger.MAX_RECORDS)
				expect(Ledger.isRecorded(current.collections, "trade:exchange:hold:11")):toBe(true)
				expect(Ledger.isRecorded(current.collections, "mail:letter:hold")):toBe(true)
				expect(Ledger.isRecorded(current.collections, "ordinary:1")):toBe(false)
			end)

			it("rebuilds a corrupted order after a 2600 entry collection projection", function()
				local collections = {
					["tx:first"] = true,
					["tx:second"] = true,
					["tx:__order|tx:first|tx:missing"] = true,
				}
				for index = 1, 2600 do
					collections[("collection%04d"):format(index)] = true
				end
				local before = profile({ collections = collections })
				local result = Ledger.commit(before, "third", grant(1, "token", 1))
				expect(result.outcome):toBe("committed")
				expect(result.state.gold):toBe(1)
				expect(result.state.collections["tx:__order|tx:first|tx:missing"]):toBeNil()
				expect(result.state.collections["tx:__order|tx:first|tx:second|tx:third"]):toBe(true)
				expect(#Ledger.recordedKeys(result.state.collections)):toBe(3)
				expect(Ledger.isRecorded(result.state.collections, "first")):toBe(true)
				expect(Ledger.isRecorded(result.state.collections, "second")):toBe(true)
			end)

			it("repairs a replayed transaction without running its effect", function()
				local before = profile({
					collections = { ["tx:first"] = true, ["tx:__order|tx:missing"] = true },
				})
				local ran = false
				local result = Ledger.commit(before, "first", function(source: Profile): (Profile?, string?)
					ran = true
					return source, nil
				end)
				expect(result.outcome):toBe("replayed")
				expect(ran):toBe(false)
				expect(result.state.collections["tx:__order|tx:first"]):toBe(true)
				expect(result.state.collections["tx:__order|tx:missing"]):toBeNil()
			end)
		end)
	end)
	it("configures namespaces, receipt retention, bindings and pinning", function()
		local settings: Module.Config<Profile> = {
			ledgerPrefix = "receipt:",
			orderPrefix = "receipt:order|",
			maxTransactionId = 4,
			maxRecords = 1,
			copy = function(p: Profile): Profile
				local out = table.clone(p)
				out.inventory = table.clone(p.inventory)
				out.collections = table.clone(p.collections)
				return out
			end,
			collections = function(p: Profile): Module.CollectionSet?
				return p.collections
			end,
			withCollections = function(p: Profile, c: Module.CollectionSet): Profile
				local out = table.clone(p)
				out.collections = table.clone(c)
				return out
			end,
			pinned = function(_p: Profile, _key: string): boolean
				return false
			end,
		}
		local law = Module.transactions(settings)
		expect(law.ledgerKey("longer")):toBeNil()
		expect(law.ledgerKey("four")):toBe("receipt:four")
		local first = law.commit(profile(), "one", grant(1, "item", 1))
		local second = law.commit(first.state, "two", grant(1, "item", 1))
		expect(law.isRecorded(second.state.collections, "one")):toBe(false)
		expect(law.isRecorded(second.state.collections, "two")):toBe(true)
		expect(second.state.collections["receipt:order|receipt:two"]):toBe(true)
		local pinned = table.clone(settings)
		pinned.pinned = function(_p: Profile, _key: string): boolean
			return true
		end
		local full = Module.transactions(pinned).commit(first.state, "two", grant(1, "item", 1))
		expect(full.outcome):toBe("rejected")
		expect(full.reason):toBe("ledger_full")
		expect(full.state):toBe(first.state)
	end)
	it("rejects an effect that injects a receipt and uses the default rejection reason", function()
		local before = profile()
		local injected = Ledger.commit(before, "new", function(p: Profile): (Profile?, string?)
			p.collections["tx:forged"] = true
			return p, nil
		end)
		expect(injected.reason):toBe("ledger_dropped")
		expect(before.collections["tx:forged"]):toBeNil()
		local rejected = Ledger.commit(before, "new", function(_p: Profile): (Profile?, string?)
			return nil, nil
		end)
		expect(rejected.reason):toBe("effect_rejected")
	end)
end
