--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Inventory = require("./inventory")
local Stacks = require("../core/inventory/stacks")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Profile = {
	inventory: Inventory.Inventory,
	coin: number,
	experience: number,
	receipts: { [string]: boolean },
	season: string?,
}
type Readable = { profile: Profile? }
local rules = Stacks.stacks({ maxStack = 10, baseCapacity = 2, permanentItems = { key = true }, bagBonus = {} })

local function rig()
	local cell: Readable = { profile = { inventory = { ore = 2 }, coin = 0, experience = 0, receipts = {} } }
	local context: string? = "first"
	local retry: ((Profile) -> Profile)? = nil
	local function withInventory(profile: Profile, bag: Inventory.Inventory): Profile
		local out = table.clone(profile)
		out.inventory = bag
		return out
	end
	local function read(value: Readable): Profile?
		return value.profile
	end
	local service = Inventory.create({
		context = function(_subject: number): string?
			return context
		end,
		readable = function(_context: string): Readable
			return cell
		end,
		peek = read,
		update = function(_context: string, apply: (Profile) -> Profile)
			local before = assert(cell.profile)
			if retry ~= nil then
				apply(before)
				before = retry(before)
			end
			cell.profile = apply(before)
		end,
		inventory = function(profile: Profile)
			return profile.inventory
		end,
		withInventory = withInventory,
		capacity = function(_profile: Profile)
			return 2
		end,
		exists = function(id: string): boolean
			return id == "ore" or id == "bar" or id == "wood" or id == "key"
		end,
		permanent = rules.permanent,
		maxStack = 10,
		transactionIdLimit = 16,
		copyBag = rules.copyBag,
		validCount = rules.isValidCount,
		addToBag = rules.addToBag,
		removeFromBag = rules.removeFromBag,
		fits = rules.fits,
		recorded = function(profile: Profile, id: string)
			return profile.receipts[id] == true
		end,
		reward = function(
			profile: Profile,
			id: string,
			bag: Inventory.Inventory,
			xp: number,
			coin: number,
			season: string?
		): Profile
			local out = withInventory(profile, bag)
			out.coin += coin
			out.experience += xp
			out.receipts = table.clone(profile.receipts)
			out.receipts[id] = true
			out.season = season
			return out
		end,
	})
	return {
		service = service,
		cell = cell,
		read = read,
		revoke = function()
			context = nil
		end,
		retry = function(change: (Profile) -> Profile)
			retry = change
		end,
	}
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("inventory host", function()
		it("reads detached bags and refuses mutation without an active context", function()
			local scene = rig()
			local copy = scene.service.getItems(scene.read, 1)
			copy.ore = 9
			expect(scene.service.getCount(scene.read, 1, "ore")):toBe(2)
			expect(scene.service.hasItem(scene.read, 1, "ore", 2)):toBe(true)
			scene.revoke()
			expect(scene.service.addItem(1, "bar", 1)):toBe(false)
			expect(scene.service.getItems(scene.read, 1)):toEqual({})
		end)
		it("enforces admission and stack bounds without changing refused inputs", function()
			local scene = rig()
			local before = assert(scene.cell.profile)
			for _, id in { "missing", "key" } do
				expect(scene.service.addItem(1, id, 1)):toBe(false)
			end
			for _, count in { -1, 0, 0.5, math.huge, math.nan, 9 } do
				expect(scene.service.addItem(1, "ore", count)):toBe(false)
			end
			expect(scene.cell.profile):toBe(before)
			expect(scene.service.addItem(1, "bar", 1)):toBe(true)
			expect(before.inventory.bar):toBeNil()
		end)
		it("recomputes removal from the authoritative transform after a retry", function()
			local scene = rig()
			scene.retry(function(profile)
				local out = table.clone(profile)
				out.inventory = { ore = 7 }
				return out
			end)
			expect(scene.service.removeItem(1, "ore", 1)):toBe(true)
			expect(assert(scene.cell.profile).inventory.ore):toBe(6)
		end)
		it("refuses new slots at capacity while allowing existing stacks in an overfull bag", function()
			local scene = rig()
			expect(scene.service.addItem(1, "bar", 1)):toBe(true)
			expect(scene.service.addItem(1, "wood", 1)):toBe(false)
			assert(scene.cell.profile).inventory.wood = 1
			expect(scene.service.addItem(1, "ore", 1)):toBe(true)
			expect(assert(scene.cell.profile).inventory.ore):toBe(3)
		end)
		it("clears provisional acceptance when a retry loses its context", function()
			local scene = rig()
			scene.retry(function(profile)
				scene.revoke()
				return profile
			end)
			expect(scene.service.addItem(1, "bar", 1)):toBe(false)
			expect(assert(scene.cell.profile).inventory.bar):toBeNil()
		end)
		it("commits rewards and their receipt together and refuses replay", function()
			local scene = rig()
			expect(scene.service.commitRewardTransaction(1, "reward", { { id = "bar", count = 1 } }, 3, 4, "track")):toBe(
				true
			)
			local profile = assert(scene.cell.profile)
			expect(profile.inventory):toEqual({ ore = 2, bar = 1 })
			expect(profile.experience):toBe(3)
			expect(profile.coin):toBe(4)
			expect(profile.receipts.reward):toBe(true)
			expect(profile.season):toBe("track")
			expect(scene.service.commitRewardTransaction(1, "reward", { { id = "bar", count = 1 } }, 3, 4)):toBe(false)
			expect(scene.cell.profile):toBe(profile)
		end)
		it("refuses malformed or empty rewards before applying their effects", function()
			local scene = rig()
			local before = scene.cell.profile
			expect(scene.service.commitRewardTransaction(1, "", {}, 1)):toBe(false)
			expect(scene.service.commitRewardTransaction(1, "empty", {}, 0)):toBe(false)
			expect(scene.service.commitRewardTransaction(1, "nan", {}, math.nan)):toBe(false)
			expect(
				scene.service.commitRewardTransaction(
					1,
					"duplicate",
					{ { id = "ore", count = 1 }, { id = "ore", count = 1 } },
					0
				)
			):toBe(false)
			expect(scene.service.commitRewardTransaction(1, "permanent", { { id = "key", count = 1 } }, 0)):toBe(false)
			expect(scene.cell.profile):toBe(before)
		end)
		it("retains admitted reward values while the host retries", function()
			local scene = rig()
			local items = { { id = "bar", count = 1 } }
			scene.retry(function(profile)
				items[1].count = 100
				return profile
			end)
			expect(scene.service.commitRewardTransaction(1, "reward", items, 0)):toBe(true)
			expect(assert(scene.cell.profile).inventory.bar):toBe(1)
		end)
	end)
end
