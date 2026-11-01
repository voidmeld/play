--!strict

local Craft = require("../core/professions/crafting")
local Fish = require("../core/professions/fishing")
local Harvest = require("../core/professions/harvest")
local Sessions = require("../core/professions/session")
local Skills = require("../core/professions/skills")
local Types = require("../core/professions/types")

type State = Skills.State
type Profession = Skills.Profession
type Recipe = Types.Recipe
type ActionSession = Sessions.Session
type Sample = Sessions.Sample
type FishingLine = Fish.Line
type Stock = { slot: number, remaining: number }
type FishingEntry = { line: FishingLine, notified: boolean, origin: ActionSession, trackReceipt: string }
type CraftOutcome = Craft.Outcome
export type Fields = {
	inventory: { [string]: number },
	gold: number,
	faction: string,
	bagItem: string?,
	professions: State,
}
export type CommitResult = {
	ok: boolean,
	outcome: "committed" | "replayed" | "rejected" | "not_durable",
	reason: string?,
}
export type ProfilePort<C, F> = {
	read: (C) -> F?,
	updateProfile: (C, (F) -> F) -> (),
	removeGold: (C, number) -> boolean,
	addGold: (C, number) -> (),
	requestSave: ((C) -> ())?,
	saveProfile: ((C) -> boolean)?,
}
export type SkinTarget = { key: string, mobId: string, x: number, z: number }
export type World<P> = {
	node: (string) -> { kindId: string, x: number, z: number }?,
	sample: (P) -> Sample?,
	stations: (P) -> { [string]: boolean },
	trainerGroup: (P) -> string?,
	nearWater: (P) -> boolean,
	corpse: (P) -> SkinTarget?,
}
export type WorkKind = "gather" | "skin" | "craft"
export type GatherPayload = { nodeId: string, nodeKind: Types.NodeKind }
export type SkinPayload = { corpseKey: string, skinRow: Types.SkinRow }
export type CraftPayload = { recipeId: string }
export type WorkPayload = GatherPayload | SkinPayload | CraftPayload
export type WorkMetadata = { session: ActionSession, trackReceipt: string }
export type GatherEntry = WorkMetadata & { kind: "gather", payload: GatherPayload }
export type SkinEntry = WorkMetadata & { kind: "skin", payload: SkinPayload }
export type CraftEntry = WorkMetadata & { kind: "craft", payload: CraftPayload }
export type WorkEntry = GatherEntry | SkinEntry | CraftEntry
export type RecipeView = {
	id: string,
	name: string,
	profession: string,
	requiredSkill: number,
	color: string?,
	canCraft: boolean,
	reason: string?,
	source: Types.Source,
	station: string?,
	outputItemId: string,
	outputQuantity: number,
	reagents: { Types.Reagent },
}
export type RecipeItemView = { itemId: string, name: string, canLearn: boolean, reason: string? }
export type ProfessionView = {
	id: string,
	name: string,
	kind: Skills.Kind,
	skill: number,
	cap: number,
	recipes: { RecipeView },
	recipeItems: { RecipeItemView },
}
export type ProfessionLesson = {
	id: string,
	name: string,
	known: boolean,
	canLearn: boolean,
	reason: string?,
	cost: number,
}
export type RecipeLesson = {
	id: string,
	name: string,
	profession: string,
	status: string,
	cost: number,
	requiredSkill: number,
	preview: string,
}
export type SupplyView = { itemId: string, price: number, stock: number?, canBuy: boolean, reason: string? }
export type TrainerBook = {
	group: string,
	professions: { ProfessionLesson },
	recipes: { RecipeLesson },
	supplies: { SupplyView },
}
export type Book<X> = {
	professions: { ProfessionView },
	primaryFree: number,
	trainer: TrainerBook?,
	stations: { [string]: boolean },
	chapterProgress: X?,
	repair: { price: number, requestId: string, pending: boolean, canRepair: boolean }?,
}

export type ResultExtras = {
	yields: { Harvest.Yield }?,
	produced: { itemId: string, quantity: number }?,
	quality: string?,
	skillUp: boolean?,
	skill: number?,
	profession: string?,
	color: string?,
	chapterProgressAwarded: number?,
	nodeId: string?,
	recipeId: string?,
	itemId: string?,
	price: number?,
}
export type ResultMessage = ResultExtras & { kind: "result", action: string, ok: boolean, reason: string? }
export type Message<X> =
	ResultMessage
	| { kind: "book", book: Book<X>, open: boolean? }
	| { kind: "cast", action: WorkKind | "fish", key: string, duration: number, endsAt: number }
	| { kind: "bite" }
export type Handle<P> = {
	handle: (P, unknown, unknown, unknown) -> (),
	interrupt: (P, string) -> (),
	step: () -> (),
	forget: (P) -> (),
	harvestedSlots: () -> { [string]: number },
}

export type CorePort = {
	read SKILL_CAP: number,
	read catalogue: { Profession },
	read normalize: (unknown) -> State,
	read profession: (unknown) -> Profession?,
	read skillOf: (State, string) -> number,
	read colorFor: (number, Types.Thresholds) -> string?,
	read primarySlotsFree: (State) -> number,
	read canLearn: (State, unknown) -> (boolean, string?),
	read learn: (State, unknown) -> (State?, string?),
	read unlearn: (State, unknown) -> (State?, string?),
	read learnRecipe: (State, unknown, "trainer" | "item") -> (State?, string?),
	read learnFromItem: (State, unknown) -> (State?, string?, Recipe?),
	read trainerRoster: (State, string) -> { { recipe: Recipe, status: string, cost: number } },
}
export type Policy<F, X> = {
	read core: CorePort,
	read crafting: {
		read plan: (State, unknown, { [string]: number }, { [string]: boolean }) -> Craft.Plan,
		read craft: (
			State,
			unknown,
			{ [string]: number },
			{ [string]: boolean },
			number,
			number?,
			number?
		) -> Craft.Outcome,
	},
	read fishing: {
		read idle: () -> Fish.Line,
		read cast: (Fish.Line, State, number, number) -> (Fish.Line?, string?),
		read observe: (Fish.Line, number) -> Fish.Line,
		read hook: (Fish.Line, number) -> (boolean, string),
		read reel: (State, string, () -> number) -> Fish.Catch,
	},
	read gather: {
		read harvestNode: (State, Types.NodeKind, () -> number) -> Harvest.Outcome,
		read skinCorpse: (State, Types.SkinRow, () -> number) -> Harvest.Outcome,
		read canAttempt: (State, string, Types.NodeKind | Types.SkinRow) -> (boolean, string?),
	},
	read session: {
		read begin: (Sessions.Kind, string, number, Sample) -> (ActionSession?, string?),
		read check: (ActionSession, Sample) -> (string, string?),
	},
	read nodes: {
		read available: ({ [string]: number }, string, number, number) -> boolean,
		read slotAt: (number, number) -> number,
		read kind: (unknown) -> Types.NodeKind?,
		read skinFor: (unknown) -> Types.SkinRow?,
		read GATHER_RANGE_STUDS: number,
		read CORPSE_RANGE_STUDS: number,
		read CRAFT_SEC: number,
	},
	read recipes: {
		read all: { Recipe },
		read get: (unknown) -> Recipe?,
		read forProfession: (string) -> { Recipe },
		read forRecipeItem: (unknown) -> Recipe?,
	},
	read trainers: {
		read LEARN_COST: number,
		read group: (unknown) -> { professions: { string }, supplies: { { itemId: string, price: number } } }?,
		read groupOfProfession: (string) -> string?,
		read supplyPrice: (string, string) -> number?,
	},
	read inventory: {
		read capacity: (string?) -> number,
		read entries: ({ [string]: number }) -> number,
		read addToBag: ({ [string]: number }, string, number) -> { [string]: number },
		read removeFromBag: ({ [string]: number }, string, number) -> ({ [string]: number }, boolean),
	},
	read maxStack: number,
	read maxIdLength: number,
	read vendorWindow: number,
	read repairGroup: string,
	read fishingTool: string,
	read fishingId: string,
	read skinningId: string,
	read itemName: (string) -> string,
	read recipeAllowed: (F, Recipe) -> boolean,
	read recordProgress: (F, string, string, string?) -> number,
	read progress: (F) -> X?,
	read repairQuote: (F) -> number,
	read repair: (F, number) -> (F?, string?),
	read earnQuestInputs: (
		State,
		{ [string]: number },
		{ [string]: { [string]: number } }
	) -> (State, { [string]: number }, boolean),
}
export type Deps<P, C, F, X> = {
	read questCounts: ((P) -> { [string]: { [string]: number } }?)?,
	read profiles: ProfilePort<C, F>,
	read context: (P) -> C?,
	read zoneId: string,
	read clock: () -> number,
	read rng: () -> number,
	read world: World<P>,
	read send: (P, Message<X>) -> (),
	read eventId: () -> string,
	read commit: (C, string, (F) -> (F?, string?)) -> CommitResult,
}
local Service = {}
export type IntentPayload = { action: string, arg: string?, extra: string? }
function Service.decodeIntent(action: unknown, arg: unknown, extra: unknown): IntentPayload?
	if type(action) ~= "string" then
		return nil
	end
	if type(arg) ~= "string" and arg ~= nil then
		return nil
	end
	if type(extra) ~= "string" and extra ~= nil then
		return nil
	end
	return { action = action, arg = arg, extra = extra }
end

function Service.new<P, C, F, X>(deps: Deps<P, C, F & Fields, X>, policy: Policy<F & Fields, X>): Handle<P>
	type Profile = F & Fields
	type Context = C
	local Core, Crafting, Fishing, Gather = policy.core, policy.crafting, policy.fishing, policy.gather
	local Nodes, Recipes, Session, Trainers = policy.nodes, policy.recipes, policy.session, policy.trainers
	local InventoryRules = policy.inventory
	local MAX_ITEM_COUNT, MAX_ID_LENGTH, VENDOR_WINDOW_SEC = policy.maxStack, policy.maxIdLength, policy.vendorWindow
	local function validId(value: unknown): boolean
		return type(value) == "string" and #value > 0 and #value <= MAX_ID_LENGTH
	end

	local function addToInventory(
		inventory: { [string]: number },
		itemId: string,
		quantity: number,
		bagItem: string?
	): boolean
		local held = inventory[itemId]
		if held == nil then
			local entries = 0
			for _ in inventory do
				entries += 1
			end
			if entries >= InventoryRules.capacity(bagItem) then
				return false
			end
			held = 0
		end
		if held + quantity > MAX_ITEM_COUNT then
			return false
		end
		local after = InventoryRules.addToBag(inventory, itemId, quantity)
		if after[itemId] ~= held + quantity then
			return false
		end
		table.clear(inventory)
		for id, count in after do
			inventory[id] = count
		end
		return true
	end

	local function removeFromInventory(inventory: { [string]: number }, itemId: string, quantity: number): boolean
		local after, removed = InventoryRules.removeFromBag(inventory, itemId, quantity)
		if not removed then
			return false
		end
		table.clear(inventory)
		for id, count in after do
			inventory[id] = count
		end
		return true
	end

	local active: { [P]: WorkEntry } = {}
	local lines: { [P]: FishingEntry } = {}
	local harvested: { [string]: number } = {}
	local skinned: { [string]: boolean } = {}
	local vendorStock: { [string]: Stock } = {}
	local repairs: { [P]: { context: Context, id: string, price: number, pending: boolean } } = {}
	local pending: { [P]: Context } = {}
	local saving: { [P]: boolean } = {}

	local function trackReceipt(): string
		return "profession:" .. deps.eventId()
	end

	local function recordProgress(updated: Profile, kind: string, receipt: string, color: string?): number
		return policy.recordProgress(updated, kind, receipt, color)
	end

	local function now(): number
		return deps.clock()
	end

	local function say(player: P, payload: Message<X>)
		deps.send(player, payload)
	end

	local function result(player: P, action: string, ok: boolean, reason: string?, extra: ResultExtras?)
		local payload: ResultMessage = { kind = "result", action = action, ok = ok, reason = reason }
		if extra ~= nil then
			payload.yields = extra.yields
			payload.produced = extra.produced
			payload.quality = extra.quality
			payload.skillUp = extra.skillUp
			payload.skill = extra.skill
			payload.profession = extra.profession
			payload.color = extra.color
			payload.chapterProgressAwarded = extra.chapterProgressAwarded
			payload.nodeId = extra.nodeId
			payload.recipeId = extra.recipeId
			payload.itemId = extra.itemId
			payload.price = extra.price
		end
		say(player, payload)
	end

	local function resolve(player: P): (Context?, Profile?)
		local context = deps.context(player)
		if context == nil then
			return nil, nil
		end
		local profile = deps.profiles.read(context)
		if profile == nil then
			return nil, nil
		end
		return context, profile
	end

	local function stateOf(profile: Profile): State
		return Core.normalize(profile.professions)
	end

	local function mutate(player: P, context: Context, change: (Profile) -> boolean): boolean
		local applied = false
		local ok = pcall(function()
			deps.profiles.updateProfile(context, function(current): Profile
				if deps.context(player) ~= context then
					return current
				end
				local updated = table.clone(current)
				updated.inventory = table.clone(current.inventory or {})
				if not change(updated) then
					return current
				end
				applied = true
				return updated
			end)
		end)
		if applied and type(deps.profiles.requestSave) == "function" then
			pcall(deps.profiles.requestSave, context)
		end
		return ok and applied
	end

	local function commit(
		player: P,
		context: Context,
		receipt: string,
		effect: (Profile) -> (Profile?, string?)
	): CommitResult
		local save = deps.profiles.saveProfile
		if save == nil then
			return { ok = false, outcome = "rejected", reason = "unavailable" }
		end
		saving[player] = true
		pending[player] = context
		local ok, outcome = pcall(deps.commit, context, receipt, function(source: Profile): (Profile?, string?)
			if deps.context(player) ~= context then
				return nil, "session_absent"
			end
			return effect(source)
		end)
		saving[player] = nil
		if not ok then
			return { ok = false, outcome = "not_durable", reason = "profile_write_failed" }
		end
		if outcome.outcome ~= "not_durable" then
			pending[player] = nil
		end
		return outcome
	end

	local function stations(player: P): { [string]: boolean }
		return deps.world.stations(player) or {}
	end

	local function earnQuestInputs(player: P): boolean
		if deps.questCounts == nil then
			return true
		end
		local counts = deps.questCounts(player)
		if counts == nil then
			return false
		end
		local context, profile = resolve(player)
		if context == nil or profile == nil then
			return false
		end
		local _, _, changed = policy.earnQuestInputs(stateOf(profile), profile.inventory, counts)
		if not changed then
			return true
		end
		return mutate(player, context, function(updated): boolean
			local state, inventory, earned = policy.earnQuestInputs(stateOf(updated), updated.inventory, counts)
			if not earned then
				return false
			end
			updated.professions, updated.inventory = state, inventory
			return true
		end)
	end

	local function nearestGroup(player: P): string?
		return deps.world.trainerGroup(player)
	end

	local function stockFor(itemId: string, at: number): Stock
		local slot = math.floor(at / VENDOR_WINDOW_SEC)
		local row = vendorStock[itemId]
		if row == nil or row.slot ~= slot then
			local recipe = Recipes.forRecipeItem(itemId)
			row = { slot = slot, remaining = if recipe ~= nil and recipe.vendor ~= nil then recipe.vendor.stock else 0 }
			vendorStock[itemId] = row
		end
		return row
	end

	local function recipeRow(
		profile: Profile,
		state: State,
		recipe: Recipe,
		held: { [string]: number },
		near: { [string]: boolean }
	): RecipeView
		local skill = Core.skillOf(state, recipe.profession)
		local plan = Crafting.plan(state, recipe.id, held, near)
		return {
			id = recipe.id,
			name = recipe.name,
			profession = recipe.profession,
			requiredSkill = recipe.requiredSkill,
			color = Core.colorFor(skill, recipe.thresholds),
			canCraft = plan.ok,
			reason = plan.reason,
			source = recipe.source,
			station = recipe.station,
			outputItemId = recipe.output.itemId,
			outputQuantity = recipe.output.quantity,
			reagents = recipe.reagents,
		}
	end

	local function lessonPreview(recipe: Recipe): string
		local inputs: { string } = {}
		for _, reagent in recipe.reagents do
			table.insert(inputs, ("%dx %s"):format(reagent.quantity, policy.itemName(reagent.itemId)))
		end
		local station = recipe.station
		local tool = if station ~= nil
			then string.upper(string.sub(station, 1, 1)) .. string.sub(station, 2)
			else "No station"
		local profession = Core.profession(recipe.profession)
		return ("%s %d | %s | %s -> %dx %s"):format(
			if profession ~= nil then profession.name else recipe.profession,
			recipe.requiredSkill,
			tool,
			table.concat(inputs, ", "),
			recipe.output.quantity,
			recipe.name
		)
	end

	local function book(player: P, profile: Profile): Book<X>
		local state = stateOf(profile)
		local held = profile.inventory or {}
		local near = stations(player)
		local professions: { ProfessionView } = {}
		for _, row in Core.catalogue do
			local skill = state.skills[row.id]
			if skill ~= nil then
				local recipes: { RecipeView } = {}
				local recipeItems: { RecipeItemView } = {}
				for _, recipe in Recipes.forProfession(row.id) do
					if not policy.recipeAllowed(profile, recipe) then
						continue
					end
					if state.recipes[recipe.id] == true then
						table.insert(recipes, recipeRow(profile, state, recipe, held, near))
					elseif recipe.recipeItemId ~= nil and (held[recipe.recipeItemId] or 0) > 0 then
						local learned, reason = Core.learnFromItem(state, recipe.recipeItemId)
						table.insert(recipeItems, {
							itemId = recipe.recipeItemId,
							name = recipe.name,
							canLearn = learned ~= nil,
							reason = reason,
						})
					end
				end
				table.insert(professions, {
					id = row.id,
					name = row.name,
					kind = row.kind,
					skill = skill,
					cap = Core.SKILL_CAP,
					recipes = recipes,
					recipeItems = recipeItems,
				})
			end
		end
		local group = nearestGroup(player)
		local trainer: TrainerBook? = nil
		if group ~= nil then
			local groupRow = Trainers.group(group)
			local teachable: { ProfessionLesson } = {}
			local roster: { RecipeLesson } = {}
			local supplies: { SupplyView } = {}
			local function offer(itemId: string, price: number, stock: number?)
				local capacity = addToInventory(table.clone(held), itemId, 1, profile.bagItem)
				local reason = if stock ~= nil and stock <= 0
					then "sold_out"
					elseif (profile.gold or 0) < price then "cannot_afford"
					elseif not capacity then "inventory_full"
					else nil
				table.insert(supplies, {
					itemId = itemId,
					price = price,
					stock = stock,
					canBuy = reason == nil,
					reason = reason,
				})
			end
			if groupRow ~= nil then
				for _, supply in groupRow.supplies do
					offer(supply.itemId, supply.price, nil)
				end
				for _, professionId in groupRow.professions do
					local profession = Core.profession(professionId)
					if profession ~= nil then
						local canLearn, reason = Core.canLearn(state, professionId)
						if canLearn and profile.gold < Trainers.LEARN_COST then
							canLearn, reason = false, "cannot_afford"
						end
						table.insert(teachable, {
							id = professionId,
							name = profession.name,
							known = state.skills[professionId] ~= nil,
							canLearn = canLearn,
							reason = reason,
							cost = Trainers.LEARN_COST,
						})
						if state.skills[professionId] ~= nil then
							for _, entry in Core.trainerRoster(state, professionId) do
								if not policy.recipeAllowed(profile, entry.recipe) then
									continue
								end
								table.insert(roster, {
									id = entry.recipe.id,
									name = entry.recipe.name,
									profession = professionId,
									status = (if entry.status == "learnable" and profile.gold < entry.cost
										then "cannot_afford"
										else entry.status),
									cost = entry.cost,
									requiredSkill = entry.recipe.requiredSkill,
									preview = lessonPreview(entry.recipe),
								})
							end
						end
					end
				end
			end
			for _, recipe in Recipes.all do
				if
					recipe.vendor ~= nil
					and recipe.recipeItemId ~= nil
					and Trainers.groupOfProfession(recipe.profession) == group
				then
					offer(recipe.recipeItemId, recipe.vendor.price, stockFor(recipe.recipeItemId, now()).remaining)
				end
			end
			trainer = { group = group, professions = teachable, recipes = roster, supplies = supplies }
		end
		local repair = nil
		local context = deps.context(player)
		if group == policy.repairGroup and context ~= nil then
			local price = policy.repairQuote(profile)
			local request = repairs[player]
			if request == nil or request.context ~= context or (request.price ~= price and not request.pending) then
				request = { context = context, id = trackReceipt(), price = price, pending = false }
				repairs[player] = request
			end
			repair = {
				price = request.price,
				requestId = request.id,
				pending = request.pending,
				canRepair = request.pending or (price > 0 and profile.gold >= price),
			}
		end
		return {
			professions = professions,
			primaryFree = Core.primarySlotsFree(state),
			trainer = trainer,
			stations = near,
			chapterProgress = policy.progress(profile),
			repair = repair,
		}
	end

	local function publish(player: P, profile: Profile)
		say(player, { kind = "book", book = book(player, profile) })
	end

	local function endSession(player: P)
		active[player] = nil
	end

	local function sampleOf(player: P): Sample?
		return deps.world.sample(player)
	end

	local function distanceTo(sample: Sample, x: number, z: number): number
		local dx = sample.x - x
		local dz = sample.z - z
		return math.sqrt(dx * dx + dz * dz)
	end

	local function cancelFishing(player: P)
		lines[player] = nil
	end

	local function begin(player: P, kind: WorkKind, key: string, duration: number, payload: WorkPayload): boolean
		local sample = sampleOf(player)
		if sample == nil then
			result(player, kind, false, "unavailable", nil)
			return false
		end
		local session, reason = Session.begin(kind, key, duration, sample)
		if session == nil then
			result(player, kind, false, reason, nil)
			return false
		end
		cancelFishing(player)
		local receipt = trackReceipt()
		if kind == "gather" then
			active[player] = {
				session = session,
				kind = "gather",
				payload = payload,
				trackReceipt = receipt,
			}
		elseif kind == "skin" then
			active[player] = { session = session, kind = "skin", payload = payload, trackReceipt = receipt }
		else
			active[player] = {
				session = session,
				kind = "craft",
				payload = payload,
				trackReceipt = receipt,
			}
		end
		say(player, { kind = "cast", action = kind, key = key, duration = duration, endsAt = session.endsAt })
		return true
	end

	local function finishGather(player: P, entry: GatherEntry)
		local context, loadedProfile = resolve(player)
		if context == nil then
			return
		end
		local profile = loadedProfile
		local nodeKind = entry.payload.nodeKind
		local nodeId = entry.payload.nodeId
		local at = now()
		if not Nodes.available(harvested, nodeId, at, nodeKind.respawnSec) then
			result(player, "gather", false, "already_harvested", nil)
			return
		end
		local outcome = Gather.harvestNode(stateOf(profile), nodeKind, deps.rng)
		if not outcome.ok then
			result(player, "gather", false, outcome.reason, nil)
			return
		end
		local awarded = 0
		local stored = mutate(player, context, function(updated): boolean
			for _, yield in outcome.yields do
				if not addToInventory(updated.inventory, yield.itemId, yield.quantity, updated.bagItem) then
					return false
				end
			end
			updated.professions = outcome.state
			awarded = recordProgress(updated, "gather", entry.trackReceipt, outcome.color)
			return true
		end)
		if not stored then
			result(player, "gather", false, "inventory_full", nil)
			return
		end
		harvested[nodeId] = Nodes.slotAt(at, nodeKind.respawnSec)
		result(player, "gather", true, nil, {
			yields = outcome.yields,
			skillUp = outcome.skillUp,
			skill = outcome.skill,
			profession = nodeKind.profession,
			color = outcome.color,
			chapterProgressAwarded = awarded,
			nodeId = nodeId,
		})
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	local function finishSkin(player: P, entry: SkinEntry)
		local context, loadedProfile = resolve(player)
		if context == nil then
			return
		end
		local profile = loadedProfile
		local key = entry.payload.corpseKey
		if skinned[key] == true then
			result(player, "skin", false, "already_skinned", nil)
			return
		end
		local outcome = Gather.skinCorpse(stateOf(profile), entry.payload.skinRow, deps.rng)
		if not outcome.ok then
			result(player, "skin", false, outcome.reason, nil)
			return
		end
		local awarded = 0
		local stored = mutate(player, context, function(updated): boolean
			for _, yield in outcome.yields do
				if not addToInventory(updated.inventory, yield.itemId, yield.quantity, updated.bagItem) then
					return false
				end
			end
			updated.professions = outcome.state
			awarded = recordProgress(updated, "gather", entry.trackReceipt, outcome.color)
			return true
		end)
		if not stored then
			result(player, "skin", false, "inventory_full", nil)
			return
		end
		skinned[key] = true
		result(player, "skin", true, nil, {
			yields = outcome.yields,
			skillUp = outcome.skillUp,
			skill = outcome.skill,
			profession = policy.skinningId,
			color = outcome.color,
			chapterProgressAwarded = awarded,
		})
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	local function finishCraft(player: P, entry: CraftEntry)
		local context, loadedProfile = resolve(player)
		if context == nil then
			return
		end
		local profile = loadedProfile
		local recipe = Recipes.get(entry.payload.recipeId)
		if recipe ~= nil and not policy.recipeAllowed(profile, recipe) then
			return result(player, "craft", false, "wrong_realm", nil)
		end
		local skillRoll, qualityRoll = deps.rng(), deps.rng()
		local outcome: CraftOutcome? = nil
		local awarded = 0
		local stored = commit(player, context, entry.trackReceipt, function(source: Profile): (Profile?, string?)
			local crafted = Crafting.craft(
				stateOf(source),
				entry.payload.recipeId,
				source.inventory,
				stations(player),
				skillRoll,
				qualityRoll,
				math.max(InventoryRules.capacity(source.bagItem), InventoryRules.entries(source.inventory))
			)
			if not crafted.ok then
				return nil, crafted.reason
			end
			local updated = table.clone(source)
			updated.inventory = crafted.inventory
			updated.professions = crafted.state
			awarded = recordProgress(updated, "craft", entry.trackReceipt, crafted.color)
			outcome = crafted
			return updated, nil
		end)
		if not stored.ok then
			result(player, "craft", false, if stored.outcome == "not_durable" then "not_saved" else stored.reason, nil)
			return
		end
		if outcome == nil then
			return
		end
		result(player, "craft", true, nil, {
			produced = outcome.produced,
			quality = outcome.quality,
			skillUp = outcome.skillUp,
			skill = outcome.skill,
			color = outcome.color,
			chapterProgressAwarded = awarded,
			recipeId = entry.payload.recipeId,
		})
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	local function finishFishingMiss(player: P)
		cancelFishing(player)
		result(player, "fish", false, "got_away", nil)
	end

	local handlers: { [string]: (P, unknown, unknown) -> () } = {}
	handlers.repair = function(player, rawId, _extra)
		local context, profile = resolve(player)
		local request = repairs[player]
		local save = deps.profiles.saveProfile
		if context == nil or profile == nil or save == nil then
			return result(player, "repair", false, "unavailable", nil)
		end
		if nearestGroup(player) ~= policy.repairGroup then
			return result(player, "repair", false, "seek_trainer", nil)
		end
		local sample = sampleOf(player)
		if sample == nil or not sample.alive or sample.inCombat then
			return result(
				player,
				"repair",
				false,
				if sample ~= nil and sample.inCombat then "in_combat" else "dead",
				nil
			)
		end
		if request == nil or request.context ~= context or request.id ~= rawId then
			return result(player, "repair", false, "quote_changed", nil)
		end
		local outcome = deps.commit(context, "repair:" .. request.id, function(source: Profile): (Profile?, string?)
			if deps.context(player) ~= context or nearestGroup(player) ~= policy.repairGroup then
				return nil, "seek_trainer"
			end
			local repaired, reason = policy.repair(source, request.price)
			return if reason == nil then repaired else nil, reason
		end)
		request.pending = outcome.outcome == "not_durable"
		result(player, "repair", outcome.ok, if request.pending then "not_saved" else outcome.reason, nil)
		local _, current = resolve(player)
		if current ~= nil then
			publish(player, current)
		end
	end

	handlers.open = function(player, _arg, _extra)
		local _, profile = resolve(player)
		if profile ~= nil then
			say(player, { kind = "book", book = book(player, profile), open = true })
		end
	end

	handlers.cancel = function(player, _arg, _extra)
		if active[player] ~= nil then
			endSession(player)
			result(player, "cancel", true, "cancelled", nil)
		end
		if lines[player] ~= nil then
			cancelFishing(player)
			result(player, "fish", false, "reeled_in", nil)
		end
	end

	handlers.learn = function(player, rawId, _extra)
		if not validId(rawId) then
			return result(player, "learn", false, "invalid_request", nil)
		end
		local professionId = rawId
		local context, loadedProfile = resolve(player)
		if context == nil then
			return result(player, "learn", false, "session_absent", nil)
		end
		local profile = loadedProfile
		local group = nearestGroup(player)
		if group == nil or Trainers.groupOfProfession(professionId) ~= group then
			return result(player, "learn", false, "seek_trainer", nil)
		end
		local nextState, reason = Core.learn(stateOf(profile), professionId)
		if nextState == nil then
			return result(player, "learn", false, reason, nil)
		end
		local stored = commit(player, context, trackReceipt(), function(source: Profile): (Profile?, string?)
			if nearestGroup(player) ~= group then
				return nil, "seek_trainer"
			end
			local fresh, freshReason = Core.learn(stateOf(source), professionId)
			if fresh == nil then
				return nil, freshReason
			end
			if source.gold < Trainers.LEARN_COST then
				return nil, "cannot_afford"
			end
			local updated: Profile = table.clone(source)
			updated.gold = source.gold - Trainers.LEARN_COST
			updated.professions = fresh
			return updated, nil
		end)
		if not stored.ok then
			return result(
				player,
				"learn",
				false,
				if stored.outcome == "not_durable" then "not_saved" else stored.reason,
				nil
			)
		end
		result(player, "learn", true, nil, { profession = professionId })
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	handlers.unlearn = function(player, rawId, confirm)
		if not validId(rawId) then
			return result(player, "unlearn", false, "invalid_request", nil)
		end
		local professionId = rawId
		if confirm ~= "confirm" then
			return result(player, "unlearn", false, "confirm_required", nil)
		end
		local context, loadedProfile = resolve(player)
		if context == nil then
			return result(player, "unlearn", false, "session_absent", nil)
		end
		local profile = loadedProfile
		local nextState, reason = Core.unlearn(stateOf(profile), professionId)
		if nextState == nil then
			return result(player, "unlearn", false, reason, nil)
		end
		local stored = mutate(player, context, function(updated): boolean
			local fresh = Core.unlearn(Core.normalize(updated.professions), professionId)
			if fresh == nil then
				return false
			end
			updated.professions = fresh
			return true
		end)
		if not stored then
			return result(player, "unlearn", false, "not_saved", nil)
		end
		endSession(player)
		cancelFishing(player)
		result(player, "unlearn", true, nil, { profession = professionId })
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	handlers.train = function(player, rawId, _extra)
		if not validId(rawId) then
			return result(player, "train", false, "invalid_request", nil)
		end
		local recipeId = rawId
		local context, loadedProfile = resolve(player)
		if context == nil then
			return result(player, "train", false, "session_absent", nil)
		end
		local profile = loadedProfile
		local recipe = Recipes.get(recipeId)
		if recipe == nil then
			return result(player, "train", false, "unknown_recipe", nil)
		end
		if not policy.recipeAllowed(profile, recipe) then
			return result(player, "train", false, "wrong_realm", nil)
		end
		local group = nearestGroup(player)
		if group == nil or Trainers.groupOfProfession(recipe.profession) ~= group then
			return result(player, "train", false, "seek_trainer", nil)
		end
		local nextState, reason = Core.learnRecipe(stateOf(profile), recipeId, "trainer")
		if nextState == nil then
			return result(player, "train", false, reason, nil)
		end
		local cost = recipe.trainerCost or 0
		local stored = commit(player, context, trackReceipt(), function(source: Profile): (Profile?, string?)
			if nearestGroup(player) ~= group then
				return nil, "seek_trainer"
			end
			local fresh, freshReason = Core.learnRecipe(stateOf(source), recipeId, "trainer")
			if fresh == nil then
				return nil, freshReason
			end
			if source.gold < cost then
				return nil, "cannot_afford"
			end
			local updated: Profile = table.clone(source)
			updated.gold = source.gold - cost
			updated.professions = fresh
			return updated, nil
		end)
		if not stored.ok then
			return result(
				player,
				"train",
				false,
				if stored.outcome == "not_durable" then "not_saved" else stored.reason,
				nil
			)
		end
		result(player, "train", true, nil, { recipeId = recipeId })
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	handlers.recipe_item = function(player, rawId, _extra)
		if not validId(rawId) then
			return result(player, "recipe_item", false, "invalid_request", nil)
		end
		local itemId = rawId
		local context, loadedProfile = resolve(player)
		if context == nil then
			return result(player, "recipe_item", false, "session_absent", nil)
		end
		local profile = loadedProfile
		if (profile.inventory or {})[itemId] == nil then
			return result(player, "recipe_item", false, "not_owned", nil)
		end
		local nextState, reason, recipe = Core.learnFromItem(stateOf(profile), itemId)
		if nextState == nil then
			return result(player, "recipe_item", false, reason, nil)
		end
		local stored = mutate(player, context, function(updated): boolean
			local fresh = Core.learnFromItem(Core.normalize(updated.professions), itemId)
			if fresh == nil or not removeFromInventory(updated.inventory, itemId, 1) then
				return false
			end
			updated.professions = fresh
			return true
		end)
		if not stored then
			return result(player, "recipe_item", false, "not_saved", nil)
		end
		result(player, "recipe_item", true, nil, { recipeId = (recipe).id })
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	handlers.buy = function(player, rawId, _extra)
		if not validId(rawId) then
			return result(player, "buy", false, "invalid_request", nil)
		end
		local itemId = rawId
		local context = resolve(player)
		if context == nil then
			return result(player, "buy", false, "session_absent", nil)
		end
		local group = nearestGroup(player)
		if group == nil then
			return result(player, "buy", false, "seek_trainer", nil)
		end
		local price = Trainers.supplyPrice(group, itemId)
		local stock: Stock? = nil
		if price == nil then
			local recipe = Recipes.forRecipeItem(itemId)
			if recipe ~= nil and recipe.vendor ~= nil and Trainers.groupOfProfession(recipe.profession) == group then
				price = recipe.vendor.price
				stock = stockFor(itemId, now())
				if (stock).remaining <= 0 then
					return result(player, "buy", false, "sold_out", nil)
				end
			end
		end
		if price == nil then
			return result(player, "buy", false, "not_sold_here", nil)
		end
		if not deps.profiles.removeGold(context, price) then
			return result(player, "buy", false, "cannot_afford", nil)
		end
		local stored = mutate(player, context, function(updated): boolean
			return addToInventory(updated.inventory, itemId, 1, updated.bagItem)
		end)
		if not stored then
			deps.profiles.addGold(context, price)
			return result(player, "buy", false, "inventory_full", nil)
		end
		if stock ~= nil then
			stock.remaining -= 1
		end
		result(player, "buy", true, nil, { itemId = itemId, price = price })
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	handlers.gather = function(player, rawId, _extra)
		if not validId(rawId) then
			return result(player, "gather", false, "invalid_request", nil)
		end
		local nodeId = rawId
		local context, loadedProfile = resolve(player)
		if context == nil then
			return result(player, "gather", false, "session_absent", nil)
		end
		local profile = loadedProfile
		local node = deps.world.node(nodeId)
		local nodeKind = if node ~= nil then Nodes.kind(node.kindId) else nil
		if node == nil or nodeKind == nil then
			return result(player, "gather", false, "unknown_node", nil)
		end
		local sample = sampleOf(player)
		if sample == nil or distanceTo(sample, node.x, node.z) > Nodes.GATHER_RANGE_STUDS then
			return result(player, "gather", false, "too_far", nil)
		end
		if not Nodes.available(harvested, nodeId, now(), nodeKind.respawnSec) then
			return result(player, "gather", false, "already_harvested", nil)
		end
		local ok, reason = Gather.canAttempt(stateOf(profile), nodeKind.profession, nodeKind)
		if not ok then
			return result(player, "gather", false, reason, nil)
		end
		begin(player, "gather", nodeId, nodeKind.gatherSec, { nodeId = nodeId, nodeKind = nodeKind })
	end

	handlers.skin = function(player, _arg, _extra)
		local _, profile = resolve(player)
		if profile == nil then
			return result(player, "skin", false, "session_absent", nil)
		end
		local corpse = deps.world.corpse(player)
		if corpse == nil then
			return result(player, "skin", false, "no_corpse", nil)
		end
		local skinRow = Nodes.skinFor(corpse.mobId)
		if skinRow == nil then
			return result(player, "skin", false, "not_skinnable", nil)
		end
		if skinned[corpse.key] == true then
			return result(player, "skin", false, "already_skinned", nil)
		end
		local sample = sampleOf(player)
		if sample == nil or distanceTo(sample, corpse.x, corpse.z) > Nodes.CORPSE_RANGE_STUDS then
			return result(player, "skin", false, "too_far", nil)
		end
		local ok, reason = Gather.canAttempt(stateOf(profile), policy.skinningId, skinRow)
		if not ok then
			return result(player, "skin", false, reason, nil)
		end
		begin(player, "skin", corpse.key, skinRow.skinSec, { corpseKey = corpse.key, skinRow = skinRow })
	end

	handlers.craft = function(player, rawId, _extra)
		if not validId(rawId) then
			return result(player, "craft", false, "invalid_request", nil)
		end
		local recipeId = rawId
		local _, profile = resolve(player)
		if profile == nil then
			return result(player, "craft", false, "session_absent", nil)
		end
		local plan = Crafting.plan(stateOf(profile), recipeId, profile.inventory or {}, stations(player))
		if plan.recipe ~= nil and not policy.recipeAllowed(profile, plan.recipe) then
			return result(player, "craft", false, "wrong_realm", nil)
		end
		if not plan.ok then
			return result(player, "craft", false, plan.reason, nil)
		end
		begin(player, "craft", recipeId, Nodes.CRAFT_SEC, { recipeId = recipeId })
	end

	handlers.cast = function(player, _arg, _extra)
		local _, profile = resolve(player)
		if profile == nil then
			return result(player, "fish", false, "session_absent", nil)
		end
		if (profile.inventory or {})[policy.fishingTool] == nil then
			return result(player, "fish", false, "needs_rod", nil)
		end
		if not deps.world.nearWater(player) then
			return result(player, "fish", false, "no_water", nil)
		end
		local sample = sampleOf(player)
		if sample == nil or not sample.alive or sample.inCombat then
			return result(player, "fish", false, "cannot_fish_now", nil)
		end
		local existing = lines[player]
		local line = if existing ~= nil then existing.line else Fishing.idle()
		local cast, reason = Fishing.cast(line, stateOf(profile), now(), deps.rng())
		if cast == nil then
			return result(player, "fish", false, reason, nil)
		end
		endSession(player)
		local fishSession, fishReason = Session.begin("fish", "line", cast.missAt - cast.castAt, sample)
		if fishSession == nil then
			return result(player, "fish", false, fishReason, nil)
		end
		lines[player] = { line = cast, notified = false, origin = fishSession, trackReceipt = trackReceipt() }
		say(
			player,
			{ kind = "cast", action = "fish", key = "line", duration = cast.missAt - cast.castAt, endsAt = cast.missAt }
		)
	end

	handlers.hook = function(player, _arg, _extra)
		local entry = lines[player]
		if entry == nil then
			return
		end
		local sample = sampleOf(player)
		if sample == nil then
			cancelFishing(player)
			return result(player, "fish", false, "session_absent", nil)
		end
		local verdict, interruption = Session.check(entry.origin, sample)
		if verdict == "interrupt" then
			cancelFishing(player)
			return result(player, "fish", false, interruption, nil)
		end
		local at = now()
		local ok, reason = Fishing.hook(entry.line, at)
		if not ok then
			cancelFishing(player)
			return result(player, "fish", false, reason, nil)
		end
		local context, profile = resolve(player)
		if context == nil or profile == nil then
			cancelFishing(player)
			return
		end
		local outcome = Fishing.reel(stateOf(profile), deps.zoneId, deps.rng)
		cancelFishing(player)
		if not outcome.ok or outcome.itemId == nil then
			return result(player, "fish", false, outcome.reason, nil)
		end
		local itemId = outcome.itemId
		local awarded = 0
		local stored = mutate(player, context, function(updated): boolean
			if not addToInventory(updated.inventory, itemId, 1, updated.bagItem) then
				return false
			end
			updated.professions = outcome.state
			awarded = recordProgress(updated, "gather", entry.trackReceipt, outcome.color)
			return true
		end)
		if not stored then
			return result(player, "fish", false, "inventory_full", nil)
		end
		result(player, "fish", true, nil, {
			yields = { { itemId = itemId, quantity = 1 } },
			skillUp = outcome.skillUp,
			skill = outcome.skill,
			profession = policy.fishingId,
			color = outcome.color,
			chapterProgressAwarded = awarded,
		})
		local _, fresh = resolve(player)
		if fresh ~= nil then
			publish(player, fresh)
		end
	end

	local service = {}

	function service.handle(player: P, action: unknown, arg: unknown, extra: unknown)
		if type(action) ~= "string" then
			return
		end
		local handler = handlers[action]
		if handler == nil then
			return
		end
		if saving[player] then
			return result(player, action, false, "busy", nil)
		end
		local unsettled = pending[player]
		if unsettled ~= nil then
			local save = deps.profiles.saveProfile
			if deps.context(player) == unsettled then
				saving[player] = true
				local ok, saved = pcall(function(): boolean
					return save ~= nil and save(unsettled)
				end)
				saving[player] = nil
				if not ok or not saved then
					return result(player, action, false, "not_saved", nil)
				end
			end
			pending[player] = nil
		end
		if not earnQuestInputs(player) then
			return result(player, action, false, "unavailable", nil)
		end
		if active[player] ~= nil and action ~= "cancel" and action ~= "open" then
			return result(player, action, false, "busy", nil)
		end
		handler(player, arg, extra)
	end

	function service.interrupt(player: P, reason: string)
		if active[player] ~= nil then
			local kind = active[player].kind
			endSession(player)
			result(player, kind, false, reason, nil)
		end
		if lines[player] ~= nil then
			cancelFishing(player)
			result(player, "fish", false, reason, nil)
		end
	end

	function service.step()
		for player, entry in active do
			local sample = sampleOf(player)
			if sample == nil then
				endSession(player)
			else
				local verdict, reason = Session.check(entry.session, sample)
				if verdict == "interrupt" then
					endSession(player)
					result(player, entry.kind, false, reason, nil)
				elseif verdict == "complete" then
					endSession(player)
					if entry.kind == "gather" then
						finishGather(player, entry)
					elseif entry.kind == "skin" then
						finishSkin(player, entry)
					elseif entry.kind == "craft" then
						finishCraft(player, entry)
					end
				end
			end
		end
		for player, entry in lines do
			local sample = sampleOf(player)
			if sample == nil or not sample.alive or sample.inCombat then
				cancelFishing(player)
			else
				local origin = entry.origin
				local moved = origin ~= nil and select(1, Session.check(origin, sample)) == "interrupt"
				if moved then
					cancelFishing(player)
					result(player, "fish", false, "moved", nil)
				else
					local seen = Fishing.observe(entry.line, now())
					if seen.phase == "idle" then
						finishFishingMiss(player)
					elseif seen.phase == "bite" and not entry.notified then
						entry.notified = true
						say(player, { kind = "bite" })
					end
				end
			end
		end
	end

	function service.forget(player: P)
		active[player] = nil
		lines[player] = nil
		repairs[player] = nil
		pending[player] = nil
		saving[player] = nil
	end

	function service.harvestedSlots(): { [string]: number }
		return harvested
	end

	return service
end

return Service
