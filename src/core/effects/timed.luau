--!strict

export type Entry = {
	remainingSec: number,
	totalSec: number,
	stacks: number?,
	tickInSec: number?,
}

export type Application = {
	durationSec: number,
	stacks: number?,
	stackLimit: number?,
	tickInSec: number?,
}

export type Refresh = "reset" | "extend" | "keep"

local Timed = {}

function Timed.application(prior: Entry?, application: Application): Entry
	local stacks = application.stacks
	if application.stackLimit ~= nil then
		stacks = math.min(application.stackLimit, (if prior ~= nil then prior.stacks or 0 else 0) + 1)
	end
	return {
		remainingSec = application.durationSec,
		totalSec = application.durationSec,
		stacks = stacks,
		tickInSec = application.tickInSec,
	}
end

function Timed.advanceTimes(remainingSec: number, tickInSec: number?, dt: number): (number, number?)
	return math.max(0, remainingSec - dt), if tickInSec ~= nil then math.max(0, tickInSec - dt) else nil
end

function Timed.advance(effect: Entry, dt: number): Entry
	local updated = table.clone(effect)
	updated.remainingSec, updated.tickInSec = Timed.advanceTimes(effect.remainingSec, effect.tickInSec, dt)
	return updated
end

function Timed.expired(effect: Entry, epsilon: number): boolean
	return effect.remainingSec <= epsilon
end

function Timed.refresh(effect: Entry, duration: number, mode: Refresh): Entry
	local updated = table.clone(effect)
	if mode == "reset" then
		updated.remainingSec = duration
		updated.totalSec = duration
	elseif mode == "extend" then
		updated.remainingSec += duration
		updated.totalSec += duration
	end
	return updated
end

function Timed.dispelFirst<T>(effects: { T }, matches: (T) -> boolean, copy: (T) -> T): ({ T }, T?)
	local kept: { T } = {}
	local removed: T? = nil
	for _, effect in effects do
		if removed == nil and matches(effect) then
			removed = copy(effect)
		else
			table.insert(kept, copy(effect))
		end
	end
	return kept, removed
end

function Timed.remainingFraction(endsAt: number, totalSec: number, now: number): number
	if totalSec <= 0 then
		return 0
	end
	local remaining = endsAt - now
	if remaining <= 0 then
		return 0
	end
	return math.clamp(remaining / totalSec, 0, 1)
end

function Timed.remainingSec(endsAt: number, now: number): number
	return math.max(0, endsAt - now)
end

function Timed.count<A, B>(buffs: { [string]: A }, debuffs: { [string]: B }): number
	local count = 0
	for _ in buffs do
		count += 1
	end
	for _ in debuffs do
		count += 1
	end
	return count
end

return table.freeze(Timed)
