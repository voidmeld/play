--!strict

export type VoiceProps = {
	SoundId: string,
	Volume: number,
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
}

export type PlaySpec = {
	soundId: string,
	volume: number,
	spatial: boolean,
	rollOffMinDistance: number,
	rollOffMaxDistance: number,
	voiceSec: number,
}

export type Source = { specFor: (string) -> PlaySpec? }

export type Deps<N, V> = {
	mountVoice: (string, VoiceProps, N) -> (() -> (), V),
	play: (V) -> (),
	schedule: (number, () -> ()) -> (),
	home: N,
	admit: (string) -> boolean,
	catalog: Source,
	tailSec: number,
}

local Playback = {}

function Playback.make<N, V>(deps: Deps<N, V>): (cueId: string, at: N?) -> boolean
	return function(cueId: string, at: N?): boolean
		local spec = deps.catalog.specFor(cueId)
		if spec == nil or not deps.admit(cueId) then
			return false
		end
		local props: VoiceProps = { SoundId = spec.soundId, Volume = spec.volume }
		if spec.spatial and at ~= nil then
			props.RollOffMinDistance = spec.rollOffMinDistance
			props.RollOffMaxDistance = spec.rollOffMaxDistance
		end
		local target: N = if spec.spatial and at ~= nil then at else deps.home
		local disposeVoice, voice = deps.mountVoice("Cue_" .. cueId, props, target)
		deps.play(voice)
		deps.schedule(spec.voiceSec + deps.tailSec, disposeVoice)
		return true
	end
end
function Playback.animator(host: { clock: () -> number, connect: (() -> ()) -> () -> () })
	return function(duration: number, step: (number) -> (), finish: () -> ())
		local started = host.clock()
		local release: () -> () = function() end
		step(0)
		release = host.connect(function()
			local alpha = math.clamp((host.clock() - started) / duration, 0, 1)
			step(alpha)
			if alpha >= 1 then
				release()
				finish()
			end
		end)
	end
end

return table.freeze(Playback)
