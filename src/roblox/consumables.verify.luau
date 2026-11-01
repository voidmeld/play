--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Consumables = require("../core/progression/consumables")
local Host = require("./consumables")
local Verify = require("../../.lute/dependencies/verify/src/core")

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("consumable host", function()
		local function fixture()
			local core = Consumables.create({
				maxBuffStat = 40,
				maxBuffSeconds = 3600,
				movementToleranceSquared = 0.25,
				drinksMana = function()
					return true
				end,
				consumedCue = "consumed",
				channelCue = "resting",
				finishedCue = "finished",
				interruptedCue = function(reason)
					return reason
				end,
			})
			assert(core.register("food", { resource = "hp", verb = "eat", durationSec = 20, fractionPerSec = 0.025 }))
			assert(
				core.register("water", { resource = "mana", verb = "drink", durationSec = 20, fractionPerSec = 0.03 })
			)
			local actor: Host.Actor = {
				id = "a",
				characterId = "hero",
				hp = 20,
				maxHp = 100,
				mana = 10,
				maxMana = 100,
				pos = { x = 0, z = 0 },
			}
			local state: {
				context: string,
				body: string,
				moving: boolean,
				fail: boolean,
				rejected: boolean,
				items: number,
				writes: number,
				serial: number,
				began: number,
				cancelled: number,
				onCommit: (() -> ())?,
			} =
				{
					context = "first",
					body = "body",
					moving = false,
					fail = false,
					rejected = false,
					items = 3,
					writes = 0,
					serial = 0,
					began = 0,
					cancelled = 0,
				}
			local profiles = { first = true, second = true }
			local receipts: { [string]: boolean } = {}
			local snapshot: Host.Snapshot = { actor = actor, mobs = {}, now = 0 }
			local service = Host.create({
				core = core,
				present = function(player: string)
					return player == "player"
				end,
				contextFor = function(_player: string)
					return state.context
				end,
				characterFor = function(_player: string)
					return state.body
				end,
				snapshotFor = function(_player: string)
					return snapshot
				end,
				characterIdFor = function(_context: string)
					return "hero"
				end,
				alive = function(_player: string)
					return actor.hp > 0
				end,
				stationary = function(_player: string)
					return not state.moving
				end,
				profilePresent = function(context: string)
					return profiles[context] == true
				end,
				recorded = function(_context: string, receipt: string)
					return receipts[receipt] == true
				end,
				commit = function(
					_player: string,
					_context: string,
					_body: string,
					receipt: string,
					_item: string
				): Host.CommitResult
					state.writes += 1
					if state.onCommit ~= nil then
						state.onCommit()
					end
					if state.rejected then
						return { ok = false, outcome = "rejected", reason = "item_missing" }
					end
					if not receipts[receipt] then
						receipts[receipt] = true
						state.items -= 1
					end
					if state.fail then
						return { ok = false, outcome = "not_durable", reason = "offline" }
					end
					return { ok = true, outcome = "committed" }
				end,
				receipt = function()
					state.serial += 1
					return tostring(state.serial)
				end,
				begin = function(_player: string, item: string, serial: number)
					state.began += 1
					actor.sustenance = core.begin(actor.sustenance, actor, {}, item, serial, snapshot.now)
					return actor.sustenance ~= nil
				end,
				cancel = function(_player: string)
					state.cancelled += 1
				end,
				unavailableCue = "unavailable",
				idleCue = "idle",
				movementToleranceSquared = 0.25,
			})
			return {
				core = core,
				service = service,
				state = state,
				actor = actor,
				profiles = profiles,
				receipts = receipts,
				snapshot = snapshot,
			}
		end
		it("starts recovery only after durable consumption and rejects replayed input", function()
			local f = fixture()
			expect((f.service.use("player", "food", 1))):toBe(true)
			expect(f.state.items):toBe(2)
			expect(f.state.began):toBe(1)
			expect(select(2, f.service.use("player", "food", 1))):toBe("stale_use")
			expect(f.state.writes):toBe(1)
			expect(f.service.status("player").hpRemaining):toBe(20)
		end)
		it("retries uncertain writes with one receipt and cannot switch the pending item", function()
			local f = fixture()
			f.state.fail = true
			expect(select(2, f.service.use("player", "food", 1))):toBe("offline")
			expect(f.state.began):toBe(0)
			expect(select(2, f.service.use("player", "water", 2))):toBe("retry_previous_item")
			f.state.fail = false
			expect((f.service.use("player", "food", 3))):toBe(true)
			expect(f.state.items):toBe(2)
			expect(f.state.serial):toBe(1)
		end)
		it("never starts a consumed recovery after movement, damage or body replacement during the write", function()
			for _, change in { "movement", "damage", "body", "generation" } do
				local f = fixture()
				f.state.onCommit = function()
					if change == "movement" then
						f.state.moving = true
					elseif change == "damage" then
						f.actor.hp -= 1
					elseif change == "body" then
						f.state.body = "replacement"
					else
						f.actor.sustenanceGeneration = 1
					end
				end
				expect((f.service.use("player", "food", 1))):toBe(false)
				expect(f.state.began):toBe(0)
				expect(f.state.items):toBe(2)
			end
		end)
		it("serializes use requests while a durable write yields", function()
			local f = fixture()
			f.state.onCommit = function()
				coroutine.yield()
			end
			local worker = coroutine.create(function()
				f.service.use("player", "food", 1)
			end)
			expect(coroutine.resume(worker)):toBe(true)
			expect(select(2, f.service.use("player", "water", 2))):toBe("use_pending")
			expect(coroutine.resume(worker)):toBe(true)
			expect(f.state.writes):toBe(1)
		end)
		it("reconciles an uncertain consumption when the same character reopens its profile", function()
			local f = fixture()
			f.state.fail = true
			f.service.use("player", "food", 1)
			f.state.context = "second"
			f.profiles.first = false
			expect(select(2, f.service.use("player", "food", 2))):toBe("session_changed_consumed")
			expect(f.state.writes):toBe(1)
			f.state.fail = false
			expect((f.service.use("player", "food", 3))):toBe(true)
		end)
		it("enforces moving cancellation and rejects malformed or absent players before writes", function()
			local f = fixture()
			expect((f.service.use("player", "missing", 1))):toBe(false)
			expect((f.service.use("player", "food", math.nan))):toBe(false)
			expect((f.service.use("absent", "food", 1))):toBe(false)
			expect(f.state.writes):toBe(0)
			f.service.use("player", "food", 1)
			f.state.moving = true
			f.service.enforce("player")
			expect(f.state.cancelled):toBe(1)
			f.service.forget("player")
		end)
	end)
end
