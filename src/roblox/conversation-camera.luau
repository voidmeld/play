--!strict

local Dynamics = require("./camera")

export type Point = { x: number, y: number, z: number }
export type Rect = { x: number, y: number, width: number, height: number }
export type View = { eye: Point, look: Point }
export type State = { key: string?, released: boolean, blend: Dynamics.Spring }

export type Tuning = {
	gap: number,
	minimumSpace: number,
	omega: number,
	minimumDistance: number,
	coverage: number,
	eyeLift: number,
	angles: { number },
	touchThresholdSquared: number,
	stickThresholdSquared: number,
}

local Module = {}

function Module.create(
	Action: {
		read newSpring: (number) -> Dynamics.Spring,
		read springStep: (Dynamics.Spring, number, number, number) -> Dynamics.Spring,
	},
	tuning: Tuning
)
	local Core = {}
	function Core.new(): State
		return { key = nil, released = false, blend = Action.newSpring(0) }
	end

	function Core.step(
		state: State,
		key: string?,
		available: boolean,
		override: boolean,
		dt: number,
		departed: boolean?
	): State
		local changed = key ~= state.key
		local released = if changed then false else state.released
		if key ~= nil and (departed == true or override) then
			released = true
		end
		return {
			key = key,
			released = released,
			blend = if override
				then Action.newSpring(0)
				else Action.springStep(
					state.blend,
					if key ~= nil and available and not released then 1 else 0,
					tuning.omega,
					dt
				),
		}
	end

	function Core.space(safe: Rect, card: Rect): Rect?
		local gap = tuning.gap
		local right, bottom = safe.x + safe.width, safe.y + safe.height
		local regions = {
			{ safe.x, safe.y, card.x - gap, bottom },
			{ card.x + card.width + gap, safe.y, right, bottom },
			{ safe.x, safe.y, right, card.y - gap },
			{ safe.x, card.y + card.height + gap, right, bottom },
		}
		local best: Rect? = nil
		local area = 0
		for _, bounds in regions do
			local x, y = math.max(bounds[1], safe.x), math.max(bounds[2], safe.y)
			local region =
				{ x = x, y = y, width = math.min(bounds[3], right) - x, height = math.min(bounds[4], bottom) - y }
			local score = region.width * region.height
			if region.width >= tuning.minimumSpace and region.height >= tuning.minimumSpace and score > area then
				best, area = region, score
			end
		end
		return best
	end

	function Core.views(
		focus: Point,
		toward: Point,
		width: number,
		height: number,
		fov: number,
		region: Rect,
		radius: number?
	): { View }
		local tangent = math.tan(math.rad(fov) * 0.5)
		local distance = math.max(
			tuning.minimumDistance,
			height
				/ (tangent * tuning.coverage)
				* math.max((radius or 2) / region.width, (if radius ~= nil then 3 else 2) / region.height)
		)
		local nx = 2 * (region.x + region.width * 0.5) / width - 1
		local ny = 1 - 2 * (region.y + region.height * 0.5) / height
		local tx, ty = nx * tangent * width / height, ny * tangent
		local range = math.sqrt(distance * distance + tuning.eyeLift * tuning.eyeLift)
		local turn = math.asin(math.clamp(tx * range / (math.sqrt(1 + tx * tx + ty * ty) * distance), -1, 1))
		local pitch = math.atan2(-tuning.eyeLift, distance * math.cos(turn)) - math.atan(ty)
		local yaw = math.atan2(toward.x - focus.x, toward.z - focus.z)
		local views: { View } = {}
		for _, angle in tuning.angles do
			local theta = yaw + math.rad(angle)
			local bx, bz = math.sin(theta), math.cos(theta)
			local eye = {
				x = focus.x + bx * distance,
				y = focus.y + tuning.eyeLift,
				z = focus.z + bz * distance,
			}
			table.insert(views, {
				eye = eye,
				look = {
					x = eye.x - math.sin(theta + turn) * math.cos(pitch) * distance,
					y = eye.y + math.sin(pitch) * distance,
					z = eye.z - math.cos(theta + turn) * math.cos(pitch) * distance,
				},
			})
		end
		return views
	end

	function Core.choose(views: { View }, clear: (View) -> boolean): View?
		for _, view in views do
			if clear(view) then
				return view
			end
		end
		return nil
	end

	function Core.cameraGesture(kind: string, x: number, y: number, rotating: boolean, processed: boolean): boolean
		if processed then
			return false
		end
		return (kind == "MouseMovement" and rotating and x * x + y * y > 0)
			or kind == "MouseWheel"
			or (kind == "Touch" and x * x + y * y > tuning.touchThresholdSquared)
			or (kind == "Thumbstick2" and x * x + y * y > tuning.stickThresholdSquared)
	end

	return table.freeze(Core)
end

return table.freeze(Module)
