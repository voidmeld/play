--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Host = require("./bank")
local Transfer = require("./profile-transfer")
local Vault = require("../core/bank/vault")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Profile = { inventory: Vault.Inventory, bank: Vault.State, recorded: { [string]: boolean } }
type Surface = { value: Profile }
local vault = Vault.vault({
	maxStack = 10,
	maxBagSlots = 3,
	maxBankSlots = 3,
	maxReceipts = 4,
	itemIdLimit = 16,
	bankerIdLimit = 16,
	requestIdLimit = 16,
	readProfile = function(profile: Profile): unknown
		return profile
	end,
	writeProfile = function(profile: Profile, inventory: Vault.Inventory, bank: Vault.State): Profile
		return { inventory = inventory, bank = bank, recorded = profile.recorded }
	end,
	permanent = function(_id: string): boolean
		return false
	end,
	fits = function(_profile: Profile, _before: Vault.Inventory, _after: Vault.Inventory): boolean
		return true
	end,
	transfer = function(profile: Profile, _request: Vault.Request): Profile
		return profile
	end,
})
local function rig()
	local surface: Surface = { value = { inventory = { ore = 3 }, bank = vault.default(), recorded = {} } }
	local player: Host.Subject = { UserId = 1 }
	local x, now = 0, 100
	local durable, allowed = true, true
	local configured = Host.configure({
		core = vault,
		read = function(value: Surface, _context: string): Profile?
			return value.value
		end,
		commit = function(
			value: Surface,
			_context: string,
			id: string,
			apply: (Profile) -> (Profile?, string?)
		): Transfer.Result
			if value.value.recorded[id] then
				return { ok = true, outcome = "replayed" }
			end
			if not durable then
				return { ok = false, outcome = "not_durable" }
			end
			local updated, reason = apply(value.value)
			if updated == nil then
				return { ok = false, outcome = "rejected", reason = reason }
			end
			updated.recorded = table.clone(updated.recorded)
			updated.recorded[id] = true
			value.value = updated
			return { ok = true, outcome = "committed" }
		end,
		bank = function(profile: Profile): unknown
			return profile.bank
		end,
		transactionId = function(id: number, request: string): string
			return id .. ":" .. request
		end,
		maxUserId = 100,
		maxReach = 5,
		rateWindowSec = 1,
		rateLimit = 3,
	})
	local service = assert(configured.create({
		profiles = surface,
		contextFor = function(_id: number): string?
			return "session"
		end,
		playerFor = function(_id: number): Host.Subject?
			return player
		end,
		positionFor = function(_id: number): Host.Location?
			return { placeId = "place", position = { x = x, y = 0, z = 0 } }
		end,
		bankerFor = function(id: string): Host.Banker?
			return { id = id, placeId = "place", position = { x = 0, y = 0, z = 0 }, enabled = true }
		end,
		canBank = function(_id: number, _profile: Profile, _item: string, _kind: string): boolean
			return allowed
		end,
		clock = function(): number
			return now
		end,
	}))
	return {
		service = service,
		player = player,
		surface = surface,
		far = function()
			x = 10
		end,
		fail = function()
			durable = false
		end,
		deny = function()
			allowed = false
		end,
		advance = function()
			now += 2
		end,
	}
end
local function deposit(service: Host.Handle, player: Host.Subject, id: string): Host.Result
	return service.intent(player, { kind = "deposit", requestId = id, bankerId = "vault", itemId = "ore", count = 1 })
end
return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("bank host", function()
		it("saves a transfer and its receipt once and checks actor identity", function()
			local scene = rig()
			expect(deposit(scene.service, scene.player, "first").ok):toBe(true)
			expect(deposit(scene.service, scene.player, "first").ok):toBe(true)
			expect(scene.surface.value.inventory.ore):toBe(2)
			expect(scene.surface.value.bank.items.ore):toBe(1)
			expect(deposit(scene.service, { UserId = 1 }, "forged").ok):toBe(false)
		end)
		it("refuses distance, lost policy and uncertain saves without reporting success", function()
			local scene = rig()
			scene.far()
			expect(deposit(scene.service, scene.player, "far").reason):toBe("banker_unreachable")
			local denied = rig()
			denied.deny()
			expect(deposit(denied.service, denied.player, "bound").reason):toBe("item_bound")
			local failed = rig()
			failed.fail()
			expect(deposit(failed.service, failed.player, "save").pending):toBe(true)
			expect(failed.surface.value.inventory.ore):toBe(3)
		end)
		it("bounds request rates and releases them on lifetime reset", function()
			local scene = rig()
			for _ = 1, 3 do
				deposit(scene.service, scene.player, "same")
			end
			expect(deposit(scene.service, scene.player, "same").reason):toBe("actor_or_rate_invalid")
			scene.service.forget(1)
			expect(deposit(scene.service, scene.player, "same").ok):toBe(true)
		end)
	end)
end
