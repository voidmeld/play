--!strict

local Vault = require("./bank/vault")

export type VaultInventory = Vault.Inventory
export type VaultRequest = Vault.Request
export type VaultState = Vault.State
export type VaultConfig<T> = Vault.Config<T>
export type VaultVault<T> = Vault.Vault<T>

export type API = {
	read vault: typeof(Vault),
}

local api: API = {
	vault = Vault,
}

return table.freeze(api)
