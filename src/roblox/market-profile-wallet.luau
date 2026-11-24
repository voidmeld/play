--!strict

local Wallets = require("../core/market/wallet")

export type Inventory = { [string]: number }
export type Wallet =
	{ read read: () -> Wallets.State?, read write: (unknown) -> boolean, read room: (string) -> number }
export type Dependencies<P, I> = {
	userId: number,
	materials: { string },
	readProfile: () -> P?,
	updateProfile: ((P) -> P) -> (),
	saveProfile: () -> boolean,
	maxItemCount: number,
	maxInventoryEntries: number,
	items: I?,
}
export type Core = {
	read ledgerOf: (unknown) -> Wallets.Ledger?,
	read compose: (unknown, unknown, unknown, unknown) -> Wallets.State?,
	read projectState: (unknown) -> Wallets.State?,
}
export type Config<P, I> = {
	read wallet: Core,
	read items: I,
	read goods: (P, { string }, I) -> Inventory,
	read coin: (P) -> number,
	read inventory: (P) -> Inventory,
	read ledger: (P) -> unknown,
	read withAccount: (P, number, Inventory, Wallets.Ledger) -> P,
	read capacity: (P) -> number,
	read entries: (Inventory) -> number,
	read fits: (Inventory, Inventory, number) -> boolean,
	read unboundCount: (P, string) -> number,
}
export type Host<P, I> = {
	read create: (Dependencies<P, I>) -> (Wallet?, string?),
	read applyDelta: (P, Wallets.State, Wallets.State, number, number) -> (P?, string?),
}
local function configure<P, I>(config: Config<P, I>): Host<P, I>
	config = table.freeze(table.clone(config))
	type Profile = P
	type State = Wallets.State
	local MarketWalletCore = config.wallet
	local MarketProfileWallet = {}

	function MarketProfileWallet.applyDelta(
		profile: Profile,
		base: State,
		nextState: State,
		maxItemCount: number,
		maxInventoryEntries: number
	): (Profile?, string?)
		local coinDelta = nextState.coin - base.coin
		local gold = config.coin(profile) + coinDelta
		if gold < 0 then
			return nil, "coin_negative"
		end
		local inventory = table.clone(config.inventory(profile))
		local touched: { [string]: boolean } = {}
		for materialId in nextState.goods do
			touched[materialId] = true
		end
		for materialId in base.goods do
			touched[materialId] = true
		end
		for materialId in touched do
			local delta = (nextState.goods[materialId] or 0) - (base.goods[materialId] or 0)
			if delta ~= 0 then
				local count = (inventory[materialId] or 0) + delta
				if count < 0 or (delta < 0 and config.unboundCount(profile, materialId) < -delta) then
					return nil, "goods_negative"
				end
				if count > maxItemCount then
					return nil, "inventory_full"
				end
				if count > 0 then
					inventory[materialId] = count
				else
					inventory[materialId] = nil
				end
			end
		end
		if
			not config.fits(
				config.inventory(profile),
				inventory,
				math.min(maxInventoryEntries, config.capacity(profile))
			)
		then
			return nil, "inventory_full"
		end
		local ledger = MarketWalletCore.ledgerOf(nextState)
		if ledger == nil then
			return nil, "wallet_invalid"
		end
		return config.withAccount(profile, gold, inventory, ledger), nil
	end

	function MarketProfileWallet.create(raw: Dependencies<P, I>): (Wallet?, string?)
		if
			type(raw) ~= "table"
			or type((raw).userId) ~= "number"
			or type((raw).materials) ~= "table"
			or type((raw).readProfile) ~= "function"
			or type((raw).updateProfile) ~= "function"
			or type((raw).saveProfile) ~= "function"
			or type((raw).maxItemCount) ~= "number"
			or type((raw).maxInventoryEntries) ~= "number"
		then
			return nil, "dependencies_invalid"
		end
		local deps = raw
		local items: I = if deps.items ~= nil then deps.items else config.items
		local base: State? = nil

		local function read(): State?
			local profile = deps.readProfile()
			if profile == nil then
				base = nil
				return nil
			end
			base = MarketWalletCore.compose(
				deps.userId,
				config.coin(profile),
				config.goods(profile, deps.materials, items),
				config.ledger(profile)
			)
			return base
		end

		local function write(nextState: unknown): boolean
			if base == nil then
				return false
			end
			local successor = MarketWalletCore.projectState(nextState)
			if successor == nil then
				return false
			end
			local from = base
			base = nil
			local applied = false
			deps.updateProfile(function(profile): Profile
				local updated = MarketProfileWallet.applyDelta(
					profile,
					from,
					successor,
					deps.maxItemCount,
					deps.maxInventoryEntries
				)
				applied = updated ~= nil
				if updated == nil then
					return profile
				end
				return updated
			end)
			if not applied then
				return false
			end
			return deps.saveProfile()
		end

		local function room(materialId: string): number
			local profile = deps.readProfile()
			if profile == nil or type(config.inventory(profile)) ~= "table" then
				return 0
			end
			local current = config.inventory(profile)[materialId] or 0
			if
				current == 0
				and config.entries(config.inventory(profile))
					>= math.min(deps.maxInventoryEntries, config.capacity(profile))
			then
				return 0
			end
			return math.max(0, deps.maxItemCount - current)
		end

		return table.freeze({ read = read, write = write, room = room }), nil
	end

	return table.freeze(MarketProfileWallet)
end

return table.freeze({ configure = configure })
