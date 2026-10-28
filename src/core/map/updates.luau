--!strict

export type NormalizedPoint = {
	u: number,
	v: number,
}

export type Sample = {
	atSeconds: number,
	player: NormalizedPoint,
	markerRevision: number,
}

export type State = {
	lastSampleAtSeconds: number?,
	lastPanAtSeconds: number?,
	markerRevision: number?,
}

export type PanUpdate = {
	atSeconds: number,
	player: NormalizedPoint,
}

export type MarkerUpdate = {
	atSeconds: number,
	player: NormalizedPoint,
	revision: number,
}

export type Output = {
	pan: PanUpdate?,
	markers: MarkerUpdate?,
}

export type Result = {
	state: State,
	output: Output,
}

local Updates = {}
function Updates.new(updateHz: number)
	assert(updateHz == updateHz and updateHz > 0 and updateHz < math.huge, "invalid update frequency")
	type Raw = { [unknown]: unknown }
	local UPDATE_HZ = updateHz
	local UPDATE_INTERVAL_SECONDS = 1 / UPDATE_HZ

	local STATE_FIELDS: { [string]: boolean } = {
		lastSampleAtSeconds = true,
		lastPanAtSeconds = true,
		markerRevision = true,
	}

	local SAMPLE_FIELDS: { [string]: boolean } = {
		atSeconds = true,
		player = true,
		markerRevision = true,
	}

	local POINT_FIELDS: { [string]: boolean } = {
		u = true,
		v = true,
	}

	local function finite(value: unknown): boolean
		return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
	end

	local function normalized(value: unknown): boolean
		return finite(value) and (value :: number) >= 0 and (value :: number) <= 1
	end

	local function revision(value: unknown): boolean
		return finite(value) and (value :: number) >= 0 and (value :: number) == math.floor(value :: number)
	end

	local function hasOnlyFields(value: unknown, fields: { [string]: boolean }): boolean
		if type(value) ~= "table" then
			return false
		end
		for key in value :: Raw do
			if type(key) ~= "string" or not fields[key] then
				return false
			end
		end
		return true
	end

	local function validPoint(value: unknown): boolean
		if not hasOnlyFields(value, POINT_FIELDS) then
			return false
		end
		local point = value :: Raw
		return normalized(point.u) and normalized(point.v)
	end

	local function validState(value: unknown): boolean
		if not hasOnlyFields(value, STATE_FIELDS) then
			return false
		end
		local state = value :: Raw
		local empty = state.lastSampleAtSeconds == nil and state.lastPanAtSeconds == nil and state.markerRevision == nil
		if empty then
			return true
		end
		return finite(state.lastSampleAtSeconds)
			and finite(state.lastPanAtSeconds)
			and (state.lastPanAtSeconds :: number) <= (state.lastSampleAtSeconds :: number)
			and revision(state.markerRevision)
	end

	local function validSample(value: unknown): boolean
		if not hasOnlyFields(value, SAMPLE_FIELDS) then
			return false
		end
		local sample = value :: Raw
		return finite(sample.atSeconds) and validPoint(sample.player) and revision(sample.markerRevision)
	end

	local function copyPoint(point: NormalizedPoint): NormalizedPoint
		return {
			u = point.u,
			v = point.v,
		}
	end

	local MinimapUpdateCore = {}

	function MinimapUpdateCore.emptyState(): State
		return {}
	end

	function MinimapUpdateCore.transition(previous: unknown, nextSample: unknown): Result?
		if not validState(previous) or not validSample(nextSample) then
			return nil
		end

		local state = previous :: State
		local sample = nextSample :: Sample
		local first = state.lastSampleAtSeconds == nil
		if not first and sample.atSeconds < (state.lastSampleAtSeconds :: number) then
			return nil
		end

		local panDue = first
		if not first then
			local lastPanAtSeconds = state.lastPanAtSeconds :: number
			local elapsed = sample.atSeconds - lastPanAtSeconds
			if not finite(elapsed) then
				return nil
			end
			local dueAtSeconds = lastPanAtSeconds + UPDATE_INTERVAL_SECONDS
			panDue = elapsed >= UPDATE_INTERVAL_SECONDS
				or (sample.atSeconds > lastPanAtSeconds and finite(dueAtSeconds) and sample.atSeconds >= dueAtSeconds)
		end
		local markersDue = first or sample.markerRevision ~= state.markerRevision

		local pan = nil
		if panDue then
			pan = {
				atSeconds = sample.atSeconds,
				player = copyPoint(sample.player),
			}
		end

		local markers = nil
		if markersDue then
			markers = {
				atSeconds = sample.atSeconds,
				player = copyPoint(sample.player),
				revision = sample.markerRevision,
			}
		end

		return {
			state = {
				lastSampleAtSeconds = sample.atSeconds,
				lastPanAtSeconds = if panDue then sample.atSeconds else state.lastPanAtSeconds,
				markerRevision = if markersDue then sample.markerRevision else state.markerRevision,
			},
			output = {
				pan = pan,
				markers = markers,
			},
		}
	end

	MinimapUpdateCore.UPDATE_INTERVAL_SECONDS = UPDATE_INTERVAL_SECONDS
	MinimapUpdateCore.UPDATE_HZ = UPDATE_HZ

	return table.freeze(MinimapUpdateCore)
end
return table.freeze(Updates)
