--!strict

export type Vec2 = { x: number, y: number }

export type Stick = {
	anchor: Vec2,
	knob: Vec2,
	vector: Vec2,
}

local Module = {}

function Module.create(options: { radiusPx: number, deadZone: number, zoneWidth: number, zoneHeight: number })
	local function vec2(x: number, y: number): Vec2
		return { x = x, y = y }
	end

	local function vectorFor(offset: Vec2, radiusPx: number, deadZone: number): Vec2
		if radiusPx <= 0 then
			return vec2(0, 0)
		end
		local dx = offset.x / radiusPx
		local dy = -offset.y / radiusPx
		local magnitude = math.sqrt(dx * dx + dy * dy)
		if magnitude <= deadZone then
			return vec2(0, 0)
		end
		local clamped = math.min(magnitude, 1)
		local scaled = (clamped - deadZone) / (1 - deadZone)
		return vec2(dx / magnitude * scaled, dy / magnitude * scaled)
	end

	local function knobFor(offset: Vec2, radiusPx: number): Vec2
		local length = math.sqrt(offset.x * offset.x + offset.y * offset.y)
		if length <= radiusPx or length == 0 then
			return vec2(offset.x, offset.y)
		end
		local scale = radiusPx / length
		return vec2(offset.x * scale, offset.y * scale)
	end

	local function anchorAt(point: Vec2): Stick
		return {
			anchor = vec2(point.x, point.y),
			knob = vec2(0, 0),
			vector = vec2(0, 0),
		}
	end

	local function drag(stick: Stick, point: Vec2, radiusPx: number?, deadZone: number?): Stick
		local radius = radiusPx or options.radiusPx
		local zone = deadZone or options.deadZone
		local offset = vec2(point.x - stick.anchor.x, point.y - stick.anchor.y)
		return {
			anchor = stick.anchor,
			knob = knobFor(offset, radius),
			vector = vectorFor(offset, radius, zone),
		}
	end

	local function release(): Vec2
		return vec2(0, 0)
	end

	return {
		DEAD_ZONE = options.deadZone,
		RADIUS_PX = options.radiusPx,
		ZONE_WIDTH_SCALE = options.zoneWidth,
		ZONE_HEIGHT_SCALE = options.zoneHeight,
		anchorAt = anchorAt,
		drag = drag,
		release = release,
		vectorFor = vectorFor,
		knobFor = knobFor,
	}
end

return table.freeze(Module)
