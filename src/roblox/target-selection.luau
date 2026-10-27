--!strict

export type Candidate<P> = { npcId: string, screenPos: P }

local Selection = {}

function Selection.pickNext(candidates: { string }, current: string?): string?
	if #candidates == 0 then
		return nil
	end
	local index = if current ~= nil then table.find(candidates, current) or 0 else 0
	return candidates[index % #candidates + 1]
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
