--!strict

export type Spring = { position: number, velocity: number }
export type Obstruction = {
	anchored: boolean,
	transparency: number,
	collidable: boolean,
	structural: boolean,
	actor: boolean,
	effect: boolean,
}
export type Tuning = {
	MIN_ZOOM: number,
	MAX_ZOOM: number,
	CLASSIC_MIN_ZOOM: number,
	CLASSIC_MAX_ZOOM: number,
	SHOULDER_RIGHT: number,
	SHOULDER_UP: number,
	BASE_FOV: number,
	MAX_FOV_WIDEN: number,
	SPRINT_SPEED_RATIO: number,
	STRUCTURE_ALPHA: number,
	OBSTRUCTION_OMEGA: number,
	OBSTRUCTION_PADDING: number,
	SPRINT_LEAD: number,
	SPRINT_SPAN: number,
}

local Module = {}

function Module.create(tuning: Tuning)
	local Camera = {}
	function Camera.zoomLimits(classic: boolean): (number, number)
		if classic then
			return tuning.CLASSIC_MIN_ZOOM, tuning.CLASSIC_MAX_ZOOM
		end
		return tuning.MIN_ZOOM, tuning.MAX_ZOOM
	end

	function Camera.isCameraStructure(part: Obstruction): boolean
		return part.anchored
			and part.transparency < tuning.STRUCTURE_ALPHA
			and not part.actor
			and not part.effect
			and (part.collidable or part.structural)
	end

	function Camera.smoothObstruction(previous: number, limit: number, dt: number): number
		return math.min(
			limit,
			previous + (limit - previous) * (1 - math.exp(-tuning.OBSTRUCTION_OMEGA * math.max(0, dt)))
		)
	end

	function Camera.obstructedDistance(distance: number, hitDistance: number?): number
		if hitDistance == nil then
			return distance
		end
		return math.clamp(hitDistance - tuning.OBSTRUCTION_PADDING, 0, distance)
	end

	function Camera.newSpring(position: number): Spring
		return { position = position, velocity = 0 }
	end

	function Camera.springStep(spring: Spring, target: number, omega: number, dt: number): Spring
		if dt <= 0 then
			return spring
		end
		local offset = spring.position - target
		local decay = math.exp(-omega * dt)
		local carry = spring.velocity + omega * offset
		return {
			position = target + (offset + carry * dt) * decay,
			velocity = (spring.velocity - carry * omega * dt) * decay,
		}
	end

	function Camera.shoulderOffset(blend: number): (number, number)
		local t = math.clamp(blend, 0, 1)
		return tuning.SHOULDER_RIGHT * t, tuning.SHOULDER_UP * t
	end

	function Camera.sprintWiden(speed: number, walkSpeed: number, autoRun: boolean): number
		if autoRun then
			return tuning.MAX_FOV_WIDEN
		end
		if walkSpeed <= 0 then
			return 0
		end
		local ratio = speed / walkSpeed
		local t = math.clamp((ratio - tuning.SPRINT_SPEED_RATIO + tuning.SPRINT_LEAD) / tuning.SPRINT_SPAN, 0, 1)
		return tuning.MAX_FOV_WIDEN * t
	end

	function Camera.fovTarget(widen: number): number
		return tuning.BASE_FOV + math.clamp(widen, 0, tuning.MAX_FOV_WIDEN)
	end

	function Camera.yields(cameraIsCustom: boolean, scriptedStateActive: boolean, classic: boolean): boolean
		return classic or scriptedStateActive or not cameraIsCustom
	end

	return table.freeze(Camera)
end

return table.freeze(Module)
