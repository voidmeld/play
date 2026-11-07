--!strict

local Admission = require("../../src/roblox/character-admission")
local Chat = require("../../src/core/chat/channels")
local Content = require("./content")
local Lock = require("../../src/core/persistence/session-lock")
local Net = require("../../src/core/net/rate-limit")
local Objectives = require("../../src/core/quest/objectives")
local ProfileSession = require("../../src/core/persistence/profile-session")
local Protocol = require("./protocol")
local Records = require("../../src/core/persistence/record-store")
local Sessions = require("../../src/roblox/profile-sessions")
local State = require("./state")
local Threat = require("../../src/core/threat/table")
local Trade = require("../../src/core/trade/exchange")
local Value = require("../../src/kernel/value")

export type Ports = {
	store: Records.Store,
	owner: Sessions.Owner,
	clock: () -> number,
	schedule: (number, () -> ()) -> () -> (),
	serverId: string,
	newId: () -> string,
	filter: (number, string, number) -> string?,
	deliver: (number, Protocol.Response) -> (),
	report: (string) -> (),
}
type Active = { context: Admission.Context, token: string, session: ProfileSession.State }
local sessionRules = ProfileSession.create({
	leaseSeconds = Content.leaseSeconds,
	renewBeforeSeconds = 20,
	coalesceSeconds = 0,
	shutdownSeconds = 10,
	ordinaryReason = "change",
	immediateReasons = {},
})
local threatRules = Threat.rules({ meleeTakeover = 1.1, rangedTakeover = 1.3, tauntLead = 1 })
local budget = { capacity = 16, refillPerSec = 8 }

local function new(ports: Ports)
	local snapshot = State.records.read(ports.store, function()
		return "world:Harbor"
	end, "Harbor", "world")
	assert(snapshot.ok, snapshot.reason)
	local world = snapshot.value
	local active: { [number]: Active } = {}
	local busy = false
	local held = false
	local stopped = false
	local buckets: Net.KeyedState = {}
	local chatBuckets: { [number]: Chat.Bucket } = {}
	local exchange: Trade.State? = nil
	local enemy = { health = 30, threat = Threat.empty(), defeatId = ports.newId() }

	local function transact(edit: (State.World) -> (boolean, string?)): (boolean, string?)
		if stopped or held or busy then
			return false, if held then "storage_held" else "busy"
		end
		busy = true
		local ran, ok, reason = pcall(function(): (boolean, string?)
			local read = State.records.read(ports.store, function()
				return "world:Harbor"
			end, "Harbor", "world")
			if not read.ok then
				return false, read.reason
			end
			local candidate = assert(State.copy(read.value))
			local accepted, refusal = edit(candidate)
			if not accepted then
				return false, refusal
			end
			local saved = State.records.update(ports.store, function()
				return "world:Harbor"
			end, read, candidate)
			if not saved.ok then
				held = true
				ports.report(saved.reason or "write_uncertain")
				return false, "storage_held"
			end
			world = saved.value
			return true, nil
		end)
		busy = false
		if not ran then
			held = true
			ports.report(tostring(ok))
			return false, "storage_held"
		end
		return ok, reason
	end

	local function live(profile: State.Profile?, entry: Active?): boolean
		return profile ~= nil
			and entry ~= nil
			and not held
			and not stopped
			and not entry.session.closed
			and not entry.session.leaseLost
			and Lock.isLocked(profile.lock, entry.token, ports.clock())
	end
	local function current(userId: number): State.Profile?
		local profile = world.players[tostring(userId)]
		return if live(profile, active[userId]) then profile else nil
	end
	local function view(userId: number): Protocol.View?
		local profile = current(userId)
		if profile == nil then
			return nil
		end
		local progress = profile.journal.quests[Content.quest.id]
		local loot: { string } = {}
		for id in profile.loot do
			table.insert(loot, id)
		end
		table.sort(loot)
		return {
			characterId = profile.characterId,
			displayName = profile.roster.characters[1].displayName,
			level = Content.levels.levelForXp(profile.xp),
			xp = profile.xp,
			coin = profile.coin,
			inventory = table.clone(profile.inventory),
			equipment = table.clone(profile.equipment),
			questStatus = progress.status,
			counts = table.clone(progress.counts or {}),
			loot = loot,
		}
	end
	local function credit(profile: State.Profile, event: Objectives.Event)
		local progress = profile.journal.quests[Content.quest.id]
		if progress.status ~= "active" then
			return
		end
		local counts = assert(progress.counts)
		for _, binding in Content.objectives.bindingsFor({ Content.quest }, event) do
			counts[binding.objectiveId] = 1
		end
		progress.step = (counts.defeat or 0) + (counts.collect or 0)
	end
	local function xp(profile: State.Profile, amount: number)
		profile.xp += amount
		profile.roster =
			Content.roster.markLevel(profile.roster, profile.characterId, Content.levels.levelForXp(profile.xp))
	end
	local function change(userId: number, edit: (State.World, State.Profile) -> (boolean, string?)): (boolean, string?)
		if busy then
			return false, "busy"
		end
		local entry = active[userId]
		if entry == nil or current(userId) == nil then
			return false, "not_admitted"
		end
		if not sessionRules.dirty(entry.session, ports.clock(), "change").ok then
			return false, "lease_lost"
		end
		if not sessionRules.begin(entry.session, ports.clock()).ok then
			return false, "busy"
		end
		local ok, reason = transact(function(candidate)
			local profile = candidate.players[tostring(userId)]
			if not live(profile, entry) then
				return false, "lease_lost"
			end
			local accepted, refusal = edit(candidate, profile)
			if not accepted then
				return false, refusal
			end
			profile.lock =
				assert(Lock.tryAcquire(profile.lock, entry.token, ports.clock(), Content.leaseSeconds).newState)
			return true, nil
		end)
		local finished = sessionRules.finish(entry.session, ports.clock(), ok)
		if ok and not finished.ok then
			held = true
		end
		return ok and finished.ok, reason or finished.reason
	end

	local sessions = Sessions.new(ports.owner, {
		clock = ports.clock,
		schedule = ports.schedule,
		report = function(_kind, key, reason)
			ports.report(key .. ":" .. (reason or "held"))
		end,
		renewalDelay = 20,
		retryDelay = 2,
		drainBudget = 10,
		jitter = function()
			return 0
		end,
		jitterFraction = 0,
		keyFor = function(context: Admission.Context)
			return tostring(context.userId)
		end,
		same = function(a: Admission.Context, b: Admission.Context)
			return a.acquisitionId == b.acquisitionId
		end,
		write = function(
			_profile: State.Profile,
			context: Admission.Context,
			_expiry,
			stillCurrent,
			release,
			_generation
		): Sessions.Outcome
			local entry = active[context.userId]
			if entry == nil or not stillCurrent() then
				return { ok = false, reason = "stale_session" }
			end
			if not release then
				local ok, reason = change(context.userId, function()
					return true, nil
				end)
				return { ok = ok, reason = reason, expiresAt = entry.session.leaseExpiresAt }
			end
			if not entry.session.closed then
				local closed = sessionRules.close(entry.session, ports.clock())
				if not closed.ok then
					return { ok = false, reason = closed.reason }
				end
			end
			local began = sessionRules.begin(entry.session, ports.clock())
			if not began.ok then
				return { ok = false, reason = began.reason }
			end
			local ok, reason = transact(function(candidate)
				local profile = candidate.players[tostring(context.userId)]
				if
					profile == nil
					or not Lock.isLocked(profile.lock, entry.token, ports.clock())
					or not stillCurrent()
				then
					return false, "lease_lost"
				end
				profile.roster = Content.roster.markPlayed(profile.roster, profile.characterId, ports.clock())
				profile.lock = assert(Lock.release(profile.lock, entry.token))
				return true, nil
			end)
			local finished = sessionRules.finish(entry.session, ports.clock(), ok)
			return { ok = ok and finished.ok, reason = reason or finished.reason, expiresAt = ports.clock() }
		end,
	})

	local function create(userId: number, displayName: string): boolean
		if Value.whole(userId, 1, 9007199254740991) == nil then
			return false
		end
		if world.players[tostring(userId)] ~= nil then
			return true
		end
		local ok = transact(function(candidate)
			if candidate.players[tostring(userId)] == nil then
				local total = 0
				for _ in candidate.players do
					total += 1
				end
				if total >= Content.playerLimit then
					return false, "world_full"
				end
				candidate.players[tostring(userId)] = State.create(userId, displayName, ports.clock())
			end
			return true, nil
		end)
		return ok
	end
	local function join(userId: number, acquisitionId: string): Admission.CharacterOutcome<State.Profile>
		if active[userId] ~= nil then
			return { ok = false, reason = "already_admitted" }
		end
		local token = ports.serverId .. ":" .. acquisitionId
		local ok, reason = transact(function(candidate)
			local profile = candidate.players[tostring(userId)]
			if profile == nil then
				return false, "character_missing"
			end
			local acquired = Lock.tryAcquire(profile.lock, token, ports.clock(), Content.leaseSeconds)
			if not acquired.granted then
				return false, "session_held"
			end
			profile.lock = assert(acquired.newState)
			profile.acquisitionId = acquisitionId
			profile.roster = Content.roster.markDeparted(profile.roster, profile.characterId, "harbor:entry")
			return true, nil
		end)
		if not ok then
			return { ok = false, reason = reason }
		end
		local profile = world.players[tostring(userId)]
		local session = assert(sessionRules.openAcquired(ports.clock(), profile.lock.lockExpiry))
		local context: Admission.Context = table.freeze({
			userId = userId,
			characterId = profile.characterId,
			key = "world:Harbor",
			sessionId = ports.serverId,
			acquisitionId = acquisitionId,
			leaseRevision = 1,
		})
		active[userId] = { context = context, token = token, session = session }
		sessions.admit(context, profile.lock.lockExpiry, function()
			return current(userId)
		end, function()
			active[userId] = nil
			enemy.threat = Threat.remove(enemy.threat, tostring(userId))
		end)
		return { ok = true, profile = assert(State.copyProfile(profile)), context = context, lease = { revision = 1 } }
	end
	local function close(userId: number): boolean
		if busy then
			return false
		end
		local entry = active[userId]
		if entry == nil then
			return true
		end
		local outcome = sessions.unload(entry.context)
		if outcome.ok and exchange ~= nil and table.find(exchange.players, userId) ~= nil then
			exchange = nil
		end
		return outcome.ok
	end
	local function response(userId: number, ok: boolean, reason: string?): Protocol.Response
		return {
			ok = ok,
			reason = reason,
			view = view(userId),
			trade = if exchange ~= nil and table.find(exchange.players, userId) ~= nil
				then Protocol.tradeView(exchange)
				else nil,
		}
	end
	local function settle(candidate: State.World, trade: Trade.State): (boolean, string?)
		for _, userId in trade.players do
			if not live(candidate.players[tostring(userId)], active[userId]) then
				return false, "partner_unavailable"
			end
		end
		for _, userId in trade.players do
			local profile = candidate.players[tostring(userId)]
			local offer = trade.offers[userId]
			if profile.coin < offer.coin then
				return false, "insufficient_coin"
			end
			profile.coin -= offer.coin
			for _, stack in offer.items do
				local removed
				profile.inventory, removed = Content.stacks.removeFromBag(profile.inventory, stack.itemId, stack.count)
				if not removed then
					return false, "item_missing"
				end
			end
		end
		for index, userId in trade.players do
			local profile = candidate.players[tostring(userId)]
			local incoming = trade.offers[trade.players[3 - index]]
			profile.coin += incoming.coin
			if profile.coin > 100000 then
				return false, "coin_full"
			end
			for _, stack in incoming.items do
				if (profile.inventory[stack.itemId] or 0) + stack.count > 99 then
					return false, "stack_full"
				end
				profile.inventory = Content.stacks.addToBag(profile.inventory, stack.itemId, stack.count)
			end
			if Content.stacks.entries(profile.inventory) > Content.stacks.capacity(nil) then
				return false, "inventory_full"
			end
		end
		return true, nil
	end
	local function request(userId: number, raw: unknown): Protocol.Response
		local permitted
		permitted, buckets = Net.consume(buckets, tostring(userId), budget, ports.clock())
		if not permitted then
			return { ok = false, reason = "rate_limited" }
		end
		if busy then
			return { ok = false, reason = "busy" }
		end
		if current(userId) == nil then
			return { ok = false, reason = "not_admitted" }
		end
		local intent = Protocol.decode(raw)
		if intent == nil then
			return response(userId, false, "request_invalid")
		end
		if intent.kind == "snapshot" then
			return response(userId, true, nil)
		end
		if intent.kind == "chat" then
			local allowed, bucket = Chat.consume(chatBuckets[userId], { capacity = 2, refillPerSec = 1 }, ports.clock())
			chatBuckets[userId] = bucket
			if not allowed then
				return response(userId, false, "chat_limited")
			end
			for listenerId in active do
				local member: Chat.Member =
					{ id = listenerId, realm = "harbor", party = false, guild = false, warband = false }
				local speaker: Chat.Member =
					{ id = userId, realm = "harbor", party = false, guild = false, warband = false }
				if
					current(listenerId) ~= nil
					and Chat.allows(
						{ audience = "say", sameRealm = true, selfDelivery = true },
						speaker,
						member,
						true,
						nil
					)
				then
					local filtered = ports.filter(userId, intent.text, listenerId)
					if filtered ~= nil and #filtered > 0 and #filtered <= 120 then
						ports.deliver(
							listenerId,
							{ ok = true, line = { senderId = userId, text = filtered, at = ports.clock() } }
						)
					end
				end
			end
			return response(userId, true, nil)
		end
		if intent.kind == "trade" then
			if current(intent.targetId) == nil then
				return response(userId, false, "partner_unavailable")
			end
			if exchange ~= nil and exchange.phase ~= "settled" then
				return response(userId, false, "trade_busy")
			end
			exchange = Content.exchange.empty(ports.newId(), userId, intent.targetId)
			if exchange == nil then
				return response(userId, false, "trade_invalid")
			end
			return response(userId, true, nil)
		end
		if intent.kind == "offer" or intent.kind == "lock" or intent.kind == "confirm" then
			if exchange == nil then
				return response(userId, false, "trade_missing")
			end
			local nextTrade, reason = Content.exchange.step(exchange, userId, intent)
			if nextTrade == nil then
				return response(userId, false, reason)
			end
			if nextTrade.phase == "confirmed" then
				local ok, refusal = change(userId, function(candidate)
					return settle(candidate, nextTrade)
				end)
				if not ok then
					return response(userId, false, refusal)
				end
				exchange = assert(Content.exchange.settled(nextTrade))
				for _, participant in exchange.players do
					ports.deliver(participant, response(participant, true, nil))
				end
			else
				exchange = nextTrade
			end
			return response(userId, true, nil)
		end
		local ok, reason = change(userId, function(_candidate, profile)
			local progress = profile.journal.quests[Content.quest.id]
			if intent.kind == "accept" then
				if progress.status ~= "offered" then
					return false, "already_accepted"
				end
				progress.status = "active"
			elseif intent.kind == "equip" then
				local plan = Content.equipment.planEquip(
					profile.inventory,
					profile.equipment,
					intent.itemId,
					Content.levels.levelForXp(profile.xp),
					"warden",
					Content.item,
					nil,
					nil
				)
				if not plan.ok then
					return false, plan.reason
				end
				profile.inventory, profile.equipment = plan.bag, plan.slots
			elseif intent.kind == "loot" then
				local drop = profile.loot[intent.defeatId]
				if drop == nil then
					return false, "loot_missing"
				end
				if (profile.inventory[drop.itemId] or 0) + drop.count > 99 then
					return false, "inventory_full"
				end
				local nextBag = Content.stacks.addToBag(profile.inventory, drop.itemId, drop.count)
				if
					(nextBag[drop.itemId] or 0) > 99
					or not Content.stacks.fits(profile.inventory, nextBag, Content.stacks.capacity(nil))
				then
					return false, "inventory_full"
				end
				profile.inventory = nextBag
				profile.loot[intent.defeatId] = nil
				credit(profile, { kind = "item_collected", targets = { itemId = drop.itemId } })
			elseif intent.kind == "claim" then
				if progress.status ~= "active" or progress.step ~= 2 then
					return false, "quest_incomplete"
				end
				progress.status = "completed"
				profile.journal.semanticEventIds["reward:Harbor Supplies"] = true
				profile.coin += 25
				xp(profile, 50)
			else
				return false, "request_invalid"
			end
			return true, nil
		end)
		return response(userId, ok, reason)
	end
	local function hit(userId: number, damage: number): (boolean, string?)
		if current(userId) == nil or enemy.health <= 0 or Value.whole(damage, 1, 30) == nil then
			return false, "hit_invalid"
		end
		local candidates: { [string]: Threat.Candidate } = {}
		for id in active do
			candidates[tostring(id)] = { alive = current(id) ~= nil, eligible = true, insideLeash = true }
		end
		local pruned = Threat.prune(enemy.threat, candidates)
		local nextThreat = threatRules.add(pruned, tostring(userId), damage, true)
		local health = math.max(0, enemy.health - damage)
		if health == 0 then
			local winner = assert(tonumber(nextThreat.targetActorId))
			local ok, reason = change(winner, function(_candidate, profile)
				if profile.defeats[enemy.defeatId] then
					return false, "defeat_recorded"
				end
				profile.defeats[enemy.defeatId] = true
				local drop = assert(Content.loot.dropFor(Content.lootTables, "Warden", profile.characterId, 1))
				profile.loot[enemy.defeatId] = { itemId = drop.itemId, count = drop.count }
				xp(profile, 100)
				credit(profile, { kind = "enemy_defeated", targets = { enemyId = "Warden" } })
				return true, nil
			end)
			if not ok then
				return false, reason
			end
		end
		enemy.health, enemy.threat = health, nextThreat
		return true, nil
	end
	return table.freeze({
		create = create,
		join = join,
		close = close,
		request = request,
		hit = hit,
		view = view,
		profile = function(context: Admission.Context?): State.Profile?
			if context == nil then
				return nil
			end
			local entry = active[context.userId]
			local profile = current(context.userId)
			return if entry ~= nil
					and entry.context.acquisitionId == context.acquisitionId
					and profile ~= nil
				then State.copyProfile(profile)
				else nil
		end,
		context = function(userId: number): Admission.Context?
			local entry = active[userId]
			return if current(userId) ~= nil and entry ~= nil then entry.context else nil
		end,
		owns = function(userId: number, characterId: string): (boolean, unknown)
			local profile = world.players[tostring(userId)]
			return profile ~= nil and profile.characterId == characterId, if profile ~= nil then profile.roster else nil
		end,
		enemy = function(): (number, string)
			return enemy.health, enemy.threat.targetActorId
		end,
		drain = function(): boolean
			if busy then
				return false
			end
			local ok = true
			for _, outcome in sessions.drain() do
				ok = outcome.ok and ok
			end
			if ok then
				stopped = true
				sessions.dispose()
			end
			return ok
		end,
	})
end

return table.freeze({ new = new })
