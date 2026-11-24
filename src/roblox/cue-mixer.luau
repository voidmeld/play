--!strict

local SoundCueMix = {}

export type MixSpec = { family: string, maxVoices: number, minIntervalSec: number, voiceSec: number }

export type DuckSpec = { bedGain: number, voiceBedGain: number, families: { string } }

export type CueSource = {
	specFor: (cueId: string) -> MixSpec?,
	duck: () -> DuckSpec,
}

export type Mixer = {
	admit: (self: Mixer, cueId: string) -> boolean,
	gate: (self: Mixer, cueId: string) -> boolean,
	activeVoices: (self: Mixer, family: string) -> number,
	duckGain: (self: Mixer) -> number,
	setVoiceActive: (self: Mixer, active: boolean) -> (),
}

local function prune(voices: { number }, now: number)
	local kept = 0
	for _, expiry in voices do
		if expiry > now then
			kept += 1
			voices[kept] = expiry
		end
	end
	for index = #voices, kept + 1, -1 do
		voices[index] = nil
	end
end

function SoundCueMix.new(catalog: CueSource, clock: () -> number): Mixer
	local lastAt: { [string]: number } = {}
	local voicesByFamily: { [string]: { number } } = {}
	local voiceActive = false

	local function admit(_self: Mixer, cueId: string): boolean
		local spec = catalog.specFor(cueId)
		if spec == nil then
			return false
		end
		local now = clock()
		local last = lastAt[cueId]
		if last ~= nil and now - last < spec.minIntervalSec then
			return false
		end
		local voices = voicesByFamily[spec.family]
		if voices == nil then
			voices = {}
			voicesByFamily[spec.family] = voices
		end
		prune(voices, now)
		if #voices >= spec.maxVoices then
			return false
		end
		lastAt[cueId] = now
		table.insert(voices, now + spec.voiceSec)
		return true
	end

	local function gate(self: Mixer, cueId: string): boolean
		if catalog.specFor(cueId) == nil then
			return true
		end
		return admit(self, cueId)
	end

	local function activeVoices(_self: Mixer, family: string): number
		local voices = voicesByFamily[family]
		if voices == nil then
			return 0
		end
		prune(voices, clock())
		return #voices
	end

	local function duckGain(self: Mixer): number
		local duck = catalog.duck()
		if voiceActive then
			return duck.voiceBedGain
		end
		for _, family in duck.families do
			if activeVoices(self, family) > 0 then
				return duck.bedGain
			end
		end
		return 1
	end

	local function setVoiceActive(_self: Mixer, active: boolean)
		voiceActive = active
	end

	return {
		admit = admit,
		gate = gate,
		activeVoices = activeVoices,
		duckGain = duckGain,
		setVoiceActive = setVoiceActive,
	}
end

return table.freeze(SoundCueMix)
