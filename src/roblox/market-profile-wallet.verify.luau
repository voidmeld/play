--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Host = require("./market-profile-wallet")
local Stacks = require("../core/inventory/stacks")
local Verify = require("../../.lute/dependencies/verify/src/core")
local Wallets = require("../core/market/wallet")

type Profile = { coin: number, bag: Host.Inventory, ledger: Wallets.Ledger, bound: boolean }
local wallet = Wallets.wallet({
	claimedWindow = 10,
	healRetentionSec = 100,
	maxPending = 4,
	maxId = 32,
	maxCount = 100,
	maxCoin = 1000,
	maxTime = 10000,
	realms = { north = true },
})
local stacks = Stacks.stacks({ maxStack = 10, baseCapacity = 2, permanentItems = {}, bagBonus = {} })
local configured = Host.configure({
	wallet = wallet,
	items = "catalog",
	goods = function(profile: Profile, _materials: { string }, _items: string): Host.Inventory
		return table.clone(profile.bag)
	end,
	coin = function(profile: Profile): number
		return profile.coin
	end,
	inventory = function(profile: Profile): Host.Inventory
		return profile.bag
	end,
	ledger = function(profile: Profile): unknown
		return profile.ledger
	end,
	withAccount = function(profile: Profile, coin: number, bag: Host.Inventory, ledger: Wallets.Ledger): Profile
		return { coin = coin, bag = bag, ledger = ledger, bound = profile.bound }
	end,
	capacity = function(_profile: Profile): number
		return 2
	end,
	entries = stacks.entries,
	fits = stacks.fits,
	unboundCount = function(profile: Profile, id: string): number
		return if profile.bound then 0 else profile.bag[id] or 0
	end,
})
local function rig()
	local profile: Profile = { coin = 100, bag = { ore = 3 }, ledger = wallet.emptyLedger(), bound = false }
	local saves = 0
	local durable = true
	local retry: ((Profile) -> Profile)? = nil
	local port = assert(configured.create({
		userId = 1,
		materials = { "ore" },
		maxItemCount = 10,
		maxInventoryEntries = 2,
		readProfile = function(): Profile?
			return profile
		end,
		updateProfile = function(apply: (Profile) -> Profile)
			if retry ~= nil then
				apply(profile)
				profile = retry(profile)
			end
			profile = apply(profile)
		end,
		saveProfile = function(): boolean
			saves += 1
			return durable
		end,
	}))
	return {
		port = port,
		profile = function()
			return profile
		end,
		set = function(value: Profile)
			profile = value
		end,
		saves = function()
			return saves
		end,
		fail = function()
			durable = false
		end,
		retry = function(change: (Profile) -> Profile)
			retry = change
		end,
	}
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("profile market wallet", function()
		it("preserves concurrent rewards while applying a paired wallet delta once", function()
			local scene = rig()
			local base = assert(scene.port.read())
			local bought = wallet.npcTrade(base, "buy", "ore", 1, 5)
			assert(bought.ok)
			local live = table.clone(scene.profile())
			live.coin += 10
			live.bag = { ore = 5 }
			scene.set(live)
			expect(scene.port.write(bought.state)):toBe(true)
			expect(scene.profile().coin):toBe(105)
			expect(scene.profile().bag.ore):toBe(6)
			expect(scene.port.write(bought.state)):toBe(false)
			expect(scene.saves()):toBe(1)
		end)
		it("refuses bound removals and computes room from current capacity", function()
			local scene = rig()
			local base = assert(scene.port.read())
			local sold = wallet.npcTrade(base, "sell", "ore", 1, 1)
			assert(sold.ok)
			local live = table.clone(scene.profile())
			live.bound = true
			scene.set(live)
			expect(scene.port.write(sold.state)):toBe(false)
			expect(scene.profile().bag.ore):toBe(3)
			expect(scene.saves()):toBe(0)
			live.bag = { ore = 3, wood = 1 }
			expect(scene.port.room("bar")):toBe(0)
			expect(scene.port.room("ore")):toBe(7)
		end)
		it("uses final callback acceptance after a retry and reports save uncertainty", function()
			local scene = rig()
			local base = assert(scene.port.read())
			local bought = wallet.npcTrade(base, "buy", "ore", 1, 5)
			assert(bought.ok)
			scene.retry(function(profile)
				local latest = table.clone(profile)
				latest.coin = 0
				return latest
			end)
			expect(scene.port.write(bought.state)):toBe(false)
			expect(scene.saves()):toBe(0)
			local failed = rig()
			local before = assert(failed.port.read())
			local changed = wallet.npcTrade(before, "buy", "ore", 1, 5)
			assert(changed.ok)
			failed.fail()
			expect(failed.port.write(changed.state)):toBe(false)
			expect(failed.saves()):toBe(1)
		end)
	end)
end
