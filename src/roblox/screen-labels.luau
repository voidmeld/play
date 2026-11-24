--!strict

export type ScreenRect = {
	left: number,
	top: number,
	right: number,
	bottom: number,
}

export type ScreenPlate = {
	id: string,
	distanceStuds: number,
	rect: ScreenRect,
	priority: number?,
}

export type ScreenPlacement = {
	rect: ScreenRect,
	collapsed: boolean,
}

local function rectsOverlap(left: ScreenRect, right: ScreenRect): boolean
	return left.left < right.right and left.right > right.left and left.top < right.bottom and left.bottom > right.top
end

local function clearOf(candidate: ScreenRect, occupied: { ScreenRect }): boolean
	for _, occupiedRect in occupied do
		if rectsOverlap(candidate, occupiedRect) then
			return false
		end
	end
	return true
end
local Labels = { rectsOverlap = rectsOverlap }

function Labels.rect(left: number, top: number, width: number, height: number): ScreenRect
	return { left = left, top = top, right = left + math.max(width, 0), bottom = top + math.max(height, 0) }
end

function Labels.contains(outer: ScreenRect, inner: ScreenRect): boolean
	return inner.left >= outer.left
		and inner.top >= outer.top
		and inner.right <= outer.right
		and inner.bottom <= outer.bottom
end

function Labels.horizontalAvoidance(label: ScreenRect, band: ScreenRect, gap: number): number
	if not rectsOverlap(label, band) then
		return 0
	end
	local left = band.left - math.max(gap, 0) - label.right
	local right = band.right + math.max(gap, 0) - label.left
	return if math.abs(left) <= math.abs(right) then left else right
end

function Labels.create(tuning: {
	maximum: number,
	farDistance: number,
	farCount: number,
	focusPriority: number,
	defaultPriority: number,
})
	local function placementForScreen(
		plates: { ScreenPlate },
		hudReserves: { ScreenRect }?,
		topbarFloorY: number?,
		screenBounds: ScreenRect?
	): { [string]: ScreenPlacement }
		local ordered = table.clone(plates)
		table.sort(ordered, function(left: ScreenPlate, right: ScreenPlate): boolean
			local leftPriority = left.priority or tuning.defaultPriority
			local rightPriority = right.priority or tuning.defaultPriority
			if leftPriority ~= rightPriority then
				return leftPriority > rightPriority
			end
			if left.distanceStuds == right.distanceStuds then
				return left.id < right.id
			end
			return left.distanceStuds < right.distanceStuds
		end)
		local result: { [string]: ScreenPlacement } = {}
		local occupied: { ScreenRect } = if hudReserves ~= nil then table.clone(hudReserves) else {}
		local presented = 0
		local farPresented = 0
		for _, plate in ordered do
			local candidate = plate.rect
			local far = plate.distanceStuds > tuning.farDistance
				and (plate.priority or tuning.defaultPriority) < tuning.focusPriority
			local inside = (topbarFloorY == nil or candidate.top >= topbarFloorY)
				and (screenBounds == nil or Labels.contains(screenBounds, candidate))
			local admitted = presented < tuning.maximum
				and (not far or farPresented < tuning.farCount)
				and inside
				and clearOf(candidate, occupied)
			if admitted then
				table.insert(occupied, candidate)
				presented += 1
				farPresented += if far then 1 else 0
			end
			result[plate.id] = { rect = candidate, collapsed = not admitted }
		end
		return result
	end
	return { placementForScreen = placementForScreen }
end

return table.freeze(Labels)
