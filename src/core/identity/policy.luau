--!strict

export type Policy = {
	validateName: (unknown) -> (boolean, string?, string?),
	registryKey: (unknown) -> (string?, string?),
	validRegistryKey: (unknown) -> boolean,
	validDestination: (unknown) -> boolean,
	profilePartitionKey: (unknown, unknown) -> string,
	realms: { [string]: boolean },
	peoples: { [string]: boolean },
	accountLimit: number,
	realmLimit: number,
	minLevel: number,
	maxLevel: number,
}

return table.freeze({})
