--!strict

export type Member = { accountId: string, characterId: string? }
export type Party = { partyId: string, realmId: string, disbandedAt: number?, members: { Member } }
export type Actor = { id: string, characterId: string?, realm: string?, partyId: string? }
export type Runtime<S> = { state: S, tick: number }
export type Result<S, A> = { parties: { [string]: Runtime<S> }, actors: { [string]: A } }
export type Config<S, A> = {
	project: (unknown) -> S?,
	party: (S) -> Party,
	lootCursor: (S) -> string?,
	withLootCursor: (S, string?) -> S,
	actor: (A) -> Actor,
	withParty: (A, string?) -> A,
	subject: (string) -> string,
}

local System = {}
function System.roster<S, A>(config: Config<S, A>)
	local function reduce(
		parties: { [string]: Runtime<S> },
		actors: { [string]: A },
		raw: unknown,
		tick: number
	): Result<S, A>?
		local projected = config.project(raw)
		if projected == nil then
			return nil
		end
		local view = config.party(projected)
		local prior = parties[view.partyId]
		local state = config.withLootCursor(projected, if prior ~= nil then config.lootCursor(prior.state) else nil)
		local nextParties = table.clone(parties)
		nextParties[view.partyId] = if view.disbandedAt ~= nil then nil else { state = state, tick = tick }
		local members: { [string]: string } = {}
		for _, member in view.members do
			members[member.accountId] = member.characterId
		end
		local nextActors = table.clone(actors)
		for key, source in actors do
			local actor = config.actor(source)
			local partyId = if view.disbandedAt == nil
					and actor.characterId ~= nil
					and string.lower(actor.realm or "") == view.realmId
					and members[config.subject(actor.id)] == actor.characterId
				then view.partyId
				elseif actor.partyId == view.partyId then nil
				else actor.partyId
			if partyId ~= actor.partyId then
				nextActors[key] = config.withParty(source, partyId)
			end
		end
		return { parties = nextParties, actors = nextActors }
	end
	return { reduce = reduce, subject = config.subject }
end
return System
