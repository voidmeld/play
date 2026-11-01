--!strict

export type Planar = { x: number, z: number }
export type Point = { x: number, y: number?, z: number }
export type Observed = { position: Planar, facing: Planar }
export type Projection = { position: Planar, facing: Planar, planarSpeed: number }
export type Changes = { transform: boolean, planarSpeed: boolean }

local Motion = {}

function Motion.projection(tuning: { epsilon: number, facingEpsilon: number, minimumDt: number })
	local function near(a: number, b: number): boolean
		return math.abs(a - b) <= tuning.epsilon
	end

	local function samePlanar(a: Planar, b: Planar): boolean
		return near(a.x, b.x) and near(a.z, b.z)
	end

	local function facingToward(from: Planar, target: Planar?): Planar?
		if target == nil then
			return nil
		end
		local x = (target).x - from.x
		local z = (target).z - from.z
		local magnitude = math.sqrt(x * x + z * z)
		if magnitude <= tuning.facingEpsilon then
			return { x = 0, z = -1 }
		end
		return { x = x / magnitude, z = z / magnitude }
	end

	local function plan(
		previous: Projection?,
		observed: Observed,
		position: Planar,
		target: Planar?,
		dt: number
	): (Projection, Changes)
		local dx = position.x - observed.position.x
		local dz = position.z - observed.position.z
		local projection = {
			position = { x = position.x, z = position.z },
			facing = facingToward(position, target) or { x = observed.facing.x, z = observed.facing.z },
			planarSpeed = math.sqrt(dx * dx + dz * dz) / math.max(dt, tuning.minimumDt),
		}
		local cachedTransformChanged = previous == nil
			or not samePlanar((previous).position, projection.position)
			or not samePlanar((previous).facing, projection.facing)
		local observedTransformChanged = not samePlanar(observed.position, projection.position)
			or not samePlanar(observed.facing, projection.facing)
		return projection,
			{
				transform = cachedTransformChanged or observedTransformChanged,
				planarSpeed = previous == nil or not near((previous).planarSpeed, projection.planarSpeed),
			}
	end

	local function groundedPivotY(
		terrainY: number,
		hipHeight: number,
		rootHalfHeight: number,
		rootToPivotY: number
	): number
		return terrainY + math.max(0, hipHeight) + rootHalfHeight + rootToPivotY
	end

	local function anchoredSurfaceY(anchorY: number, hitY: number?): number
		return if hitY == nil then anchorY else math.max(anchorY, hitY)
	end

	return {
		anchoredSurfaceY = anchoredSurfaceY,
		groundedPivotY = groundedPivotY,
		plan = plan,
	}
end

function Motion.distance(a: Point, b: Point): number
	local dx = a.x - b.x
	local dz = a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
end
function Motion.movement(epsilon: number)
	local Movement = {}
	function Movement.insideLeash(origin: Point?, radius: number?, point: Point): boolean
		return origin == nil or radius == nil or Motion.distance(origin, point) <= radius + epsilon
	end
	function Movement.moveToward(pos: Point, target: Point, maxDistance: number): Point
		local dx = target.x - pos.x
		local dz = target.z - pos.z
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance <= epsilon or maxDistance <= 0 then
			return { x = pos.x, y = pos.y, z = pos.z }
		end
		local step = math.min(maxDistance, distance)
		local scale = step / distance
		return {
			x = pos.x + dx * scale,
			y = pos.y,
			z = pos.z + dz * scale,
		}
	end
	return table.freeze(Movement)
end

return table.freeze(Motion)
