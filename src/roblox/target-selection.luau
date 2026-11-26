--!strict

export type Candidate<P> = { npcId: string, screenPos: P }
export type Cycle = {
	signature: string,
	ids: { string },
	index: number,
	at: number,
	visited: { [string]: boolean },
}
export type Pick = { id: string, cycle: Cycle }

local Selection = {}

function Selection.pickNext(candidates: { string }, current: string?): string?
	if #candidates == 0 then
		return nil
	end
	local index = if current ~= nil then table.find(candidates, current) or 0 else 0
	return candidates[index % #candidates + 1]
end

function Selection.nextInCycle(
	previous: Cycle?,
	selectedId: string?,
	now: number,
	idleResetSec: number,
	signature: string,
	rankedIds: () -> { string }
): Pick?
	local function pick(ids: { string }, index: number, visited: { [string]: boolean }): Pick
		local id = ids[index]
		visited[id] = true
		return { id = id, cycle = { signature = signature, ids = ids, index = index, at = now, visited = visited } }
	end

	local live = previous ~= nil
		and selectedId ~= nil
		and now - previous.at <= idleResetSec
		and previous.ids[previous.index] == selectedId
	if live and previous ~= nil and previous.signature == signature then
		return pick(previous.ids, previous.index % #previous.ids + 1, table.clone(previous.visited))
	end

	local ids = rankedIds()
	if #ids == 0 then
		return nil
	end
	if live and previous ~= nil then
		local seen = table.clone(previous.visited)
		seen[assert(selectedId)] = true
		for index, id in ids do
			if not seen[id] then
				return pick(ids, index, seen)
			end
		end
	end
	return pick(ids, if #ids > 1 and ids[1] == selectedId then 2 else 1, {})
end

function Selection.release(range: number, seconds: number)
	assert(range > 0 and seconds > 0, "target release needs a positive range and time")
	local outsideSince: number? = nil
	return table.freeze({
		observe = function(distance: number?, now: number): boolean
			outsideSince = if distance ~= nil and distance <= range then nil else outsideSince or now
			return outsideSince ~= nil and now - outsideSince >= seconds
		end,
		reset = function()
			outsideSince = nil
		end,
	})
end
export type Release = typeof(Selection.release(1, 1))

function Selection.create<P>(coordinates: (P) -> (number, number))
	local Projected = {}
	function Projected.pickNearestToTap(tap: P, candidates: { Candidate<P> }, radius: number): string?
		local x, y = coordinates(tap)
		local bestId: string? = nil
		local best = math.huge
		for _, candidate in candidates do
			local cx, cy = coordinates(candidate.screenPos)
			local distance = (cx - x) ^ 2 + (cy - y) ^ 2
			if
				distance <= radius * radius
				and (distance < best or (distance == best and bestId ~= nil and candidate.npcId < bestId))
			then
				bestId, best = candidate.npcId, distance
			end
		end
		return bestId
	end
	function Projected.tapSelection(resolved: string?, tap: P, candidates: { Candidate<P> }, radius: number): string?
		return if resolved ~= nil then resolved else Projected.pickNearestToTap(tap, candidates, radius)
	end
	return table.freeze(Projected)
end

return table.freeze(Selection)
