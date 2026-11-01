--!strict

local Value = require("../value")

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
		return (type(value) == "number" and finite(value)) and value >= 0 and value <= 1
	end

	local function revision(value: unknown): boolean
		return (type(value) == "number" and finite(value)) and value >= 0 and value == math.floor(value)
	end

	local function readPoint(value: unknown): NormalizedPoint?
		local point = Value.record(value, POINT_FIELDS, false, false)
		if point == nil then
			return nil
		end
		local u, v = point.u, point.v
		if
			type(u) ~= "number"
			or type(v) ~= "number"
			or not (type(u) == "number" and normalized(u))
			or not (type(v) == "number" and normalized(v))
		then
			return nil
		end
		return { u = u, v = v }
	end
	local function readState(value: unknown): State?
		local state = Value.record(value, STATE_FIELDS, false, false)
		if state == nil then
			return nil
		end
		local sample, pan, marker = state.lastSampleAtSeconds, state.lastPanAtSeconds, state.markerRevision
		if sample == nil and pan == nil and marker == nil then
			return {}
		end
		if
			type(sample) ~= "number"
			or type(pan) ~= "number"
			or type(marker) ~= "number"
			or not (type(sample) == "number" and finite(sample))
			or not (type(pan) == "number" and finite(pan))
			or pan > sample
			or not (type(marker) == "number" and revision(marker))
		then
			return nil
		end
		return { lastSampleAtSeconds = sample, lastPanAtSeconds = pan, markerRevision = marker }
	end
	local function readSample(value: unknown): Sample?
		local sample = Value.record(value, SAMPLE_FIELDS, false, false)
		if sample == nil then
			return nil
		end
		local at, marker = sample.atSeconds, sample.markerRevision
		local player = readPoint(sample.player)
		if
			type(at) ~= "number"
			or not (type(at) == "number" and finite(at))
			or type(marker) ~= "number"
			or not (type(marker) == "number" and revision(marker))
			or player == nil
		then
			return nil
		end
		return { atSeconds = at, player = player, markerRevision = marker }
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
		local state, sample = readState(previous), readSample(nextSample)
		if state == nil or sample == nil then
			return nil
		end
		local first = state.lastSampleAtSeconds == nil
		if state.lastSampleAtSeconds ~= nil and sample.atSeconds < state.lastSampleAtSeconds then
			return nil
		end

		local panDue = first
		if not first then
			local lastPanAtSeconds = state.lastPanAtSeconds
			if lastPanAtSeconds == nil then
				return nil
			end
			local elapsed = sample.atSeconds - lastPanAtSeconds
			if not (type(elapsed) == "number" and finite(elapsed)) then
				return nil
			end
			local dueAtSeconds = lastPanAtSeconds + UPDATE_INTERVAL_SECONDS
			panDue = elapsed >= UPDATE_INTERVAL_SECONDS
				or (
					sample.atSeconds > lastPanAtSeconds
					and (type(dueAtSeconds) == "number" and finite(dueAtSeconds))
					and sample.atSeconds >= dueAtSeconds
				)
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
