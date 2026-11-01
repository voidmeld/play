--!strict
local Consumables = require("../core/progression/consumables")
export type Actor = Consumables.Actor & { characterId: string? }
export type Snapshot = { actor: Actor?, mobs: { [string]: Consumables.Mob }?, now: number }
export type Status = { cue: string, hpRemaining: number, manaRemaining: number, hpGained: number?, manaGained: number? }
export type CommitResult = { ok: boolean, outcome: string, reason: string? }
export type Rules = {
	read item: (unknown) -> Consumables.Item?,
	read begin: (
		Consumables.State?,
		Consumables.Actor,
		{ [string]: Consumables.Mob }?,
		unknown,
		unknown,
		unknown
	) -> (Consumables.State?, string?),
}
export type Dependencies<P, C, B> = {
	core: Rules,
	present: (P) -> boolean,
	contextFor: (P) -> C?,
	characterFor: (P) -> B?,
	snapshotFor: (P) -> Snapshot?,
	characterIdFor: (C) -> string,
	alive: (P) -> boolean,
	stationary: (P) -> boolean,
	profilePresent: (C) -> boolean,
	recorded: (C, string) -> boolean,
	commit: (P, C, B, string, string) -> CommitResult,
	receipt: () -> string,
	begin: (P, string, number) -> boolean,
	cancel: ((P) -> ())?,
	unavailableCue: string,
	idleCue: string,
	movementToleranceSquared: number,
}
export type Handle<P> = {
	read use: (P, unknown, unknown) -> (boolean, string),
	read status: (P) -> Status,
	read enforce: (P) -> (),
	read forget: (P) -> (),
}
type Request<C, B> = {
	context: C,
	character: B,
	lastOrder: number,
	busy: boolean,
	pending: { itemId: string, serial: number, receipt: string }?,
}
export type UseRequest = { kind: "use", itemId: string, order: number } | { kind: "refused" }
local Service = {}
function Service.decodeUseRequest(item: (unknown) -> Consumables.Item?, itemId: unknown, order: unknown): UseRequest
	if
		type(itemId) ~= "string"
		or item(itemId) == nil
		or type(order) ~= "number"
		or order ~= order
		or order % 1 ~= 0
		or order < 1
		or order > 9007199254740991
	then
		return { kind = "refused" }
	end
	return { kind = "use", itemId = itemId, order = order }
end
function Service.create<P, C, B>(deps: Dependencies<P, C, B>): Handle<P>
	local Core = deps.core
	local requests: { [P]: Request<C, B> } = {}
	local function current(player: P): (C?, B?, Snapshot?, Actor?)
		if not deps.present(player) then
			return nil, nil, nil, nil
		end
		local context = deps.contextFor(player)
		local character = deps.characterFor(player)
		local state = deps.snapshotFor(player)
		local actor = if state ~= nil then state.actor else nil
		return context, character, state, actor
	end
	local function status(player: P): Status
		local context, _, state, actor = current(player)
		local profile = context ~= nil and deps.profilePresent(context)
		if actor == nil or state == nil or not profile then
			return { cue = deps.unavailableCue, hpRemaining = 0, manaRemaining = 0 }
		end
		local rest = actor.sustenance
		local now = state.now
		local function remaining(channel: Consumables.Channel?): number
			return if channel ~= nil then math.max(0, channel.endsAt - now) else 0
		end
		return {
			cue = if rest ~= nil then rest.cue else deps.idleCue,
			hpRemaining = remaining(if rest ~= nil then rest.hp else nil),
			manaRemaining = remaining(if rest ~= nil then rest.mana else nil),
			hpGained = if rest ~= nil then rest.hpGained or 0 else 0,
			manaGained = if rest ~= nil then rest.manaGained or 0 else 0,
		}
	end
	local function use(player: P, rawItemId: unknown, rawOrder: unknown): (boolean, string)
		local decoded = Service.decodeUseRequest(Core.item, rawItemId, rawOrder)
		if decoded.kind == "refused" then
			return false, "malformed_use"
		end
		local itemId = decoded.itemId
		local order = decoded.order
		local context, character, state, actor = current(player)
		if
			context == nil
			or character == nil
			or state == nil
			or actor == nil
			or actor.characterId ~= deps.characterIdFor(context)
		then
			return false, "character_unavailable"
		end
		if not deps.alive(player) or not deps.stationary(player) then
			return false, "stand_still_alive_to_rest"
		end
		local request = requests[player]
		if request ~= nil and request.busy then
			return false, "use_pending"
		end
		if request == nil or request.context ~= context or request.character ~= character then
			if request ~= nil and request.pending ~= nil then
				local profile = deps.profilePresent(context)
				if
					request.context ~= context
					and deps.characterIdFor(request.context) == deps.characterIdFor(context)
					and not deps.profilePresent(request.context)
					and profile
				then
					local consumed = deps.recorded(context, request.pending.receipt)
					requests[player] = {
						context = context,
						character = character,
						lastOrder = math.max(order, request.lastOrder),
						busy = false,
					}
					return false, if consumed then "session_changed_consumed" else "session_changed"
				end
				return false, "pending_previous_character"
			end
			local nextRequest: Request<C, B> = {
				context = context,
				character = character,
				lastOrder = if request ~= nil then request.lastOrder else 0,
				busy = false,
			}
			request = nextRequest
			requests[player] = request
		end
		if order <= request.lastOrder then
			return false, "stale_use"
		end
		request.lastOrder = order
		if request.pending ~= nil and request.pending.itemId ~= itemId then
			return false, "retry_previous_item"
		end
		local serial = if request.pending ~= nil
			then request.pending.serial
			else (if actor.sustenance then actor.sustenance.serial else 0) + 1
		local planned, reason = Core.begin(actor.sustenance, actor, state.mobs, itemId, serial, state.now)
		if planned == nil then
			return false, reason or "not_food_or_drink"
		end
		request.pending = request.pending or { itemId = itemId, serial = serial, receipt = deps.receipt() }
		local startHp, startX, startZ = actor.hp, actor.pos.x, actor.pos.z
		local generation = actor.sustenanceGeneration or 0
		request.busy = true
		local succeeded, result = pcall(function(): CommitResult
			return deps.commit(player, context, character, assert(request.pending).receipt, itemId)
		end)
		if not succeeded or result.ok ~= true then
			request.busy = false
			if succeeded and result.outcome == "rejected" then
				request.pending = nil
			end
			return false, if succeeded then result.reason or "persistence_unavailable" else "persistence_unavailable"
		end
		local nextContext, nextCharacter, nextState, nextActor = current(player)
		request.pending = nil
		if nextContext ~= context or nextCharacter ~= character or nextState == nil or nextActor == nil then
			request.busy = false
			return false, "session_changed_consumed"
		end
		local dx, dz = nextActor.pos.x - startX, nextActor.pos.z - startZ
		if
			not deps.alive(player)
			or not deps.stationary(player)
			or nextActor.hp < startHp
			or (nextActor.sustenanceGeneration or 0) ~= generation
			or dx * dx + dz * dz > deps.movementToleranceSquared
		then
			request.busy = false
			return false, "rest_interrupted_consumed"
		end
		local beganOk, began = pcall(deps.begin, player, itemId, serial)
		request.busy = false
		return beganOk and began == true, if beganOk and began then "rest_started" else "rest_interrupted_consumed"
	end
	local function enforce(player: P)
		local context, character, _, actor = current(player)
		if
			context == nil
			or character == nil
			or actor == nil
			or (
				(requests[player] == nil or not requests[player].busy)
				and (actor.sustenance == nil or (actor.sustenance.hp == nil and actor.sustenance.mana == nil))
			)
		then
			return
		end
		if not deps.alive(player) or not deps.stationary(player) then
			if deps.cancel ~= nil then
				deps.cancel(player)
			end
		end
	end
	return table.freeze({
		use = use,
		status = status,
		enforce = enforce,
		forget = function(player)
			requests[player] = nil
		end,
	})
end

return table.freeze(Service)
