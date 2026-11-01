--!strict

export type Policy = {
	read validateName: (unknown) -> (boolean, string?, string?),
	read registryKey: (unknown) -> (string?, string?),
	read validRegistryKey: (unknown) -> boolean,
	read validDestination: (unknown) -> boolean,
	read profilePartitionKey: (unknown, unknown) -> string,
	read realms: { [string]: boolean },
	read peoples: { [string]: boolean },
	read accountLimit: number,
	read realmLimit: number,
	read minLevel: number,
	read maxLevel: number,
}

return table.freeze({})
