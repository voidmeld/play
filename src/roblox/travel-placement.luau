--!strict

local Travel = {}

function Travel.place<Frame, Floor>(host: {
	count: number,
	candidate: (number) -> Frame,
	clear: (Frame) -> boolean,
	ground: () -> Floor?,
	floor: (Frame) -> Floor?,
	safe: (Floor, Floor) -> boolean,
	commit: (Frame) -> (),
}): Frame?
	local ground = if host.count > 0 then host.ground() else nil
	for index = 0, host.count * 2 do
		local candidate = host.candidate(index)
		local clear = host.clear(candidate)
		local floor = if clear and index > 0 and ground ~= nil then host.floor(candidate) else nil
		if clear and (index == 0 or (floor ~= nil and ground ~= nil and host.safe(floor, ground))) then
			host.commit(candidate)
			return candidate
		end
	end
	return nil
end

function Travel.entrance<Frame, Point, Floor>(host: {
	count: number,
	point: (number) -> Point,
	clear: (Point) -> boolean,
	near: (Point) -> Floor?,
	far: (Point) -> Floor?,
	safe: (Floor) -> boolean,
	frame: (Floor) -> Frame,
}): Frame?
	for index = 0, host.count * 2 do
		local point = host.point(index)
		if not host.clear(point) then
			continue
		end
		local near = host.near(point)
		if near ~= nil then
			if host.safe(near) then
				return host.frame(near)
			end
		else
			local far = host.far(point)
			if far ~= nil and host.safe(far) then
				return host.frame(far)
			end
		end
	end
	return nil
end

return table.freeze(Travel)
