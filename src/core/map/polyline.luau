--!strict
export type PixelPoint = { x: number, y: number }
local Polyline = {}
local function distanceToSegment(point: PixelPoint, from: PixelPoint, to: PixelPoint): number
	local dx, dy = to.x - from.x, to.y - from.y
	local lengthSquared = dx * dx + dy * dy
	if lengthSquared == 0 then
		return math.sqrt((point.x - from.x) ^ 2 + (point.y - from.y) ^ 2)
	end
	local t = math.clamp(((point.x - from.x) * dx + (point.y - from.y) * dy) / lengthSquared, 0, 1)
	return math.sqrt((point.x - (from.x + t * dx)) ^ 2 + (point.y - (from.y + t * dy)) ^ 2)
end

function Polyline.simplifyPolyline(points: { PixelPoint }, tolerance: number): { PixelPoint }
	local count = #points
	if count <= 2 then
		return table.clone(points)
	end
	local keep: { [number]: boolean } = { [1] = true, [count] = true }
	local stack = { { 1, count } }
	while #stack > 0 do
		local range = assert(table.remove(stack))
		local first, last = range[1], range[2]
		local farthest, farthestDistance = nil, tolerance
		for index = first + 1, last - 1 do
			local distance = distanceToSegment(points[index], points[first], points[last])
			if distance > farthestDistance then
				farthest, farthestDistance = index, distance
			end
		end
		if farthest ~= nil then
			keep[farthest] = true
			table.insert(stack, { first, farthest })
			table.insert(stack, { farthest, last })
		end
	end
	local result = {}
	for index = 1, count do
		if keep[index] then
			result[#result + 1] = points[index]
		end
	end
	return result
end

function Polyline.smoothPolyline(points: { PixelPoint }): { PixelPoint }
	local count = #points
	if count <= 2 then
		return table.clone(points)
	end
	local result = { points[1] }
	for index = 1, count - 1 do
		local from, to = points[index], points[index + 1]
		if index > 1 then
			result[#result + 1] = { x = from.x * 0.75 + to.x * 0.25, y = from.y * 0.75 + to.y * 0.25 }
		end
		if index < count - 1 then
			result[#result + 1] = { x = from.x * 0.25 + to.x * 0.75, y = from.y * 0.25 + to.y * 0.75 }
		end
	end
	result[#result + 1] = points[count]
	return result
end

return table.freeze(Polyline)
