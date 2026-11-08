--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Protocol = require("./protocol")
local Scene = require("./scene")
local State = require("./state")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect

	describe("isolated checkpoint recovery", function()
		it("restores two same-hour revisions without replaying quest or market value", function(own)
			local source = Scene.new()
			own(source.dispose)
			local first = source.connect(11)
			local second = source.connect(22)
			own(first.dispose)
			own(second.dispose)
			for _, buyer in { { userId = 11, client = first }, { userId = 22, client = second } } do
				buyer.client.request({ kind = "accept" })
				local equip: Protocol.EquipRequest = { kind = "equip", itemId = "training_sword" }
				buyer.client.request(equip)
				for _ = 1, 3 do
					buyer.client.request({ kind = "attack" })
					source.clock.advance(0.25)
					source.clock.advance(0.3)
				end
				buyer.client.request({ kind = "loot", defeatId = assert(source.mount.world.view(buyer.userId)).loot[1] })
				buyer.client.request({ kind = "claim" })
				expect(assert(buyer.client.latest()).ok):toBe(true)
				source.clock.advance(3)
			end
			local earlier = assert(State.copy(source.values["world:Harbor"]))
			local earlierAt = source.clock.clock()
			expect(earlier.market):toBe(nil)
			source.clock.advance(1)
			first.request({ kind = "craft" })
			expect(assert(first.latest()).ok):toBe(true)
			first.request({ kind = "list" })
			expect(assert(first.latest()).ok):toBe(true)
			second.request({ kind = "buy" })
			expect(assert(second.latest()).ok):toBe(true)
			local later = assert(State.copy(source.values["world:Harbor"]))
			local laterAt = source.clock.clock()
			expect(later.revision > earlier.revision):toBe(true)
			expect(math.floor(laterAt / 3600)):toBe(math.floor(earlierAt / 3600))
			expect(later.players["11"].coin):toBe(29)
			expect(later.players["22"].coin):toBe(20)
			expect(assert(later.market).burnedCoin):toBe(1)
			expect(source.mount.shutdown()):toBe(true)
			expect(earlier.players["11"].coin):toBe(25)
			expect(earlier.players["22"].coin):toBe(25)
			expect(earlier.players["11"].inventory.copper_ore):toBe(1)
			expect(later.players["11"].inventory.copper_ore):toBe(nil)
			expect(earlier.players["11"].lock.sessionId == nil):toBe(false)
			expect(later.players["11"].lock.sessionId == nil):toBe(false)
			expect(assert(State.copy(source.values["world:Harbor"])).players["11"].lock.sessionId):toBe(nil)
			first.dispose()
			second.dispose()
			for _, archived in { earlier, later } do
				local original = assert(State.copy(archived))
				local restored = Scene.new({ ["world:Harbor"] = assert(State.copy(archived)) }, laterAt + 61)
				own(restored.dispose)
				local returned, firstPlayer = restored.connect(11)
				local partner, secondPlayer = restored.connect(22)
				own(returned.dispose)
				own(partner.dispose)
				expect(restored.mount.admission.isAdmitted(firstPlayer)):toBe(true)
				expect(restored.mount.admission.isAdmitted(secondPlayer)):toBe(true)
				local admitted = assert(State.copy(restored.values["world:Harbor"]))
				expect(admitted.market):toEqual(original.market)
				for _, userId in { "11", "22" } do
					local expected, actual = original.players[userId], admitted.players[userId]
					expect(actual.acquisitionId == expected.acquisitionId):toBe(false)
					expect(actual.inventory):toEqual(expected.inventory)
					expect(actual.equipment):toEqual(expected.equipment)
					expect(actual.coin):toBe(expected.coin)
					expect(actual.xp):toBe(expected.xp)
					expect(actual.journal):toEqual(expected.journal)
					expect(actual.defeats):toEqual(expected.defeats)
					expect(actual.loot):toEqual(expected.loot)
				end
				returned.request({ kind = "claim" })
				expect(assert(returned.latest()).reason):toBe("quest_incomplete")
				local defeatId: string? = nil
				for id in original.players["11"].defeats do
					defeatId = id
					break
				end
				returned.request({ kind = "loot", defeatId = assert(defeatId) })
				expect(assert(returned.latest()).reason):toBe("loot_missing")
				partner.request({ kind = "buy" })
				expect(assert(partner.latest()).reason):toBe("no_supply")
				expect(State.copy(restored.values["world:Harbor"])):toEqual(admitted)
				expect(restored.mount.shutdown()):toBe(true)
				expect(State.copy(archived)):toEqual(original)
				expect(restored.engine.scheduler.failures):toEqual({})
				returned.dispose()
				partner.dispose()
				restored.dispose()
			end
			source.dispose()
		end)
	end)
end
