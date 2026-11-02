--!strict

local Bdd = require("../../.lute/dependencies/verify/src/bdd")
local Mail = require("./mail")
local Mailbox = require("../core/mail/mailbox")
local Transfer = require("./profile-transfer")
local Verify = require("../../.lute/dependencies/verify/src/core")

type Profile = {
	character: string,
	coin: number,
	bag: Mailbox.Inventory,
	pending: { [string]: Mail.Pointer },
	recorded: { [string]: boolean },
}
type Surface = { [number]: Profile }

local function rig()
	local profiles: Surface = {
		[1] = { character = "first", coin = 20, bag = { ore = 3 }, pending = {}, recorded = {} },
		[2] = { character = "second", coin = 10, bag = {}, pending = {}, recorded = {} },
	}
	local contexts: { [number]: Mail.Context } = {}
	for id, profile in profiles do
		contexts[id] = {
			userId = id,
			characterId = profile.character,
			key = "profile:" .. id,
			sessionId = "session:" .. id,
			acquisitionId = "acquisition:" .. id,
			leaseRevision = 1,
		}
	end
	local store: { [string]: Mail.Envelope } = {}
	local fail: { [string]: boolean } = {}
	local now = 100
	local blocked, ambiguous = false, false
	local core = Mailbox.mailbox({
		maxItems = 2,
		maxCount = 10,
		maxCoin = 100,
		maxUserId = 100,
		maxTimestamp = 10000,
		maxTtl = 100,
		itemIdLimit = 16,
		requestIdLimit = 16,
		characterIdLimit = 16,
		maxPointers = 4,
		readAccount = function(profile: Profile): unknown
			return { coin = profile.coin, inventory = profile.bag }
		end,
		writeAccount = function(profile: Profile, account: Mailbox.Account): Profile
			local updated = table.clone(profile)
			updated.coin, updated.bag = account.coin, account.inventory
			return updated
		end,
		capacity = function(_profile: Profile): number
			return 3
		end,
		entries = function(bag: Mailbox.Inventory): number
			local count = 0
			for _ in bag do
				count += 1
			end
			return count
		end,
	})
	local function contextFor(id: number): Mail.Context?
		return contexts[id]
	end
	local host = Mail.configure({
		core = core,
		identity = function(value: unknown): unknown
			return value
		end,
		profileFor = function(
			surface: Surface,
			resolve: (number) -> Mail.Context?,
			id: number
		): (Profile?, Mail.Context?)
			local context = resolve(id)
			return if context ~= nil then surface[id] else nil, context
		end,
		commit = function(
			surface: Surface,
			context: Mail.Context,
			id: string,
			effect: Mail.Effect<Profile>
		): Transfer.Result
			local profile = surface[context.userId]
			if profile.recorded[id] then
				return { ok = true, outcome = "replayed" }
			end
			if fail[id] then
				return { ok = false, outcome = "not_durable", reason = "save_failed" }
			end
			local updated, reason = effect(profile)
			if updated == nil then
				return { ok = false, outcome = "rejected", reason = reason }
			end
			updated = table.clone(updated)
			updated.recorded = table.clone(updated.recorded)
			updated.recorded[id] = true
			surface[context.userId] = updated
			return { ok = true, outcome = "committed" }
		end,
		update = function(surface: Surface, context: Mail.Context, apply: (Profile) -> Profile)
			surface[context.userId] = apply(surface[context.userId])
		end,
		characterId = function(profile: Profile): string?
			return profile.character
		end,
		pointers = function(profile: Profile): { [string]: Mail.Pointer }?
			return profile.pending
		end,
		withPointers = function(profile: Profile, pending: { [string]: Mail.Pointer }): Profile
			local updated = table.clone(profile)
			updated.pending = pending
			return updated
		end,
		envelopeKey = function(id: string): string
			return "envelope:" .. id
		end,
		transactionId = function(id: string, phase: string): string
			return id .. ":" .. phase
		end,
		senderId = function(id: string): number?
			return tonumber(string.match(id, "^(%d+):"))
		end,
		maxUserId = 100,
		maxPointers = 4,
		maxTtlSec = 100,
		idLimit = 32,
		rateWindowSec = 10,
		rateLimit = 20,
	})
	local deps: Mail.Dependencies<Profile, Surface> = {
		profiles = profiles,
		envelopes = {
			getOutcome = function(key: string): Mail.Outcome
				return { ok = not blocked, value = store[key] }
			end,
			updateOutcome = function(key: string, apply: (Mail.Envelope?) -> Mail.Envelope?): Mail.Outcome
				local envelope = apply(store[key])
				if envelope == nil then
					return { ok = false, value = nil }
				end
				store[key] = envelope
				if ambiguous then
					ambiguous = false
					return { ok = false, value = nil }
				end
				return { ok = true, value = envelope }
			end,
		},
		contextFor = contextFor,
		resolveRecipient = function(id: number, _character: unknown, _sender: number): unknown
			return profiles[id] ~= nil
		end,
		tradeable = function(_id: number, _profile: Profile, item: string, _count: number): boolean
			return item ~= "bound"
		end,
		allowed = function(_sender: number, _recipient: number): boolean
			return true
		end,
		reserveInbox = function(_id: number, _key: string, _envelope: Mail.Envelope): (boolean, string?)
			return true, nil
		end,
		releaseInbox = function(_id: number, _key: string, _envelope: Mail.Envelope): boolean
			return true
		end,
		clock = function(): number
			return now
		end,
		ttlSec = 50,
		requireSessions = true,
	}
	return {
		service = assert(host.create(deps)),
		profiles = profiles,
		store = store,
		fail = fail,
		contexts = contexts,
		restart = function()
			return assert(host.create(deps))
		end,
		block = function(value: boolean)
			blocked = value
		end,
		ambiguous = function()
			ambiguous = true
		end,
		advance = function()
			now += 51
		end,
	}
end

local function send(service: Mail.Service): Mail.Result
	return service.send(1, {
		requestId = "gift",
		recipientId = 2,
		recipientCharacterId = "second",
		attachments = { coin = 5, items = { { itemId = "ore", count = 2 } } },
	})
end

return function(suite: Verify.Harness)
	local test = Bdd.create(suite)
	local describe, it, expect = test.describe, test.it, test.expect
	describe("mail host", function()
		it("delivers a held attachment once across send and claim replay", function()
			local scene = rig()
			scene.ambiguous()
			expect(send(scene.service).ok):toBe(true)
			expect(send(scene.service).ok):toBe(true)
			expect(scene.profiles[1].coin):toBe(15)
			expect(scene.service.claim(2, "1:gift").ok):toBe(true)
			expect(scene.service.claim(2, "1:gift").ok):toBe(false)
			expect(scene.service.recover("1:gift").ok):toBe(true)
			expect(scene.profiles[2].coin):toBe(15)
			expect(scene.profiles[2].bag.ore):toBe(2)
			expect(scene.profiles[1].pending):toEqual({})
			expect(scene.profiles[2].pending):toEqual({})
		end)
		it("recovers an interrupted claim through fresh admitted pointers", function()
			local scene = rig()
			assert(send(scene.service).ok)
			scene.fail["1:gift:claim"] = true
			expect(scene.service.claim(2, "1:gift").pending):toBe(true)
			expect(scene.profiles[2].coin):toBe(10)
			scene.fail["1:gift:claim"] = nil
			expect(scene.restart().admit(2).ok):toBe(true)
			expect(scene.profiles[2].coin):toBe(15)
		end)
		it("holds unreadable decisions without removing sender funds", function()
			local scene = rig()
			scene.block(true)
			expect(send(scene.service).pending):toBe(true)
			expect(scene.profiles[1].coin):toBe(20)
			expect(scene.profiles[1].bag.ore):toBe(3)
		end)
		it("preserves the return path and fences a replacement recipient character", function()
			local scene = rig()
			assert(send(scene.service).ok)
			local prior = scene.contexts[2]
			scene.contexts[2] = {
				userId = 2,
				characterId = "replacement",
				key = prior.key,
				sessionId = prior.sessionId,
				acquisitionId = prior.acquisitionId,
				leaseRevision = 2,
			}
			expect(scene.service.claim(2, "1:gift").ok):toBe(false)
			expect(scene.profiles[2].coin):toBe(10)
			scene.contexts[2] = prior
			expect(scene.service.returnMail(2, "1:gift").ok):toBe(true)
			expect(scene.profiles[1].coin):toBe(20)
			expect(scene.profiles[1].bag.ore):toBe(3)
		end)
	end)
end
